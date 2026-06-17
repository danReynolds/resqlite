// Helpers for converting hook file URIs to native file-system paths.
//
// Lives under lib/ (not hook/) because pub.dev only permits `build.dart` and
// `link.dart` inside a package's hook/ directory. The build hook imports these
// via a `package:resqlite/...` URI.

String packageFilePath(Uri packageRoot, String relativePath, {bool? windows}) {
  return packageRoot.resolve(relativePath).toFilePath(windows: windows);
}

String outputFilePath(Uri outputDirectory, String fileName, {bool? windows}) {
  return outputDirectory.resolve(fileName).toFilePath(windows: windows);
}
