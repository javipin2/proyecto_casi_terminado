// lib/models/app_version.dart

class AppVersion {
  final String currentVersion;
  final String minimumRequiredVersion;
  final bool forceUpdate;
  final String updateMessage;
  final String downloadUrl;
  final bool isPlayStoreAvailable;
  final String playStoreUrl;
  final DateTime? lastUpdated;
  final List<String> newFeatures;
  final bool maintenanceMode;
  final String maintenanceMessage;

  const AppVersion({
    required this.currentVersion,
    required this.minimumRequiredVersion,
    this.forceUpdate = false,
    this.updateMessage = 'Nueva versión disponible',
    this.downloadUrl = '',
    this.isPlayStoreAvailable = false,
    this.playStoreUrl = '',
    this.lastUpdated,
    this.newFeatures = const [],
    this.maintenanceMode = false,
    this.maintenanceMessage = 'La aplicación está en mantenimiento',
  });

  factory AppVersion.fromFirestore(Map<String, dynamic> data) {
    return AppVersion(
      currentVersion: data['current_version'] ?? '1.0.0',
      minimumRequiredVersion: data['minimum_required_version'] ?? '1.0.0',
      forceUpdate: data['force_update'] ?? false,
      updateMessage: data['update_message'] ?? 'Nueva versión disponible',
      downloadUrl: data['download_url'] ?? '',
      isPlayStoreAvailable: data['is_play_store_available'] ?? false,
      playStoreUrl: data['play_store_url'] ?? '',
      lastUpdated: data['last_updated']?.toDate(),
      newFeatures: List<String>.from(data['new_features'] ?? []),
      maintenanceMode: data['maintenance_mode'] ?? false,
      maintenanceMessage: data['maintenance_message'] ?? 'La aplicación está en mantenimiento',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'current_version': currentVersion,
      'minimum_required_version': minimumRequiredVersion,
      'force_update': forceUpdate,
      'update_message': updateMessage,
      'download_url': downloadUrl,
      'is_play_store_available': isPlayStoreAvailable,
      'play_store_url': playStoreUrl,
      'last_updated': lastUpdated,
      'new_features': newFeatures,
      'maintenance_mode': maintenanceMode,
      'maintenance_message': maintenanceMessage,
    };
  }

  /// Compara versiones usando el formato estándar x.y.z
  bool isVersionGreaterThan(String version1, String version2) {
    List<int> v1Parts = version1.split('.').map(int.parse).toList();
    List<int> v2Parts = version2.split('.').map(int.parse).toList();

    // Asegurar que ambas versiones tengan 3 partes
    while (v1Parts.length < 3) {
      v1Parts.add(0);
    }
    while (v2Parts.length < 3) {
      v2Parts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (v1Parts[i] > v2Parts[i]) return true;
      if (v1Parts[i] < v2Parts[i]) return false;
    }
    return false;
  }

  /// Verifica si la versión actual requiere actualización
  bool requiresUpdate(String currentAppVersion) {
    return isVersionGreaterThan(minimumRequiredVersion, currentAppVersion);
  }

  /// Verifica si hay una nueva versión disponible
  bool hasNewVersion(String currentAppVersion) {
    return isVersionGreaterThan(currentVersion, currentAppVersion);
  }

  AppVersion copyWith({
    String? currentVersion,
    String? minimumRequiredVersion,
    bool? forceUpdate,
    String? updateMessage,
    String? downloadUrl,
    bool? isPlayStoreAvailable,
    String? playStoreUrl,
    DateTime? lastUpdated,
    List<String>? newFeatures,
    bool? maintenanceMode,
    String? maintenanceMessage,
  }) {
    return AppVersion(
      currentVersion: currentVersion ?? this.currentVersion,
      minimumRequiredVersion: minimumRequiredVersion ?? this.minimumRequiredVersion,
      forceUpdate: forceUpdate ?? this.forceUpdate,
      updateMessage: updateMessage ?? this.updateMessage,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      isPlayStoreAvailable: isPlayStoreAvailable ?? this.isPlayStoreAvailable,
      playStoreUrl: playStoreUrl ?? this.playStoreUrl,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      newFeatures: newFeatures ?? this.newFeatures,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      maintenanceMessage: maintenanceMessage ?? this.maintenanceMessage,
    );
  }
}