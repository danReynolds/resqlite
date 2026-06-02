import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;
    final arch = codeConfig.targetArchitecture;

    final binaryPath = _resolveBinaryPath(os, arch, codeConfig);
    if (binaryPath == null) {
      throw UnsupportedError('resqlite_js does not support $os $arch.');
    }

    final file = File(
      p.join(input.packageRoot.toFilePath(), 'native_libraries', binaryPath),
    );
    if (!file.existsSync()) {
      throw StateError('Missing native extension binary: ${file.path}');
    }

    output.dependencies.add(file.uri);

    final assetFile = await _prepareAssetFile(
      input: input,
      os: os,
      arch: arch,
      config: codeConfig,
      file: file,
    );

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/native/sqlite_js_extension.dart',
        linkMode: DynamicLoadingBundled(),
        file: assetFile.uri,
      ),
    );
  });
}

Future<File> _prepareAssetFile({
  required BuildInput input,
  required OS os,
  required Architecture arch,
  required CodeConfig config,
  required File file,
}) async {
  if (os != OS.iOS || config.iOS.targetSdk == IOSSdk.iPhoneOS) {
    return file;
  }

  final thinArch = switch (arch) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x86_64',
    _ => null,
  };
  if (thinArch == null) return file;

  final outputFile = File.fromUri(
    input.outputDirectory.resolve('js_ios_sim_$thinArch.dylib'),
  );
  await outputFile.parent.create(recursive: true);

  final result = await Process.run('/usr/bin/lipo', [
    file.path,
    '-thin',
    thinArch,
    '-output',
    outputFile.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Failed to thin sqlite_js iOS simulator binary: ${result.stderr}',
    );
  }

  return outputFile;
}

String? _resolveBinaryPath(OS os, Architecture arch, CodeConfig config) {
  return switch ((os, arch)) {
    (OS.android, Architecture.arm64) => 'android/js_android_arm64.so',
    (OS.android, Architecture.x64) => 'android/js_android_x64.so',
    (OS.iOS, _) when config.iOS.targetSdk == IOSSdk.iPhoneOS =>
      'ios/js_ios_arm64.dylib',
    (OS.iOS, Architecture.arm64) => 'ios-sim/js_ios-sim.dylib',
    (OS.iOS, Architecture.x64) => 'ios-sim/js_ios-sim.dylib',
    (OS.macOS, Architecture.arm64) => 'mac/js_mac_arm64.dylib',
    (OS.macOS, Architecture.x64) => 'mac/js_mac_x64.dylib',
    (OS.linux, Architecture.arm64) => 'linux/js_linux_arm64.so',
    (OS.linux, Architecture.x64) => 'linux/js_linux_x64.so',
    (OS.windows, Architecture.x64) => 'windows/js_windows_x64.dll',
    _ => null,
  };
}
