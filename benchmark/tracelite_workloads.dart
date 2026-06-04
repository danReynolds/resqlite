const traceliteReleasePolicyScenarios = [
  'high-cardinality-fanout',
  'many-streams-writer-throughput',
];

const traceliteProductionSuiteScenarios = [
  ...traceliteReleasePolicyScenarios,
  'sqlite-diagnostics',
];

const traceliteDiagnosticScenarios = [
  'point-select',
  'feed-paging',
  'sync-burst',
  'large-working-set',
  'keyed-pk-subscriptions',
];

const traceliteCiSuiteScenarios = [
  'narrow-batch-insert',
  'point-select',
  'keyed-pk-subscriptions',
  'sqlite-diagnostics',
];

const traceliteExperimentSuiteScenarios = [
  'feed-paging',
  'chat-sim',
  'keyed-pk-subscriptions',
];
