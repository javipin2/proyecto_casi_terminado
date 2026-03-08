// lib/services/version_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer' as developer;
import '../models/app_version.dart';

class VersionService {
  static const String _collectionName = 'app_config';
  static const String _documentId = 'version_control';
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Obtiene la información de versión actual de la app
  Future<String> getCurrentAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      developer.log('Error obteniendo versión de la app: $e', name: 'VersionService');
      return '1.0.0'; // Versión por defecto
    }
  }

  /// Obtiene el build number de la app
  Future<String> getCurrentBuildNumber() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.buildNumber;
    } catch (e) {
      developer.log('Error obteniendo build number: $e', name: 'VersionService');
      return '1';
    }
  }

  /// Obtiene la configuración de versión desde Firestore
  Future<AppVersion?> getVersionConfig() async {
    try {
      developer.log('Consultando configuración de versión...', name: 'VersionService');
      
      final doc = await _firestore
          .collection(_collectionName)
          .doc(_documentId)
          .get();

      if (!doc.exists) {
        developer.log('Documento de configuración no existe, creando configuración por defecto', name: 'VersionService');
        await _createDefaultVersionConfig();
        return await getVersionConfig(); // Recursión para obtener la configuración recién creada
      }

      final data = doc.data() as Map<String, dynamic>;
      final version = AppVersion.fromFirestore(data);
      
      developer.log('Configuración obtenida - Versión actual: ${version.currentVersion}, Mínima requerida: ${version.minimumRequiredVersion}, Fuerza actualización: ${version.forceUpdate}', name: 'VersionService');
      
      return version;
    } catch (e) {
      developer.log('Error consultando configuración de versión: $e', name: 'VersionService', error: e);
      return null;
    }
  }

  /// Crea una configuración por defecto si no existe
  Future<void> _createDefaultVersionConfig() async {
    try {
      final currentVersion = await getCurrentAppVersion();
      
      final defaultConfig = AppVersion(
        currentVersion: currentVersion,
        minimumRequiredVersion: currentVersion,
        forceUpdate: false,
        updateMessage: 'Nueva versión disponible con mejoras importantes',
        downloadUrl: 'https://tu-servidor.com/app-release.apk', // Cambia por tu URL real
        isPlayStoreAvailable: false,
        playStoreUrl: 'https://play.google.com/store/apps/details?id=com.tuempresa.reserva_canchas',
        lastUpdated: DateTime.now(),
        newFeatures: [
          'Mejoras en la interfaz de usuario',
          'Corrección de errores menores',
          'Optimización de rendimiento'
        ],
        maintenanceMode: false,
        maintenanceMessage: 'La aplicación está temporalmente en mantenimiento. Intenta más tarde.',
      );

      await _firestore
          .collection(_collectionName)
          .doc(_documentId)
          .set(defaultConfig.toFirestore());

      developer.log('Configuración por defecto creada exitosamente', name: 'VersionService');
    } catch (e) {
      developer.log('Error creando configuración por defecto: $e', name: 'VersionService', error: e);
    }
  }

  /// Verifica si la app necesita actualización
  Future<UpdateStatus> checkForUpdates() async {
    try {
      final currentVersion = await getCurrentAppVersion();
      final versionConfig = await getVersionConfig();

      if (versionConfig == null) {
        return UpdateStatus.error;
      }

      // Verificar modo mantenimiento
      if (versionConfig.maintenanceMode) {
        return UpdateStatus.maintenance;
      }

      // Verificar actualización obligatoria
      if (versionConfig.forceUpdate && 
          versionConfig.requiresUpdate(currentVersion)) {
        return UpdateStatus.forceUpdate;
      }

      // Verificar actualización opcional
      if (versionConfig.hasNewVersion(currentVersion)) {
        return UpdateStatus.optionalUpdate;
      }

      return UpdateStatus.upToDate;
    } catch (e) {
      developer.log('Error verificando actualizaciones: $e', name: 'VersionService', error: e);
      return UpdateStatus.error;
    }
  }

  /// Actualiza la configuración de versión en Firestore
  Future<bool> updateVersionConfig(AppVersion newConfig) async {
    try {
      await _firestore
          .collection(_collectionName)
          .doc(_documentId)
          .set(newConfig.toFirestore());

      developer.log('Configuración de versión actualizada exitosamente', name: 'VersionService');
      return true;
    } catch (e) {
      developer.log('Error actualizando configuración: $e', name: 'VersionService', error: e);
      return false;
    }
  }

  /// Abre la URL de descarga o Play Store
  Future<bool> openUpdateUrl(AppVersion versionConfig) async {
    try {
      String url;
      
      if (versionConfig.isPlayStoreAvailable && versionConfig.playStoreUrl.isNotEmpty) {
        url = versionConfig.playStoreUrl;
        developer.log('Abriendo Play Store: $url', name: 'VersionService');
      } else if (versionConfig.downloadUrl.isNotEmpty) {
        url = versionConfig.downloadUrl;
        developer.log('Abriendo enlace de descarga directa: $url', name: 'VersionService');
      } else {
        developer.log('No hay URL de actualización disponible', name: 'VersionService');
        return false;
      }

      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        return true;
      } else {
        developer.log('No se puede abrir la URL: $url', name: 'VersionService');
        return false;
      }
    } catch (e) {
      developer.log('Error abriendo URL de actualización: $e', name: 'VersionService', error: e);
      return false;
    }
  }

  /// Solicita permisos necesarios para la descarga
  Future<bool> requestDownloadPermissions() async {
    try {
      // En Android 10+ ya no se necesita WRITE_EXTERNAL_STORAGE para descargas
      // Pero verificamos por compatibilidad
      final status = await Permission.storage.status;
      
      if (status.isDenied) {
        final result = await Permission.storage.request();
        return result.isGranted;
      }
      
      return status.isGranted;
    } catch (e) {
      developer.log('Error solicitando permisos: $e', name: 'VersionService', error: e);
      return true; // Asumir que está bien si hay error
    }
  }

  /// Obtiene información detallada de la app
  Future<Map<String, String>> getAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return {
        'appName': packageInfo.appName,
        'packageName': packageInfo.packageName,
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
        'buildSignature': packageInfo.buildSignature,
      };
    } catch (e) {
      developer.log('Error obteniendo información de la app: $e', name: 'VersionService', error: e);
      return {
        'appName': 'Reserva Canchas',
        'packageName': 'com.example.reserva_canchas',
        'version': '1.0.0',
        'buildNumber': '1',
        'buildSignature': '',
      };
    }
  }

  /// Muestra un dialog de confirmación para actualización opcional
  Future<bool> showOptionalUpdateDialog(BuildContext context, AppVersion versionConfig) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '🚀 Actualización Disponible',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(versionConfig.updateMessage),
              const SizedBox(height: 16),
              if (versionConfig.newFeatures.isNotEmpty) ...[
                const Text(
                  'Nuevas características:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...versionConfig.newFeatures.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(feature)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Más tarde'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D60),
                foregroundColor: Colors.white,
              ),
              child: const Text('Actualizar'),
            ),
          ],
        );
      },
    ) ?? false;
  }
}

/// Estados posibles para las actualizaciones
enum UpdateStatus {
  upToDate,      // App está actualizada
  optionalUpdate, // Hay actualización opcional
  forceUpdate,   // Actualización obligatoria
  maintenance,   // Modo mantenimiento
  error,         // Error verificando
}