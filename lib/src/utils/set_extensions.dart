/// Extension methods for [Set].
extension SetExtensions<E> on Set<E> {
  /// Returns true if this set intersects with [other].
  ///
  /// Complexity: O(min(n, m)) where n and m are the set sizes.
  bool intersects(Set<E> other) {
    if (length <= other.length) {
      for (final value in this) {
        if (other.contains(value)) return true;
      }
      return false;
    }

    for (final value in other) {
      if (contains(value)) return true;
    }
    return false;
  }
}
