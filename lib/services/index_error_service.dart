import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class IndexErrorService {
  
  /// Intercepta errores de Firestore y detecta si son errores de índices
  static void handleFirestoreError(dynamic error, String operation) {
    if (error is FirebaseException) {
      if (error.code == 'failed-precondition') {
        _handleIndexError(error, operation);
      } else {
        debugPrint('❌ Error de Firestore en $operation: ${error.message}');
      }
    } else {
      debugPrint('❌ Error general en $operation: $error');
    }
  }
  
  /// Maneja específicamente errores de índices
  static void _handleIndexError(FirebaseException error, String operation) {
    final message = error.message ?? '';
    
    if (message.contains('index') || message.contains('query')) {
      debugPrint('\n🔥 ===== ERROR DE ÍNDICE DETECTADO =====');
      debugPrint('📋 Operación: $operation');
      debugPrint('❌ Error: ${error.message}');
      debugPrint('🔗 Código: ${error.code}');
      
      // Extraer información del error para crear el índice
      _extractIndexInfo(message);
      
      debugPrint('💡 SOLUCIÓN:');
      debugPrint('1. Ve a Firebase Console > Firestore > Indexes');
      debugPrint('2. Crea un índice compuesto con los campos sugeridos');
      debugPrint('3. O ejecuta el comando de Firebase CLI mostrado arriba');
      debugPrint('==========================================\n');
    }
  }
  
  /// Extrae información del error para sugerir la creación del índice
  static void _extractIndexInfo(String errorMessage) {
    try {
      // Buscar patrones comunes en errores de índices
      if (errorMessage.contains('where') && errorMessage.contains('orderBy')) {
        debugPrint('📊 ÍNDICE COMPUESTO NECESARIO:');
        
        // Extraer campos de where y orderBy
        final whereMatch = RegExp(r'where\(([^)]+)\)').firstMatch(errorMessage);
        final orderByMatch = RegExp(r'orderBy\(([^)]+)\)').firstMatch(errorMessage);
        
        if (whereMatch != null) {
          debugPrint('   🔍 Campos WHERE: ${whereMatch.group(1)}');
        }
        
        if (orderByMatch != null) {
          debugPrint('   📈 Campos ORDER BY: ${orderByMatch.group(1)}');
        }
        
        debugPrint('\n🛠️  COMANDO FIREBASE CLI:');
        debugPrint('firebase firestore:indexes');
        
      } else if (errorMessage.contains('array-contains')) {
        debugPrint('📊 ÍNDICE DE ARRAY NECESARIO:');
        debugPrint('   🔍 Campo con array-contains detectado');
        debugPrint('\n🛠️  COMANDO FIREBASE CLI:');
        debugPrint('firebase firestore:indexes');
      }
      
    } catch (e) {
      debugPrint('⚠️  No se pudo extraer información detallada del error');
    }
  }
  
  /// Wrapper para operaciones de Firestore que detecta errores de índices
  static Future<T> executeWithIndexErrorHandling<T>(
    Future<T> Function() operation,
    String operationName,
  ) async {
    try {
      return await operation();
    } catch (error) {
      handleFirestoreError(error, operationName);
      rethrow;
    }
  }
  
  /// Método específico para queries que comúnmente requieren índices
  static Future<QuerySnapshot> queryWithIndexHandling(
    Query query,
    String collectionName,
  ) async {
    return await executeWithIndexErrorHandling(
      () => query.get(),
      'Query en $collectionName',
    );
  }
  
  /// Método para detectar y mostrar índices faltantes en tiempo real
  static void logIndexRequirements(String collection, List<String> whereFields, List<String> orderByFields) {
    if (whereFields.isNotEmpty || orderByFields.isNotEmpty) {
      debugPrint('\n📋 REQUISITOS DE ÍNDICE PARA $collection:');
      
      if (whereFields.isNotEmpty) {
        debugPrint('   🔍 WHERE fields: ${whereFields.join(', ')}');
      }
      
      if (orderByFields.isNotEmpty) {
        debugPrint('   📈 ORDER BY fields: ${orderByFields.join(', ')}');
      }
      
      debugPrint('💡 Asegúrate de que existe un índice compuesto para estos campos');
      debugPrint('🛠️  Verifica en: Firebase Console > Firestore > Indexes\n');
    }
  }
  
  /// Genera un reporte de índices necesarios basado en el uso de la app
  static void generateIndexReport() {
    debugPrint('\n📊 ===== REPORTE DE ÍNDICES NECESARIOS =====');
    debugPrint('🔍 Colecciones que requieren índices:');
    debugPrint('');
    
    debugPrint('📁 CIUDADES:');
    debugPrint('   - Índice: activa (ascending) + nombre (ascending)');
    debugPrint('   - Uso: Listar ciudades activas ordenadas por nombre');
    debugPrint('');
    
    debugPrint('📁 LUGARES:');
    debugPrint('   - Índice: ciudadId (ascending) + activo (ascending) + nombre (ascending)');
    debugPrint('   - Uso: Listar lugares por ciudad, activos, ordenados por nombre');
    debugPrint('');
    
    debugPrint('📁 SEDES:');
    debugPrint('   - Índice: lugarId (ascending) + activa (ascending) + nombre (ascending)');
    debugPrint('   - Uso: Listar sedes por lugar, activas, ordenadas por nombre');
    debugPrint('');
    
    debugPrint('📁 USUARIOS:');
    debugPrint('   - Índice: lugarId (ascending) + activo (ascending)');
    debugPrint('   - Índice: rol (ascending) + activo (ascending)');
    debugPrint('   - Uso: Filtrar usuarios por lugar y rol');
    debugPrint('');
    
    debugPrint('📁 RESERVAS:');
    debugPrint('   - Índice: cancha_id (ascending) + fecha (ascending)');
    debugPrint('   - Índice: estado (ascending) + fecha (ascending)');
    debugPrint('   - Uso: Consultas de disponibilidad y estado');
    debugPrint('');
    
    debugPrint('📁 AUDIT_LOGS:');
    debugPrint('   - Índice: timestamp (descending) + usuario_id (ascending)');
    debugPrint('   - Índice: accion (ascending) + timestamp (descending)');
    debugPrint('   - Uso: Auditoría y logs del sistema');
    debugPrint('');
    
    debugPrint('🛠️  COMANDOS PARA CREAR ÍNDICES:');
    debugPrint('firebase firestore:indexes');
    debugPrint('==========================================\n');
  }
}
