import 'dart:collection';

/// LRU Cache for recently visited paths
/// Used to penalize frequently visited directories in random video playback
class LruPathCache {
  final int _capacity;
  final LinkedHashMap<String, bool> _cache = LinkedHashMap();

  LruPathCache({int capacity = 30}) : _capacity = capacity;

  /// Add a path to the cache (marks it as recently visited)
  void add(String path) {
    if (_cache.containsKey(path)) {
      // Move to end (most recent)
      _cache.remove(path);
    } else if (_cache.length >= _capacity) {
      // Remove oldest entry
      _cache.remove(_cache.keys.first);
    }
    _cache[path] = true;
  }

  /// Check if a path is in the cache (recently visited)
  bool contains(String path) {
    return _cache.containsKey(path);
  }

  /// Get all paths in the cache
  List<String> get paths => _cache.keys.toList();

  /// Clear the cache
  void clear() {
    _cache.clear();
  }

  /// Get cache size
  int get size => _cache.length;
}
