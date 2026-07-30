/// Guards the invariant that makes `impact.dart` mean anything: the state of a
/// revision is derived only from that revision's own bytes.
///
/// The bug this was written after: retiring edges were re-read from the working
/// tree while claims came from the compared revision, so a retirement performed
/// by editing an existing claim's edges looked identical before and after — and
/// the report silently omitted it while still showing its downstream fallout.
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../tool/knowledge/impact.dart';

Map<String, Claim> claimsFrom(String expId, List<Map<String, Object?>> claims) {
  final out = <String, Claim>{};
  collectClaims(json.encode({'claims': claims}), expId, out);
  return out;
}

void main() {
  group('deriveStates', () {
    test('a claim nothing points at is live', () {
      final s = deriveStates(
        claimsFrom('245', [
          {'id': '245.1', 'text': 'foundation'},
        ]),
      );
      expect(s['245.1'], 'live');
    });

    test('refutes and supersedes are distinguished', () {
      final s = deriveStates(
        claimsFrom('245', [
          {'id': '245.1', 'text': 'a'},
          {'id': '245.2', 'text': 'b'},
          {
            'id': '245.3',
            'text': 'c',
            'edges': [
              {'type': 'refutes', 'target': '245.1'},
              {'type': 'supersedes', 'target': '245.2'},
            ],
          },
        ]),
      );
      expect(s['245.1'], 'refuted');
      expect(s['245.2'], 'superseded');
    });

    test('dependsOn propagates transitively', () {
      final s = deriveStates(
        claimsFrom('245', [
          {'id': '245.1', 'text': 'foundation'},
          {
            'id': '245.9',
            'text': 'kills it',
            'edges': [
              {'type': 'refutes', 'target': '245.1'},
            ],
          },
          {
            'id': '246.1',
            'text': 'rests on the foundation',
            'edges': [
              {'type': 'dependsOn', 'target': '245.1'},
            ],
          },
          {
            'id': '247.1',
            'text': 'rests on 246.1',
            'edges': [
              {'type': 'dependsOn', 'target': '246.1'},
            ],
          },
        ]),
      );
      expect(s['246.1'], 'unsupported');
      expect(s['247.1'], 'unsupported');
    });

    // The regression. Both snapshots hold the same claim ids; only the edges
    // differ. If either snapshot consulted the working tree instead of its own
    // bytes, these two would agree and the retirement would vanish.
    test('two snapshots of the same ids derive independent states', () {
      const before = [
        {'id': '245.1', 'text': 'foundation'},
        {'id': '245.2', 'text': 'sibling'},
      ];
      const after = [
        {'id': '245.1', 'text': 'foundation'},
        {
          'id': '245.2',
          'text': 'sibling',
          'edges': [
            {'type': 'refutes', 'target': '245.1'},
          ],
        },
      ];
      expect(deriveStates(claimsFrom('245', before))['245.1'], 'live');
      expect(deriveStates(claimsFrom('245', after))['245.1'], 'refuted');
    });

    test('an edge with no target is ignored rather than crashing', () {
      final s = deriveStates(
        claimsFrom('245', [
          {
            'id': '245.1',
            'text': 'a',
            'edges': [
              {'type': 'refutes'},
            ],
          },
        ]),
      );
      expect(s['245.1'], 'live');
    });
  });
}
