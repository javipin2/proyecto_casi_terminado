import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Helper para obtener el lugarId del usuario autenticado
class LugarHelper {
  static String? _cachedLugarId;
  static String? _cachedUserId;

  /// Obtener el lugarId del usuario autenticado
  static Future<String?> getLugarId() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      // Si es el mismo usuario y ya tenemos el lugarId en caché, devolverlo
      if (_cachedUserId == user.uid && _cachedLugarId != null) {
        return _cachedLugarId;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final lugarId = userData['lugarId'] as String?;
        
        // Guardar en caché
        _cachedLugarId = lugarId;
        _cachedUserId = user.uid;
        
        debugPrint('LugarHelper: LugarId obtenido: $lugarId para usuario: ${user.uid}');
        return lugarId;
      }
      
      debugPrint('LugarHelper: Usuario no encontrado en Firestore');
      return null;
    } catch (e) {
      debugPrint('LugarHelper: Error obteniendo lugarId: $e');
      return null;
    }
  }

  /// Obtener el rol del usuario autenticado
  static Future<String?> getUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final rol = userData['rol'] as String?;
        debugPrint('LugarHelper: Rol obtenido: $rol para usuario: ${user.uid}');
        return rol;
      }
      
      return null;
    } catch (e) {
      debugPrint('LugarHelper: Error obteniendo rol: $e');
      return null;
    }
  }

  /// Verificar si el usuario es programador
  static Future<bool> isProgramador() async {
    final rol = await getUserRole();
    return rol == 'programador';
  }

  /// Limpiar caché (usar al cerrar sesión)
  static void clearCache() {
    _cachedLugarId = null;
    _cachedUserId = null;
    debugPrint('LugarHelper: Caché limpiado');
  }

  /// Obtener lugarId con validación de acceso
  static Future<String?> getLugarIdWithValidation(String? targetLugarId) async {
    final userLugarId = await getLugarId();
    final isProgramadorUser = await isProgramador();
    
    // Si es programador, puede acceder a cualquier lugar
    if (isProgramadorUser) {
      return targetLugarId ?? userLugarId;
    }
    
    // Para otros roles, solo pueden acceder a su lugar
    if (userLugarId == null) {
      debugPrint('LugarHelper: Usuario sin lugarId asignado');
      return null;
    }
    
    // Si se especifica un lugar objetivo, verificar que coincida
    if (targetLugarId != null && targetLugarId != userLugarId) {
      debugPrint('LugarHelper: Usuario no autorizado para lugar $targetLugarId');
      return null;
    }
    
    return userLugarId;
  }
}
