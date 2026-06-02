import '../exceptions.dart';
import 'extension.dart';

final class ExtensionRegistrationPlan {
  ExtensionRegistrationPlan._({
    required this.entrypoints,
    required this.setupSteps,
  });

  factory ExtensionRegistrationPlan.from(
    Iterable<ResqliteExtension> extensions,
  ) {
    final extensionList = extensions.toList(growable: false);
    return ExtensionRegistrationPlan._(
      entrypoints: _collectExtensionEntrypoints(extensionList),
      setupSteps: _collectExtensionSetup(extensionList),
    );
  }

  final List<ExtensionEntrypoint> entrypoints;
  final List<ExtensionSetupStep> setupSteps;
}

final class ExtensionEntrypoint {
  const ExtensionEntrypoint({required this.address, required this.name});

  final int address;
  final String name;
}

final class ExtensionSetupStep {
  const ExtensionSetupStep({
    required this.extensionName,
    required this.sql,
    required this.parameters,
    required this.scope,
  });

  final String extensionName;
  final String sql;
  final List<Object?> parameters;
  final ResqliteConnectionScope scope;
}

List<ExtensionEntrypoint> _collectExtensionEntrypoints(
  Iterable<ResqliteExtension> extensions,
) {
  final entrypoints = <ExtensionEntrypoint>[];
  final seenEntrypoints = <int, String>{};
  for (final extension in extensions) {
    final address = extension.entrypointAddress.address;
    final existingName = seenEntrypoints[address];
    if (existingName != null) {
      throw ArgumentError(
        'Duplicate resqlite extension entrypoint: '
        '${extension.debugName} reuses the native entrypoint from '
        '$existingName. Combine setup in one extension value instead.',
      );
    }
    seenEntrypoints[address] = extension.debugName;
    entrypoints.add(
      ExtensionEntrypoint(address: address, name: extension.debugName),
    );
  }
  return List.unmodifiable(entrypoints);
}

List<ExtensionSetupStep> _collectExtensionSetup(
  Iterable<ResqliteExtension> extensions,
) {
  final setup = <ExtensionSetupStep>[];
  for (final extension in extensions) {
    final onRegister = extension.onRegister;
    if (onRegister == null) continue;

    final registrar = _ExtensionRegistrar(
      extensionName: extension.debugName,
      setup: setup,
    );
    try {
      onRegister(registrar);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ResqliteConnectionException(
          'Failed to register extension ${extension.debugName}: $error',
        ),
        stackTrace,
      );
    }
  }
  return List.unmodifiable(setup);
}

final class _ExtensionRegistrar implements ResqliteExtensionRegistrar {
  _ExtensionRegistrar({
    required this.extensionName,
    required List<ExtensionSetupStep> setup,
  }) : _setup = setup;

  final String extensionName;
  final List<ExtensionSetupStep> _setup;

  @override
  void execute(
    String sql, {
    List<Object?> parameters = const [],
    ResqliteConnectionScope scope = ResqliteConnectionScope.all,
  }) {
    if (sql.trim().isEmpty) {
      throw ArgumentError.value(sql, 'sql', 'must not be empty');
    }
    _setup.add(
      ExtensionSetupStep(
        extensionName: extensionName,
        sql: sql,
        parameters: List.unmodifiable(parameters),
        scope: scope,
      ),
    );
  }
}
