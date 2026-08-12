// ignore_for_file: avoid_print
//
// How often would a `select()` result cache actually hit?
// ([EXP-270](../../experiments/270-read-result-cache.md))
//
// The focused A/B lanes for this experiment are all-hit lanes by construction:
// they repeat one statement with nothing writing, so they measure the ceiling of
// the mechanism and say nothing about whether the mechanism matters. The release
// suite is no better here, and for the same reason — its read scenarios execute
// one statement thousands of times, so a cache keyed on that statement measures
// itself.
//
// The closest thing this repo has to an application is its two workload
// simulations: Chat Sim (A5) interleaves message inserts, conversation updates,
// a last-20 JOIN and a user-by-PK fetch; Feed Paging (A6) walks pages and
// reactive updates. Neither is a production trace. Both at least mix reads with
// writes to the tables those reads depend on, which is the property that decides
// a cache's hit rate and the property the focused lanes deliberately remove.
//
// This runs them and reports what fraction of `select()` calls the cache could
// serve. It is a hit-rate probe, not a timing harness — a number to hold the
// aggregate-value argument to, not a benchmark result.
//
// Usage:
//   dart run benchmark/experiments/select_read_cache_incidence.dart
import 'package:resqlite/src/read_cache.dart';

import '../suites/chat_sim.dart';
import '../suites/feed_paging.dart';

Future<void> main() async {
  if (!kReadCacheEnabled) {
    print('read cache disabled in this build — nothing to report');
    return;
  }

  for (final (label, run) in <(String, Future<String> Function())>[
    ('chat_sim (A5)', runChatSimBenchmark),
    ('feed_paging (A6)', runFeedPagingBenchmark),
  ]) {
    ReadCache.resetStats();
    await run();
    final hits = ReadCache.hits;
    final misses = ReadCache.misses;
    final total = hits + misses;
    final rate = total == 0 ? 0.0 : hits / total * 100.0;
    print(
      'workload=$label selects=$total hits=$hits misses=$misses '
      'hit_rate=${rate.toStringAsFixed(1)}%',
    );
  }
}
