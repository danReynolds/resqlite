/// A single write statement used by [Database.executeStatements].
final class WriteStatement {
  const WriteStatement(this.sql, [this.parameters = const []]);

  /// The INSERT, UPDATE, DELETE, or DDL statement to execute.
  final String sql;

  /// Positional parameters bound to `?` placeholders in [sql].
  final List<Object?> parameters;
}
