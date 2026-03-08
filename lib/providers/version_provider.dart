// lib/providers/version_provider.dart

import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../models/app_version.dart';
import '../services/version_service.dart';

class VersionProvider with ChangeNotifier {
  final VersionService _versionService = VersionService();
  
  AppVersion? _versionConfig;
  UpdateStatus _updateStatus = UpdateStatus.upToDate;
  bool _isCheckingForUpdates = false;
  String _errorMessage = '';
  String _currentAppVersion = '1.0.0';
  bool _hasCheckedToday = false;

  // Getters
  AppVersion? get versionConfig => _versionConfig;
  UpdateStatus get updateStatus => _updateStatus;
  bool get isCheckingForUpdates => _isCheckingForUpdates;
  String get errorMessage => _errorMessage;
  String get currentAppVersion => _currentAppVersion;
  bool get hasCheckedToday => _hasCheckedToday;

  // Estados de actualización
  bool get requiresForceUpdate => _updateStatus == UpdateStatus.forceUpdate;
  bool get hasOptionalUpdate => _updateStatus == UpdateStatus.optionalUpdate;
  bool get isInMaintenance => _updateStatus == UpdateStatus.maintenance;
  bool get isUpToDate => _updateStatus == UpdateStatus.upToDate;
  bool get hasError => _updateStatus == UpdateStatus.error;

  /// Inicializa el provider obteniendo la versión actual
  Future<void> initialize() async {
    try {
      _currentAppVersion = await _versionService.getCurrentAppVersion();
      developer.log('VersionProvider inicializado - Versión actual: $_currentAppVersion', name: 'VersionProvider');
      notifyListeners();
    } catch (e) {
      developer.log('Error inicializando VersionProvider: $e', name: 'VersionProvider', error: e);
      _errorMessage = 'Error inicializando verificador de versiones';
      notifyListeners();
    }
  }

  /// Verifica si hay actualizaciones disponibles
  Future<void> checkForUpdates({bool force = false}) async {
    if (_isCheckingForUpdates && !force) return;

    _isCheckingForUpdates = true;
    _errorMessage = '';
    notifyListeners();

    try {
      developer.log('Verificando actualizaciones...', name: 'VersionProvider');
      
      // Obtener configuración de versión
      _versionConfig = await _versionService.getVersionConfig();
      
      if (_versionConfig == null) {
        _updateStatus = UpdateStatus.error;
        _errorMessage = 'No se pudo obtener la configuración de versión';
        developer.log('Error: No se pudo obtener configuración de versión', name: 'VersionProvider');
      } else {
        // Verificar estado de actualización
        _updateStatus = await _versionService.checkForUpdates();
        _hasCheckedToday = true;
        
        developer.log('Estado de actualización: $_updateStatus', name: 'VersionProvider');
        
        // Log detallado según el estado
        switch (_updateStatus) {
          case UpdateStatus.forceUpdate:
            developer.log('🚨 ACTUALIZACIÓN OBLIGATORIA requerida', name: 'VersionProvider');
            break;
          case UpdateStatus.optionalUpdate:
            developer.log('✨ Actualización opcional disponible', name: 'VersionProvider');
            break;
          case UpdateStatus.maintenance:
            developer.log('🔧 Aplicación en modo mantenimiento', name: 'VersionProvider');
            break;
          case UpdateStatus.upToDate:
            developer.log('✅ Aplicación actualizada', name: 'VersionProvider');
            break;
          case UpdateStatus.error:
            developer.log('❌ Error verificando actualizaciones', name: 'VersionProvider');
            break;
        }
      }
    } catch (e) {
      _updateStatus = UpdateStatus.error;
      _errorMessage = 'Error verificando actualizaciones: $e';
      developer.log('Error en checkForUpdates: $e', name: 'VersionProvider', error: e);
    } finally {
      _isCheckingForUpdates = false;
      notifyListeners();
    }
  }

