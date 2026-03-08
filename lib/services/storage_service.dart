import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _userKey = 'user_data';
  static const String _authKey = 'auth_token';
  static const String _loginCredentialsKey = 'login_credentials';
  static const String _rememberMeKey = 'remember_me';

  /// Convierte un mapa (p. ej. de Firestore) a uno encodable con jsonEncode.
  static Map<String, dynamic> _toEncodableMap(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      result[entry.key] = _toEncodableValue(entry.value);
    }
    return result;
  }

  static dynamic _toEncodableValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) return _toEncodableMap(Map<String, dynamic>.from(value));
    if (value is List) return value.map(_toEncodableValue).toList();
    return value;
  }

  /// Guardar datos del usuario
  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    try {
      final encodable = _toEncodableMap(userData);
      if (kIsWeb) {
        // En web, usar localStorage a través de SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, jsonEncode(encodable));
      } else {
        // En móvil, usar SharedPreferences normalmente
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, jsonEncode(encodable));
      }
    } catch (e) {
      debugPrint('Error guardando datos del usuario: $e');
    }
  }

  /// Cargar datos del usuario
  static Future<Map<String, dynamic>?> loadUserData() async {
    try {
      if (kIsWeb) {
        // En web, usar localStorage a través de SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final userDataString = prefs.getString(_userKey);
        
        if (userDataString != null) {
          return jsonDecode(userDataString);
        }
      } else {
        // En móvil, usar SharedPreferences normalmente
        final prefs = await SharedPreferences.getInstance();
        final userDataString = prefs.getString(_userKey);
        
        if (userDataString != null) {
          return jsonDecode(userDataString);
        }
      }
    } catch (e) {
      debugPrint('Error cargando datos del usuario: $e');
    }
    return null;
  }

  /// Limpiar datos del usuario
  static Future<void> clearUserData() async {
    try {
      if (kIsWeb) {
        // En web, limpiar localStorage
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_userKey);
        await prefs.remove(_authKey);
      } else {
        // En móvil, limpiar SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_userKey);
        await prefs.remove(_authKey);
      }
    } catch (e) {
      debugPrint('Error limpiando datos del usuario: $e');
    }
  }

  /// Guardar token de autenticación
  static Future<void> saveAuthToken(String token) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_authKey, token);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_authKey, token);
      }
    } catch (e) {
      debugPrint('Error guardando token de autenticación: $e');
    }
  }

  /// Cargar token de autenticación
  static Future<String?> loadAuthToken() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_authKey);
      } else {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_authKey);
      }
    } catch (e) {
      debugPrint('Error cargando token de autenticación: $e');
    }
    return null;
  }

  /// Verificar si hay datos de usuario guardados
  static Future<bool> hasUserData() async {
    try {
      final userData = await loadUserData();
      return userData != null && userData.isNotEmpty;
    } catch (e) {
      debugPrint('Error verificando datos del usuario: $e');
      return false;
    }
  }

  /// Obtener información específica del usuario
  static Future<String?> getUserRole() async {
    try {
      final userData = await loadUserData();
      return userData?['rol'] as String?;
    } catch (e) {
      debugPrint('Error obteniendo rol del usuario: $e');
      return null;
    }
  }

  /// Obtener nombre del usuario
  static Future<String?> getUserName() async {
    try {
      final userData = await loadUserData();
      return userData?['name'] ?? userData?['nombre'] as String?;
    } catch (e) {
      debugPrint('Error obteniendo nombre del usuario: $e');
      return null;
    }
  }

  /// Obtener email del usuario
  static Future<String?> getUserEmail() async {
    try {
      final userData = await loadUserData();
      return userData?['email'] as String?;
    } catch (e) {
      debugPrint('Error obteniendo email del usuario: $e');
      return null;
    }
  }

  /// Guardar credenciales de login
  static Future<void> saveLoginCredentials(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credentials = {
        'email': email,
        'password': password,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_loginCredentialsKey, jsonEncode(credentials));
    } catch (e) {
      debugPrint('Error guardando credenciales de login: $e');
    }
  }

  /// Cargar credenciales de login guardadas
  static Future<Map<String, String>?> loadLoginCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credentialsString = prefs.getString(_loginCredentialsKey);
      
      if (credentialsString != null) {
        final credentials = jsonDecode(credentialsString) as Map<String, dynamic>;
        
        // Verificar que las credenciales no sean muy antiguas (30 días)
        final timestamp = credentials['timestamp'] as int?;
        if (timestamp != null) {
          final savedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final now = DateTime.now();
          final difference = now.difference(savedDate);
          
          if (difference.inDays <= 30) {
            return {
              'email': credentials['email'] as String,
              'password': credentials['password'] as String,
            };
          } else {
            // Credenciales muy antiguas, limpiarlas
            await clearLoginCredentials();
          }
        }
      }
    } catch (e) {
      debugPrint('Error cargando credenciales de login: $e');
    }
    return null;
  }

  /// Limpiar credenciales de login
  static Future<void> clearLoginCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_loginCredentialsKey);
    } catch (e) {
      debugPrint('Error limpiando credenciales de login: $e');
    }
  }

  /// Guardar preferencia de "Recordarme"
  static Future<void> saveRememberMe(bool remember) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMeKey, remember);
    } catch (e) {
      debugPrint('Error guardando preferencia de recordar: $e');
    }
  }

  /// Cargar preferencia de "Recordarme"
  static Future<bool> loadRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_rememberMeKey) ?? false;
    } catch (e) {
      debugPrint('Error cargando preferencia de recordar: $e');
      return false;
    }
  }

  /// Verificar si hay credenciales guardadas
  static Future<bool> hasSavedCredentials() async {
    try {
      final credentials = await loadLoginCredentials();
      return credentials != null && credentials.isNotEmpty;
    } catch (e) {
      debugPrint('Error verificando credenciales guardadas: $e');
      return false;
    }
  }
}
