import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:math' as math;
import '../models/cancha.dart';
import '../models/horario.dart';
import '../providers/sede_provider.dart';
import '../providers/cancha_provider.dart';
import '../models/reserva_recurrente.dart';
import '../providers/reserva_recurrente_provider.dart';
import '../providers/promocion_provider.dart';
import '../models/config_lugar.dart';
import '../services/config_lugar_service.dart';
import 'detalles_screen.dart';
import 'reserva_detalles_screen.dart';
import '../main.dart';
import 'dart:async';

class HorariosScreen extends StatefulWidget {
  final Cancha cancha;

  const HorariosScreen({super.key, required this.cancha});

  @override
  State<HorariosScreen> createState() => _HorariosScreenState();
}

class _HorariosScreenState extends State<HorariosScreen> with RouteAware, TickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  List<Horario> horarios = [];
  bool _isLoading = false;
  bool _calendarExpanded = false;
  final Map<String, QuerySnapshot> _reservasSnapshots = {};
  Timer? _debounceTimer;
  Cancha? _updatedCancha;
  Timer? _updateTimer;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  
  // ✅ OPTIMIZADO: Variables para promociones (ahora usando Provider centralizado)
  Map<String, Map<String, dynamic>> _promocionesPorHorario = {}; // horarioNormalizado -> {precio, id, precio_promocional, ...}
  StreamSubscription<Map<String, Map<String, dynamic>>>? _promocionesSubscription;
  late AnimationController _goldShimmerController;
  
  // ✅ NUEVO: Streams en tiempo real para reservas
  StreamSubscription<QuerySnapshot>? _reservasSubscription;
  StreamSubscription<QuerySnapshot>? _reservasTemporalesSubscription;

  /// Configuración del lugar (horarios de actividad). Si el día está cerrado o fuera de horario, no se puede reservar.
  ConfigLugar? _configLugar;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    // ✅ NUEVO: Controlador para efecto dorado
    _goldShimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);

    sedeProvider.fetchSedes().then((_) {
      if (!mounted) return;
      String selectedSede = sedeProvider.selectedSede.isNotEmpty
          ? sedeProvider.selectedSede
          : sedeProvider.sedeNames.isNotEmpty
              ? sedeProvider.sedeNames.first
              : '';
      if (selectedSede.isNotEmpty) {
        sedeProvider.setSede(selectedSede);
        canchaProvider.fetchCanchas(selectedSede).then((_) {
          if (!mounted) return;
          setState(() {
            _updatedCancha = canchaProvider.canchas.firstWhere(
              (c) => c.id == widget.cancha.id,
              orElse: () => widget.cancha,
            );
            _loadHorarios();
          });
        }).catchError((error) {
          if (!mounted) return;
          setState(() {
            _updatedCancha = widget.cancha;
            _loadHorarios();
          });
        });
      } else {
        if (!mounted) return;
        setState(() {
          _updatedCancha = widget.cancha;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No hay sedes disponibles'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    });

    _fadeController.forward();
    _slideController.forward();

    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now())) {
        _refreshHorariosEstados();
      }
    });
    
    // ✅ NUEVO: Iniciar escucha de promociones
    _iniciarEscuchaPromociones();

    // Cargar configuración del lugar (horarios de actividad para mostrar "Cerrado" / bloquear reservas)
    final lugarId = widget.cancha.lugarId;
    if (lugarId != null && lugarId.isNotEmpty) {
      ConfigLugarService.getConfig(lugarId).then((c) {
        if (mounted) setState(() => _configLugar = c);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _fadeController.dispose();
    _slideController.dispose();
    _goldShimmerController.dispose(); // ✅ NUEVO
    _promocionesSubscription?.cancel(); // ✅ NUEVO
    _reservasSubscription?.cancel(); // ✅ NUEVO: Cancelar stream de reservas
    _reservasTemporalesSubscription?.cancel(); // ✅ NUEVO: Cancelar stream de reservas temporales
    _debounceTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadHorarios();
  }
  
  // ✅ OPTIMIZADO: Método para escuchar promociones usando Provider centralizado
  void _iniciarEscuchaPromociones() {
    if (!mounted) return;
    _promocionesSubscription?.cancel();
    
    final fechaSeleccionadaStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    debugPrint('🔍 Iniciando escucha de promociones (Provider centralizado)...');
    debugPrint('   - Fecha: $fechaSeleccionadaStr');
    debugPrint('   - Cancha ID: ${widget.cancha.id}');
    
    // ✅ Obtener lugarId desde SedeProvider o desde la cancha
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final lugarId = sedeProvider.lugarId ?? widget.cancha.lugarId;
    
    if (lugarId == null || lugarId.isEmpty) {
      debugPrint('❌ No se pudo obtener lugarId (SedeProvider: ${sedeProvider.lugarId}, Cancha: ${widget.cancha.lugarId})');
      return;
    }
    
    // Obtener sedeId y sedeNombre
    String? sedeId;
    String? sedeNombre;
    
    if (sedeProvider.selectedSede.isNotEmpty) {
      try {
        final sede = sedeProvider.sedes.firstWhere(
          (s) => s['id'] == sedeProvider.selectedSede || s['nombre'] == sedeProvider.selectedSede,
          orElse: () => {'id': widget.cancha.sedeId, 'nombre': sedeProvider.selectedSede},
        );
        sedeId = sede['id'] as String? ?? widget.cancha.sedeId;
        sedeNombre = sede['nombre'] as String?;
      } catch (e) {
        debugPrint('⚠️ Error obteniendo sede: $e');
        sedeId = widget.cancha.sedeId;
      }
    } else {
      sedeId = widget.cancha.sedeId;
    }
    
    debugPrint('   - Lugar ID: $lugarId (desde ${sedeProvider.lugarId != null ? "SedeProvider" : "Cancha"})');
    debugPrint('   - Sede ID: $sedeId');
    debugPrint('   - Sede Nombre: $sedeNombre');
    
    // ✅ OPTIMIZADO: Usar PromocionProvider centralizado
    final promocionProvider = Provider.of<PromocionProvider>(context, listen: false);
    
    _promocionesSubscription = promocionProvider.getPromociones(
      lugarId: lugarId,
      canchaId: widget.cancha.id,
      fecha: fechaSeleccionadaStr,
      sedeId: sedeId,
      sedeNombre: sedeNombre,
    ).listen(
      (promocionesTemp) {
        if (!mounted) return;
        
        setState(() {
          _promocionesPorHorario = promocionesTemp;
        });
        
        debugPrint('🎯 Promociones cargadas en mapa: ${_promocionesPorHorario.length}');
        if (_promocionesPorHorario.isNotEmpty) {
          _promocionesPorHorario.forEach((key, value) {
            debugPrint('   📌 "$key" -> S/ ${value['precio_promocional']}');
          });
        } else {
          debugPrint('   ⚠️ No se cargaron promociones en el mapa');
        }
      },
      onError: (error) {
        debugPrint('❌ Error en stream de promociones: $error');
        if (mounted) {
          setState(() {
            _promocionesPorHorario = {};
          });
        }
      },
    );
  }

  Future<void> _loadHorarios() async {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      setState(() {
        _isLoading = true;
        horarios.clear();
      });

      try {
        final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
        final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
        
        Map<String, dynamic> selectedSede;
        if (sedeProvider.selectedSede.isNotEmpty) {
          selectedSede = sedeProvider.sedes.firstWhere(
            (sede) => sede['id'] == sedeProvider.selectedSede || sede['nombre'] == sedeProvider.selectedSede,
            orElse: () => {'id': widget.cancha.sedeId},
          );
        } else {
          selectedSede = sedeProvider.sedes.firstWhere(
            (sede) => sede['id'] == widget.cancha.sedeId,
            orElse: () => {'id': widget.cancha.sedeId},
          );
        }
        final sedeId = selectedSede['id'] as String;

        debugPrint('🏢 === INICIO CARGA HORARIOS ===');
        debugPrint('🏢 Sede seleccionada: $sedeId');
        debugPrint('🏟️ Cancha: ${widget.cancha.id} - ${widget.cancha.nombre}');
        debugPrint('📅 Fecha: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');

        // ✅ CORRECCIÓN CRÍTICA: SIEMPRE RECARGAR RESERVAS RECURRENTES PARA LA SEDE ACTUAL
        debugPrint('🔄 Recargando reservas recurrentes para sede: $sedeId');
        await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: sedeId);
        
        final todasReservasRecurrentes = reservaRecurrenteProvider.reservasRecurrentes;
        debugPrint('📊 Total reservas recurrentes cargadas: ${todasReservasRecurrentes.length}');
        debugPrint('📊 Por estado:');
        debugPrint('   - Activas: ${todasReservasRecurrentes.where((r) => r.estado == EstadoRecurrencia.activa).length}');
        debugPrint('   - Canceladas: ${todasReservasRecurrentes.where((r) => r.estado == EstadoRecurrencia.cancelada).length}');
        debugPrint('   - Pausadas: ${todasReservasRecurrentes.where((r) => r.estado == EstadoRecurrencia.pausada).length}');

        // ✅ NUEVO: Iniciar escucha en tiempo real de reservas
        _iniciarEscuchaReservasEnTiempoReal(sedeId);

        // ✅ CARGAR RESERVAS INICIALES (primera carga)
        debugPrint('🔍 Consultando reservas normales (carga inicial)...');
        final reservasSnapshotInicial = await FirebaseFirestore.instance
            .collection('reservas')
            .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate))
            .where('cancha_id', isEqualTo: widget.cancha.id)
            .where('sede', isEqualTo: sedeId)
            .limit(24)
            .get();
        
        debugPrint('📋 Reservas normales encontradas: ${reservasSnapshotInicial.docs.length}');
        
        // Generar horarios base
        final nuevosHorarios = await Horario.generarHorarios(
          fecha: _selectedDate,
          canchaId: widget.cancha.id,
          sede: sedeId,
          reservasSnapshot: reservasSnapshotInicial,
          cancha: _updatedCancha ?? widget.cancha,
        );

        debugPrint('⏰ Horarios base generados: ${nuevosHorarios.length}');

        // ✅ OBTENER RESERVAS RECURRENTES PARA ESTA FECHA ESPECÍFICA
        final reservasRecurrentesActivas = reservaRecurrenteProvider.obtenerReservasActivasParaFecha(
          _selectedDate, 
          sede: sedeId, 
          canchaId: widget.cancha.id
        );

        debugPrint('🔄 === PROCESANDO RESERVAS RECURRENTES ===');
        debugPrint('🔄 Reservas recurrentes activas para esta fecha: ${reservasRecurrentesActivas.length}');
        
        if (reservasRecurrentesActivas.isNotEmpty) {
          debugPrint('🔄 Lista de reservas a procesar:');
          for (var i = 0; i < reservasRecurrentesActivas.length; i++) {
            final reserva = reservasRecurrentesActivas[i];
            debugPrint('   ${i + 1}. ${reserva.clienteNombre} - ${reserva.horario} - Estado: ${reserva.estado}');
          }
        }

        // ✅ PROCESAR CADA RESERVA RECURRENTE CON LOGGING DETALLADO
        int reservasAplicadas = 0;
        for (var reservaRecurrente in reservasRecurrentesActivas) {
          final horarioOriginal = reservaRecurrente.horario.trim();
          final horaNormalizada = _normalizarHorarioMejorado(horarioOriginal);
          
          debugPrint('⏰ Procesando: "$horarioOriginal" -> "$horaNormalizada"');
          
          // Buscar el horario correspondiente
          final indiceHorario = nuevosHorarios.indexWhere((h) {
            final horaNormalizadaDisponible = _normalizarHorarioMejorado(h.horaFormateada);
            final coincide = horaNormalizadaDisponible == horaNormalizada;
            
            if (coincide) {
              debugPrint('   ✅ Match encontrado: "${h.horaFormateada}" -> "$horaNormalizadaDisponible"');
            }
            
            return coincide;
          });
          
          if (indiceHorario != -1) {
            final horarioActual = nuevosHorarios[indiceHorario];
            
            if (horarioActual.estado == EstadoHorario.disponible) {
              nuevosHorarios[indiceHorario] = Horario(
                hora: horarioActual.hora,
                estado: EstadoHorario.reservado,
                esReservaRecurrente: true,
                clienteNombre: reservaRecurrente.clienteNombre,
                reservaRecurrenteData: {
                  'id': reservaRecurrente.id,
                  'clienteId': reservaRecurrente.clienteId,
                  'clienteTelefono': reservaRecurrente.clienteTelefono,
                  'montoTotal': reservaRecurrente.montoTotal,
                  'montoPagado': reservaRecurrente.montoPagado,
                  'precioPersonalizado': reservaRecurrente.precioPersonalizado,
                  'precioOriginal': reservaRecurrente.precioOriginal,
                  'descuentoAplicado': reservaRecurrente.descuentoAplicado,
                  'esReservaRecurrente': true,
                },
              );
              
              reservasAplicadas++;
              debugPrint('   ✅ Reserva recurrente aplicada: ${reservaRecurrente.clienteNombre}');
            } else {
              debugPrint('   ⚠️ Horario ya ocupado por reserva normal (estado: ${horarioActual.estado})');
            }
          } else {
            debugPrint('   ❌ No se encontró horario matching para: "$horaNormalizada"');
            
            // Debug adicional: mostrar todos los horarios disponibles
            debugPrint('   🔍 Horarios disponibles para comparar:');
            for (var h in nuevosHorarios) {
              final hNorm = _normalizarHorarioMejorado(h.horaFormateada);
              debugPrint('      - "${h.horaFormateada}" -> "$hNorm"');
            }
          }
        }

        debugPrint('📊 === RESUMEN FINAL ===');
        debugPrint('📊 Reservas recurrentes aplicadas: $reservasAplicadas de ${reservasRecurrentesActivas.length}');

        // ✅ NUEVO: Recargar promociones después de cargar horarios
        _iniciarEscuchaPromociones();
        
        if (mounted) {
          setState(() {
            horarios = nuevosHorarios;
            _isLoading = false;
          });

          final disponibles = horarios.where((h) => h.estado == EstadoHorario.disponible).length;
          final reservados = horarios.where((h) => h.estado == EstadoHorario.reservado).length;
          final vencidos = horarios.where((h) => h.estado == EstadoHorario.vencido).length;
          final procesando = horarios.where((h) => h.estado == EstadoHorario.procesandoPago).length; // ✅ NUEVO
          final recurrentes = horarios.where((h) => h.esReservaRecurrente == true).length;

          debugPrint('📊 ESTADO FINAL:');
          debugPrint('   - Disponibles: $disponibles');
          debugPrint('   - Reservados: $reservados (de los cuales $recurrentes son recurrentes)');
          debugPrint('   - Procesando pago: $procesando'); // ✅ NUEVO
          debugPrint('   - Vencidos: $vencidos');
          debugPrint('🏢 === FIN CARGA HORARIOS ===');
        }
      } catch (e) {
        debugPrint('❌ Error en _loadHorarios: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cargar horarios: $e')),
          );
        }
      }
    });
  }

  // ✅ NUEVO: Escuchar reservas en tiempo real
  void _iniciarEscuchaReservasEnTiempoReal(String sedeId) {
    _reservasSubscription?.cancel();
    _reservasTemporalesSubscription?.cancel();
    
    final fechaStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    debugPrint('🔍 Iniciando escucha en tiempo real de reservas...');
    debugPrint('   - Fecha: $fechaStr');
    debugPrint('   - Cancha: ${widget.cancha.id}');
    debugPrint('   - Sede: $sedeId');
    
    // ✅ Escuchar reservas normales
    _reservasSubscription = FirebaseFirestore.instance
        .collection('reservas')
        .where('fecha', isEqualTo: fechaStr)
        .where('cancha_id', isEqualTo: widget.cancha.id)
        .where('sede', isEqualTo: sedeId)
        .limit(24)
        .snapshots()
        .listen(
          (querySnapshot) async {
            if (!mounted) return;
            
            debugPrint('📊 Reservas actualizadas: ${querySnapshot.docs.length}');
            await _actualizarHorariosConReservas(querySnapshot, sedeId);
          },
          onError: (error) {
            debugPrint('❌ Error en stream de reservas: $error');
          },
        );
    
    // ✅ Escuchar reservas temporales (en proceso de pago)
    final ahora = DateTime.now().millisecondsSinceEpoch;
    _reservasTemporalesSubscription = FirebaseFirestore.instance
        .collection('reservas_temporales')
        .where('cancha_id', isEqualTo: widget.cancha.id)
        .where('fecha', isEqualTo: fechaStr)
        .where('sede', isEqualTo: sedeId)
        .where('expira_en', isGreaterThan: ahora)
        .snapshots()
        .listen(
          (querySnapshot) async {
            if (!mounted) return;
            
            debugPrint('⏳ Reservas temporales actualizadas: ${querySnapshot.docs.length}');
            // Las reservas temporales se procesan dentro de _actualizarHorariosConReservas
            // pero necesitamos obtener las reservas normales también
            final reservasSnapshot = await FirebaseFirestore.instance
                .collection('reservas')
                .where('fecha', isEqualTo: fechaStr)
                .where('cancha_id', isEqualTo: widget.cancha.id)
                .where('sede', isEqualTo: sedeId)
                .limit(24)
                .get();
            
            await _actualizarHorariosConReservas(reservasSnapshot, sedeId);
          },
          onError: (error) {
            debugPrint('❌ Error en stream de reservas temporales: $error');
          },
        );
  }
  
  // ✅ NUEVO: Actualizar horarios cuando cambian las reservas
  Future<void> _actualizarHorariosConReservas(QuerySnapshot reservasSnapshot, String sedeId) async {
    if (!mounted) return;
    
    try {
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      
      // Generar horarios base con las reservas actualizadas
      final nuevosHorarios = await Horario.generarHorarios(
        fecha: _selectedDate,
        canchaId: widget.cancha.id,
        sede: sedeId,
        reservasSnapshot: reservasSnapshot,
        cancha: _updatedCancha ?? widget.cancha,
      );
      
      // ✅ OBTENER RESERVAS RECURRENTES PARA ESTA FECHA ESPECÍFICA
      final reservasRecurrentesActivas = reservaRecurrenteProvider.obtenerReservasActivasParaFecha(
        _selectedDate, 
        sede: sedeId, 
        canchaId: widget.cancha.id
      );
      
      // ✅ PROCESAR RESERVAS RECURRENTES
      for (var reservaRecurrente in reservasRecurrentesActivas) {
        final horarioOriginal = reservaRecurrente.horario.trim();
        final horaNormalizada = _normalizarHorarioMejorado(horarioOriginal);
        
        final indiceHorario = nuevosHorarios.indexWhere((h) {
          final horaNormalizadaDisponible = _normalizarHorarioMejorado(h.horaFormateada);
          return horaNormalizadaDisponible == horaNormalizada;
        });
        
        if (indiceHorario != -1) {
          final horarioActual = nuevosHorarios[indiceHorario];
          
          if (horarioActual.estado == EstadoHorario.disponible) {
            nuevosHorarios[indiceHorario] = Horario(
              hora: horarioActual.hora,
              estado: EstadoHorario.reservado,
              esReservaRecurrente: true,
              clienteNombre: reservaRecurrente.clienteNombre,
              reservaRecurrenteData: {
                'id': reservaRecurrente.id,
                'clienteId': reservaRecurrente.clienteId,
                'clienteTelefono': reservaRecurrente.clienteTelefono,
                'montoTotal': reservaRecurrente.montoTotal,
                'montoPagado': reservaRecurrente.montoPagado,
                'precioPersonalizado': reservaRecurrente.precioPersonalizado,
                'precioOriginal': reservaRecurrente.precioOriginal,
                'descuentoAplicado': reservaRecurrente.descuentoAplicado,
                'esReservaRecurrente': true,
              },
            );
          }
        }
      }
      
      if (mounted) {
        setState(() {
          horarios = nuevosHorarios;
        });
        
        debugPrint('✅ Horarios actualizados en tiempo real');
        debugPrint('   - Disponibles: ${horarios.where((h) => h.estado == EstadoHorario.disponible).length}');
        debugPrint('   - Reservados: ${horarios.where((h) => h.estado == EstadoHorario.reservado).length}');
        debugPrint('   - Procesando pago: ${horarios.where((h) => h.estado == EstadoHorario.procesandoPago).length}');
      }
    } catch (e) {
      debugPrint('❌ Error actualizando horarios: $e');
    }
  }

  // ✅ NUEVO: Actualizar estado local inmediatamente cuando se crea una reserva
  Future<void> _actualizarEstadoLocalReservaCreada(Horario horario) async {
    try {
      final horaNormalizada = Horario.normalizarHora(horario.horaFormateada);
      
      // Buscar el horario en la lista y actualizar su estado
      final indice = horarios.indexWhere((h) => 
        Horario.normalizarHora(h.horaFormateada) == horaNormalizada
      );
      
      if (indice != -1 && mounted) {
        setState(() {
          // Actualizar el estado a "procesando pago"
          horarios[indice] = Horario(
            hora: horarios[indice].hora,
            estado: EstadoHorario.procesandoPago,
            esReservaRecurrente: false,
            clienteNombre: 'Procesando pago',
          );
        });
        
        debugPrint('✅ Estado local actualizado: $horaNormalizada -> PROCESANDO PAGO');
      }
    } catch (e) {
      debugPrint('⚠️ Error actualizando estado local: $e');
    }
  }

  // ✅ MÉTODO DE NORMALIZACIÓN MEJORADO
  String _normalizarHorarioMejorado(String horaStr) {
    // Limpiar espacios y convertir a mayúsculas
    String normalizada = horaStr.trim().toUpperCase();
    
    // Reemplazar múltiples espacios con uno solo
    normalizada = normalizada.replaceAll(RegExp(r'\s+'), ' ');
    
    // Asegurar formato consistente con AM/PM
    if (normalizada.contains('AM') || normalizada.contains('PM')) {
      // Ya está en formato 12 horas, solo limpiar
      return normalizada;
    }
    
    // Si no tiene AM/PM, asumir que es formato 24 horas y convertir
    try {
      final parts = normalizada.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        
        if (hour == 0) {
          return '12:${minute.toString().padLeft(2, '0')} AM';
        } else if (hour < 12) {
          return '$hour:${minute.toString().padLeft(2, '0')} AM';
        } else if (hour == 12) {
          return '12:${minute.toString().padLeft(2, '0')} PM';
        } else {
          return '${hour - 12}:${minute.toString().padLeft(2, '0')} PM';
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error convirtiendo horario "$horaStr": $e');
    }
    
    return normalizada;
  }

  void _refreshHorariosEstados() {
    if (!mounted) return;

    bool hayCambios = false;
    for (int i = 0; i < horarios.length; i++) {
      final horario = horarios[i];
      if (horario.estado == EstadoHorario.disponible && horario.estaVencida(_selectedDate)) {
        horarios[i] = Horario(hora: horario.hora, estado: EstadoHorario.vencido);
        hayCambios = true;
      }
    }

    if (hayCambios && mounted) {
      setState(() {});
    }
  }

  void _toggleCalendar() {
    setState(() {
      _calendarExpanded = !_calendarExpanded;
    });
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (selectedDay.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No puedes seleccionar fechas pasadas'),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
      return;
    }

    if (!isSameDay(_selectedDate, selectedDay)) {
      setState(() {
        _selectedDate = selectedDay;
        horarios.clear();
        _isLoading = true;
        _calendarExpanded = false;
      });

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _loadHorarios();
        _iniciarEscuchaPromociones(); // ✅ NUEVO: Actualizar promociones al cambiar fecha
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: Provider.of<SedeProvider>(context)),
        ChangeNotifierProvider.value(value: Provider.of<CanchaProvider>(context)),
        ChangeNotifierProvider.value(value: Provider.of<ReservaRecurrenteProvider>(context)),
      ],
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F5F5), Colors.white],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.white,
            scrolledUnderElevation: 0,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Center(
                child: Material(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      if (mounted) Navigator.pop(context);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF424242), size: 20),
                    ),
                  ),
                ),
              ),
            ),
            title: FadeTransition(
              opacity: _fadeAnimation,
              child: const Text(
                'Reserva de Cancha',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Material(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        _reservasSnapshots.clear();
                        _loadHorarios();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.refresh_rounded, color: Color(0xFF424242), size: 22),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCanchaInfo(),
                          const SizedBox(height: 20),
                          _buildDateSelector(),
                          const SizedBox(height: 8),
                          if (_calendarExpanded) _buildCalendar(),
                          const SizedBox(height: 20),
                          _buildWarningOficina(),
                          const SizedBox(height: 16),
                          if (_mostrarAvisoCerrado()) _buildAvisoCerrado(),
                          if (_mostrarAvisoCerrado()) const SizedBox(height: 16),
                          _buildHorariosHeader(),
                          const SizedBox(height: 16),
                          _buildHorariosGridContent(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  _buildBottomButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanchaInfo() {
    final cancha = _updatedCancha ?? widget.cancha;
    final sedeNombre = Provider.of<SedeProvider>(context).selectedSede;
    final techada = cancha.techada;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: cancha.imagen.startsWith('http')
                  ? Image.network(
                      cancha.imagen,
                      fit: BoxFit.cover,
                      cacheWidth: 144,
                      errorBuilder: (_, __, ___) => _canchaPlaceholder(),
                    )
                  : Image.asset(
                      cancha.imagen.isNotEmpty ? cancha.imagen : 'assets/demo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _canchaPlaceholder(),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (cancha.nombre).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Sede $sedeNombre',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if ((!cancha.disponible) && cancha.motivoNoDisponible != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      cancha.motivoNoDisponible!,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.red.shade700),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2DD4BF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2DD4BF).withOpacity(0.4)),
            ),
            child: Text(
              techada ? 'TECHADA' : 'AL AIRE LIBRE',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D9488),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canchaPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.sports_soccer_rounded, color: Colors.grey, size: 36),
    );
  }

  Widget _buildDateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'FECHA SELECCIONADA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              letterSpacing: 0.6,
            ),
          ),
        ),
        GestureDetector(
          onTap: (_updatedCancha?.disponible ?? widget.cancha.disponible) ? _toggleCalendar : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, color: Colors.grey.shade600, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, d MMMM yyyy', 'es').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _calendarExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey.shade600,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: TableCalendar(
            firstDay: DateTime.now(),
            lastDay: DateTime.now().add(const Duration(days: 30)),
            focusedDay: _selectedDate,
            selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
            onDaySelected: _onDaySelected,
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.green.withAlpha(128),
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              outsideDaysVisible: false,
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
          ),
        ),
      ),
    );
  }

  Widget _buildHorariosHeader() {
    return Row(
      children: [
        Icon(Icons.schedule_rounded, color: const Color(0xFF2DD4BF), size: 22),
        const SizedBox(width: 8),
        Text(
          'Horarios Disponibles',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2033),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            DateFormat('d MMM', 'es').format(_selectedDate).toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }

  /// True si el día está cerrado o (si es hoy) fuera del rango de horario de actividad.
  bool _noReservarPorHorario() {
    if (_configLugar == null) return false;
    final weekday = _selectedDate.weekday;
    if (_configLugar!.estaCerradoDia(weekday)) return true;
    final now = DateTime.now();
    if (!isSameDay(_selectedDate, now)) return false;
    return !_configLugar!.estaDentroDeHorario(weekday, now.hour, now.minute);
  }

  bool _mostrarAvisoCerrado() => _noReservarPorHorario();

  /// Aviso: reservas fuera de horario de oficina pueden tardar en confirmarse.
  Widget _buildWarningOficina() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.amber.shade700, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Recuerda que las reservas fuera de horario de oficina podrían tardar unos minutos en confirmarse.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Material(
          color: const Color(0xFF1A2033),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Selecciona un horario disponible de la lista para continuar'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  margin: const EdgeInsets.all(12),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'CONFIRMAR RESERVA',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvisoCerrado() {
    final weekday = _selectedDate.weekday;
    final bool cerrado = _configLugar!.estaCerradoDia(weekday);
    final String mensaje = cerrado
        ? 'Cerrado este día. No se pueden realizar reservas.'
        : 'Fuera del horario de atención. No se pueden realizar reservas.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Contenido del área de horarios (sin Expanded, para usar dentro de Expanded del body).
  Widget _buildHorariosGridContent() {
    if (!(_updatedCancha?.disponible ?? widget.cancha.disponible)) {
      return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_rounded, size: 70, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'Cancha no disponible',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _updatedCancha?.motivoNoDisponible ?? widget.cancha.motivoNoDisponible ?? 'No especificado',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  _reservasSnapshots.clear();
                  _loadHorarios();
                },
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Actualizar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.grey.shade800,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ],
          ),
      );
    }

    if (_isLoading) {
      return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade300),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Cargando horarios...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
      );
    }

    if (horarios.isEmpty) {
      return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.access_time_rounded, size: 70, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'No hay horarios disponibles',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Intenta seleccionar otra fecha',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  _reservasSnapshots.clear();
                  _loadHorarios();
                },
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Actualizar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.grey.shade800,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ],
          ),
      );
    }

    // Responsividad mejorada
    return LayoutBuilder(
        builder: (context, constraints) {
          // Calcular crossAxisCount basado en el ancho disponible
          int crossAxisCount;
          double childAspectRatio;
          
          if (constraints.maxWidth < 500) {
            // Pantallas pequeñas: 3 columnas (más anchas)
            crossAxisCount = 3;
            childAspectRatio = 1.1;
          } else if (constraints.maxWidth < 700) {
            // Pantallas medianas: 3 columnas
            crossAxisCount = 3;
            childAspectRatio = 1.1;
          } else if (constraints.maxWidth < 900) {
            // Pantallas medianas-grandes: 4 columnas
            crossAxisCount = 4;
            childAspectRatio = 1.1;
          } else {
            // Pantallas grandes: 5 columnas
            crossAxisCount = 5;
            childAspectRatio = 1.1;
          }

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: childAspectRatio,
            ),
            padding: EdgeInsets.zero,
            itemCount: horarios.length,
            itemBuilder: (context, index) {
              final horario = horarios[index];
              return _buildHorarioCard(horario, Provider.of<SedeProvider>(context, listen: false).selectedSede);
            },
          );
        },
    );
  }

  Widget _buildHorarioCard(Horario horario, String sedeNombre) {
    final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
    final String horaStr = horario.horaFormateada;
    final horaNormalizada = Horario.normalizarHora(horaStr);
    
    // ✅ OPTIMIZADO: Verificar promoción usando solo la clave normalizada
    final tienePromocion = _promocionesPorHorario.containsKey(horaNormalizada);
    final promocion = tienePromocion ? _promocionesPorHorario[horaNormalizada] : null;
    
    // Debug para verificar promociones
    if (_promocionesPorHorario.isNotEmpty && horario.estado == EstadoHorario.disponible) {
      debugPrint('🔍 Verificando promoción para: "$horaStr" (normalizado: "$horaNormalizada")');
      debugPrint('   - Promociones disponibles: ${_promocionesPorHorario.keys.toList()}');
      debugPrint('   - Tiene promoción: $tienePromocion');
    }
    
    final Map<String, Map<String, dynamic>>? dayPrices = (_updatedCancha?.preciosPorHorario ?? widget.cancha.preciosPorHorario)[day];
    double precio = dayPrices != null && dayPrices.containsKey(horaStr)
        ? (dayPrices[horaStr] is Map<String, dynamic>
            ? (dayPrices[horaStr]!['precio'] as num?)?.toDouble() ?? (_updatedCancha?.precio ?? widget.cancha.precio)
            : (dayPrices[horaStr] as num?)?.toDouble() ?? (_updatedCancha?.precio ?? widget.cancha.precio))
        : (_updatedCancha?.precio ?? widget.cancha.precio);
    
    // ✅ NUEVO: Aplicar precio promocional si está disponible y no está reservado
    if (tienePromocion && promocion != null && horario.estado == EstadoHorario.disponible) {
      precio = promocion['precio_promocional'] as double;
      debugPrint('✨ Precio promocional aplicado: S/ $precio para $horaStr');
    }

    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final sede = sedeProvider.sedes.firstWhere(
      (s) => s['nombre'] == sedeNombre,
      orElse: () => {'id': '', 'nombre': sedeNombre},
    );
    final sedeId = sede['id'] as String;

    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: child,
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Ajustes responsivos para tamaños de texto
          double fontSize = constraints.maxWidth < 90 ? 13 : 15;
          double priceFontSize = constraints.maxWidth < 90 ? 10 : 12;
          double statusFontSize = constraints.maxWidth < 90 ? 9 : 10;
          double iconSize = constraints.maxWidth < 90 ? 11 : 13;
          
          return InkWell(
            onTap: () {
              if (horario.estado == EstadoHorario.vencido) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Esta hora ya ha pasado'),
                    backgroundColor: Colors.grey.shade600,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    margin: const EdgeInsets.all(12),
                  ),
                );
                return;
              }

              // ✅ AGREGAR CASO PARA PROCESANDO PAGO
              if (horario.estado == EstadoHorario.procesandoPago) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Se está procesando el pago con otro cliente, si no se confirma, se liberará automáticamente'),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    margin: const EdgeInsets.all(12),
                    duration: const Duration(seconds: 4), // Mensaje más largo
                  ),
                );
                return;
              }

              // Cerrado o fuera de horario de actividad: no permitir reservar
              if (horario.estado == EstadoHorario.disponible && _noReservarPorHorario()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Cerrado o fuera del horario de atención. No se pueden realizar reservas.'),
                    backgroundColor: Colors.orange.shade800,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    margin: const EdgeInsets.all(12),
                  ),
                );
                return;
              }

              if (horario.estado == EstadoHorario.reservado) {
                if (horario.esReservaRecurrente == true && horario.reservaRecurrenteData != null) {
                  if (mounted) {
                    Navigator.push<bool>(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, animation, __) {
                          return FadeTransition(
                            opacity: animation,
                            child: ReservaDetallesScreen(
                              cancha: widget.cancha,
                              fecha: _selectedDate,
                              horario: horario,
                              sede: sedeId,
                              esReservaRecurrente: true,
                            ),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 300),
                      ),
                    ).then((reservaRealizada) {
                      if (reservaRealizada == true) {
                        _reservasSnapshots.clear();
                        _loadHorarios();
                      }
                    });
                  }
                } else {
                  if (mounted) {
                    Navigator.push<bool>(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, animation, __) {
                          return FadeTransition(
                            opacity: animation,
                            child: ReservaDetallesScreen(
                              cancha: widget.cancha,
                              fecha: _selectedDate,
                              horario: horario,
                              sede: sedeId,
                              esReservaRecurrente: false,
                            ),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 300),
                      ),
                    ).then((reservaRealizada) {
                      if (reservaRealizada == true) {
                        _reservasSnapshots.clear();
                        _loadHorarios();
                      }
                    });
                  }
                }
                return;
              }

              if (mounted) {
                Navigator.push<bool>(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, animation, __) {
                      return FadeTransition(
                        opacity: animation,
                        child: DetallesScreen(
                          cancha: widget.cancha,
                          fecha: _selectedDate,
                          horario: horario,
                          sede: sedeId,
                          precioPromocional: tienePromocion && promocion != null ? promocion['precio_promocional'] as double? : null,
                          promocionId: tienePromocion && promocion != null ? promocion['id'] as String? : null,
                        ),
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 300),
                  ),
                ).then((reservaRealizada) async {
                  if (reservaRealizada == true) {
                    // ✅ ACTUALIZAR ESTADO LOCAL INMEDIATAMENTE
                    await _actualizarEstadoLocalReservaCreada(horario);
                    // También recargar para sincronizar con Firestore
                    _reservasSnapshots.clear();
                    _loadHorarios();
                  }
                });
              }
            },
            borderRadius: BorderRadius.circular(12),
            splashColor: horario.estado == EstadoHorario.reservado
                ? Colors.green.shade100.withOpacity(0.3)
                : horario.estado == EstadoHorario.procesandoPago
                    ? Colors.red.shade100.withOpacity(0.3) // ✅ NUEVO
                    : Colors.green.shade100.withOpacity(0.5),
            highlightColor: horario.estado == EstadoHorario.reservado
                ? Colors.green.shade200.withOpacity(0.2)
                : horario.estado == EstadoHorario.procesandoPago
                    ? Colors.red.shade200.withOpacity(0.2) // ✅ NUEVO
                    : Colors.green.shade200.withOpacity(0.3),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: tienePromocion && horario.estado == EstadoHorario.disponible
                      ? Colors.amber.shade600 // ✅ NUEVO: Borde dorado para promociones
                      : horario.estado == EstadoHorario.disponible
                          ? const Color(0xFF4CAF50)
                          : horario.estado == EstadoHorario.reservado
                              ? const Color(0xFF1B5E20)
                          : horario.estado == EstadoHorario.procesandoPago
                              ? Colors.red.shade600
                          : Colors.grey.shade400,
                  width: tienePromocion && horario.estado == EstadoHorario.disponible ? 2.5 : 1.5, // ✅ NUEVO: Borde más grueso para promociones
                ),
                boxShadow: [
                  // ✅ NUEVO: Sombra dorada para promociones
                  if (tienePromocion && horario.estado == EstadoHorario.disponible) ...[
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.5),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  if (horario.estado == EstadoHorario.disponible && !tienePromocion) ...[
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withOpacity(0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  if (horario.estado == EstadoHorario.reservado) ...[
                    BoxShadow(
                      color: const Color(0xFF1B5E20).withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  // ✅ SOMBRA PARA PROCESANDO PAGO
                  if (horario.estado == EstadoHorario.procesandoPago) ...[
                    BoxShadow(
                      color: Colors.red.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  if (horario.estado == EstadoHorario.vencido)
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  children: [
                    // Fondo base mejorado
                    Container(
                      decoration: BoxDecoration(
                        gradient: tienePromocion && horario.estado == EstadoHorario.disponible
                            ? LinearGradient( // ✅ NUEVO: Gradiente dorado para promociones
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.amber.shade50,
                                  Colors.orange.shade50,
                                  Colors.yellow.shade50,
                                ],
                              )
                            : horario.estado == EstadoHorario.disponible
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white,
                                      const Color(0xFFF1F8E9),
                                      const Color(0xFFE8F5E8),
                                    ],
                                  )
                            : horario.estado == EstadoHorario.reservado
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      const Color(0xFF1B5E20),
                                      const Color(0xFF2E7D32),
                                      const Color(0xFF388E3C),
                                    ],
                                  )
                            // ✅ GRADIENTE PARA PROCESANDO PAGO
                            : horario.estado == EstadoHorario.procesandoPago
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.red.shade600,
                                      Colors.red.shade500,
                                      Colors.red.shade400,
                                    ],
                                  )
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.grey.shade200,
                                      Colors.grey.shade100,
                                    ],
                                  ),
                      ),
                    ),
                    
                    // Imagen de fondo para reservados y procesando pago
                    if (horario.estado == EstadoHorario.reservado || horario.estado == EstadoHorario.procesandoPago)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage('assets/redi22.png'),
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              opacity: 0.6,
                            ),
                          ),
                        ),
                      ),
                    
                    // Contenido principal
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Hora - Ajustada responsivamente
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  horario.horaFormateada,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.bold,
                                    color: horario.estado == EstadoHorario.disponible
                                        ? const Color(0xFF1B5E20)
                                        : horario.estado == EstadoHorario.reservado
                                            ? Colors.white
                                        : horario.estado == EstadoHorario.procesandoPago  // ✅ COLOR PARA PROCESANDO
                                            ? Colors.white
                                        : Colors.black54,
                                    letterSpacing: 0.3,
                                    shadows: (horario.estado == EstadoHorario.reservado || horario.estado == EstadoHorario.procesandoPago)
                                        ? [
                                            Shadow(
                                              color: Colors.black.withOpacity(0.5),
                                              offset: const Offset(1, 1),
                                              blurRadius: 3,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                            
                            SizedBox(height: constraints.maxHeight * 0.05),
                            
                            // Precio solo para disponibles
                            if (horario.estado == EstadoHorario.disponible) ...[
                              Flexible(
                                child: tienePromocion
                                    ? _buildPrecioPromocional(precio, priceFontSize, constraints)
                                    : Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: constraints.maxWidth * 0.08,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4CAF50).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: const Color(0xFF4CAF50).withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(precio),
                                            style: TextStyle(
                                              fontSize: priceFontSize,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1B5E20),
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                              ),
                              SizedBox(height: constraints.maxHeight * 0.05),
                            ] else
                              SizedBox(height: constraints.maxHeight * 0.05),
                            
                            // Estado
                            Flexible(
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: constraints.maxWidth * 0.08,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: horario.estado == EstadoHorario.disponible
                                      ? const Color(0xFF4CAF50).withOpacity(0.15)
                                      : horario.estado == EstadoHorario.reservado
                                          ? Colors.white.withOpacity(0.95)
                                      : horario.estado == EstadoHorario.procesandoPago  // ✅ FONDO PARA PROCESANDO
                                          ? Colors.white.withOpacity(0.95)
                                      : Colors.black.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: horario.estado == EstadoHorario.disponible
                                        ? const Color(0xFF4CAF50).withOpacity(0.4)
                                        : horario.estado == EstadoHorario.reservado
                                            ? Colors.white.withOpacity(0.8)
                                        : horario.estado == EstadoHorario.procesandoPago  // ✅ BORDE PARA PROCESANDO
                                            ? Colors.white.withOpacity(0.8)
                                        : Colors.grey.withOpacity(0.4),
                                    width: 1,
                                  ),
                                  boxShadow: (horario.estado == EstadoHorario.reservado || horario.estado == EstadoHorario.procesandoPago)
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.15),
                                            blurRadius: 3,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        horario.estado == EstadoHorario.disponible
                                            ? Icons.check_circle_outline
                                            : horario.estado == EstadoHorario.reservado
                                                ? Icons.sports_soccer
                                            : horario.estado == EstadoHorario.procesandoPago  // ✅ ICONO PARA PROCESANDO
                                                ? Icons.hourglass_empty
                                            : Icons.access_time,
                                        size: iconSize,
                                        color: horario.estado == EstadoHorario.disponible
                                            ? const Color(0xFF1B5E20)
                                            : horario.estado == EstadoHorario.reservado
                                                ? const Color(0xFF1B5E20)
                                            : horario.estado == EstadoHorario.procesandoPago  // ✅ COLOR ICONO PROCESANDO
                                                ? Colors.red.shade700
                                            : Colors.black54,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        horario.estado == EstadoHorario.disponible
                                            ? 'LIBRE'
                                            : horario.estado == EstadoHorario.reservado
                                                ? 'Reservado'
                                            : horario.estado == EstadoHorario.procesandoPago  // ✅ TEXTO PARA PROCESANDO
                                                ? 'Procesando'
                                            : 'Vencido',
                                        style: TextStyle(
                                          fontSize: statusFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: horario.estado == EstadoHorario.disponible
                                              ? const Color(0xFF1B5E20)
                                              : horario.estado == EstadoHorario.reservado
                                                  ? const Color(0xFF1B5E20)
                                              : horario.estado == EstadoHorario.procesandoPago  // ✅ COLOR TEXTO PROCESANDO
                                                  ? Colors.red.shade700
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // ✅ NUEVO: Efecto dorado animado para promociones
                    if (tienePromocion && horario.estado == EstadoHorario.disponible)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _goldShimmerController,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: GoldShimmerPainter(_goldShimmerController.value),
                              );
                            },
                          ),
                        ),
                      ),
                    // Efecto de brillo sutil para reservados y procesando
                    if (horario.estado == EstadoHorario.reservado || horario.estado == EstadoHorario.procesandoPago)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: constraints.maxHeight * 0.3,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(11),
                              topRight: Radius.circular(11),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.2),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
  
  // ✅ NUEVO: Widget para precio promocional con efecto dorado
  Widget _buildPrecioPromocional(double precio, double fontSize, BoxConstraints constraints) {
    return AnimatedBuilder(
      animation: _goldShimmerController,
      builder: (context, child) {
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: constraints.maxWidth * 0.08,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.amber.shade400,
                Colors.orange.shade400,
                Colors.amber.shade500,
              ],
            ),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: Colors.amber.shade700,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(-1.0 + (_goldShimmerController.value * 2), 0),
                end: Alignment(1.0 + (_goldShimmerController.value * 2), 0),
                colors: [
                  Colors.white,
                  Colors.yellow.shade200,
                  Colors.white,
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(bounds);
            },
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_offer,
                    size: fontSize * 0.85,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(precio),
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ✅ NUEVO: CustomPainter para efecto dorado animado
class GoldShimmerPainter extends CustomPainter {
  final double animationValue;

  GoldShimmerPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    // Crear gradiente dorado que se mueve
    final gradient = LinearGradient(
      begin: Alignment(-1.0 + (animationValue * 2), 0),
      end: Alignment(1.0 + (animationValue * 2), 0),
      colors: [
        Colors.transparent,
        Colors.amber.withOpacity(0.3),
        Colors.yellow.withOpacity(0.4),
        Colors.amber.withOpacity(0.3),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    paint.shader = gradient;
    
    // Dibujar múltiples líneas de brillo
    for (int i = 0; i < 3; i++) {
      final y = (size.height / 4) * (i + 1);
      final path = Path()
        ..moveTo(0, y)
        ..lineTo(size.width, y);
      
      paint.strokeWidth = 2 - (i * 0.5);
      paint.style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
    }
    
    // Partículas doradas flotantes
    for (int i = 0; i < 5; i++) {
      final x = (size.width / 6) * (i + 1);
      final y = size.height * (0.2 + (i % 3) * 0.3);
      final offset = (animationValue * 2 * math.pi) + (i * 0.5);
      
      final particleY = y + math.sin(offset) * 5;
      final opacity = 0.4 + (math.sin(offset) * 0.3);
      
      paint
        ..style = PaintingStyle.fill
        ..color = Colors.amber.withOpacity(opacity)
        ..shader = null;
      
      canvas.drawCircle(
        Offset(x, particleY),
        2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GoldShimmerPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}