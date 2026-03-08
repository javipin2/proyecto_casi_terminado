// agregar_reserva_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:reserva_canchas/services/plan_feature_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/utils/reserva_audit_utils.dart';

import '../../../models/cancha.dart';
import '../../../models/horario.dart';
import '../../../models/reserva.dart';
import '../../../models/cliente.dart';
import '../../../models/reserva_recurrente.dart';
import '../../../providers/reserva_recurrente_provider.dart';
import '../../../services/lugar_helper.dart';


class AgregarReservaScreen extends StatefulWidget {
  final DateTime fecha;
  final List<Horario> horarios;
  final Cancha cancha;
  final String sede;

  const AgregarReservaScreen({
    super.key,
    required this.fecha,
    required this.horarios,
    required this.cancha,
    required this.sede,
  });

  @override
  AgregarReservaScreenState createState() => AgregarReservaScreenState();
}

class AgregarReservaScreenState extends State<AgregarReservaScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreController;
  late TextEditingController _telefonoController;
  late TextEditingController _abonoController;
  late TextEditingController _precioTotalController;
  late TextEditingController _notasController;
  TipoAbono? _selectedTipo;
  bool _isProcessing = false;
  String? _selectedClienteId;
  bool _showAbonoField = true;
  late AnimationController _fadeController;
  bool _precioEditableActivado = false;
  bool _esReservaRecurrente = false;
  List<String> _diasSeleccionados = [];
  DateTime? _fechaFinRecurrencia;
  List<Map<String, dynamic>> _conflictosDetectados = [];
  bool _verificandoConflictos = false; // Nueva variable para loading state
  // bool _esAdmin = false; // Reservado para uso futuro si es necesario
  
  // 🚀 Optimizaciones para verificación de conflictos
  Timer? _debounceTimer;
  String? _cachedLugarId; // Cache del lugarId para evitar consultas repetidas
  Map<String, List<Map<String, dynamic>>> _cacheConflictos = {}; // Cache de conflictos por combinación de días
  int _verificacionId = 0; // ID para cancelar verificaciones obsoletas

  final List<String> _diasSemana = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo'
  ];

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);
  final Color _disabledColor = const Color(0xFFDADCE0);

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController();
    _telefonoController = TextEditingController();
    _abonoController = TextEditingController(text: '0');
    _precioTotalController = TextEditingController();
    _notasController = TextEditingController();
    _selectedTipo = TipoAbono.parcial;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inicializarPrecioTotal();
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel(); // Cancelar timer pendiente
    _nombreController.dispose();
    _telefonoController.dispose();
    _abonoController.dispose();
    _precioTotalController.dispose();
    _notasController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  double _calcularMontoTotal() {
    if (_precioEditableActivado && _precioTotalController.text.isNotEmpty) {
      return double.tryParse(_precioTotalController.text) ?? 0.0;
    }

    double total = 0.0;
    for (final horario in widget.horarios) {
      final precio = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
      total += precio;
    }
    return total;
  }

  void _inicializarPrecioTotal() {
    if (!_precioEditableActivado) {
      double total = 0.0;
      for (final horario in widget.horarios) {
        final precio = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
        total += precio;
      }
      _precioTotalController.text = total.toStringAsFixed(0);
    }
  }

  /// 🚀 Versión optimizada con debounce, cache y paralelización
  void _verificarConflictosReservasDebounced() {
    // Cancelar timer anterior si existe
    _debounceTimer?.cancel();
    
    // Crear nuevo timer con debounce de 500ms
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _verificarConflictosReservas();
    });
  }

  Future<void> _verificarConflictosReservas() async {
    if (!_esReservaRecurrente || widget.horarios.isEmpty || _diasSeleccionados.isEmpty) {
      setState(() {
        _conflictosDetectados = [];
        _verificandoConflictos = false;
      });
      return;
    }

    // 🚀 Generar clave de cache basada en días seleccionados y fecha
    final cacheKey = '${_diasSeleccionados.join(",")}_${widget.fecha.toIso8601String()}_${widget.cancha.id}';
    
    // 🚀 Verificar cache primero
    if (_cacheConflictos.containsKey(cacheKey)) {
      setState(() {
        _conflictosDetectados = _cacheConflictos[cacheKey]!;
        _verificandoConflictos = false;
      });
      debugPrint('✅ Conflictos obtenidos del cache');
      return;
    }

    // 🚀 Incrementar ID de verificación para cancelar verificaciones obsoletas
    final currentVerificacionId = ++_verificacionId;

    setState(() {
      _verificandoConflictos = true;
    });

    try {
      final horario = widget.horarios.first;
      
      // 🚀 Obtener lugarId una sola vez (con cache)
      if (_cachedLugarId == null) {
        _cachedLugarId = await LugarHelper.getLugarId();
      }
      
      final lugarId = _cachedLugarId;
      if (lugarId == null) {
        debugPrint('⚠️ AgregarReservaScreen: No se pudo obtener lugarId');
        setState(() {
          _conflictosDetectados = [];
          _verificandoConflictos = false;
        });
        return;
      }

      // 🚀 Pre-calcular todas las fechas a verificar
      final fechasAVerificar = <String>[];
      final fechaInicioMap = <String, DateTime>{}; // Map para evitar recalcular
      
      for (String dia in _diasSeleccionados) {
        DateTime fechaActual = widget.fecha;
        
        // Encontrar el próximo día de la semana especificado
        while (DateFormat('EEEE', 'es').format(fechaActual).toLowerCase() != dia) {
          fechaActual = fechaActual.add(const Duration(days: 1));
        }
        
        fechaInicioMap[dia] = fechaActual;

        // Agregar las próximas 8 ocurrencias
        for (int i = 0; i < 8; i++) {
          final fechaVerificar = fechaActual.add(Duration(days: i * 7));
          fechasAVerificar.add(DateFormat('yyyy-MM-dd').format(fechaVerificar));
        }
      }

      // 🚀 OPTIMIZACIÓN: Paralelizar consultas en lugar de secuenciales
      if (fechasAVerificar.isNotEmpty) {
        final batchSize = 10; // Firebase permite máximo 10 elementos en whereIn
        final batches = <List<String>>[];
        
        // Dividir fechas en batches
        for (int i = 0; i < fechasAVerificar.length; i += batchSize) {
          batches.add(fechasAVerificar.skip(i).take(batchSize).toList());
        }

        // 🚀 Ejecutar todas las consultas en paralelo
        final futures = batches.map((batch) async {
          // Verificar si esta verificación sigue siendo válida
          if (currentVerificacionId != _verificacionId) {
            return <Map<String, dynamic>>[];
          }

          try {
            final querySnapshot = await FirebaseFirestore.instance
                .collection('reservas')
                .where('fecha', whereIn: batch)
                .where('cancha_id', isEqualTo: widget.cancha.id)
                .where('horario', isEqualTo: horario.horaFormateada)
                .where('lugarId', isEqualTo: lugarId)
                .get();

            final conflictosBatch = <Map<String, dynamic>>[];
            
            for (final doc in querySnapshot.docs) {
              final data = doc.data();
              
              // 🚫 FILTRAR RESERVAS CON ESTADO "devolucion" - NO SON CONFLICTOS
              final estado = data['estado'] as String?;
              if (estado == 'devolucion') {
                debugPrint('🚫 Reserva ${doc.id} excluida por tener estado "devolucion"');
                continue; // Saltar esta reserva - no es un conflicto
              }
              
              // 🚫 TAMBIÉN FILTRAR RESERVAS SIN CAMPO "confirmada" (pueden ser devoluciones antiguas)
              // Las devoluciones eliminan el campo confirmada, así que si no existe, podría ser devolución
              // Pero mejor confiar en el campo 'estado' que es más explícito
              
              final fechaStr = data['fecha'] as String;
              final fecha = DateTime.parse(fechaStr);
              
              conflictosBatch.add({
                'fecha': fecha,
                'fechaStr': DateFormat('dd/MM/yyyy').format(fecha),
                'dia': DateFormat('EEEE', 'es').format(fecha).toLowerCase(),
                'horario': horario.horaFormateada,
                'nombre': data['nombre'] ?? 'Sin nombre',
                'telefono': data['telefono'] ?? 'Sin teléfono',
                'precio': data['valor']?.toDouble() ?? 0.0,
                'reservaId': doc.id,
              });
            }
            
            return conflictosBatch;
          } catch (e) {
            debugPrint('⚠️ Error en batch de consulta: $e');
            return <Map<String, dynamic>>[];
          }
        }).toList();

        // 🚀 Esperar todas las consultas en paralelo
        final resultados = await Future.wait(futures);
        
        // Verificar si esta verificación sigue siendo válida después de las consultas
        if (currentVerificacionId != _verificacionId) {
          debugPrint('⏭️ Verificación cancelada (nueva verificación iniciada)');
          return;
        }

        // Combinar todos los resultados
        final conflictos = <Map<String, dynamic>>[];
        for (final resultado in resultados) {
          conflictos.addAll(resultado);
        }

        // 🚀 Eliminar duplicados (por si acaso)
        final conflictosUnicos = <String, Map<String, dynamic>>{};
        for (final conflicto in conflictos) {
          final key = '${conflicto['fechaStr']}_${conflicto['horario']}';
          conflictosUnicos[key] = conflicto;
        }

        final conflictosFinales = conflictosUnicos.values.toList();
        
        // 🚀 Guardar en cache
        _cacheConflictos[cacheKey] = conflictosFinales;
        
        // 🚀 Limpiar cache antiguo (mantener solo últimas 10 entradas)
        if (_cacheConflictos.length > 10) {
          final keysToRemove = _cacheConflictos.keys.take(_cacheConflictos.length - 10).toList();
          for (final key in keysToRemove) {
            _cacheConflictos.remove(key);
          }
        }

        if (mounted && currentVerificacionId == _verificacionId) {
          setState(() {
            _conflictosDetectados = conflictosFinales;
            _verificandoConflictos = false;
          });
          
          debugPrint('✅ Conflictos verificados: ${conflictosFinales.length} encontrados');
        }
      } else {
        if (mounted && currentVerificacionId == _verificacionId) {
          setState(() {
            _conflictosDetectados = [];
            _verificandoConflictos = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error al verificar conflictos: $e');
      if (mounted && currentVerificacionId == _verificacionId) {
        setState(() {
          _conflictosDetectados = [];
          _verificandoConflictos = false;
        });
      }
    }
  }



  Future<void> _crearReserva() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() {
    _isProcessing = true;
  });

  try {
    if (_esReservaRecurrente) {
      await _crearReservaRecurrente();
    } else {
      await _crearReservaNormal();
    }
  } catch (e) {
    if (!mounted) return;

    String tipoReserva = _esReservaRecurrente ? ' reserva recurrente' : widget.horarios.length > 1 ? 's reservas' : ' reserva';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Error al crear la$tipoReserva: ${e.toString()}',
          style: GoogleFonts.montserrat(),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }
}



  Future<void> _crearReservaNormal() async {
  final distribucionPrecios = _calcularDistribucionPrecio();
  final montoTotalGeneral = _calcularMontoTotal();

  final abonoTotal = _selectedTipo == TipoAbono.completo
      ? montoTotalGeneral
      : double.parse(_abonoController.text);

  final distribucionAbono =
      _calcularDistribucionAbono(abonoTotal, montoTotalGeneral, distribucionPrecios);

  String? grupoReservaId;
  if (widget.horarios.length > 1) {
    grupoReservaId = DateTime.now().millisecondsSinceEpoch.toString();
  }

  final List<String> reservasCreadas = [];

  for (final horario in widget.horarios) {
    final precioHora = distribucionPrecios[horario]!;
    final abonoHora = distribucionAbono[horario]!;

    // Obtener lugarId del usuario autenticado
    final lugarId = await LugarHelper.getLugarId();
    if (lugarId == null) {
      throw Exception('No se pudo obtener el lugarId del usuario autenticado');
    }

    final reserva = Reserva(
      id: '',
      cancha: widget.cancha,
      fecha: widget.fecha,
      horario: horario,
      sede: widget.sede,
      tipoAbono: _selectedTipo!,
      montoTotal: precioHora,
      montoPagado: abonoHora,
      nombre: _nombreController.text,
      telefono: _telefonoController.text,
      confirmada: true,
      lugarId: lugarId, // ✅ Agregar lugarId
    );

    final docRef = FirebaseFirestore.instance.collection('reservas').doc();
    final datosReserva = reserva.toFirestore();

    if (grupoReservaId != null) {
      datosReserva['grupo_reserva_id'] = grupoReservaId;
      datosReserva['total_horas_grupo'] = widget.horarios.length;
    }

    if (_precioEditableActivado) {
      final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
      datosReserva['precio_original'] = precioOriginal;
      datosReserva['precio_personalizado'] = true;
      datosReserva['descuento_aplicado'] = precioOriginal - precioHora;
    }

    await docRef.set(datosReserva);
    reservasCreadas.add(docRef.id);
  }

  // 🔥 AGREGAR AUDITORÍA AQUÍ - Después de crear todas las reservas
  try {
    // Auditoría para cada reserva creada
    for (int i = 0; i < reservasCreadas.length; i++) {
      final reservaId = reservasCreadas[i];
      final horario = widget.horarios[i];
      final precioHora = distribucionPrecios[horario]!;
      final abonoHora = distribucionAbono[horario]!;
      
      // Calcular contexto para auditoría
      double? descuentoAplicado;
      if (_precioEditableActivado) {
        final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
        descuentoAplicado = precioOriginal - precioHora;
      }

      // Datos de la reserva para auditoría
      final datosReserva = {
        'nombre': _nombreController.text,
        'telefono': _telefonoController.text,
        'fecha': DateFormat('yyyy-MM-dd').format(widget.fecha),
        'horario': horario.horaFormateada,
        'cancha_nombre': widget.cancha.nombre,
        'cancha_id': widget.cancha.id,
        'sede': widget.sede,
        'montoTotal': precioHora,
        'montoPagado': abonoHora,
        'estado': abonoHora >= precioHora ? 'completo' : 'parcial',
        'confirmada': true,
        'precio_personalizado': _precioEditableActivado,
      };

      await ReservaAuditUtils.auditarCreacionReserva(
        reservaId: reservaId,
        datosReserva: datosReserva,
        tieneDescuento: _precioEditableActivado,
        descuentoAplicado: descuentoAplicado,
        esReservaGrupal: widget.horarios.length > 1,
        cantidadHoras: widget.horarios.length,
        contextoPrecio: {
          'precio_original': _precioEditableActivado 
              ? Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario)
              : precioHora,
          'precio_aplicado': precioHora,
          'metodo_creacion': 'interfaz_creacion',
          'grupo_reserva_id': grupoReservaId,
        },
      );
    }
  } catch (e) {
    debugPrint('⚠️ Error en auditoría de creación: $e');
    // No interrumpir el flujo si la auditoría falla
  }

  debugPrint('=== RESUMEN DE RESERVAS CREADAS ===');
  debugPrint('Total de horas: ${widget.horarios.length}');
  debugPrint('ID de grupo: ${grupoReservaId ?? "No aplica (reserva individual)"}');
  debugPrint('Precio personalizado activado: $_precioEditableActivado');
  debugPrint('Monto total: ${montoTotalGeneral.toStringAsFixed(0)}');
  debugPrint('Abono total: ${abonoTotal.toStringAsFixed(0)}');

  for (final horario in widget.horarios) {
    final precioHora = distribucionPrecios[horario]!;
    final abonoHora = distribucionAbono[horario]!;
    debugPrint(
        '${horario.horaFormateada}: Precio=${precioHora.toStringAsFixed(0)}, Abono=${abonoHora.toStringAsFixed(0)}');
  }
  debugPrint('Reservas creadas: ${reservasCreadas.length}');

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Reserva${widget.horarios.length > 1 ? 's' : ''} creada${widget.horarios.length > 1 ? 's' : ''} exitosamente.${_precioEditableActivado ? ' Descuento aplicado.' : ''}${grupoReservaId != null ? ' ID de grupo: $grupoReservaId' : ''}',
        style: GoogleFonts.montserrat(),
      ),
      backgroundColor: _secondaryColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 4),
    ),
  );

  await Future.delayed(const Duration(milliseconds: 100));
  if (mounted) {
    Navigator.of(context).pop(true);
  }
}


  Future<void> _crearReservaRecurrente() async {
  if (widget.horarios.length > 1) {
    throw Exception('Las reservas recurrentes solo admiten un horario por vez');
  }

  final horario = widget.horarios.first;
  final montoTotal = _calcularMontoTotal();
  final montoPagado = _selectedTipo == TipoAbono.completo
      ? montoTotal
      : double.parse(_abonoController.text);

  // ✅ CALCULAR PRECIO ORIGINAL Y DESCUENTO SI ESTÁ ACTIVADO
  double? precioOriginal;
  double? descuentoAplicado;
  bool precioPersonalizado = false;

  if (_precioEditableActivado && _precioTotalController.text.isNotEmpty) {
    precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
    final precioPersonalizadoValor = double.tryParse(_precioTotalController.text) ?? 0.0;
    descuentoAplicado = precioOriginal - precioPersonalizadoValor;
    precioPersonalizado = true;
  }

  // ✅ CREAR LISTA DE DÍAS EXCLUIDOS BASADA EN CONFLICTOS
  final List<String> diasExcluidos = [];
  for (var conflicto in _conflictosDetectados) {
    final fechaConflicto = DateFormat('yyyy-MM-dd').format(conflicto['fecha']);
    diasExcluidos.add(fechaConflicto);
  }

  // Obtener lugarId del usuario autenticado
  final lugarId = await LugarHelper.getLugarId();
  if (lugarId == null) {
    throw Exception('No se pudo obtener el lugarId del usuario autenticado');
  }

  final reservaRecurrente = ReservaRecurrente(
    id: '',
    clienteId: _selectedClienteId ?? '',
    clienteNombre: _nombreController.text,
    clienteTelefono: _telefonoController.text,
    canchaId: widget.cancha.id,
    sede: widget.sede,
    horario: horario.horaFormateada,
    diasSemana: _diasSeleccionados,
    tipoRecurrencia: TipoRecurrencia.semanal,
    estado: EstadoRecurrencia.activa,
    fechaInicio: widget.fecha,
    fechaFin: _fechaFinRecurrencia,
    montoTotal: montoTotal,
    montoPagado: montoPagado,
    diasExcluidos: diasExcluidos,
    fechaCreacion: DateTime.now(),
    fechaActualizacion: DateTime.now(),
    notas: _notasController.text.isEmpty ? null : _notasController.text,
    precioPersonalizado: precioPersonalizado,
    precioOriginal: precioOriginal,
    descuentoAplicado: descuentoAplicado,
    lugarId: lugarId, // ✅ Agregar lugarId
  );

  final reservaRecurrenteProvider =
      Provider.of<ReservaRecurrenteProvider>(context, listen: false);
  
  // 🔑 DESHABILITAR TEMPORALMENTE CUALQUIER AUDITORÍA AUTOMÁTICA
  // La auditoría se maneja manualmente después de crear la reserva recurrente
  final reservaConMarcador = ReservaRecurrente(
    id: reservaRecurrente.id,
    clienteId: reservaRecurrente.clienteId,
    clienteNombre: reservaRecurrente.clienteNombre,
    clienteTelefono: reservaRecurrente.clienteTelefono,
    canchaId: reservaRecurrente.canchaId,
    sede: reservaRecurrente.sede,
    horario: reservaRecurrente.horario,
    diasSemana: reservaRecurrente.diasSemana,
    tipoRecurrencia: reservaRecurrente.tipoRecurrencia,
    estado: reservaRecurrente.estado,
    fechaInicio: reservaRecurrente.fechaInicio,
    fechaFin: reservaRecurrente.fechaFin,
    montoTotal: reservaRecurrente.montoTotal,
    montoPagado: reservaRecurrente.montoPagado,
    diasExcluidos: reservaRecurrente.diasExcluidos,
    fechaCreacion: reservaRecurrente.fechaCreacion,
    fechaActualizacion: reservaRecurrente.fechaActualizacion,
    notas: reservaRecurrente.notas,
    precioPersonalizado: reservaRecurrente.precioPersonalizado,
    precioOriginal: reservaRecurrente.precioOriginal,
    descuentoAplicado: reservaRecurrente.descuentoAplicado,
    lugarId: reservaRecurrente.lugarId, // ✅ Agregar lugarId
    // Agregar marcador para evitar auditoría automática
  );

  final reservaRecurrenteId = await reservaRecurrenteProvider.crearReservaRecurrente(reservaConMarcador);

  // 🔥 REGISTRAR AUDITORÍA MANUAL - SOLO UNA VEZ
  try {
    final datosReservaRecurrente = {
      'nombre': _nombreController.text,
      'telefono': _telefonoController.text,
      'fecha': DateFormat('yyyy-MM-dd').format(widget.fecha),
      'fecha_fin': _fechaFinRecurrencia != null ? DateFormat('yyyy-MM-dd').format(_fechaFinRecurrencia!) : null,
      'horario': horario.horaFormateada,
      'cancha_nombre': widget.cancha.nombre,
      'cancha_id': widget.cancha.id,
      'sede': widget.sede,
      'montoTotal': montoTotal,
      'montoPagado': montoPagado,
      'estado': montoPagado >= montoTotal ? 'completo' : 'parcial',
      'dias_semana': _diasSeleccionados,
      'precio_personalizado': precioPersonalizado,
      'tipo_recurrencia': 'semanal',
    };

    // 🎯 REGISTRAR UNA SOLA AUDITORÍA PARA TODA LA RESERVA RECURRENTE
    await ReservaAuditUtils.auditarCreacionReserva(
      reservaId: reservaRecurrenteId,
      datosReserva: datosReservaRecurrente,
      tieneDescuento: precioPersonalizado,
      descuentoAplicado: descuentoAplicado,
      esReservaGrupal: false, // Aunque sea recurrente, no es grupal
      cantidadHoras: 1,
      contextoPrecio: {
        'precio_original': precioOriginal ?? montoTotal,
        'precio_aplicado': montoTotal,
        'metodo_creacion': 'reserva_recurrente',
        'dias_semana': _diasSeleccionados.length,
        'fecha_inicio': DateFormat('yyyy-MM-dd').format(widget.fecha),
        'fecha_fin': _fechaFinRecurrencia != null ? DateFormat('yyyy-MM-dd').format(_fechaFinRecurrencia!) : null,
        'conflictos_excluidos': _conflictosDetectados.length,
        'es_reserva_recurrente': true,
        // 🔧 MARCAR PARA EVITAR AUDITORÍAS DUPLICADAS
        'auditoria_manual': true,
        'fuente_creacion': 'interfaz_usuario',
      },
    );

    debugPrint('✅ Auditoría de reserva recurrente registrada: $reservaRecurrenteId');
    
  } catch (e) {
    debugPrint('⚠️ Error en auditoría de creación de reserva recurrente: $e');
    // No interrumpir el flujo si la auditoría falla
  }

  if (!mounted) return;

  final mensajeDescuento = precioPersonalizado && (descuentoAplicado ?? 0) > 0 
      ? ' Con descuento de COP ${descuentoAplicado!.toStringAsFixed(0)} por reserva.'
      : '';

  final mensajeConflictos = _conflictosDetectados.isNotEmpty
      ? '\n\n⚠️ IMPORTANTE: Se excluyeron automáticamente ${_conflictosDetectados.length} fecha(s) con conflictos. La reserva recurrente se creó solo para los días sin conflictos.'
      : '';

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '✅ Reserva recurrente creada exitosamente. Los horarios se aplicarán automáticamente según la programación.$mensajeDescuento$mensajeConflictos',
        style: GoogleFonts.montserrat(),
      ),
      backgroundColor: _conflictosDetectados.isNotEmpty 
          ? Colors.orange.shade600 
          : _secondaryColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: Duration(seconds: _conflictosDetectados.isNotEmpty ? 7 : 5),
    ),
  );

  await Future.delayed(const Duration(milliseconds: 100));
  if (mounted) {
    Navigator.of(context).pop(true);
  }
}


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

  Map<Horario, double> _calcularDistribucionPrecio() {
    final Map<Horario, double> distribucion = {};

    if (_precioEditableActivado && _precioTotalController.text.isNotEmpty) {
      final precioPersonalizado = double.tryParse(_precioTotalController.text) ?? 0.0;

      final Map<Horario, double> preciosOriginales = {};
      double totalOriginal = 0.0;

      for (final horario in widget.horarios) {
        final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
        preciosOriginales[horario] = precioOriginal;
        totalOriginal += precioOriginal;
      }

      if (totalOriginal > 0) {
        double sumaDistribuida = 0.0;
        List<double> preciosTemporales = [];

        for (int i = 0; i < widget.horarios.length - 1; i++) {
          final horario = widget.horarios[i];
          final precioOriginal = preciosOriginales[horario]!;
          final proporcion = precioOriginal / totalOriginal;
          final precioDistribuido = precioPersonalizado * proporcion;

          final precioRedondeado = _redondearANumeroLimpio(precioDistribuido);
          preciosTemporales.add(precioRedondeado);
          sumaDistribuida += precioRedondeado;
        }

        final precioUltimoHorario = precioPersonalizado - sumaDistribuida;
        preciosTemporales.add(precioUltimoHorario);

        for (int i = 0; i < widget.horarios.length; i++) {
          distribucion[widget.horarios[i]] = preciosTemporales[i];
        }
      } else {
        final precioPorHora = precioPersonalizado / widget.horarios.length;
        final precioRedondeado = _redondearANumeroLimpio(precioPorHora);
        double sumaDistribuida = 0.0;

        for (int i = 0; i < widget.horarios.length - 1; i++) {
          distribucion[widget.horarios[i]] = precioRedondeado;
          sumaDistribuida += precioRedondeado;
        }

        distribucion[widget.horarios.last] = precioPersonalizado - sumaDistribuida;
      }
    } else {
      for (final horario in widget.horarios) {
        distribucion[horario] =
            Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
      }
    }

    return distribucion;
  }

  Map<Horario, double> _calcularDistribucionAbono(
      double abonoTotal, double montoTotalGeneral, Map<Horario, double> distribucionPrecios) {
    final Map<Horario, double> distribucionAbono = {};
    double sumaAbonos = 0.0;
    List<double> abonosTemporales = [];

    for (int i = 0; i < widget.horarios.length - 1; i++) {
      final horario = widget.horarios[i];
      final precioHora = distribucionPrecios[horario]!;

      final proporcionAbono =
          montoTotalGeneral > 0 ? (precioHora / montoTotalGeneral) : (1.0 / widget.horarios.length);
      final abonoHora = abonoTotal * proporcionAbono;

      final abonoRedondeado = _redondearANumeroLimpio(abonoHora);
      abonosTemporales.add(abonoRedondeado);
      sumaAbonos += abonoRedondeado;
    }

    final abonoUltimoHorario = abonoTotal - sumaAbonos;
    abonosTemporales.add(abonoUltimoHorario);

    for (int i = 0; i < widget.horarios.length; i++) {
      distribucionAbono[widget.horarios[i]] = abonosTemporales[i];
    }

    return distribucionAbono;
  }

  void _seleccionarCliente(Cliente? cliente) {
    if (cliente != null) {
      setState(() {
        _selectedClienteId = cliente.id;
        _nombreController.text = cliente.nombre;
        _telefonoController.text = cliente.telefono;
      });
    } else {
      setState(() {
        _selectedClienteId = null;
        _nombreController.clear();
        _telefonoController.clear();
        _abonoController.text = '0';
      });
    }
  }

  Widget _buildRecurrenciaToggle() {
    final puedeActivarRecurrencia = widget.horarios.length == 1;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _esReservaRecurrente
            ? Color.fromRGBO(66, 133, 244, 0.05)
            : Color.fromRGBO(158, 158, 158, 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _esReservaRecurrente
              ? Color.fromRGBO(66, 133, 244, 0.3)
              : Color.fromRGBO(158, 158, 158, 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.repeat,
                color: _esReservaRecurrente 
                    ? _secondaryColor 
                    : puedeActivarRecurrencia 
                        ? Color.fromRGBO(158, 158, 158, 1.0) 
                        : Color.fromRGBO(158, 158, 158, 0.5),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reserva Recurrente',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: puedeActivarRecurrencia 
                            ? _primaryColor 
                            : Color.fromRGBO(60, 64, 67, 0.5),
                      ),
                    ),
                    Text(
                      puedeActivarRecurrencia
                          ? 'Selecciona días de la semana para repetir'
                          : 'Solo disponible para un horario',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: puedeActivarRecurrencia 
                            ? Color.fromRGBO(60, 64, 67, 0.6)
                            : Color.fromRGBO(255, 152, 0, 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _esReservaRecurrente,
                onChanged: puedeActivarRecurrencia
                    ? (value) async {
                        // 🔐 Validar plan: reservas recurrentes solo para Plan Premium o Pro
                        final allowed = await PlanFeatureService.ensureFeatureAvailable(
                          context,
                          PlanFeature.reservasRecurrentes,
                        );
                        if (!allowed) {
                          // Asegurar que el switch vuelva a apagado
                          if (mounted) {
                            setState(() {
                              _esReservaRecurrente = false;
                            });
                          }
                          return;
                        }

                        if (!mounted) return;

                        setState(() {
                          _esReservaRecurrente = value;
                          if (value) {
                            final diaSemanaActual =
                                DateFormat('EEEE', 'es').format(widget.fecha).toLowerCase();
                            _diasSeleccionados = [diaSemanaActual];
                            // 🚀 Verificar conflictos con debounce
                            _verificarConflictosReservasDebounced();
                          } else {
                            _diasSeleccionados.clear();
                            _conflictosDetectados.clear();
                            _cacheConflictos.clear(); // Limpiar cache al desactivar recurrencia
                          }
                        });
                      }
                    : null,
                activeColor: _secondaryColor,
              ),
            ],
          ),
          if (!puedeActivarRecurrencia) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Color.fromRGBO(255, 152, 0, 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Color.fromRGBO(255, 152, 0, 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Las reservas recurrentes requieren seleccionar exactamente un horario',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecurrenciaSection() {
    if (!_esReservaRecurrente) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración de Recurrencia Semanal',
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Días de la semana',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _diasSemana.map((dia) {
                final isSelected = _diasSeleccionados.contains(dia);
                return FilterChip(
                  label: Text(
                    dia.substring(0, 3).toUpperCase(),
                    style: GoogleFonts.montserrat(
                      color: isSelected ? Colors.white : _primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _diasSeleccionados.add(dia);
                      } else {
                        _diasSeleccionados.remove(dia);
                      }
                      // 🚀 Verificar conflictos con debounce al cambiar días
                      _verificarConflictosReservasDebounced();
                    });
                  },
                  selectedColor: _secondaryColor,
                  backgroundColor: _cardColor,
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Indicador de carga para verificación de conflictos
            if (_verificandoConflictos) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color.fromRGBO(66, 133, 244, 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color.fromRGBO(66, 133, 244, 0.3)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Verificando conflictos...',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: _secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_conflictosDetectados.isNotEmpty && !_verificandoConflictos) ...[
              _buildAvisoExclusionAutomatica(),
              const SizedBox(height: 12),
              _buildConflictosWidget(),
              const SizedBox(height: 16),
            ],
            _buildPrecioEditableSection(),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final fecha = await showDatePicker(
                  context: context,
                  initialDate: _fechaFinRecurrencia ?? widget.fecha.add(const Duration(days: 30)),
                  firstDate: widget.fecha,
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (fecha != null) {
                  setState(() {
                    _fechaFinRecurrencia = fecha;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: _disabledColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: _secondaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fecha fin (opcional)',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              color: Color.fromRGBO(60, 64, 67, 0.6),
                            ),
                          ),
                          Text(
                            _fechaFinRecurrencia != null
                                ? DateFormat('dd/MM/yyyy').format(_fechaFinRecurrencia!)
                                : 'Sin fecha límite',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_fechaFinRecurrencia != null)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _fechaFinRecurrencia = null;
                          });
                        },
                        icon: const Icon(Icons.clear),
                        color: Colors.grey,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notasController,
              decoration: InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Ej: Cliente fijo todos los martes',
                labelStyle: GoogleFonts.montserrat(color: Color.fromRGBO(60, 64, 67, 0.6)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _disabledColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _disabledColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrecioEditableSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _precioEditableActivado
            ? Color.fromRGBO(66, 133, 244, 0.05)
            : Color.fromRGBO(158, 158, 158, 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _precioEditableActivado
              ? Color.fromRGBO(66, 133, 244, 0.3)
              : Color.fromRGBO(158, 158, 158, 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.edit_outlined,
                color: _precioEditableActivado ? _secondaryColor : Color.fromRGBO(158, 158, 158, 1.0),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Precio personalizado (descuentos)',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _primaryColor,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _precioEditableActivado,
                onChanged: (value) {
                  setState(() {
                    _precioEditableActivado = value;
                    if (value) {
                      _inicializarPrecioTotal();
                    }
                  });
                },
                activeColor: _secondaryColor,
              ),
            ],
          ),
          
          // Mostrar indicador del estado del control total
          if (_precioEditableActivado) ...[
            const SizedBox(height: 12),
            Container(
  padding: const EdgeInsets.all(8),
  decoration: BoxDecoration(
    color: Color.fromRGBO(0, 128, 0, 0.1),
    borderRadius: BorderRadius.circular(6),
    border: Border.all(
      color: Color.fromRGBO(0, 128, 0, 0.3),
    ),
  ),
  child: Row(
    children: [
      Icon(
        Icons.check_circle,
        size: 16,
        color: Colors.green.shade600,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          _esReservaRecurrente
              ? 'La reserva recurrente se creará inmediatamente'
              : 'Los cambios se aplicarán inmediatamente',
          style: GoogleFonts.montserrat(
            fontSize: 11,
            color: Colors.green.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  ),
),

            
            // Información adicional para reservas recurrentes
            if (_esReservaRecurrente) ...[
  const SizedBox(height: 8),
  Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Color.fromRGBO(0, 0, 255, 0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: Color.fromRGBO(0, 0, 255, 0.3),
      ),
    ),
    child: Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 14,
          color: Colors.blue.shade600,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Las reservas recurrentes con precio personalizado se crearán con el descuento indicado.',
            style: GoogleFonts.montserrat(
              fontSize: 10,
              color: Colors.blue.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  ),
],
            
            const SizedBox(height: 16),
            TextFormField(
              controller: _precioTotalController,
              decoration: InputDecoration(
                labelText: _esReservaRecurrente 
                    ? 'Precio por reserva individual' 
                    : 'Nuevo precio total',
                prefixText: 'COP ',
                suffixIcon: Icon(Icons.attach_money, color: _secondaryColor),
                helperText: _esReservaRecurrente 
                    ? 'Este precio se aplicará a cada reserva de la recurrencia'
                    : null,
                helperMaxLines: 2,
                labelStyle: GoogleFonts.montserrat(
                  color: Color.fromRGBO(60, 64, 67, 0.7),
                ),
                helperStyle: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: Colors.blue.shade600,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _disabledColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _disabledColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _secondaryColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {});
                
                // 🆕 MOSTRAR INFORMACIÓN DEL DESCUENTO EN TIEMPO REAL
                if (_esReservaRecurrente && value.isNotEmpty) {
                  final precioPersonalizado = double.tryParse(value) ?? 0;
                  final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, widget.horarios.first);
                  final descuento = precioOriginal - precioPersonalizado;
                  
                  if (descuento > 0) {
                    debugPrint('📊 Descuento por reserva: COP ${descuento.toStringAsFixed(0)}');
                  }
                }
              },
              validator: (value) {
                if (!_precioEditableActivado) return null;
                
                if (value == null || value.isEmpty) {
                  return 'Ingrese el nuevo precio';
                }
                
                final precio = double.tryParse(value);
                if (precio == null || precio <= 0) {
                  return 'Ingrese un precio válido';
                }
                
                // Validación específica para reservas recurrentes
                if (_esReservaRecurrente) {
                  final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, widget.horarios.first);
                  if (precio >= precioOriginal) {
                    return 'El precio debe ser menor al original (COP ${precioOriginal.toStringAsFixed(0)})';
                  }
                }
                
                return null;
              },
            ),
            
            // 🆕 MOSTRAR INFORMACIÓN DEL DESCUENTO CALCULADO
            if (_precioTotalController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDescuentoInfo(),
            ],
          ],
          ],
      ),
    );
  }

  Widget _buildDescuentoInfo() {
    final precioPersonalizado = double.tryParse(_precioTotalController.text) ?? 0;
    if (precioPersonalizado <= 0) return const SizedBox.shrink();
    
    final precioOriginal = _esReservaRecurrente 
        ? Reserva.calcularMontoTotal(widget.cancha, widget.fecha, widget.horarios.first)
        : widget.horarios.map((h) => Reserva.calcularMontoTotal(widget.cancha, widget.fecha, h)).reduce((a, b) => a + b);
        
    final descuento = precioOriginal - (_esReservaRecurrente ? precioPersonalizado : _calcularMontoTotal());
    
    if (descuento <= 0) return const SizedBox.shrink();
    
    final formatter = NumberFormat('#,##0', 'es_CO');
    final porcentajeDescuento = (descuento / precioOriginal * 100);
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color.fromRGBO(0, 255, 0, 0.2), Color.fromRGBO(0, 255, 0, 0.4)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.savings, color: Colors.green.shade600, size: 16),
              const SizedBox(width: 6),
              Text(
                'Descuento calculado',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _esReservaRecurrente ? 'Por reserva:' : 'Total:',
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: Colors.green.shade700,
                ),
              ),
              Text(
                'COP ${formatter.format(descuento)} (${porcentajeDescuento.toStringAsFixed(1)}%)',
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          if (_esReservaRecurrente && _diasSeleccionados.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Por semana (${_diasSeleccionados.length} días):',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    color: Colors.green.shade700,
                  ),
                ),
                Text(
                  'COP ${formatter.format(descuento * _diasSeleccionados.length)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvisoExclusionAutomatica() {
    // Obtener días únicos con conflictos
    final diasConConflictos = <String>{};
    for (final conflicto in _conflictosDetectados) {
      diasConConflictos.add(conflicto['dia'] as String);
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.fromRGBO(66, 133, 244, 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color.fromRGBO(66, 133, 244, 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: _secondaryColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚠️ Exclusión automática de conflictos',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _secondaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Los días con conflictos (${_conflictosDetectados.length} fecha${_conflictosDetectados.length > 1 ? 's' : ''}) se excluirán automáticamente de la reserva recurrente. La reserva se creará solo para los días sin conflictos.',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: _primaryColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictosWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.fromRGBO(255, 0, 0, 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color.fromRGBO(255, 0, 0, 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Text(
                'Conflictos detectados (${_conflictosDetectados.length})',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._conflictosDetectados.map((conflicto) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red.shade300, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${conflicto['fechaStr']} - ${conflicto['horario']} - ${conflicto['nombre']}',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildInfoCard(double total) {
    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalles de la${widget.horarios.length > 1 ? 's' : ''} Reserva${widget.horarios.length > 1 ? 's' : ''}',
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.sports_soccer, 'Cancha', widget.cancha.nombre),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.calendar_today, 'Fecha',
                DateFormat('EEEE d MMMM, yyyy', 'es').format(widget.fecha)),
            const SizedBox(height: 16),
            _buildHorariosSection(),
            const SizedBox(height: 16),
            _buildPrecioEditableSection(),
            const SizedBox(height: 12),
            _buildDistribucionPreview(),
            const SizedBox(height: 12),
            _buildTotalSection(total),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: _secondaryColor, size: 20),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w500,
            color: _primaryColor,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.montserrat(color: _primaryColor),
          ),
        ),
      ],
    );
  }

  Widget _buildHorariosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horarios',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: _primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        ...widget.horarios.map((horario) => Text(
              horario.horaFormateada,
              style: GoogleFonts.montserrat(fontSize: 14),
            )),
      ],
    );
  }

  Widget _buildTotalSection(double total) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.fromRGBO(66, 133, 244, 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total:',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _primaryColor,
            ),
          ),
          Text(
            'COP ${total.toStringAsFixed(0)}',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _secondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteSelectorCard() {
    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seleccionar Cliente Registrado (Opcional)',
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<String?>(
              future: LugarHelper.getLugarId(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    'Error al cargar clientes: ${snapshot.error}',
                    style: GoogleFonts.montserrat(color: Colors.redAccent),
                  );
                }
                final lugarId = snapshot.data;
                if (lugarId == null) {
                  return Text('No se pudo obtener lugar del usuario', style: GoogleFonts.montserrat(color: Colors.redAccent));
                }
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('clientes')
                      .where('lugarId', isEqualTo: lugarId)
                      .snapshots(),
                  builder: (context, snapCli) {
                    if (snapCli.hasError) {
                      return Text(
                        'Error al cargar clientes: ${snapCli.error}',
                        style: GoogleFonts.montserrat(color: Colors.redAccent),
                      );
                    }
                    if (snapCli.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                        ),
                      );
                    }
                    if (!snapCli.hasData || snapCli.data!.docs.isEmpty) {
                  return Text(
                    'No hay clientes registrados.',
                    style: GoogleFonts.montserrat(color: _primaryColor),
                  );
                }
                    final clientes = snapCli.data!.docs
                        .map((doc) => Cliente.fromFirestore(doc))
                        .toList();
                return DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Seleccionar Cliente',
                    labelStyle: GoogleFonts.montserrat(
                      color: Color.fromRGBO(
                          (_primaryColor.red * 255).toInt(),
                          (_primaryColor.green * 255).toInt(),
                          (_primaryColor.blue * 255).toInt(),
                          0.6),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _disabledColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _disabledColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _secondaryColor),
                    ),
                  ),
                  value: _selectedClienteId,
                  hint: Text(
                    'Selecciona un cliente',
                    style: GoogleFonts.montserrat(color: _primaryColor),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'Ninguno (Ingresar manualmente)',
                        style: GoogleFonts.montserrat(),
                      ),
                    ),
                    ...clientes.map ((cliente) => DropdownMenuItem<String>(
                          value: cliente.id,
                          child: Text(
                            cliente.nombre,
                            style: GoogleFonts.montserrat(),
                          ),
                        )),
                  ],
                  onChanged: (value) {
                    final selectedCliente = clientes.firstWhere(
                      (cliente) => cliente.id == value,
                      orElse: () => Cliente(id: '', nombre: '', telefono: ''),
                    );
                    _seleccionarCliente(
                        selectedCliente.id.isEmpty ? null : selectedCliente);
                  },
                  icon: Icon(Icons.keyboard_arrow_down, color: _secondaryColor),
                );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistribucionPreview() {
    if (!_precioEditableActivado || _precioTotalController.text.isEmpty) {
      return const SizedBox.shrink();
    }

    final distribucion = _calcularDistribucionPrecio();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.fromRGBO(
            (_secondaryColor.red * 255).toInt(),
            (_secondaryColor.green * 255).toInt(),
            (_secondaryColor.blue * 255).toInt(),
            0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Color.fromRGBO(
              (_secondaryColor.red * 255).toInt(),
              (_secondaryColor.green * 255).toInt(),
              (_secondaryColor.blue * 255).toInt(),
              0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: _secondaryColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Distribución del precio personalizado:',
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...distribucion.entries.map((entry) {
            final horario = entry.key;
            final precio = entry.value;
            final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
            final descuento = precioOriginal - precio;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    horario.horaFormateada,
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: _primaryColor,
                    ),
                  ),
                  Row(
                    children: [
                      if (descuento > 0) ...[
                        Text(
                          'COP ${precioOriginal.toStringAsFixed(0)}',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        'COP ${precio.toStringAsFixed(0)}',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: descuento > 0 ? Colors.green : _primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _calcularMontoTotal();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agregar ${_esReservaRecurrente ? 'Reserva Recurrente' : 'Reserva'}${!_esReservaRecurrente && widget.horarios.length > 1 ? 's' : ''}',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _backgroundColor,
        elevation: 0,
        foregroundColor: _primaryColor,
      ),
      body: Container(
        color: _backgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isProcessing
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Procesando...',
                        style: GoogleFonts.montserrat(
                          color: Color.fromRGBO(
                              (_primaryColor.red * 255).toInt(),
                              (_primaryColor.green * 255).toInt(),
                              (_primaryColor.blue * 255).toInt(),
                              0.6),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    _buildClienteSelectorCard()
                        .animate()
                        .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                        .slideY(
                            begin: -0.2,
                            end: 0,
                            duration: 600.ms,
                            curve: Curves.easeOutQuad),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: _cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildRecurrenciaToggle(),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                        .slideY(
                            begin: -0.2,
                            end: 0,
                            duration: 600.ms,
                            curve: Curves.easeOutQuad),
                    const SizedBox(height: 16),
                    if (_esReservaRecurrente) ...[
                      _buildRecurrenciaSection()
                          .animate()
                          .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                          .slideY(
                              begin: -0.2,
                              end: 0,
                              duration: 600.ms,
                              curve: Curves.easeOutQuad),
                      const SizedBox(height: 16),
                    ],
                    if (!_esReservaRecurrente) ...[
                      _buildInfoCard(total)
                          .animate()
                          .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                          .slideY(
                              begin: -0.2,
                              end: 0,
                              duration: 600.ms,
                              curve: Curves.easeOutQuad),
                      const SizedBox(height: 16),
                    ],
                    _buildFormCard()
                        .animate()
                        .fadeIn(
                            duration: 600.ms,
                            delay: 200.ms,
                            curve: Curves.easeOutQuad)
                        .slideY(
                          begin: -0.2,
                          end: 0,
                          duration: 600.ms,
                          delay: 200.ms,
                          curve: Curves.easeOutQuad,
                        ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Información del Cliente',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              
              // TextFormFields
              TextFormField(
                controller: _nombreController,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  labelStyle: GoogleFonts.montserrat(
                    color: Color.fromRGBO(
                        (_primaryColor.red * 255).toInt(),
                        (_primaryColor.green * 255).toInt(),
                        (_primaryColor.blue * 255).toInt(),
                        0.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _disabledColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _disabledColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _secondaryColor),
                  ),
                ),
                style: GoogleFonts.montserrat(color: _primaryColor),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el nombre';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoController,
                decoration: InputDecoration(
                  labelText: 'Teléfono',
                  labelStyle: GoogleFonts.montserrat(
                    color: Color.fromRGBO(
                        (_primaryColor.red * 255).toInt(),
                        (_primaryColor.green * 255).toInt(),
                        (_primaryColor.blue * 255).toInt(),
                        0.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _disabledColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _disabledColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _secondaryColor),
                  ),
                ),
                style: GoogleFonts.montserrat(color: _primaryColor),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el teléfono';
                  }
                  return null;
                },
              ),
              if (_showAbonoField) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _abonoController,
                  decoration: InputDecoration(
                    labelText: 'Abono',
                    labelStyle: GoogleFonts.montserrat(
                      color: Color.fromRGBO(
                          (_primaryColor.red * 255).toInt(),
                          (_primaryColor.green * 255).toInt(),
                          (_primaryColor.blue * 255).toInt(),
                          0.6),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _disabledColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _disabledColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _secondaryColor),
                    ),
                  ),
                  style: GoogleFonts.montserrat(color: _primaryColor),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa el abono';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Ingresa un número válido';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<TipoAbono>(
                value: _selectedTipo,
                decoration: InputDecoration(
                  labelText: 'Estado de pago',
                  labelStyle: GoogleFonts.montserrat(
                    color: Color.fromRGBO(
                        (_primaryColor.red * 255).toInt(),
                        (_primaryColor.green * 255).toInt(),
                        (_primaryColor.blue * 255).toInt(),
                        0.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _disabledColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _disabledColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _secondaryColor),
                  ),
                ),
                style: GoogleFonts.montserrat(color: _primaryColor),
                icon: Icon(Icons.keyboard_arrow_down, color: _secondaryColor),
                items: [
                  DropdownMenuItem(
                    value: TipoAbono.parcial,
                    child: Text(
                      'Pendiente',
                      style: GoogleFonts.montserrat(),
                    ),
                  ),
                  DropdownMenuItem(
                    value: TipoAbono.completo,
                    child: Text(
                      'Completo',
                      style: GoogleFonts.montserrat(),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedTipo = value;
                    _showAbonoField = value == TipoAbono.parcial;
                    if (!_showAbonoField) {
                      _abonoController.text = '0';
                    }
                  });
                },
              ),
              const SizedBox(height: 24),
              
              // Botón modificado para mostrar el tipo de acción
              ElevatedButton(
  onPressed: (_esReservaRecurrente && widget.horarios.length > 1) ||
          (_esReservaRecurrente && _diasSeleccionados.isEmpty)
      ? null
      : _crearReserva,
  style: ElevatedButton.styleFrom(
    backgroundColor: _secondaryColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    elevation: 0,
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.add_circle, size: 18),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          _esReservaRecurrente
              ? 'Crear Reserva Recurrente'
              : 'Confirmar Reserva${widget.horarios.length > 1 ? 's' : ''}',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  ),
),

            ],
          ),
        ),
      ),
    );
  }

}


extension StringCapitalize on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}