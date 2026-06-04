const traceliteReleasePolicyScenarios = [
  'high-cardinality-fanout',
  'many-streams-writer-throughput',
  'point-select',
  'keyed-pk-subscriptions',
];

const traceliteProductionSuiteScenarios = [
  ...traceliteReleasePolicyScenarios,
  'sqlite-diagnostics',
];

const traceliteDiagnosticScenarios = [
  'feed-paging',
  'sync-burst',
  'large-working-set',
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
