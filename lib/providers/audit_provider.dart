// lib/providers/audit_provider_mejorado.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/audit_log.dart';
import '../services/lugar_helper.dart';
import '../utils/reserva_audit_utils.dart'; // Para acceder a UmbralesRiesgo

class AuditProvider with ChangeNotifier {
  List<AuditEntry> _auditEntries = [];
  bool _isLoading = false;
  String _errorMessage = '';
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String _filtroAccion = 'todas';
  String _filtroRiesgo = 'todos';
  String _filtroUsuario = 'todos';

  // Cache para optimización
  Map<String, dynamic>? _estadisticasCache;
  DateTime? _ultimaActualizacionCache;
  
  // ✅ CORRECCIÓN: Timer para debounce en filtros automáticos
  Timer? _debounceTimer;
  
  // ✅ CORRECCIÓN: Completer para evitar consultas concurrentes
  Completer<void>? _cargaCompleter;

  // ✅ NUEVO: Soporte de paginación
  DocumentSnapshot? _ultimoDocumento; // Último documento cargado para paginación
  bool _tieneMasResultados = true; // Indica si hay más resultados en Firestore

  // Getters
  List<AuditEntry> get auditEntries => _auditEntries;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  DateTime? get fechaInicio => _fechaInicio;
  DateTime? get fechaFin => _fechaFin;
  String get filtroAccion => _filtroAccion;
  String get filtroRiesgo => _filtroRiesgo;
  String get filtroUsuario => _filtroUsuario;
  bool get tieneMasResultados => _tieneMasResultados;

  // Filtros aplicados con mejor rendimiento
  List<AuditEntry> get entriesFiltradas {
    List<AuditEntry> filtradas = List.from(_auditEntries);

    // Aplicar filtros en orden de selectividad
    if (_filtroRiesgo != 'todos') {
      filtradas = filtradas.where((entry) => entry.nivelRiesgo == _filtroRiesgo).toList();
    }

    if (_filtroAccion != 'todas') {
      filtradas = filtradas.where((entry) => entry.accion == _filtroAccion).toList();
    }

    if (_filtroUsuario != 'todos') {
      filtradas = filtradas.where((entry) => entry.usuarioId == _filtroUsuario).toList();
    }

    if (_fechaInicio != null && _fechaFin != null) {
      final inicio = DateTime(_fechaInicio!.year, _fechaInicio!.month, _fechaInicio!.day, 0, 0, 0);
      final fin = DateTime(_fechaFin!.year, _fechaFin!.month, _fechaFin!.day, 23, 59, 59, 999);
      filtradas = filtradas.where((entry) {
        final fecha = entry.timestamp.toDate();
        return !fecha.isBefore(inicio) && !fecha.isAfter(fin);
      }).toList();
    }

    return filtradas;
  }

  // Estadísticas mejoradas con cache
  Map<String, dynamic> get estadisticas {
    // Verificar cache
    if (_estadisticasCache != null && 
        _ultimaActualizacionCache != null &&
        DateTime.now().difference(_ultimaActualizacionCache!).inMinutes < 5) {
      return _estadisticasCache!;
    }

    final entries = entriesFiltradas;
    final estadisticasCalculadas = {
      'total': entries.length,
      'critico': entries.where((e) => e.nivelRiesgo == 'critico').length,
      'alto': entries.where((e) => e.nivelRiesgo == 'alto').length,
      'medio': entries.where((e) => e.nivelRiesgo == 'medio').length,
      'bajo': entries.where((e) => e.nivelRiesgo == 'bajo').length,
      'porAccion': _agruparPorAccion(entries),
      'porUsuario': _agruparPorUsuario(entries),
      'porFecha': _agruparPorFecha(entries),
      'tendencias': _calcularTendencias(entries),
      'alertasActivas': entries.where((e) => e.tieneAlertas).length,
      'impactoFinanciero': _calcularImpactoFinanciero(entries),
    };

    _estadisticasCache = estadisticasCalculadas;
    _ultimaActualizacionCache = DateTime.now();

    return estadisticasCalculadas;
  }

  /// Cargar auditoría con filtros mejorados y optimizaciones
  Future<void> cargarAuditoria({
    int limite = 100, // Página inicial más pequeña para mejor rendimiento
    bool forzarRecarga = false,
  }) async {
    // ✅ CORRECCIÓN: Si ya hay una carga en progreso, esperar a que termine
    if (_cargaCompleter != null && !forzarRecarga) {
      return _cargaCompleter!.future;
    }
    
    if (_isLoading && !forzarRecarga) {
      // Si hay una carga en progreso y no es forzada, esperar a que termine
      if (_cargaCompleter != null) {
        return _cargaCompleter!.future;
      }
      return;
    }

    // ✅ CORRECCIÓN: Crear nuevo completer para esta carga
    _cargaCompleter = Completer<void>();
    
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // Obtener el lugarId del usuario autenticado
      final lugarId = await LugarHelper.getLugarId();
      if (lugarId == null) {
        _errorMessage = 'No se pudo obtener el lugar del usuario';
        debugPrint('AuditProvider: No se pudo obtener lugarId');
        _isLoading = false;
        // Completar el completer incluso en caso de error temprano
        _cargaCompleter?.completeError('No se pudo obtener lugarId');
        _cargaCompleter = null;
        notifyListeners();
        return;
      }

      // Construir consulta base optimizada
      Query query = FirebaseFirestore.instance
          .collection('auditoria')
          .where('lugarId', isEqualTo: lugarId);

      // OPTIMIZACIÓN: Aplicar filtros de fecha PRIMERO (más selectivo)
      // Esto reduce significativamente el número de documentos a procesar
      if (_fechaInicio != null && _fechaFin != null) {
        final inicio = DateTime(_fechaInicio!.year, _fechaInicio!.month, _fechaInicio!.day, 0, 0, 0);
        final fin = DateTime(_fechaFin!.year, _fechaFin!.month, _fechaFin!.day, 23, 59, 59, 999);
        
        // Validar que las fechas sean válidas
        if (inicio.isAfter(fin)) {
          _errorMessage = 'Rango de fechas inválido';
          debugPrint('AuditProvider: Fechas inválidas - inicio: $inicio, fin: $fin');
          _isLoading = false;
          notifyListeners();
          return;
        }

        query = query
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(fin));
      }

