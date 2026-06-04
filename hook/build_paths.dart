// Helpers for converting hook file URIs to native file-system paths.

String packageFilePath(Uri packageRoot, String relativePath, {bool? windows}) {
  return packageRoot.resolve(relativePath).toFilePath(windows: windows);
}

String outputFilePath(Uri outputDirectory, String fileName, {bool? windows}) {
  return outputDirectory.resolve(fileName).toFilePath(windows: windows);
}
