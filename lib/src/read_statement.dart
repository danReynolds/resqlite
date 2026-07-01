/// One SELECT statement to run inside a [Database.selectAll] batch.
///
/// Groups a SQL string with its positional parameters so a caller can
/// hand a whole batch of unrelated reads to `selectAll(...)` in a single
/// reader-isolate round trip.
final class ReadStatement {
  const ReadStatement(this.sql, [this.parameters = const []]);

  final String sql;
  final List<Object?> parameters;
}