      // Aplicar filtro de riesgo si está activo (después de fecha para mejor índice)
      if (_filtroRiesgo != 'todos') {
        query = query.where('nivel_riesgo', isEqualTo: _filtroRiesgo);
      }

      // Ordenar y limitar (después de todos los filtros)
      query = query.orderBy('timestamp', descending: true).limit(limite);

      // Ejecutar consulta con timeout
      final querySnapshot = await query.get().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('La consulta tardó demasiado tiempo');
        },
      );

      // Procesar resultados
      _auditEntries = querySnapshot.docs
          .map((doc) {
            try {
              return AuditEntry.fromFirestore(doc);
            } catch (e) {
              debugPrint('Error al parsear documento ${doc.id}: $e');
              return null;
            }
          })
          .whereType<AuditEntry>()
          .toList();

      // Debug: Log de resultados
      debugPrint('AuditProvider: Cargadas ${_auditEntries.length} entradas. Filtros: fecha=${_fechaInicio != null && _fechaFin != null}, riesgo=${_filtroRiesgo}');

      // Invalidar cache de estadísticas
      _estadisticasCache = null;
      _ultimaActualizacionCache = DateTime.now();
      
      // Reiniciar estado de paginación
      if (querySnapshot.docs.isNotEmpty) {
        _ultimoDocumento = querySnapshot.docs.last;
        // Si se reciben menos documentos que el límite, asumimos que no hay más
        _tieneMasResultados = querySnapshot.docs.length >= limite;
      } else {
        _ultimoDocumento = null;
        _tieneMasResultados = false;
      }
      
      // ✅ CORRECCIÓN: Completar el completer cuando termine la carga exitosamente
      _cargaCompleter?.complete();
      _cargaCompleter = null;

    } on TimeoutException catch (e) {
      _errorMessage = 'La consulta tardó demasiado tiempo. Intenta con un rango de fechas más pequeño.';
      debugPrint('AuditProvider Timeout: $e');
      // ✅ CORRECCIÓN: Completar el completer incluso en caso de error
      _cargaCompleter?.completeError(e);
      _cargaCompleter = null;
    } catch (e) {
      _errorMessage = 'Error al cargar auditoría: $e';
      debugPrint('AuditProvider Error: $_errorMessage');
      debugPrint('Stack trace: ${StackTrace.current}');
      // ✅ CORRECCIÓN: Completar el completer incluso en caso de error
      _cargaCompleter?.completeError(e);
      _cargaCompleter = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ✅ NUEVO: Cargar más auditoría (paginación)
  Future<void> cargarMasAuditoria({
    int limite = 100,
  }) async {
    // Si ya estamos cargando, o no hay más resultados, salir
    if (_isLoading || !_tieneMasResultados || _ultimoDocumento == null) return;

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final lugarId = await LugarHelper.getLugarId();
      if (lugarId == null) {
        _errorMessage = 'No se pudo obtener el lugar del usuario';
        debugPrint('AuditProvider: No se pudo obtener lugarId (paginación)');
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Construir la misma consulta base que en cargarAuditoria
      Query query = FirebaseFirestore.instance
          .collection('auditoria')
          .where('lugarId', isEqualTo: lugarId);

      // Aplicar filtros de fecha
      if (_fechaInicio != null && _fechaFin != null) {
        final inicio = DateTime(_fechaInicio!.year, _fechaInicio!.month, _fechaInicio!.day, 0, 0, 0);
        final fin = DateTime(_fechaFin!.year, _fechaFin!.month, _fechaFin!.day, 23, 59, 59, 999);

        if (inicio.isAfter(fin)) {
          _errorMessage = 'Rango de fechas inválido';
          debugPrint('AuditProvider (paginación): Fechas inválidas - inicio: $inicio, fin: $fin');
          _isLoading = false;
          notifyListeners();
          return;
        }

        query = query
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(fin));
      }

      // Filtro de riesgo
      if (_filtroRiesgo != 'todos') {
        query = query.where('nivel_riesgo', isEqualTo: _filtroRiesgo);
      }

      // Orden, paginación y límite
      query = query
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_ultimoDocumento!)
          .limit(limite);

      final querySnapshot = await query.get().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('La consulta de paginación tardó demasiado tiempo');
        },
      );

      final nuevos = querySnapshot.docs
          .map((doc) {
            try {
              return AuditEntry.fromFirestore(doc);
            } catch (e) {
              debugPrint('Error al parsear documento (paginación) ${doc.id}: $e');
              return null;
            }
          })
          .whereType<AuditEntry>()
          .toList();

      _auditEntries.addAll(nuevos);

      // Actualizar estado de paginación
      if (querySnapshot.docs.isNotEmpty) {
        _ultimoDocumento = querySnapshot.docs.last;
        _tieneMasResultados = querySnapshot.docs.length >= limite;
      } else {
        _tieneMasResultados = false;
      }

      // Invalidar cache de estadísticas
      _estadisticasCache = null;
      _ultimaActualizacionCache = DateTime.now();

      debugPrint('AuditProvider: Cargadas ${nuevos.length} entradas adicionales. Total: ${_auditEntries.length}');
    } on TimeoutException catch (e) {
      _errorMessage = 'La consulta de paginación tardó demasiado tiempo. Intenta más tarde.';
      debugPrint('AuditProvider Paginación Timeout: $e');
    } catch (e) {
      _errorMessage = 'Error al cargar más auditoría: $e';
      debugPrint('AuditProvider Paginación Error: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Aplicar filtros con validación y recarga automática con debounce
  Future<void> aplicarFiltros({
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? accion,
    String? nivelRiesgo,
    String? usuario,
    bool usarDebounce = true, // ✅ CORRECCIÓN: Permitir desactivar debounce si es necesario
  }) async {
    // Validar fechas
    if (fechaInicio != null && fechaFin != null && fechaInicio.isAfter(fechaFin)) {
      _errorMessage = 'La fecha de inicio no puede ser posterior a la fecha fin';
      notifyListeners();
      return;
    }

    // Detectar si cambiaron los filtros que requieren recarga de Firestore
    final fechaCambio = _fechaInicio != fechaInicio || _fechaFin != fechaFin;
    final riesgoCambio = _filtroRiesgo != (nivelRiesgo ?? 'todos');
    
    _fechaInicio = fechaInicio;
    _fechaFin = fechaFin;
    _filtroAccion = accion ?? 'todas';
    _filtroRiesgo = nivelRiesgo ?? 'todos';
    _filtroUsuario = usuario ?? 'todos';

    // Invalidar cache
    _estadisticasCache = null;

    // ✅ CORRECCIÓN: Si cambiaron filtros que afectan Firestore, usar debounce para evitar múltiples consultas
    if (fechaCambio || riesgoCambio) {
      if (usarDebounce) {
        // Cancelar timer anterior si existe
        _debounceTimer?.cancel();
        
        // Crear nuevo timer con debounce de 400ms
        _debounceTimer = Timer(Duration(milliseconds: 400), () async {
          await cargarAuditoria(forzarRecarga: true);
        });
      } else {
        // Si no se usa debounce, cargar inmediatamente
        await cargarAuditoria(forzarRecarga: true);
      }
    } else {
      notifyListeners();
    }
  }

  /// Limpiar filtros y recargar datos
  Future<void> limpiarFiltros() async {
    _fechaInicio = null;
    _fechaFin = null;
    _filtroAccion = 'todas';
    _filtroRiesgo = 'todos';
    _filtroUsuario = 'todos';
    _estadisticasCache = null;
    await cargarAuditoria(forzarRecarga: true);
  }

  /// MÉTODO PRINCIPAL CORREGIDO - Registrar acción sin duplicar análisis
  static Future<void> registrarAccion({
    required String accion,
    required String entidad,
    required String entidadId,
    Map<String, dynamic>? datosAntiguos,
    Map<String, dynamic>? datosNuevos,
    Map<String, dynamic>? metadatos,
    String? descripcion,
    String? nivelRiesgoForzado,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Obtener datos del usuario con cache
      final userData = await _obtenerDatosUsuario(user.uid);

      // Obtener lugarId del usuario autenticado para etiquetar auditoría y alertas
      final lugarId = await LugarHelper.getLugarId();

      // DECISIÓN CLAVE: Detectar si viene de ReservaAuditUtils
      final esDesdeReservaUtils = metadatos?.containsKey('nivel_riesgo_calculado') == true ||
                                 metadatos?.containsKey('cambios_detectados') == true ||
                                 metadatos?.containsKey('alertas_generadas') == true ||
                                 metadatos?.containsKey('_audit_processed') == true;

      Map<String, dynamic> analisisRiesgo;
      String nivelRiesgoFinal;
      String descripcionFinal;
      
      if (esDesdeReservaUtils) {
        // CASO 1: Viene de ReservaAuditUtils - Usar análisis ya realizado
        analisisRiesgo = _extraerAnalisisDeReservaUtils(metadatos!);
        nivelRiesgoFinal = nivelRiesgoForzado ?? analisisRiesgo['nivel'];
        descripcionFinal = descripcion ?? 'Operación de reserva procesada';
        
        debugPrint('🔄 Auditoría desde ReservaAuditUtils: $accion [${nivelRiesgoFinal.toUpperCase()}]');
      } else {
        // CASO 2: Auditoría directa - Hacer análisis completo
        analisisRiesgo = _analizarRiesgoMejorado(
          accion: accion,
          entidad: entidad,
          datosAntiguos: datosAntiguos,
          datosNuevos: datosNuevos,
          metadatos: metadatos,
        );
        nivelRiesgoFinal = nivelRiesgoForzado ?? analisisRiesgo['nivel'];
        descripcionFinal = descripcion ?? _generarDescripcionMejorada(
          accion: accion,
          entidad: entidad,
          datosAntiguos: datosAntiguos,
          datosNuevos: datosNuevos,
          metadatos: metadatos,
          analisisRiesgo: analisisRiesgo,
        );
        
        debugPrint('🔍 Auditoría directa: $accion [${nivelRiesgoFinal.toUpperCase()}]');
      }

      // Obtener información de contexto
      final contextoAdicional = await _obtenerContextoAdicional(accion, entidad, entidadId);

      final auditEntry = {
        'accion': accion,
        'entidad': entidad,
        'entidad_id': entidadId,
        'usuario_id': user.uid,
        'usuario_nombre': userData['nombre'],
        'usuario_rol': userData['rol'],
        'timestamp': Timestamp.now(),
        'lugarId': lugarId,
        'datos_antiguos': datosAntiguos ?? {},
        'datos_nuevos': datosNuevos ?? {},
        'metadatos': {
          ...metadatos ?? {},
          ...contextoAdicional,
          'version_sistema': '2.0',
          'fuente_analisis': esDesdeReservaUtils ? 'ReservaAuditUtils' : 'AuditProvider',
          'analisis_duplicado': false, // Marcador para confirmar que no hay duplicación
        },
        'descripcion': descripcionFinal,
        'nivel_riesgo': nivelRiesgoFinal,
        'alertas': analisisRiesgo['alertas'] ?? [],
        'cambios_detectados': analisisRiesgo['cambios'] ?? [],
        'puntuacion_riesgo': analisisRiesgo['puntuacion_riesgo'] ?? 0,
        'ip_address': await _obtenerIP(),
        'user_agent': 'Flutter App v2.0',
        'dispositivo_info': await _obtenerInfoDispositivo(),
      };

      // Guardar en Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('auditoria')
          .add(auditEntry);

      // Procesar alertas críticas
      if (nivelRiesgoFinal == 'critico') {
        await _procesarAlertaCritica(auditEntry, docRef.id);
      }

      debugPrint('✅ Auditoría registrada exitosamente: $accion');

    } catch (e) {
      debugPrint('❌ Error registrando auditoría: $e');
    }
  }




  /// Extraer análisis ya realizado por ReservaAuditUtils
static Map<String, dynamic> _extraerAnalisisDeReservaUtils(Map<String, dynamic> metadatos) {
  // Extraer información del análisis completo realizado en ReservaAuditUtils
  final alertasGeneradas = List<String>.from(metadatos['alertas_generadas'] ?? []);
  final cambiosDetectados = List<String>.from(metadatos['cambios_detectados'] ?? []);
  final nivelRiesgoCalculado = metadatos['nivel_riesgo_calculado'] ?? 'bajo';
  final esCambioCritico = metadatos['esCambioCriticoPrecios'] ?? false;
  final porcentajeCambio = (metadatos['porcentaje_cambio_precio'] ?? 0.0) as double;

  // Calcular puntuación basada en el análisis existente
  int puntuacionRiesgo = 0;
  
  switch (nivelRiesgoCalculado) {
    case 'critico':
      puntuacionRiesgo = 85;
      break;
    case 'alto':
      puntuacionRiesgo = 65;
      break;
    case 'medio':
      puntuacionRiesgo = 40;
      break;
    case 'bajo':
      puntuacionRiesgo = 15;
      break;
  }

  // Ajustar puntuación según cambios críticos
  if (esCambioCritico) {
    puntuacionRiesgo += 10;
  }

  return {
    'nivel': nivelRiesgoCalculado,
    'alertas': alertasGeneradas,
    'cambios': cambiosDetectados,
    'puntuacion_riesgo': puntuacionRiesgo,
    'es_cambio_critico': esCambioCritico,
    'porcentaje_cambio': porcentajeCambio,
    'fuente': 'ReservaAuditUtils',
  };
}





  /// ✅ Análisis de riesgo mejorado - SOLO para entidades que NO son reservas
  /// Usa umbrales unificados importados de ReservaAuditUtils
  static Map<String, dynamic> _analizarRiesgoMejorado({
    required String accion,
    required String entidad,
    Map<String, dynamic>? datosAntiguos,
    Map<String, dynamic>? datosNuevos,
    Map<String, dynamic>? metadatos,
  }) {
    // VALIDACIÓN CRÍTICA: Solo analizar entidades que NO sean reservas
    if (entidad.contains('reserva')) {
      debugPrint('⚠️ ADVERTENCIA: Se intentó analizar reserva en AuditProvider. Esto debería venir de ReservaAuditUtils');
      return {
        'nivel': 'bajo', 
        'cambios': <String>[], 
        'puntuacion_riesgo': 0
      };
    }

    num puntuacionRiesgo = 0;
    List<String> alertas = [];
    List<String> cambios = [];

    // 1. Análisis por tipo de acción (peso base: 20 puntos)
    puntuacionRiesgo += _analizarRiesgoPorAccion(accion, alertas);

    // 2. Análisis de cambios de datos (peso: 40 puntos)
    if (datosAntiguos != null && datosNuevos != null) {
      final analisisCambios = _analizarCambiosDatos(datosAntiguos, datosNuevos);
      puntuacionRiesgo += analisisCambios['puntuacion'];
      alertas.addAll(analisisCambios['alertas']);
      cambios.addAll(analisisCambios['cambios']);
    }

    // 3. Análisis de contexto temporal (peso: 15 puntos)
    puntuacionRiesgo += _analizarContextoTemporal(metadatos, alertas);

    // 4. Análisis de patrones de usuario (peso: 15 puntos)
    puntuacionRiesgo += _analizarPatronesUsuario(accion, alertas);

    // 5. Análisis de impacto financiero (peso: 10 puntos)
    puntuacionRiesgo += _analizarImpactoFinanciero(datosAntiguos, datosNuevos, alertas);

    // ✅ Determinar nivel de riesgo con UMBRALES UNIFICADOS
    String nivelRiesgo;
    final puntuacionInt = puntuacionRiesgo.toInt();
    if (puntuacionInt >= UmbralesRiesgo.critico) {
      nivelRiesgo = 'critico';
    } else if (puntuacionInt >= UmbralesRiesgo.alto) {
      nivelRiesgo = 'alto';
    } else if (puntuacionInt >= UmbralesRiesgo.medio) {
      nivelRiesgo = 'medio';
    } else {
      nivelRiesgo = 'bajo';
    }

    debugPrint('🔍 Análisis de riesgo para $entidad: Nivel $nivelRiesgo ($puntuacionInt puntos)');

    return {
      'nivel': nivelRiesgo,
      'alertas': alertas,
      'cambios': cambios,
      'puntuacion_riesgo': puntuacionInt,
      'factores_analizados': {
        'accion': true,
        'cambios_datos': datosAntiguos != null && datosNuevos != null,
        'contexto_temporal': true,
        'patrones_usuario': true,
        'impacto_financiero': true,
      },
    };
  }




  /// Análisis de riesgo por tipo de acción
  static int _analizarRiesgoPorAccion(String accion, List<String> alertas) {
    switch (accion) {
      case 'eliminar_reserva':
      case 'eliminar_reserva_impacto_alto':
        alertas.add('Eliminación de reserva detectada');
        return 25;
      
      case 'editar_reserva_precio_critico':
      case 'crear_reserva_descuento_alto':
        alertas.add('Operación financiera crítica');
        return 30;
      
      case 'cancelar_reserva_recurrente':
      case 'eliminar_reserva_masivo':
        alertas.add('Operación masiva detectada');
        return 20;
      
      case 'editar_precio_reserva_recurrente':
        alertas.add('Modificación de precio en reserva recurrente');
        return 25;
        
      case 'crear_reserva_sospechosa':
        alertas.add('Patrones sospechosos en creación');
        return 35;
      
      case 'crear_reserva_precio_personalizado':
      case 'editar_reserva':
        return 10;
      
      default:
        return 5;
    }
  }

  /// Análisis de cambios en datos
  static Map<String, dynamic> _analizarCambiosDatos(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    int puntuacion = 0;
    List<String> alertas = [];
    List<String> cambios = [];

    // Análisis de cambios de precio
    final precioAnterior = _extraerPrecio(datosAntiguos);
    final precioNuevo = _extraerPrecio(datosNuevos);
    
    if (precioAnterior != null && precioNuevo != null && precioAnterior != precioNuevo) {
      final diferencia = precioNuevo - precioAnterior;
      final porcentaje = precioAnterior > 0 ? (diferencia / precioAnterior * 100).abs() : 0;
      
      cambios.add('Precio: ${NumberFormat('#,##0', 'es_CO').format(precioAnterior)} → ${NumberFormat('#,##0', 'es_CO').format(precioNuevo)}');
      
      if (porcentaje >= 70) {
        alertas.add('CAMBIO DE PRECIO EXTREMO: ${porcentaje.toStringAsFixed(1)}%');
        puntuacion += 40;
      } else if (porcentaje >= 50) {
        alertas.add('Cambio de precio crítico: ${porcentaje.toStringAsFixed(1)}%');
        puntuacion += 35;
      } else if (porcentaje >= 30) {
        alertas.add('Cambio de precio significativo: ${porcentaje.toStringAsFixed(1)}%');
        puntuacion += 25;
      } else if (porcentaje >= 15) {
        alertas.add('Cambio de precio moderado: ${porcentaje.toStringAsFixed(1)}%');
        puntuacion += 15;
      } else {
        puntuacion += 5;
      }
    }

    // Análisis de otros cambios importantes
    final camposImportantes = ['fecha', 'horario', 'cancha_id', 'sede'];
    int cambiosImportantes = 0;
    
    for (String campo in camposImportantes) {
      if (datosAntiguos[campo] != datosNuevos[campo]) {
        cambiosImportantes++;
        cambios.add('$campo modificado');
      }
    }
    
    if (cambiosImportantes >= 3) {
      alertas.add('MÚLTIPLES CAMBIOS SIMULTÁNEOS: $cambiosImportantes');
      puntuacion += 20;
    } else if (cambiosImportantes >= 2) {
      alertas.add('Cambios múltiples detectados');
      puntuacion += 10;
    }

    return {
      'puntuacion': puntuacion,
      'alertas': alertas,
      'cambios': cambios,
    };
  }

  /// ✅ Análisis de contexto temporal - CORREGIDO horario laboral (5am-11pm)
  static int _analizarContextoTemporal(Map<String, dynamic>? metadatos, List<String> alertas) {
    int puntuacion = 0;
    final ahora = DateTime.now();
    
    // ✅ CORREGIDO: Horario laboral es 5am-11pm (no 6am-11pm)
    // Solo alertar si es fuera de horario laboral (11pm-5am)
    if (ahora.hour < 5 || ahora.hour >= 23) {
      alertas.add('Operación fuera de horario laboral (11pm-5am)');
      puntuacion += 15;
    }
    
    // ✅ ELIMINADO: Fines de semana NO son sospechosos (se trabaja igual)
    // Los fines de semana son horario laboral normal
    
    // Verificar proximidad de fecha de reserva si está disponible
    if (metadatos != null && metadatos.containsKey('fecha_reserva')) {
      try {
        final fechaReserva = DateTime.parse(metadatos['fecha_reserva'].toString());
        final diferencia = fechaReserva.difference(ahora).inDays;
        
        if (diferencia <= 0) {
          alertas.add('Modificación de reserva para fecha pasada o hoy');
          puntuacion += 15;
        } else if (diferencia == 1) {
          alertas.add('Modificación de reserva para mañana');
          puntuacion += 10;
        }
      } catch (e) {
        // Ignorar errores de parsing
      }
    }
    
    return puntuacion;
  }

  /// ✅ Análisis de patrones de usuario - MEJORADO (implementación básica)
  static int _analizarPatronesUsuario(String accion, List<String> alertas) {
    // TODO: Implementación completa requeriría consultar historial de auditoría
    // Por ahora, análisis básico basado en el tipo de acción
    
    // Acciones que indican patrones sospechosos si se repiten
    final accionesSospechosas = [
      'eliminar_reserva',
      'eliminar_reserva_impacto_alto',
      'editar_reserva_precio_critico',
      'crear_reserva_sospechosa',
    ];
    
    if (accionesSospechosas.contains(accion)) {
      // Estas acciones ya tienen puntuación alta por sí solas
      // El análisis de patrones agregaría puntos adicionales si se repiten
      // Por ahora retornamos 0, pero la estructura está lista para mejoras futuras
      return 0;
    }
    
    return 0;
  }

  /// Análisis de impacto financiero
  static int _analizarImpactoFinanciero(
    Map<String, dynamic>? datosAntiguos,
    Map<String, dynamic>? datosNuevos,
    List<String> alertas,
  ) {
    int puntuacion = 0;
    
    if (datosAntiguos != null && datosNuevos != null) {
      final precioAnterior = _extraerPrecio(datosAntiguos) ?? 0;
      final precioNuevo = _extraerPrecio(datosNuevos) ?? 0;
      final diferencia = (precioNuevo - precioAnterior).abs();
      
      if (diferencia >= 100000) {
        alertas.add('ALTO IMPACTO FINANCIERO: ${NumberFormat('#,##0', 'es_CO').format(diferencia)}');
        puntuacion += 10;
      } else if (diferencia >= 50000) {
        alertas.add('Impacto financiero significativo');
        puntuacion += 5;
      }
    }
    
    return puntuacion;
  }

  /// Generar descripción mejorada
  static String _generarDescripcionMejorada({
    required String accion,
    required String entidad,
    Map<String, dynamic>? datosAntiguos,
    Map<String, dynamic>? datosNuevos,
    Map<String, dynamic>? metadatos,
    Map<String, dynamic>? analisisRiesgo,
  }) {
    // Obtener información básica
    final cliente = datosNuevos?['nombre'] ?? datosAntiguos?['nombre'] ?? 'Cliente';
    final cancha = metadatos?['cancha_nombre'] ?? 'Cancha';
    
    String descripcion = '';
    
    // Prefijo según nivel de riesgo
    final nivelRiesgo = analisisRiesgo?['nivel'] ?? 'bajo';
    if (nivelRiesgo == 'critico') {
      descripcion += '🚨 ';
    } else if (nivelRiesgo == 'alto') descripcion += '🔴 ';
    else if (nivelRiesgo == 'medio') descripcion += '🟡 ';
    
    // Descripción base según acción
    switch (accion) {
      case 'crear_reserva':
        descripcion += 'Reserva creada para $cliente en $cancha';
        break;
      case 'crear_reserva_precio_personalizado':
        descripcion += 'Reserva con precio personalizado creada para $cliente';
        break;
      case 'crear_reserva_sospechosa':
        descripcion += 'RESERVA SOSPECHOSA creada para $cliente';
        break;
      case 'editar_reserva':
        descripcion += 'Reserva de $cliente editada';
        break;
      case 'editar_reserva_precio_critico':
        descripcion += 'EDICIÓN CRÍTICA de reserva de $cliente';
        break;
      case 'eliminar_reserva':
        descripcion += 'Reserva de $cliente eliminada';
        break;
      case 'eliminar_reserva_impacto_alto':
        descripcion += 'ELIMINACIÓN DE ALTO IMPACTO: reserva de $cliente';
        break;
      default:
        descripcion += 'Acción $accion realizada';
    }
    
    // Añadir información de cambios si está disponible
    final cambios = analisisRiesgo?['cambios'] as List<String>?;
    if (cambios != null && cambios.isNotEmpty) {
      if (cambios.length == 1) {
        descripcion += ' (${cambios.first})';
      } else if (cambios.length <= 3) {
        descripcion += ' (${cambios.join(', ')})';
      } else {
        descripcion += ' (${cambios.take(2).join(', ')} +${cambios.length - 2} más)';
      }
    }
    
    return descripcion;
  }

  /// Obtener datos del usuario con cache
  static final Map<String, Map<String, dynamic>> _cacheUsuarios = {};
  
  static Future<Map<String, dynamic>> _obtenerDatosUsuario(String userId) async {
    if (_cacheUsuarios.containsKey(userId)) {
      return _cacheUsuarios[userId]!;
    }
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userId)
          .get();

      final userData = userDoc.data() ?? {};
      final resultado = {
        'nombre': userData['nombre'] ?? userData['name'] ?? 'Usuario desconocido',
        'rol': userData['rol'] ?? 'usuario',
      };
      
      _cacheUsuarios[userId] = resultado;
      return resultado;
    } catch (e) {
      return {'nombre': 'Usuario desconocido', 'rol': 'usuario'};
    }
  }

  /// Obtener contexto adicional
  static Future<Map<String, dynamic>> _obtenerContextoAdicional(
    String accion,
    String entidad,
    String entidadId,
  ) async {
    final contexto = <String, dynamic>{};
    
    // Obtener información adicional según el tipo de entidad
    if (entidad == 'reserva' || entidad == 'reserva_recurrente') {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(entidad == 'reserva' ? 'reservas' : 'reservas_recurrentes')
            .doc(entidadId)
            .get();
            
        if (doc.exists) {
          final data = doc.data()!;
          final sedeId = data['sede'];
          String? sedeNombre;
          
          // Obtener nombre de la sede si es un ID
          if (sedeId != null && sedeId.toString().length > 10) {
            try {
              final sedeDoc = await FirebaseFirestore.instance
                  .collection('sedes')
                  .doc(sedeId)
                  .get();
              if (sedeDoc.exists) {
                sedeNombre = sedeDoc.data()?['nombre'];
              }
            } catch (e) {
              // Ignorar errores
            }
          }
          
          contexto.addAll({
            'sede': sedeNombre ?? sedeId,
            'cancha_nombre': data['cancha_nombre'],
            'fecha': data['fecha'],
            'estado': data['estado'],
            'cliente_nombre': data['cliente_nombre'] ?? data['nombre'],
            'horario': data['horario'],
          });
        }
      } catch (e) {
        // Ignorar errores
      }
    }
    
    return contexto;
  }

  /// Procesar alerta crítica mejorada
  static Future<void> _procesarAlertaCritica(
    Map<String, dynamic> auditEntry,
    String auditEntryId,
  ) async {
    try {
      // Crear alerta crítica mejorada
      await FirebaseFirestore.instance
          .collection('alertas_criticas')
          .add({
        'audit_entry_id': auditEntryId,
        'titulo': _generarTituloAlerta(auditEntry),
        'descripcion': auditEntry['descripcion'],
        'usuario': auditEntry['usuario_nombre'],
        'usuario_id': auditEntry['usuario_id'],
        'accion': auditEntry['accion'],
        'entidad': auditEntry['entidad'],
        'entidad_id': auditEntry['entidad_id'],
        'timestamp': auditEntry['timestamp'],
        'alertas': auditEntry['alertas'],
        'puntuacion_riesgo': auditEntry['puntuacion_riesgo'],
        'metadatos': auditEntry['metadatos'],
        'leida': false,
        'nivel': 'critico',
        'prioridad': _calcularPrioridadAlerta(auditEntry),
        'requiere_accion': true,
        'fecha_expiracion': Timestamp.fromDate(
          DateTime.now().add(Duration(days: 7)),
        ),
      });
      
      // Enviar notificación push si está configurado
      await _enviarNotificacionPush(auditEntry);
      
      debugPrint('🚨 Alerta crítica procesada: ${auditEntry['accion']}');
    } catch (e) {
      debugPrint('❌ Error procesando alerta crítica: $e');
    }
  }

  static String _generarTituloAlerta(Map<String, dynamic> auditEntry) {
    final accion = auditEntry['accion'];
    final usuario = auditEntry['usuario_nombre'];
    
    switch (accion) {
      case 'editar_reserva_precio_critico':
        return 'PRECIO CRÍTICO: $usuario modificó precio drásticamente';
      case 'eliminar_reserva_impacto_alto':
        return 'ELIMINACIÓN CRÍTICA: $usuario eliminó reserva de alto valor';
      case 'crear_reserva_sospechosa':
        return 'RESERVA SOSPECHOSA: Patrones anómalos detectados por $usuario';
      default:
        return 'ALERTA CRÍTICA: $accion por $usuario';
    }
  }

  static int _calcularPrioridadAlerta(Map<String, dynamic> auditEntry) {
    final puntuacion = auditEntry['puntuacion_riesgo'] as int? ?? 0;
    if (puntuacion >= 90) return 1; // Crítica
    if (puntuacion >= 80) return 2; // Alta
    return 3; // Normal
  }


  /// Enviar notificación push
  static Future<void> _enviarNotificacionPush(Map<String, dynamic> auditEntry) async {
    // Implementación de notificaciones push
    // Esto dependería de tu sistema de notificaciones
    debugPrint('📱 Notificación push enviada: ${auditEntry['titulo'] ?? auditEntry['descripcion']}');
  }

  /// Métodos auxiliares
  static double? _extraerPrecio(Map<String, dynamic> datos) {
    final campos = ['valor', 'montoTotal', 'precio', 'monto_total'];
    for (final campo in campos) {
      if (datos.containsKey(campo) && datos[campo] != null) {
        return (datos[campo] as num).toDouble();
      }
    }
    return null;
  }

  static Future<String> _obtenerIP() async {
    return 'IP no disponible en Flutter';
  }

  static Future<Map<String, dynamic>> _obtenerInfoDispositivo() async {
    return {
      'plataforma': 'Flutter',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // Métodos de agrupación mejorados
  Map<String, int> _agruparPorAccion(List<AuditEntry> entries) {
    final Map<String, int> agrupado = {};
    for (var entry in entries) {
      agrupado[entry.accion] = (agrupado[entry.accion] ?? 0) + 1;
    }
    return Map.fromEntries(
      agrupado.entries.toList()..sort((a, b) => b.value.compareTo(a.value))
    );
  }

  Map<String, int> _agruparPorUsuario(List<AuditEntry> entries) {
    final Map<String, int> agrupado = {};
    for (var entry in entries) {
      agrupado[entry.usuarioNombre] = (agrupado[entry.usuarioNombre] ?? 0) + 1;
    }
    return Map.fromEntries(
      agrupado.entries.toList()..sort((a, b) => b.value.compareTo(a.value))
    );
  }

  Map<String, int> _agruparPorFecha(List<AuditEntry> entries) {
    final Map<String, int> agrupado = {};
    for (var entry in entries) {
      final fecha = DateFormat('yyyy-MM-dd').format(entry.fechaLocal);
      agrupado[fecha] = (agrupado[fecha] ?? 0) + 1;
    }
    return agrupado;
  }

  Map<String, dynamic> _calcularTendencias(List<AuditEntry> entries) {
    if (entries.length < 2) return {};
    
    final hoy = DateTime.now();
    final ayer = hoy.subtract(Duration(days: 1));
    
    final entradashoy = entries.where((e) => 
      DateFormat('yyyy-MM-dd').format(e.fechaLocal) == 
      DateFormat('yyyy-MM-dd').format(hoy)
    ).length;
    
    final entradasAyer = entries.where((e) => 
      DateFormat('yyyy-MM-dd').format(e.fechaLocal) == 
      DateFormat('yyyy-MM-dd').format(ayer)
    ).length;
    
    final tendencia = entradashoy - entradasAyer;
    
    return {
      'hoy': entradashoy,
      'ayer': entradasAyer,
      'tendencia': tendencia,
      'porcentaje_cambio': entradasAyer > 0 ? (tendencia / entradasAyer * 100) : 0,
    };
  }

  Map<String, dynamic> _calcularImpactoFinanciero(List<AuditEntry> entries) {
    double impactoTotal = 0;
    int operacionesFinancieras = 0;
    
    for (var entry in entries) {
      if (entry.metadatos.containsKey('impacto_financiero')) {
        final impacto = entry.metadatos['impacto_financiero'];
        if (impacto is Map && impacto.containsKey('diferencia_ingresos')) {
          impactoTotal += (impacto['diferencia_ingresos'] as num?)?.toDouble() ?? 0;
          operacionesFinancieras++;
        }
      }
    }
    
    return {
      'impacto_total': impactoTotal,
      'operaciones_financieras': operacionesFinancieras,
      'impacto_promedio': operacionesFinancieras > 0 ? impactoTotal / operacionesFinancieras : 0,
    };
  }

  /// Obtener alertas no leídas con mejor rendimiento
  Future<List<Map<String, dynamic>>> obtenerAlertasNoLeidas() async {
    try {
      // Filtrar por lugarId del usuario autenticado
      final lugarId = await LugarHelper.getLugarId();
      final query = await FirebaseFirestore.instance
          .collection('alertas_criticas')
          .where('lugarId', isEqualTo: lugarId)
          .where('leida', isEqualTo: false)
          .orderBy('prioridad')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      return query.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      debugPrint('Error obteniendo alertas: $e');
      return [];
    }
  }

  /// Marcar alerta como leída
  Future<void> marcarAlertaLeida(String alertaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('alertas_criticas')
          .doc(alertaId)
          .update({
        'leida': true,
        'fecha_lectura': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('Error marcando alerta como leída: $e');
    }
  }

  /// Obtener resumen de alertas críticas del día
  Future<Map<String, dynamic>> obtenerResumenAlertasHoy() async {
    try {
      final hoy = DateTime.now();
      final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
      final finHoy = inicioHoy.add(Duration(days: 1));
      final lugarId = await LugarHelper.getLugarId();
      
      final query = await FirebaseFirestore.instance
          .collection('alertas_criticas')
          .where('lugarId', isEqualTo: lugarId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioHoy))
          .where('timestamp', isLessThan: Timestamp.fromDate(finHoy))
          .get();

      final alertas = query.docs;
      final noLeidas = alertas.where((doc) => doc.data()['leida'] == false).length;
      final criticas = alertas.where((doc) => doc.data()['prioridad'] == 1).length;
      
      return {
        'total_hoy': alertas.length,
        'no_leidas': noLeidas,
        'criticas': criticas,
        'requieren_accion': alertas.where((doc) => 
          doc.data()['requiere_accion'] == true).length,
      };
    } catch (e) {
      debugPrint('Error obteniendo resumen de alertas: $e');
      return {};
    }
  }
  
  // ✅ CORRECCIÓN: Método dispose para limpiar recursos cuando el provider se destruye
  @override
  void dispose() {
    // Cancelar timer de debounce si existe
    _debounceTimer?.cancel();
    _debounceTimer = null;
    
    // Cancelar completer si hay una carga en progreso
    if (_cargaCompleter != null && !_cargaCompleter!.isCompleted) {
      _cargaCompleter!.completeError('Provider disposed');
      _cargaCompleter = null;
    }
    
    super.dispose();
  }
}