// lib/services/cleanup_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class CleanupService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Configuración de limpieza
  static const int DIAS_RETENCION = 30; // Mantener datos por 30 días
  static const String COLLECTION_AUDIT = 'audit_logs';
  
  /// Ejecuta la limpieza automática de datos antiguos
  static Future<Map<String, int>> ejecutarLimpiezaAutomatica() async {
    try {
      // No ejecutar si no hay usuario autenticado
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('⏭️ Limpieza omitida: no hay usuario autenticado');
        }
        return {};
      }

      if (kDebugMode) {
        print('🚀 Iniciando limpieza automática...');
      }
      
      // Verificar autenticación
      await _verificarAutenticacion();
      
      final resultados = <String, int>{};
      
      // Limpiar logs de auditoría
      final auditEliminados = await _limpiarAuditLogs();
      resultados['audit_eliminados'] = auditEliminados;
      
      // Registrar la limpieza en el log
      await _registrarLimpieza(resultados);
      
      if (kDebugMode) {
        print('🧹 Limpieza automática completada:');
        print('   - Audit logs eliminados: $auditEliminados');
      }
      
      return resultados;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error en limpieza automática: $e');
        print('   Tipo de error: ${e.runtimeType}');
        if (e.toString().contains('permission-denied')) {
          print('   🔥 ERROR DE PERMISOS: Verificar reglas de Firestore');
          print('   💡 Solución: Aplicar reglas simplificadas de firestore_cleanup_rules.txt');
        }
      }
      rethrow;
    }
  }
  
  /// Verifica que el usuario esté autenticado y tenga permisos
  static Future<void> _verificarAutenticacion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuario no autenticado. Debe estar logueado para ejecutar limpieza.');
    }
    
    if (kDebugMode) {
      print('👤 Usuario autenticado: ${user.uid}');
    }
    
    // Verificar rol del usuario
    try {
      final userDoc = await _firestore
          .collection('usuarios')
          .doc(user.uid)
          .get();
      
      if (!userDoc.exists) {
        throw Exception('Usuario no encontrado en la base de datos');
      }
      
      final userData = userDoc.data()!;
      final rol = userData['rol'] as String?;
      
      if (rol == null || !['admin', 'superadmin'].contains(rol)) {
        throw Exception('Usuario no tiene permisos de limpieza. Rol actual: $rol');
      }
      
      if (kDebugMode) {
        print('✅ Usuario autorizado con rol: $rol');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error verificando permisos: $e');
      }
      rethrow;
    }
  }
  
  /// Limpia logs de auditoría antiguos
  static Future<int> _limpiarAuditLogs() async {
    try {
      final fechaLimite = DateTime.now().subtract(Duration(days: DIAS_RETENCION));
      
      if (kDebugMode) {
        print('🧹 Limpiando audit logs anteriores a: ${fechaLimite.toString()}');
      }
      
      // Obtener documentos antiguos
      final query = await _firestore
          .collection(COLLECTION_AUDIT)
          .where('timestamp', isLessThan: Timestamp.fromDate(fechaLimite))
          .limit(500) // Procesar en lotes para evitar timeouts
          .get();
      
      if (query.docs.isEmpty) {
        if (kDebugMode) {
          print('✅ No hay audit logs antiguos para eliminar');
        }
        return 0;
      }
      
      if (kDebugMode) {
        print('📊 Encontrados ${query.docs.length} audit logs antiguos');
      }
      
      // Eliminar en lotes de 100
      int eliminados = 0;
      final docs = query.docs;
      
      for (int i = 0; i < docs.length; i += 100) {
        final batch = _firestore.batch();
        final endIndex = (i + 100 < docs.length) ? i + 100 : docs.length;
        
        for (int j = i; j < endIndex; j++) {
          batch.delete(docs[j].reference);
          eliminados++;
        }
        
        try {
          await batch.commit();
          if (kDebugMode) {
            print('✅ Eliminados ${endIndex - i} audit logs (lote ${(i ~/ 100) + 1})');
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error en lote de audit logs: $e');
          }
          // Continuar con el siguiente lote
        }
      }
      
      if (kDebugMode) {
        print('✅ Total audit logs eliminados: $eliminados');
      }
      
      return eliminados;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error limpiando audit logs: $e');
      }
      return 0;
    }
  }
  
  /// Registra la limpieza realizada
  static Future<void> _registrarLimpieza(Map<String, int> resultados) async {
    try {
      await _firestore.collection('cleanup_logs').add({
        'fecha': Timestamp.now(),
        'tipo': 'automatica',
        'resultados': resultados,
        'dias_retencion': DIAS_RETENCION,
        'total_eliminados': resultados.values.fold(0, (sum, count) => sum + count),
      });
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error registrando limpieza: $e');
      }
    }
  }
  
  /// Obtiene estadísticas de datos antiguos
  static Future<Map<String, int>> obtenerEstadisticasAntiguos() async {
    try {
      final fechaLimite = DateTime.now().subtract(Duration(days: DIAS_RETENCION));
      
      // Contar audit logs antiguos
      final auditQuery = await _firestore
          .collection(COLLECTION_AUDIT)
          .where('timestamp', isLessThan: Timestamp.fromDate(fechaLimite))
          .get();
      
      return {
        'audit_antiguos': auditQuery.docs.length,
        'total_antiguos': auditQuery.docs.length,
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error obteniendo estadísticas: $e');
      }
      return {'audit_antiguos': 0, 'total_antiguos': 0};
    }
  }
  
  /// Ejecuta limpieza manual (desde la UI)
  static Future<Map<String, int>> ejecutarLimpiezaManual() async {
    try {
      final resultados = await ejecutarLimpiezaAutomatica();
      
      // Registrar como limpieza manual
      await _firestore.collection('cleanup_logs').add({
        'fecha': Timestamp.now(),
        'tipo': 'manual',
        'resultados': resultados,
        'dias_retencion': DIAS_RETENCION,
        'total_eliminados': resultados.values.fold(0, (sum, count) => sum + count),
      });
      
      return resultados;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error en limpieza manual: $e');
      }
      rethrow;
    }
  }
  
  /// Programa la limpieza automática (se ejecuta al iniciar la app)
  static void programarLimpiezaAutomatica() {
    // Verificar si ya se ejecutó la limpieza hoy
    _verificarLimpiezaDiaria();
  }
  
  /// Verifica si se debe ejecutar la limpieza diaria
  static Future<void> _verificarLimpiezaDiaria() async {
    try {
      // No ejecutar si no hay usuario autenticado
      if (FirebaseAuth.instance.currentUser == null) return;

      final hoy = DateTime.now();
      final inicioDia = DateTime(hoy.year, hoy.month, hoy.day, 0, 0, 0);
      
      // Verificar si ya se ejecutó limpieza hoy
      final query = await _firestore
          .collection('cleanup_logs')
          .where('fecha', isGreaterThan: Timestamp.fromDate(inicioDia))
          .where('tipo', isEqualTo: 'automatica')
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) {
        // No se ha ejecutado limpieza hoy, ejecutarla
        await ejecutarLimpiezaAutomatica();
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error verificando limpieza diaria: $e');
      }
    }
  }
}
