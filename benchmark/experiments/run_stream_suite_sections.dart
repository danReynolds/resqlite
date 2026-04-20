// ignore_for_file: avoid_print

import 'dart:io';

import '../suites/feed_paging.dart';
import '../suites/high_cardinality_fanout.dart';
import '../suites/keyed_pk_subscriptions.dart';
import '../suites/sync_burst.dart';

Future<void> main(List<String> args) async {
  final outPath = _extractOutPath(args);

  final markdown = StringBuffer()
    ..writeln('# Stream Suite Sections')
    ..writeln()
    ..writeln('Generated: ${DateTime.now().toIso8601String()}')
    ..writeln();

  print('[1/4] Feed Paging (A6)...');
  markdown.write(await runFeedPagingBenchmark());
  markdown.writeln();

  print('[2/4] Keyed PK Subscriptions (A11)...');
  markdown.write(await runKeyedPkSubscriptionsBenchmark());
  markdown.writeln();

  print('[3/4] High-Cardinality Stream Fan-out (A11b)...');
  markdown.write(await runHighCardinalityFanoutBenchmark());
  markdown.writeln();

  print('[4/4] Sync Burst (A7)...');
  markdown.write(await runSyncBurstBenchmark());
  markdown.writeln();

  final content = markdown.toString();
  if (outPath != null) {
    await File(outPath).writeAsString(content);
    print('Results written to: $outPath');
  } else {
    print(content);
  }
}

String? _extractOutPath(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--out=')) return arg.substring('--out='.length);
  }
  return null;
}