  /// Abre la URL de actualización
  Future<bool> openUpdateUrl() async {
    if (_versionConfig == null) {
      developer.log('No hay configuración de versión para abrir URL', name: 'VersionProvider');
      return false;
    }

    try {
      developer.log('Abriendo URL de actualización...', name: 'VersionProvider');
      final success = await _versionService.openUpdateUrl(_versionConfig!);
      
      if (success) {
        developer.log('✅ URL de actualización abierta exitosamente', name: 'VersionProvider');
      } else {
        developer.log('❌ Error abriendo URL de actualización', name: 'VersionProvider');
        _errorMessage = 'No se pudo abrir el enlace de actualización';
        notifyListeners();
      }
      
      return success;
    } catch (e) {
      developer.log('Error abriendo URL de actualización: $e', name: 'VersionProvider', error: e);
      _errorMessage = 'Error abriendo enlace de actualización: $e';
      notifyListeners();
      return false;
    }
  }

  /// Muestra dialog de actualización opcional
  Future<bool> showOptionalUpdateDialog(BuildContext context) async {
    if (_versionConfig == null) return false;

    try {
      return await _versionService.showOptionalUpdateDialog(context, _versionConfig!);
    } catch (e) {
      developer.log('Error mostrando dialog de actualización: $e', name: 'VersionProvider', error: e);
      return false;
    }
  }

  /// Obtiene información detallada de la app
  Future<Map<String, String>> getAppInfo() async {
    try {
      return await _versionService.getAppInfo();
    } catch (e) {
      developer.log('Error obteniendo información de la app: $e', name: 'VersionProvider', error: e);
      return {};
    }
  }

  /// Solicita permisos para descarga
  Future<bool> requestDownloadPermissions() async {
    try {
      return await _versionService.requestDownloadPermissions();
    } catch (e) {
      developer.log('Error solicitando permisos: $e', name: 'VersionProvider', error: e);
      return false;
    }
  }

  /// Reintenta la verificación de actualizaciones
  Future<void> retryUpdateCheck() async {
    developer.log('Reintentando verificación de actualizaciones...', name: 'VersionProvider');
    await checkForUpdates(force: true);
  }

  /// Limpia el estado de error
  void clearError() {
    if (_errorMessage.isNotEmpty) {
      _errorMessage = '';
      notifyListeners();
    }
  }

  /// Marca que se pospondrá la actualización opcional
  void postponeOptionalUpdate() {
    if (_updateStatus == UpdateStatus.optionalUpdate) {
      developer.log('Actualización opcional pospuesta por el usuario', name: 'VersionProvider');
      // Podrías implementar lógica para no mostrar nuevamente hoy
    }
  }

  /// Fuerza una nueva verificación ignorando cache
  Future<void> forceUpdateCheck() async {
    _hasCheckedToday = false;
    await checkForUpdates(force: true);
  }

  /// Resetea el provider a su estado inicial
  void reset() {
    _versionConfig = null;
    _updateStatus = UpdateStatus.upToDate;
    _isCheckingForUpdates = false;
    _errorMessage = '';
    _hasCheckedToday = false;
    developer.log('VersionProvider reseteado', name: 'VersionProvider');
    notifyListeners();
  }

  /// Getter para obtener el mensaje apropiado según el estado
  String get statusMessage {
    switch (_updateStatus) {
      case UpdateStatus.upToDate:
        return 'Tu aplicación está actualizada';
      case UpdateStatus.optionalUpdate:
        return _versionConfig?.updateMessage ?? 'Hay una nueva versión disponible';
      case UpdateStatus.forceUpdate:
        return 'Es necesario actualizar la aplicación para continuar';
      case UpdateStatus.maintenance:
        return _versionConfig?.maintenanceMessage ?? 'La aplicación está en mantenimiento';
      case UpdateStatus.error:
        return _errorMessage.isNotEmpty ? _errorMessage : 'Error verificando actualizaciones';
    }
  }

  /// Getter para verificar si se puede usar la app
  bool get canUseApp {
    return _updateStatus != UpdateStatus.forceUpdate && 
           _updateStatus != UpdateStatus.maintenance;
  }

  /// Obtiene el progreso de carga (útil para UI)
  double get loadingProgress {
    if (!_isCheckingForUpdates) return 1.0;
    return 0.0; // Indeterminado mientras carga
  }
}