// peticion_provider.dart
// lib/providers/peticion_provider.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';
import '../models/peticion.dart';

class PeticionProvider with ChangeNotifier {
  List<Peticion> _peticiones = [];
  bool _isLoading = false;
  bool _controlTotalActivado = false;
  StreamSubscription<DocumentSnapshot>? _controlSubscription;

  List<Peticion> get peticiones => _peticiones;
  bool get isLoading => _isLoading;
  bool get controlTotalActivado => _controlTotalActivado;

  // Obtener peticiones pendientes (para superadmin)
  List<Peticion> get peticionesPendientes => 
      _peticiones.where((p) => p.estaPendiente).toList();

  // Obtener peticiones por admin
  List<Peticion> peticionesPorAdmin(String adminId) =>
      _peticiones.where((p) => p.adminId == adminId).toList();

  /// **Inicializar escucha en tiempo real del control total**
  void iniciarEscuchaControlTotal() {
    _controlSubscription?.cancel();
    
    _controlSubscription = FirebaseFirestore.instance
        .collection('config')
        .doc('admin_control')
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final nuevoEstado = snapshot.data()!['control_total_activado'] ?? false;
          if (_controlTotalActivado != nuevoEstado) {
            _controlTotalActivado = nuevoEstado;
            debugPrint('Control total actualizado en tiempo real: $_controlTotalActivado');
            notifyListeners();
          }
        } else {
          if (_controlTotalActivado != false) {
            _controlTotalActivado = false;
            notifyListeners();
          }
        }
      },
      onError: (error) {
        debugPrint('Error en escucha de control total: $error');
      },
    );
  }

  /// **Detener escucha del control total**
  void detenerEscuchaControlTotal() {
    _controlSubscription?.cancel();
    _controlSubscription = null;
  }

  /// **Alternar control total de administradores (solo superadmin)**
  Future<void> alternarControlTotal() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      if (!await esSuperAdmin()) {
        throw Exception('Solo los superadministradores pueden cambiar esta configuración');
      }

      final nuevoEstado = !_controlTotalActivado;
      
      final configRef = FirebaseFirestore.instance
          .collection('config')
          .doc('admin_control');
      
      await configRef.set({
        'control_total_activado': nuevoEstado,
        'activado_por': user.uid,
        'fecha_cambio': Timestamp.now(),
        'version': FieldValue.increment(1),
      }, SetOptions(merge: true));

      debugPrint('Control total ${nuevoEstado ? "activado" : "desactivado"}');
      
    } catch (e) {
      debugPrint('Error al alternar control total: $e');
      throw Exception('Error al cambiar la configuración: $e');
    }
  }

  /// **Cargar configuración de control total**
  Future<void> cargarConfiguracionControl() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('admin_control')
          .get();

      if (doc.exists && doc.data() != null) {
        final nuevoEstado = doc.data()!['control_total_activado'] ?? false;
        if (_controlTotalActivado != nuevoEstado) {
          _controlTotalActivado = nuevoEstado;
          notifyListeners();
        }
      } else {
        await FirebaseFirestore.instance
            .collection('config')
            .doc('admin_control')
            .set({
          'control_total_activado': false,
          'fecha_creacion': Timestamp.now(),
        });
        
        if (_controlTotalActivado != false) {
          _controlTotalActivado = false;
          notifyListeners();
        }
      }
      
    } catch (e) {
      debugPrint('Error al cargar configuración de control: $e');
      if (_controlTotalActivado != false) {
        _controlTotalActivado = false;
        notifyListeners();
      }
    }
  }

  /// **Verificar si un admin puede hacer cambios directos**
  Future<bool> puedeHacerCambiosDirectos() async {
    if (await esSuperAdmin()) {
      return true;
    }

    if (await esAdmin() && _controlTotalActivado) {
      return true;
    }

    return false;
  }

  /// **Crear una nueva petición (método simplificado)**
  Future<String> crearPeticion({
    required String reservaId,
    required Map<String, dynamic> valoresAntiguos,
    required Map<String, dynamic> valoresNuevos,
  }) async {
    return await crearPeticionMejorada(
      reservaId: reservaId,
      valoresAntiguos: valoresAntiguos,
      valoresNuevos: valoresNuevos,
    );
  }

  /// **Cargar todas las peticiones**
  Future<void> cargarPeticiones() async {
    _isLoading = true;
    notifyListeners();

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('peticiones')
          .orderBy('fecha_creacion', descending: true)
          .get();

      _peticiones = querySnapshot.docs
          .map((doc) => Peticion.fromFirestore(doc))
          .toList();

    } catch (e) {
      debugPrint('Error al cargar peticiones: $e');
      _peticiones = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// **Aprobar una petición**
  Future<void> aprobarPeticion(String peticionId) async {
    return await aprobarPeticionMejorada(peticionId);
  }

  /// **Rechazar una petición**
  Future<void> rechazarPeticion(String peticionId, String motivo) async {
    return await rechazarPeticionMejorada(peticionId, motivo);
  }

  /// **Aplicar cambios a la reserva - MÉTODO PRINCIPAL OPTIMIZADO**
  Future<void> _aplicarCambiosReserva(
    String reservaId, 
    Map<String, dynamic> nuevosValores
  ) async {
    try {
      final tipoPeticion = nuevosValores['tipo'] as String?;
      
      debugPrint('📄 Aplicando cambios - Tipo: $tipoPeticion, ReservaID: $reservaId');
      
      switch (tipoPeticion) {
        case 'nueva_reserva_precio_personalizado':
          await _aplicarCambiosNuevaReserva(nuevosValores);
          break;
        case 'reserva_recurrente_precio':
          await _aplicarCambiosReservaRecurrente(nuevosValores);
          break;
        // 🆕 NUEVO CASO PARA RESERVAS RECURRENTES CON PRECIO PERSONALIZADO
        case 'nueva_reserva_recurrente_precio_personalizado':
          await _aplicarCambiosNuevaReservaRecurrente(nuevosValores);
          break;
        default:
          if (reservaId.startsWith('nueva_reserva_')) {
            throw Exception('ID temporal detectado para reserva existente: $reservaId');
          }
          await _aplicarCambiosReservaNormalVerificada(reservaId, nuevosValores);
          break;
      }
      
    } catch (e) {
      debugPrint('❌ Error al aplicar cambios: $e');
      throw Exception('Error al aplicar cambios: $e');
    }
  }

  /// **Aplicar cambios a reserva normal con verificación**
  Future<void> _aplicarCambiosReservaNormalVerificada(
    String reservaId,
    Map<String, dynamic> nuevosValores
  ) async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(reservaId)
          .get();
      
      if (!docSnapshot.exists) {
        throw Exception('La reserva con ID $reservaId no existe');
      }
      
      await _aplicarCambiosReservaNormal(reservaId, nuevosValores);
      
    } catch (e) {
      debugPrint('❌ Error al aplicar cambios a reserva normal: $e');
      throw Exception('Error al aplicar cambios a la reserva: $e');
    }
  }

  /// **Aplicar cambios a reserva normal - OPTIMIZADO**
  Future<void> _aplicarCambiosReservaNormal(
  String reservaId,
  Map<String, dynamic> nuevosValores
) async {
  try {
    final updateData = <String, dynamic>{};
    
    // Mapeo optimizado de campos
    final camposMapeados = {
      'nombre': 'nombre',
      'telefono': 'telefono',
      'correo': 'correo',
      'fecha': 'fecha',
      'horario': 'horario',
      'cancha_id': 'cancha_id',
      'sede': 'sede',
      'estado': 'estado',
      'confirmada': 'confirmada',
    };

    // Aplicar campos básicos
    camposMapeados.forEach((key, firebaseField) {
      if (nuevosValores.containsKey(key)) {
        updateData[firebaseField] = nuevosValores[key];
      }
    });

    // Campos especiales para montos - ESTANDARIZADO
    if (nuevosValores.containsKey('valor') || nuevosValores.containsKey('montoTotal')) {
      final valor = nuevosValores['valor'] ?? nuevosValores['montoTotal'];
      updateData['valor'] = valor;
      updateData['montoTotal'] = valor;
    }

    if (nuevosValores.containsKey('montoPagado')) {
      updateData['montoPagado'] = nuevosValores['montoPagado'];
    }

    // ✅ CORRECCIÓN CRÍTICA: Usar snake_case consistentemente
    bool esPrecioPersonalizado = false;
    if (nuevosValores.containsKey('precioPersonalizado')) {
      esPrecioPersonalizado = nuevosValores['precioPersonalizado'] as bool? ?? false;
      updateData['precioPersonalizado'] = esPrecioPersonalizado;
    } else if (nuevosValores.containsKey('precio_personalizado')) {
      esPrecioPersonalizado = nuevosValores['precio_personalizado'] as bool? ?? false;
      updateData['precioPersonalizado'] = esPrecioPersonalizado;
    }

    // ✅ AGREGAR CAMPOS DE DESCUENTO CON NOMENCLATURA CORRECTA
    if (esPrecioPersonalizado) {
      if (nuevosValores.containsKey('precioOriginal')) {
        updateData['precio_original'] = nuevosValores['precioOriginal'];  // ✅ snake_case
      } else if (nuevosValores.containsKey('precio_original')) {
        updateData['precio_original'] = nuevosValores['precio_original'];
      }

      if (nuevosValores.containsKey('descuentoAplicado')) {
        updateData['descuento_aplicado'] = nuevosValores['descuentoAplicado'];  // ✅ snake_case
      } else if (nuevosValores.containsKey('descuento_aplicado')) {
        updateData['descuento_aplicado'] = nuevosValores['descuento_aplicado'];
      }

      // ✅ AGREGAR LOG PARA DEBUG
      debugPrint('💰 Actualizando precio personalizado:');
      debugPrint('   - Precio original: ${updateData['precio_original']}');
      debugPrint('   - Descuento aplicado: ${updateData['descuento_aplicado']}');
      debugPrint('   - Precio final: ${updateData['valor'] ?? updateData['montoTotal']}');
    }
    
    if (updateData.isNotEmpty) {
      updateData['fechaActualizacion'] = Timestamp.now();
      
      await FirebaseFirestore.instance
          .collection('reservas')
          .doc(reservaId)
          .update(updateData);
      
      debugPrint('✅ Cambios aplicados a reserva $reservaId: ${updateData.keys}');
      debugPrint('📋 Datos actualizados: $updateData');
    }
  } catch (e) {
    debugPrint('❌ Error al aplicar cambios a reserva normal: $e');
    throw Exception('Error al aplicar cambios: $e');
  }
}



  /// **Aplicar cambios a reserva recurrente - OPTIMIZADO**
  Future<void> _aplicarCambiosReservaRecurrente(Map<String, dynamic> nuevosValores) async {
    try {
      final reservaRecurrenteId = nuevosValores['reservaRecurrenteId'] as String?;
      if (reservaRecurrenteId == null || reservaRecurrenteId.isEmpty) {
        throw Exception('ID de reserva recurrente no proporcionado');
      }

      // Verificar que la reserva recurrente existe
      final recurrenteDoc = await FirebaseFirestore.instance
          .collection('reservas_recurrentes')
          .doc(reservaRecurrenteId)
          .get();

      if (!recurrenteDoc.exists) {
        throw Exception('La reserva recurrente $reservaRecurrenteId no existe');
      }

      final nuevoPrecio = nuevosValores['montoTotal'] as double;
      final nuevoMontoPagado = nuevosValores['montoPagado'] as double;
      final esPrecioPersonalizado = nuevosValores['precioPersonalizado'] as bool? ?? false;
      final precioOriginal = nuevosValores['precioOriginal'] as double?;
      final descuentoAplicado = nuevosValores['descuentoAplicado'] as double?;

      // Actualizar reserva recurrente
      Map<String, dynamic> updateDataRecurrente = {
        'montoTotal': nuevoPrecio,
        'montoPagado': nuevoMontoPagado,
        'fechaActualizacion': Timestamp.now(),
        'actualizado_por_peticion': true,
        'precioPersonalizado': esPrecioPersonalizado,
      };

      if (esPrecioPersonalizado) {
        updateDataRecurrente['precioOriginal'] = precioOriginal;
        updateDataRecurrente['descuentoAplicado'] = descuentoAplicado;
      } else {
        updateDataRecurrente['precioOriginal'] = null;
        updateDataRecurrente['descuentoAplicado'] = null;
      }

      await FirebaseFirestore.instance
          .collection('reservas_recurrentes')
          .doc(reservaRecurrenteId)
          .update(updateDataRecurrente);

      debugPrint('✅ Reserva recurrente actualizada: $reservaRecurrenteId');

      // Actualizar reservas individuales asociadas
      await _actualizarReservasIndividualesRecurrentes(
        reservaRecurrenteId,
        nuevoPrecio,
        nuevoMontoPagado,
        esPrecioPersonalizado,
        precioOriginal,
        descuentoAplicado,
      );
      
    } catch (e) {
      debugPrint('❌ Error al aplicar cambios a reserva recurrente: $e');
      throw Exception('Error al aplicar cambios: $e');
    }
  }

  /// **Actualizar reservas individuales de una recurrente**
  Future<void> _actualizarReservasIndividualesRecurrentes(
    String reservaRecurrenteId,
    double nuevoPrecio,
    double nuevoMontoPagado,
    bool esPrecioPersonalizado,
    double? precioOriginal,
    double? descuentoAplicado,
  ) async {
    try {
      final reservasIndividualesSnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .where('reservaRecurrenteId', isEqualTo: reservaRecurrenteId)
          .get();

      if (reservasIndividualesSnapshot.docs.isEmpty) {
        debugPrint('ℹ️ No se encontraron reservas individuales para actualizar');
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      int contadorActualizadas = 0;
      
      for (var doc in reservasIndividualesSnapshot.docs) {
        final reservaData = doc.data();
        
        // Solo actualizar reservas que no tengan precio independiente
        final tienePrecioIndependiente = reservaData['precio_independiente_de_recurrencia'] as bool? ?? false;
        
        if (!tienePrecioIndependiente) {
          final montoPagadoIndividual = reservaData['montoPagado'] as double? ?? 0.0;
          final montoTotalIndividual = reservaData['montoTotal'] as double? ?? 0.0;
          
          // Calcular nuevo monto pagado proporcionalmente
          double nuevoMontoPagadoIndividual = montoPagadoIndividual;
          if (montoPagadoIndividual > 0 && montoTotalIndividual != nuevoPrecio && montoTotalIndividual > 0) {
            final proporcionIndividual = montoPagadoIndividual / montoTotalIndividual;
            nuevoMontoPagadoIndividual = nuevoPrecio * proporcionIndividual;
            nuevoMontoPagadoIndividual = nuevoMontoPagadoIndividual > nuevoPrecio ? nuevoPrecio : nuevoMontoPagadoIndividual;
          }
          
          Map<String, dynamic> updateDataIndividual = {
            'montoTotal': nuevoPrecio,
            'valor': nuevoPrecio,
            'montoPagado': nuevoMontoPagadoIndividual,
            'estado': nuevoMontoPagadoIndividual >= nuevoPrecio ? 'completo' : 'parcial',
            'actualizado_por_peticion_recurrente': true,
            'fecha_actualizacion_recurrente': Timestamp.now(),
            'precioPersonalizado': esPrecioPersonalizado,
          };

          if (esPrecioPersonalizado) {
            updateDataIndividual['precioOriginal'] = precioOriginal;
            updateDataIndividual['descuentoAplicado'] = descuentoAplicado;
          } else {
            updateDataIndividual['precioOriginal'] = null;
            updateDataIndividual['descuentoAplicado'] = null;
          }

          batch.update(doc.reference, updateDataIndividual);
          contadorActualizadas++;
        }
      }

      if (contadorActualizadas > 0) {
        await batch.commit();
        debugPrint('✅ $contadorActualizadas reservas individuales actualizadas');
      }
      
    } catch (e) {
      debugPrint('❌ Error actualizando reservas individuales: $e');
      throw Exception('Error actualizando reservas individuales: $e');
    }
  }

  /// **Aplicar cambios para nueva reserva - OPTIMIZADO**
  Future<void> _aplicarCambiosNuevaReserva(Map<String, dynamic> nuevosValores) async {
    try {
      final datosReserva = nuevosValores['datos_reserva'] as Map<String, dynamic>?;
      if (datosReserva == null) {
        throw Exception('No se encontraron datos de la reserva');
      }
      
      // Validaciones mejoradas
      _validarDatosNuevaReserva(datosReserva);
      
      final horarios = datosReserva['horarios'] as List;
      final fechaReserva = DateTime.parse(datosReserva['fecha']);
      final precioPersonalizadoTotal = datosReserva['precio_personalizado_total'] as double;
      final precioOriginalTotal = datosReserva['precio_original_total'] as double;
      final montoPagado = datosReserva['monto_pagado'] as double;

      debugPrint('📄 Creando reserva desde petición aprobada');
      debugPrint('🏟️ Cancha: ${datosReserva['cancha_nombre']}');
      debugPrint('📅 Fecha: ${datosReserva['fecha']}');
      debugPrint('🕐 Horarios: $horarios');

      // Obtener y validar horarios disponibles
      final horariosDisponibles = await _obtenerHorariosDisponibles();
      await _validarHorariosExisten(horarios, horariosDisponibles);

      // Calcular distribución de precios
      final distribucionPrecios = _calcularDistribucionPrecios(
        horarios, precioPersonalizadoTotal, montoPagado
      );

      // Crear las reservas
      await _crearReservasIndividuales(
        datosReserva,
        horarios,
        distribucionPrecios,
        precioOriginalTotal,
        horariosDisponibles,
      );

      debugPrint('✅ ${horarios.length} reserva(s) creada(s) exitosamente');
      
    } catch (e) {
      debugPrint('❌ Error al crear nueva reserva: $e');
      throw Exception('Error al crear la reserva: $e');
    }
  }

  /// **Validar datos de nueva reserva**
  void _validarDatosNuevaReserva(Map<String, dynamic> datosReserva) {
    final camposRequeridos = [
      'cancha_id', 'cancha_nombre', 'fecha', 'horarios', 
      'sede', 'cliente_nombre', 'cliente_telefono'
    ];
    
    for (final campo in camposRequeridos) {
      if (!datosReserva.containsKey(campo) || datosReserva[campo] == null) {
        throw Exception('Campo requerido faltante: $campo');
      }
    }
    
    final horarios = datosReserva['horarios'];
    if (horarios is! List || horarios.isEmpty) {
      throw Exception('Lista de horarios inválida');
    }
    
    final precioPersonalizadoTotal = datosReserva['precio_personalizado_total'] as double?;
    final precioOriginalTotal = datosReserva['precio_original_total'] as double?;
    final montoPagado = datosReserva['monto_pagado'] as double?;
    
    if (precioPersonalizadoTotal == null || precioPersonalizadoTotal <= 0) {
      throw Exception('Precio personalizado inválido');
    }
    if (precioOriginalTotal == null || precioOriginalTotal <= 0) {
      throw Exception('Precio original inválido');
    }
    if (montoPagado == null || montoPagado < 0) {
      throw Exception('Monto pagado inválido');
    }
  }

  /// **Obtener horarios disponibles de Firebase**
  Future<Map<String, Map<String, dynamic>>> _obtenerHorariosDisponibles() async {
    final horariosSnapshot = await FirebaseFirestore.instance
        .collection('horarios')
        .get();
    
    final horariosDisponibles = <String, Map<String, dynamic>>{};
    for (var doc in horariosSnapshot.docs) {
      final data = doc.data();
      final horaFormateada = data['horaFormateada'] as String?;
      if (horaFormateada != null) {
        horariosDisponibles[horaFormateada] = data;
        
        // Agregar variaciones de formato
        final variaciones = _generarVariacionesHorario(horaFormateada);
        for (String variacion in variaciones) {
          horariosDisponibles[variacion] = data;
        }
      }
    }
    
    return horariosDisponibles;
  }

  /// **Validar que todos los horarios existen**
  Future<void> _validarHorariosExisten(
    List horarios,
    Map<String, Map<String, dynamic>> horariosDisponibles
  ) async {
    final horariosNoEncontrados = <String>[];
    
    for (final horarioStr in horarios) {
      if (!horariosDisponibles.containsKey(horarioStr)) {
        horariosNoEncontrados.add(horarioStr.toString());
      }
    }
    
    if (horariosNoEncontrados.isNotEmpty) {
      // Intentar crear horarios básicos
      final horariosBasicos = <String, Map<String, dynamic>>{};
      for (final horarioStr in horariosNoEncontrados) {
        final datosBasicos = _crearDatosHorarioBasicos(horarioStr.toString());
        if (datosBasicos != null) {
          horariosBasicos[horarioStr.toString()] = datosBasicos;
        }
      }
      
      horariosDisponibles.addAll(horariosBasicos);
      
      final aunFaltantes = horariosNoEncontrados.where((h) => !horariosBasicos.containsKey(h)).toList();
      if (aunFaltantes.isNotEmpty) {
        throw Exception('Horarios no encontrados: $aunFaltantes');
      }
    }
  }

  /// **Calcular distribución de precios por horario**
  Map<String, Map<String, double>> _calcularDistribucionPrecios(
    List horarios,
    double precioTotal,
    double montoPagado
  ) {
    final distribucion = <String, Map<String, double>>{};
    
    if (horarios.length == 1) {
      distribucion[horarios.first] = {
        'precio': precioTotal,
        'abono': montoPagado,
      };
    } else {
      double sumaDistribuida = 0;
      double sumaAbonoDistribuida = 0;
      
      for (int i = 0; i < horarios.length - 1; i++) {
        final horario = horarios[i] as String;
        final precioPorHora = precioTotal / horarios.length;
        final abonoPorHora = montoPagado / horarios.length;
        
        final precioRedondeado = _redondearANumeroLimpio(precioPorHora);
        final abonoRedondeado = _redondearANumeroLimpio(abonoPorHora);
        
        distribucion[horario] = {
          'precio': precioRedondeado,
          'abono': abonoRedondeado,
        };
        
        sumaDistribuida += precioRedondeado;
        sumaAbonoDistribuida += abonoRedondeado;
      }
      
      // Último horario con el restante
      final ultimoHorario = horarios.last as String;
      distribucion[ultimoHorario] = {
        'precio': precioTotal - sumaDistribuida,
        'abono': montoPagado - sumaAbonoDistribuida,
      };
    }
    
    return distribucion;
  }

  /// **Crear las reservas individuales en batch - CORREGIDO PARA DESCUENTOS**
Future<void> _crearReservasIndividuales(
  Map<String, dynamic> datosReserva,
  List horarios,
  Map<String, Map<String, double>> distribucionPrecios,
  double precioOriginalTotal,
  Map<String, Map<String, dynamic>> horariosDisponibles,
) async {
  final batch = FirebaseFirestore.instance.batch();
  final reservasCreadas = <String>[];
  
  String? grupoReservaId;
  if (horarios.length > 1) {
    grupoReservaId = DateTime.now().millisecondsSinceEpoch.toString();
  }

  // 🔧 CORREGIR: Obtener el precio personalizado total correctamente
  final precioPersonalizadoTotal = datosReserva['precio_personalizado_total'] as double? ?? 
                                   datosReserva['precio_aplicado'] as double? ?? 0.0;
  
  // 🔧 CORREGIR: Calcular el descuento total correctamente
  final descuentoTotal = precioOriginalTotal - precioPersonalizadoTotal;
  
  debugPrint('💰 === DATOS DE DESCUENTO TOTALES ===');
  debugPrint('   📊 Precio original total: \$${precioOriginalTotal.toStringAsFixed(0)}');
  debugPrint('   💸 Precio personalizado total: \$${precioPersonalizadoTotal.toStringAsFixed(0)}');
  debugPrint('   🎯 Descuento total: \$${descuentoTotal.toStringAsFixed(0)}');
  debugPrint('   🕐 Cantidad horarios: ${horarios.length}');

  for (final horarioStr in horarios) {
    final horarioData = horariosDisponibles[horarioStr]!;
    final precioData = distribucionPrecios[horarioStr]!;
    
    final precioHora = precioData['precio']!;
    final abonoHora = precioData['abono']!;
    
    // 🔧 CORREGIR: Calcular precio original y descuento por hora correctamente
    final precioOriginalHora = precioOriginalTotal / horarios.length;
    final descuentoHora = descuentoTotal / horarios.length; // Usar descuento total calculado
    
    // 🔧 VALIDACIÓN: Verificar que los cálculos sean consistentes
    final precioCalculado = precioOriginalHora - descuentoHora;
    if ((precioCalculado - precioHora).abs() > 0.01) {
      debugPrint('⚠️ ADVERTENCIA: Inconsistencia en precios');
      debugPrint('   📊 Precio calculado: \$${precioCalculado.toStringAsFixed(2)}');
      debugPrint('   📊 Precio distribuido: \$${precioHora.toStringAsFixed(2)}');
      debugPrint('   📊 Diferencia: \$${(precioCalculado - precioHora).abs().toStringAsFixed(2)}');
    }
    
    final docRef = FirebaseFirestore.instance.collection('reservas').doc();
    
    final datosReservaFirestore = {
      'cancha_id': datosReserva['cancha_id'],
      'cancha_nombre': datosReserva['cancha_nombre'],
      'fecha': datosReserva['fecha'],
      'horario': horarioStr,
      'sede': datosReserva['sede'],
      'nombre': datosReserva['cliente_nombre'],
      'telefono': datosReserva['cliente_telefono'],
      'correo': datosReserva['cliente_email'],
      'valor': precioHora,
      'montoTotal': precioHora,
      'montoPagado': abonoHora,
      'tipoAbono': abonoHora >= precioHora ? 'completo' : 'parcial',
      'estado': abonoHora >= precioHora ? 'completo' : 'parcial',
      'confirmada': true,
      'created_at': Timestamp.now(),
      'creadaPorPeticion': true,
      'peticionAprobada': true,
      
      // ✅ CORREGIDO: Usar la nomenclatura correcta y valores calculados
      'precio_personalizado': true,
      'precio_original': precioOriginalHora,      // ✅ Precio original por hora
      'descuento_aplicado': descuentoHora,       // ✅ Descuento por hora calculado correctamente
      
      // Campos de horario
      'hora_inicio': horarioData['hora_inicio'] ?? 0,
      'hora_fin': horarioData['hora_fin'] ?? 0,
      'minutos_inicio': horarioData['minutos_inicio'] ?? 0,
      'minutos_fin': horarioData['minutos_fin'] ?? 0,
    };

    if (grupoReservaId != null) {
      datosReservaFirestore['grupo_reserva_id'] = grupoReservaId;
      datosReservaFirestore['total_horas_grupo'] = horarios.length;
    }

    // ✅ LOG DETALLADO PARA VERIFICAR LOS DATOS
    debugPrint('💾 === RESERVA INDIVIDUAL ${horarios.indexOf(horarioStr) + 1}/${horarios.length} ===');
    debugPrint('   📅 Fecha: ${datosReserva['fecha']}');
    debugPrint('   🕐 Horario: $horarioStr');
    debugPrint('   💰 Precio original hora: \$${precioOriginalHora.toStringAsFixed(0)}');
    debugPrint('   💸 Precio final hora: \$${precioHora.toStringAsFixed(0)}');
    debugPrint('   🎯 Descuento hora: \$${descuentoHora.toStringAsFixed(0)}');
    debugPrint('   📊 Porcentaje descuento: ${precioOriginalHora > 0 ? ((descuentoHora / precioOriginalHora) * 100).toStringAsFixed(1) : 0}%');
    debugPrint('   💵 Abono: \$${abonoHora.toStringAsFixed(0)}');
    debugPrint('   🔢 precio_original (campo BD): ${datosReservaFirestore['precio_original']}');
    debugPrint('   🔢 descuento_aplicado (campo BD): ${datosReservaFirestore['descuento_aplicado']}');
    debugPrint('   🔢 valor (campo BD): ${datosReservaFirestore['valor']}');

    batch.set(docRef, datosReservaFirestore);
    reservasCreadas.add(docRef.id);
  }

  await batch.commit();
  debugPrint('📋 IDs creadas: $reservasCreadas');
  
  if (grupoReservaId != null) {
    debugPrint('👥 Grupo reserva ID: $grupoReservaId');
  }

  // ✅ VERIFICACIÓN FINAL DE TOTALES
  debugPrint('🔍 === VERIFICACIÓN FINAL ===');
  debugPrint('   📊 Precio original total esperado: \${precioOriginalTotal.toStringAsFixed(0)}');
  debugPrint('   📊 Precio personalizado total esperado: \${precioPersonalizadoTotal.toStringAsFixed(0)}');
  debugPrint('   📊 Descuento total esperado: \${descuentoTotal.toStringAsFixed(0)}');
  
  // Verificar suma de precios individuales
  final precioOriginalPorHora = precioOriginalTotal / horarios.length;
  final sumaPreciosOriginales = precioOriginalPorHora * horarios.length;
  final sumaPreciosPersonalizados = horarios.fold<double>(0, (sum, h) => sum + distribucionPrecios[h]!['precio']!);
  final sumaDescuentos = sumaPreciosOriginales - sumaPreciosPersonalizados;
  
  debugPrint('   ✅ Suma precios originales calculados: \${sumaPreciosOriginales.toStringAsFixed(0)}');
  debugPrint('   ✅ Suma precios personalizados: \${sumaPreciosPersonalizados.toStringAsFixed(0)}');
  debugPrint('   ✅ Suma descuentos calculados: \${sumaDescuentos.toStringAsFixed(0)}');
}



  /// **Generar variaciones de formato de hora**
  List<String> _generarVariacionesHorario(String horarioOriginal) {
    final variaciones = <String>[horarioOriginal];
    
    try {
      if (horarioOriginal.contains('PM') || horarioOriginal.contains('AM')) {
        final regex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
        final match = regex.firstMatch(horarioOriginal);
        
        if (match != null) {
          final hora = int.tryParse(match.group(1)!) ?? 0;
          final minutos = match.group(2)!;
          final periodo = match.group(3)!;
          
          if (hora < 10) {
            variaciones.add('0$hora:$minutos $periodo');
          }
          
          variaciones.add('${hora.toString().padLeft(2, '0')}:$minutos$periodo');
        }
      }
      
      if (horarioOriginal.contains(':') && !horarioOriginal.contains('AM') && !horarioOriginal.contains('PM')) {
        final partes = horarioOriginal.split(':');
        if (partes.length == 2) {
          final hora = int.tryParse(partes[0]) ?? 0;
          final minutos = partes[1];
          
          if (hora >= 0 && hora <= 23) {
            if (hora == 0) {
              variaciones.add('12:$minutos AM');
            } else if (hora <= 12) {
              variaciones.add('$hora:$minutos AM');
            } else {
              variaciones.add('${hora - 12}:$minutos PM');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error al generar variaciones para $horarioOriginal: $e');
    }
    
    return variaciones;
  }

  /// **Crear datos básicos de horario si no existe**
  Map<String, dynamic>? _crearDatosHorarioBasicos(String horarioStr) {
    try {
      final regex12h = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
      final match12h = regex12h.firstMatch(horarioStr);
      
      if (match12h != null) {
        final hora = int.parse(match12h.group(1)!);
        final minutos = int.parse(match12h.group(2)!);
        final periodo = match12h.group(3)!.toUpperCase();
        
        int hora24 = hora;
        if (periodo == 'PM' && hora != 12) {
          hora24 += 12;
        } else if (periodo == 'AM' && hora == 12) {
          hora24 = 0;
        }
        
        return {
          'horaFormateada': horarioStr,
          'hora_inicio': hora24,
          'minutos_inicio': minutos,
          'hora_fin': hora24 + 1,
          'minutos_fin': minutos,
          'duracion': 60,
          'activo': true,
          'creado_automaticamente': true,
          'timestamp_creacion': Timestamp.now(),
        };
      }
      
      final regex24h = RegExp(r'(\d{1,2}):(\d{2})');
      final match24h = regex24h.firstMatch(horarioStr);
      
      if (match24h != null) {
        final hora = int.parse(match24h.group(1)!);
        final minutos = int.parse(match24h.group(2)!);
        
        if (hora >= 0 && hora <= 23) {
          return {
            'horaFormateada': horarioStr,
            'hora_inicio': hora,
            'minutos_inicio': minutos,
            'hora_fin': hora + 1,
            'minutos_fin': minutos,
            'duracion': 60,
            'activo': true,
            'creado_automaticamente': true,
            'timestamp_creacion': Timestamp.now(),
          };
        }
      }
      
    } catch (e) {
      debugPrint('Error al crear datos básicos para horario $horarioStr: $e');
    }
    
    return null;
  }

  /// **Redondear números a valores limpios**
  double _redondearANumeroLimpio(double valor) {
    if (valor < 1000) {
      return (valor / 100).round() * 100.0;
    } else if (valor < 10000) {
      return (valor / 500).round() * 500.0;
    } else if (valor < 50000) {
      return (valor / 1000).round() * 1000.0;
    } else {
      return (valor / 2500).round() * 2500.0;
    }
  }

  /// **Generar descripción de cambios mejorada**
  static String generarDescripcionCambiosMejorada(
    Map<String, dynamic> valoresAntiguos, 
    Map<String, dynamic> valoresNuevos
  ) {
    List<String> cambios = [];

    final tipoPeticion = valoresNuevos['tipo'] as String?;
    
    if (tipoPeticion == 'nueva_reserva_precio_personalizado') {
      cambios.add('🆕 NUEVA RESERVA CON DESCUENTO');
      
      final datosReserva = valoresNuevos['datos_reserva'] as Map<String, dynamic>? ?? {};
      final precioOriginal = valoresNuevos['precio_original'] as double? ?? 0;
      final precioPersonalizado = valoresNuevos['precio_aplicado'] as double? ?? 0;
      final descuento = valoresNuevos['descuento_aplicado'] as double? ?? 0;
      final cantidadHorarios = valoresNuevos['cantidad_horarios'] as int? ?? 1;
      
      final formatter = NumberFormat('#,##0', 'es_CO');
      
      cambios.add('Cancha: ${datosReserva['cancha_nombre'] ?? 'No especificada'}');
      cambios.add('Fecha: ${datosReserva['fecha'] ?? 'No especificada'}');
      cambios.add('Horarios: $cantidadHorarios hora${cantidadHorarios > 1 ? 's' : ''}');
      cambios.add('Cliente: ${datosReserva['cliente_nombre'] ?? 'No especificado'}');
      cambios.add('Precio original: COP ${formatter.format(precioOriginal)}');
      cambios.add('Precio con descuento: COP ${formatter.format(precioPersonalizado)}');
      cambios.add('Descuento aplicado: COP ${formatter.format(descuento)}');
      
      final montoPagado = datosReserva['monto_pagado'] as double? ?? 0;
      cambios.add('Abono: COP ${formatter.format(montoPagado)}');
      
    } else if (tipoPeticion == 'nueva_reserva_recurrente_precio_personalizado') {
      cambios.add('🔄 NUEVA RESERVA RECURRENTE CON DESCUENTO');
      
      final datosReserva = valoresNuevos['datos_reserva_recurrente'] as Map<String, dynamic>? ?? {};
      final precioOriginal = valoresNuevos['precio_original'] as double? ?? 0;
      final precioPersonalizado = valoresNuevos['precio_aplicado'] as double? ?? 0;
      final descuento = valoresNuevos['descuento_aplicado'] as double? ?? 0;
      final cantidadDias = valoresNuevos['cantidad_dias_semana'] as int? ?? 1;
      
      final formatter = NumberFormat('#,##0', 'es_CO');
      
      cambios.add('Cancha: ${datosReserva['cancha_nombre'] ?? 'No especificada'}');
      cambios.add('Fecha inicio: ${datosReserva['fecha_inicio'] ?? 'No especificada'}');
      cambios.add('Fecha fin: ${datosReserva['fecha_fin'] ?? 'Indefinida'}');
      cambios.add('Horario: ${datosReserva['horario'] ?? 'No especificado'}');
      
      final diasSemana = datosReserva['dias_semana'] as List? ?? [];
      cambios.add('Días: ${diasSemana.map((d) => d.toString().capitalize()).join(', ')} ($cantidadDias días/semana)');
      
      cambios.add('Cliente: ${datosReserva['cliente_nombre'] ?? 'No especificado'}');
      cambios.add('Precio original por reserva: COP ${formatter.format(precioOriginal)}');
      cambios.add('Precio con descuento por reserva: COP ${formatter.format(precioPersonalizado)}');
      cambios.add('Descuento por reserva: COP ${formatter.format(descuento)}');
      
      final montoPagado = datosReserva['monto_pagado'] as double? ?? 0;
      cambios.add('Abono por reserva: COP ${formatter.format(montoPagado)}');
      
      final diasExcluidos = datosReserva['dias_excluidos'] as List? ?? [];
      if (diasExcluidos.isNotEmpty) {
        cambios.add('Días excluidos: ${diasExcluidos.length} fecha(s)');
      }
      
    } else if (tipoPeticion == 'reserva_recurrente_precio') {
      cambios.add('🔄 RESERVA RECURRENTE');
      
      final oldTotal = valoresAntiguos['montoTotal'] as double? ?? 0;
      final newTotal = valoresNuevos['montoTotal'] as double? ?? 0;
      
      if (oldTotal != newTotal) {
        final formatter = NumberFormat('#,##0', 'es_CO');
        cambios.add('Precio total: COP ${formatter.format(oldTotal)} → COP ${formatter.format(newTotal)}');
      }

      final oldPagado = valoresAntiguos['montoPagado'] as double? ?? 0;
      final newPagado = valoresNuevos['montoPagado'] as double? ?? 0;
      
      if (oldPagado != newPagado) {
        final formatter = NumberFormat('#,##0', 'es_CO');
        cambios.add('Abono: COP ${formatter.format(oldPagado)} → COP ${formatter.format(newPagado)}');
      }

      final oldPersonalizado = valoresAntiguos['precioPersonalizado'] as bool? ?? false;
      final newPersonalizado = valoresNuevos['precioPersonalizado'] as bool? ?? false;
      
      if (oldPersonalizado != newPersonalizado) {
        cambios.add('Precio personalizado: ${oldPersonalizado ? "Sí" : "No"} → ${newPersonalizado ? "Sí" : "No"}');
      }

    } else {
      return Peticion.generarDescripcionCambios(valoresAntiguos, valoresNuevos);
    }

    return cambios.isEmpty ? 'Sin cambios detectados' : cambios.join('\n• ');
  }

  /// **Crear petición con descripción mejorada**
  Future<String> crearPeticionMejorada({
    required String reservaId,
    required Map<String, dynamic> valoresAntiguos,
    required Map<String, dynamic> valoresNuevos,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      final tipoPeticion = valoresNuevos['tipo'] as String?;
      
      if (tipoPeticion == 'nueva_reserva_precio_personalizado') {
        reservaId = 'nueva_reserva_${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('🆕 Creando petición para nueva reserva con ID: $reservaId');
      } else {
        if (!await esAdmin() || await esSuperAdmin()) {
          throw Exception('Solo los administradores pueden crear peticiones');
        }

        if (_controlTotalActivado) {
          throw Exception('El control total está activado, puedes hacer cambios directamente');
        }
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      
      final userName = userDoc.exists 
          ? (userDoc.data()?['name'] ?? userDoc.data()?['nombre'] ?? 'Usuario desconocido')
          : 'Usuario desconocido';

      final descripcion = generarDescripcionCambiosMejorada(
        valoresAntiguos, 
        valoresNuevos
      );

      // Determinar prioridad
      String prioridad = 'normal';
      if (tipoPeticion == 'nueva_reserva_precio_personalizado') {
        final descuento = valoresNuevos['descuento_aplicado'] as double? ?? 0;
        if (descuento > 50000) {
          prioridad = 'muy_alta';
        } else if (descuento > 20000) {
          prioridad = 'alta';
        } else if (descuento > 10000) {
          prioridad = 'media';
        }
      }

      final peticionData = {
        'reserva_id': reservaId,
        'admin_id': user.uid,
        'admin_name': userName,
        'estado': 'pendiente',
        'valores_antiguos': valoresAntiguos,
        'valores_nuevos': valoresNuevos,
        'fecha_creacion': Timestamp.now(),
        'descripcion_cambios': descripcion,
        'tipo_peticion': tipoPeticion ?? 'reserva_normal',
        'prioridad': prioridad,
        'requiere_validacion_especial': tipoPeticion == 'nueva_reserva_precio_personalizado' || tipoPeticion == 'reserva_recurrente_precio',
        'monto_descuento': tipoPeticion == 'nueva_reserva_precio_personalizado' 
            ? valoresNuevos['descuento_aplicado'] 
            : 0,
        'version': '2.0',
      };

      if (tipoPeticion == 'nueva_reserva_precio_personalizado') {
        final datosReserva = valoresNuevos['datos_reserva'] as Map<String, dynamic>? ?? {};
        peticionData.addAll({
          'cancha_nombre': datosReserva['cancha_nombre'],
          'fecha_reserva': datosReserva['fecha'],
          'cantidad_horarios': valoresNuevos['cantidad_horarios'],
          'necesita_creacion': true,
          'es_nueva_reserva': true,
        });
      }

      final docRef = await FirebaseFirestore.instance
          .collection('peticiones')
          .add(peticionData);

      await cargarPeticiones();
      
      debugPrint('✅ Petición creada exitosamente: ${docRef.id}');
      debugPrint('📋 Tipo: ${peticionData['tipo_peticion']}');
      debugPrint('🎯 Prioridad: $prioridad');
      
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Error al crear petición: $e');
      throw Exception('Error al crear la petición: $e');
    }
  }

  /// **Aprobar petición con manejo mejorado**
  Future<void> aprobarPeticionMejorada(String peticionId) async {
    String? estadoOriginal;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      if (!await esSuperAdmin()) {
        throw Exception('Solo los superadministradores pueden aprobar peticiones');
      }

      final peticion = _peticiones.firstWhere((p) => p.id == peticionId);
      
      // Guardar estado original para rollback
      final peticionDoc = await FirebaseFirestore.instance
          .collection('peticiones')
          .doc(peticionId)
          .get();
      
      if (peticionDoc.exists) {
        estadoOriginal = peticionDoc.data()?['estado'] as String?;
      }

      debugPrint('📄 Iniciando aprobación de petición: $peticionId');
      
      // Usar transacción para atomicidad
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final peticionRef = FirebaseFirestore.instance
            .collection('peticiones')
            .doc(peticionId);
        
        transaction.update(peticionRef, {
          'estado': 'aprobada',
          'fecha_respuesta': Timestamp.now(),
          'super_admin_id': user.uid,
          'fecha_aprobacion': Timestamp.now(),
          'aprobada_por': user.uid,
        });
      });

      // Aplicar los cambios
      try {
        await _aplicarCambiosReserva(peticion.reservaId, peticion.valoresNuevos);
      } catch (e) {
        // Rollback en caso de error
        if (estadoOriginal != null) {
          await FirebaseFirestore.instance
              .collection('peticiones')
              .doc(peticionId)
              .update({
            'estado': estadoOriginal,
            'fecha_respuesta': FieldValue.delete(),
            'super_admin_id': FieldValue.delete(),
            'fecha_aprobacion': FieldValue.delete(),
            'aprobada_por': FieldValue.delete(),
            'error_aprobacion': e.toString(),
            'fecha_error': Timestamp.now(),
          });
        }
        
        throw Exception('Error al aplicar cambios después de aprobar: $e');
      }

      // Crear registro de auditoría
      await _crearRegistroAuditoria({
        'accion': 'peticion_aprobada',
        'peticion_id': peticionId,
        'reserva_id': peticion.reservaId,
        'admin_solicitante': peticion.adminId,
        'super_admin_aprobador': user.uid,
        'tipo_peticion': peticion.valoresNuevos['tipo'] ?? 'reserva_normal',
        'descripcion_cambios': peticion.descripcionCambios,
        'timestamp': Timestamp.now(),
      });

      await cargarPeticiones();
      debugPrint('✅ Petición aprobada exitosamente: $peticionId');

    } catch (e) {
      debugPrint('❌ Error al aprobar petición: $e');
      
      await _crearRegistroAuditoria({
        'accion': 'error_aprobacion_peticion',
        'peticion_id': peticionId,
        'error': e.toString(),
        'timestamp': Timestamp.now(),
      });
      
      throw Exception('Error al aprobar la petición: $e');
    }
  }

  /// **Rechazar petición con registro mejorado**
  Future<void> rechazarPeticionMejorada(String peticionId, String motivo) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      if (!await esSuperAdmin()) {
        throw Exception('Solo los superadministradores pueden rechazar peticiones');
      }

      final peticion = _peticiones.firstWhere((p) => p.id == peticionId);
      
      debugPrint('📄 Iniciando rechazo de petición: $peticionId');

      await FirebaseFirestore.instance
          .collection('peticiones')
          .doc(peticionId)
          .update({
        'estado': 'rechazada',
        'fecha_respuesta': Timestamp.now(),
        'super_admin_id': user.uid,
        'motivo_rechazo': motivo,
        'fecha_rechazo': Timestamp.now(),
        'rechazada_por': user.uid,
      });

      await _crearRegistroAuditoria({
        'accion': 'peticion_rechazada',
        'peticion_id': peticionId,
        'reserva_id': peticion.reservaId,
        'admin_solicitante': peticion.adminId,
        'super_admin_rechazador': user.uid,
        'tipo_peticion': peticion.valoresNuevos['tipo'] ?? 'reserva_normal',
        'motivo_rechazo': motivo,
        'descripcion_cambios': peticion.descripcionCambios,
        'timestamp': Timestamp.now(),
      });

      await cargarPeticiones();
      debugPrint('✅ Petición rechazada exitosamente: $peticionId');

    } catch (e) {
      debugPrint('❌ Error al rechazar petición: $e');
      throw Exception('Error al rechazar la petición: $e');
    }
  }

  /// **Crear registro de auditoría**
  Future<void> _crearRegistroAuditoria(Map<String, dynamic> datos) async {
  try {
    // Usar el sistema centralizado de auditoría
    await AuditProvider.registrarAccion(
      accion: datos['accion'],
      entidad: 'peticion',
      entidadId: datos['peticion_id'],
      datosAntiguos: datos.containsKey('datos_anteriores') ? datos['datos_anteriores'] : null,
      datosNuevos: datos.containsKey('datos_nuevos') ? datos['datos_nuevos'] : null,
      metadatos: {
        'reserva_id': datos['reserva_id'],
        'admin_solicitante': datos['admin_solicitante'],
        'super_admin_id': datos.containsKey('super_admin_aprobador') ? datos['super_admin_aprobador'] : datos.containsKey('super_admin_rechazador') ? datos['super_admin_rechazador'] : null,
        'tipo_peticion': datos['tipo_peticion'],
        'motivo_rechazo': datos.containsKey('motivo_rechazo') ? datos['motivo_rechazo'] : null,
      },
      descripcion: datos['descripcion_cambios'] ?? 'Acción en petición',
    );
    
    debugPrint('📝 Registro de auditoría creado');
  } catch (e) {
    debugPrint('⚠️ Error al crear registro de auditoría: $e');
  }
}


  /// **Verificar si el usuario es superadmin**
  Future<bool> esSuperAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final role = userDoc.data()?['rol'] as String?;
        return role == 'superadmin';
      }

      return false;
    } catch (e) {
      debugPrint('Error al verificar rol de superadmin: $e');
      return false;
    }
  }

  /// **Verificar si el usuario es admin**
  Future<bool> esAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final role = userDoc.data()?['rol'] as String?;
        return role == 'admin' || role == 'superadmin';
      }

      return false;
    } catch (e) {
      debugPrint('Error al verificar rol de admin: $e');
      return false;
    }
  }

  /// **Obtener estadísticas básicas**
  Map<String, int> get estadisticas {
    return {
      'total': _peticiones.length,
      'pendientes': _peticiones.where((p) => p.estaPendiente).length,
      'aprobadas': _peticiones.where((p) => p.fueAprobada).length,
      'rechazadas': _peticiones.where((p) => p.fueRechazada).length,
    };
  }

  /// **Obtener estadísticas detalladas**
  Map<String, dynamic> get estadisticasDetalladas {
    final estadisticasBasicas = estadisticas;
    
    final porTipo = <String, int>{};
    final porPrioridad = <String, int>{};
    
    for (final peticion in _peticiones) {
      final tipo = peticion.valoresNuevos['tipo'] as String? ?? 'reserva_normal';
      final prioridad = peticion.valoresNuevos['prioridad'] as String? ?? 'normal';
      
      porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
      porPrioridad[prioridad] = (porPrioridad[prioridad] ?? 0) + 1;
    }
    
    return {
      ...estadisticasBasicas,
      'por_tipo': porTipo,
      'por_prioridad': porPrioridad,
      'total_recurrentes': porTipo['reserva_recurrente_precio'] ?? 0,
      'total_nuevas_recurrentes_descuento': porTipo['nueva_reserva_recurrente_precio_personalizado'] ?? 0, // 🆕 NUEVO
      'total_normales': porTipo['reserva_normal'] ?? 0,
      'total_nuevas_con_descuento': porTipo['nueva_reserva_precio_personalizado'] ?? 0,
      'alta_prioridad': porPrioridad['alta'] ?? 0,
      'muy_alta_prioridad': porPrioridad['muy_alta'] ?? 0,
      'media_prioridad': porPrioridad['media'] ?? 0,
    };
  }

  // Métodos auxiliares para obtener peticiones específicas
  List<Peticion> getPeticionesPorPrioridad(String prioridad) {
    return _peticiones.where((p) => 
      (p.valoresNuevos['prioridad'] as String? ?? 'normal') == prioridad &&
      p.estaPendiente
    ).toList();
  }

  List<Peticion> get peticionesNuevasReservasDescuento {
    return _peticiones.where((p) => 
      (p.valoresNuevos['tipo'] as String?) == 'nueva_reserva_precio_personalizado'
    ).toList();
  }

  Future<bool> puedeCrearReservaConDescuentoDirectamente() async {
    if (await esSuperAdmin()) {
      return true;
    }

    if (await esAdmin() && _controlTotalActivado) {
      return true;
    }

    return false;
  }

  /// **Limpiar peticiones locales**
  void limpiar() {
    _peticiones = [];
    _isLoading = false;
    _controlTotalActivado = false;
    detenerEscuchaControlTotal();
    notifyListeners();
  }

  @override
  void dispose() {
    detenerEscuchaControlTotal();
    super.dispose();
  }

  Future<void> _aplicarCambiosNuevaReservaRecurrente(Map<String, dynamic> nuevosValores) async {
    try {
      final datosReservaRecurrente = nuevosValores['datos_reserva_recurrente'] as Map<String, dynamic>?;
      if (datosReservaRecurrente == null) {
        throw Exception('No se encontraron datos de la reserva recurrente');
      }
      
      // Validaciones mejoradas
      _validarDatosNuevaReservaRecurrente(datosReservaRecurrente);
      
      final montoTotal = datosReservaRecurrente['monto_total'] as double;
      final montoPagado = datosReservaRecurrente['monto_pagado'] as double;
      final precioOriginal = nuevosValores['precio_original'] as double;
      final descuentoAplicado = nuevosValores['descuento_aplicado'] as double;
  
      debugPrint('📄 Creando reserva recurrente desde petición aprobada');
      debugPrint('🏟️ Cancha: ${datosReservaRecurrente['cancha_nombre']}');
      debugPrint('📅 Fecha inicio: ${datosReservaRecurrente['fecha_inicio']}');
      debugPrint('🗓️ Días semana: ${datosReservaRecurrente['dias_semana']}');
      debugPrint('🕐 Horario: ${datosReservaRecurrente['horario']}');
  
      // Crear la reserva recurrente en Firestore
      await _crearReservaRecurrenteFirestore(datosReservaRecurrente, nuevosValores);
  
      debugPrint('✅ Reserva recurrente creada exitosamente');
      
    } catch (e) {
      debugPrint('❌ Error al crear nueva reserva recurrente: $e');
      throw Exception('Error al crear la reserva recurrente: $e');
    }
  }

  void _validarDatosNuevaReservaRecurrente(Map<String, dynamic> datosReserva) {
    final camposRequeridos = [
      'cancha_id', 'cancha_nombre', 'fecha_inicio', 'horario', 
      'sede', 'cliente_nombre', 'cliente_telefono', 'dias_semana',
      'monto_total', 'monto_pagado'
    ];
    
    for (final campo in camposRequeridos) {
      if (!datosReserva.containsKey(campo) || datosReserva[campo] == null) {
        throw Exception('Campo requerido faltante: $campo');
      }
    }
    
    final diasSemana = datosReserva['dias_semana'];
    if (diasSemana is! List || diasSemana.isEmpty) {
      throw Exception('Lista de días de la semana inválida');
    }
    
    final montoTotal = datosReserva['monto_total'] as double?;
    final montoPagado = datosReserva['monto_pagado'] as double?;
    
    if (montoTotal == null || montoTotal <= 0) {
      throw Exception('Monto total inválido');
    }
    if (montoPagado == null || montoPagado < 0) {
      throw Exception('Monto pagado inválido');
    }
  }

  Future<void> _crearReservaRecurrenteFirestore(
    Map<String, dynamic> datosReservaRecurrente,
    Map<String, dynamic> nuevosValores
  ) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('reservas_recurrentes')
          .doc();
  
      // Parsear fecha de inicio
      final fechaInicioStr = datosReservaRecurrente['fecha_inicio'] as String;
      final fechaInicio = DateTime.parse(fechaInicioStr);
      
      // Parsear fecha de fin si existe
      DateTime? fechaFin;
      final fechaFinStr = datosReservaRecurrente['fecha_fin'] as String?;
      if (fechaFinStr != null && fechaFinStr.isNotEmpty) {
        fechaFin = DateTime.parse(fechaFinStr);
      }
  
      final datosFirestore = {
        'clienteId': datosReservaRecurrente['cliente_id'],
        'clienteNombre': datosReservaRecurrente['cliente_nombre'],
        'clienteTelefono': datosReservaRecurrente['cliente_telefono'],
        'clienteEmail': datosReservaRecurrente['cliente_email'],
        'canchaId': datosReservaRecurrente['cancha_id'],
        'sede': datosReservaRecurrente['sede'],
        'horario': datosReservaRecurrente['horario'],
        'diasSemana': datosReservaRecurrente['dias_semana'],
        'tipoRecurrencia': 'semanal',
        'estado': 'activa',
        'fechaInicio': fechaInicio,
        'fechaFin': fechaFin,
        'montoTotal': datosReservaRecurrente['monto_total'],
        'montoPagado': datosReservaRecurrente['monto_pagado'],
        'diasExcluidos': datosReservaRecurrente['dias_excluidos'] ?? [],
        'fechaCreacion': Timestamp.now(),
        'fechaActualizacion': Timestamp.now(),
        'notas': datosReservaRecurrente['notas'],
        'creadaPorPeticion': true,
        'peticionAprobada': true,
        'precioPersonalizado': nuevosValores['precioPersonalizado'] ?? false,
        'precioOriginal': nuevosValores['precioOriginal'],
        'descuentoAplicado': nuevosValores['descuentoAplicado'],
      };
  
      await docRef.set(datosFirestore);
      
      debugPrint('📋 Reserva recurrente creada con ID: ${docRef.id}');
      
    } catch (e) {
      debugPrint('❌ Error creando reserva recurrente en Firestore: $e');
      throw Exception('Error al crear la reserva recurrente: $e');
    }
  }

  List<Peticion> getPeticionesPorTipo(String tipo) {
    return _peticiones.where((p) => 
      (p.valoresNuevos['tipo'] as String? ?? 'reserva_normal') == tipo
    ).toList();
  }

  List<Peticion> get peticionesNuevasReservasRecurrentesDescuento {
    return _peticiones.where((p) => 
      (p.valoresNuevos['tipo'] as String?) == 'nueva_reserva_recurrente_precio_personalizado'
    ).toList();
  }

  List<Peticion> get peticionesPendientesRecurrentes {
    return _peticiones.where((p) => 
      p.estaPendiente && 
      ((p.valoresNuevos['tipo'] as String?) == 'reserva_recurrente_precio' ||
       (p.valoresNuevos['tipo'] as String?) == 'nueva_reserva_recurrente_precio_personalizado')
    ).toList();
  }

  List<Peticion> get peticionesPendientesNormales {
    return _peticiones.where((p) => 
      p.estaPendiente && 
      ((p.valoresNuevos['tipo'] as String?) == 'reserva_normal' ||
       (p.valoresNuevos['tipo'] as String?) == 'nueva_reserva_precio_personalizado')
    ).toList();
  }

  Future<bool> puedeCrearReservaRecurrenteConDescuentoDirectamente() async {
    if (await esSuperAdmin()) {
      return true;
    }
  
    if (await esAdmin() && _controlTotalActivado) {
      return true;
    }
  
    return false;
  }

  Map<String, Map<String, int>> get resumenPeticionesPorTipo {
    final resumen = <String, Map<String, int>>{};
    
    final tipos = [
      'reserva_normal',
      'nueva_reserva_precio_personalizado', 
      'reserva_recurrente_precio',
      'nueva_reserva_recurrente_precio_personalizado',
    ];
    
    for (final tipo in tipos) {
      final peticionesTipo = _peticiones.where((p) => 
        (p.valoresNuevos['tipo'] as String? ?? 'reserva_normal') == tipo
      ).toList();
      
      resumen[tipo] = {
        'total': peticionesTipo.length,
        'pendientes': peticionesTipo.where((p) => p.estaPendiente).length,
        'aprobadas': peticionesTipo.where((p) => p.fueAprobada).length,
        'rechazadas': peticionesTipo.where((p) => p.fueRechazada).length,
      };
    }
    
    return resumen;
  }

  static String obtenerNombreTipoPeticion(String tipo) {
    switch (tipo) {
      case 'reserva_normal':
        return 'Reserva Normal';
      case 'nueva_reserva_precio_personalizado':
        return 'Nueva Reserva con Descuento';
      case 'reserva_recurrente_precio':
        return 'Reserva Recurrente';
      case 'nueva_reserva_recurrente_precio_personalizado':
        return 'Nueva Reserva Recurrente con Descuento';
      default:
        return 'Tipo Desconocido';
    }
  }
}

extension StringCapitalize on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}