import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/version.dart';

class VersionService {
  List<Version>? _cachedVersions;

  Future<List<Version>> loadVersions() async {
    if (_cachedVersions != null) {
      return _cachedVersions!;
    }

    try {
      final jsonString = await rootBundle.loadString('assets/data/versions.json');
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      final versionsList = jsonData['versions'] as List;
      _cachedVersions = versionsList
          .map((versionJson) => Version.fromJson(versionJson))
          .toList();
      return _cachedVersions!;
    } catch (e) {
      throw Exception('Failed to load versions: $e');
    }
  }

  Future<Version?> getVersionById(String id) async {
    final versions = await loadVersions();
    try {
      return versions.firstWhere((v) => v.id == id);
    } catch (e) {
      return null;
    }
  }

  void clearCache() {
    _cachedVersions = null;
  }
}
