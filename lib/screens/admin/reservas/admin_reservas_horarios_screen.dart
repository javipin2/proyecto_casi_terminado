import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';
import 'package:reserva_canchas/screens/admin/reservas/admin_detalles_reservas.dart';
import 'package:reserva_canchas/utils/reserva_audit_utils.dart';
import '../../../models/cancha.dart';
import '../../../models/reserva.dart';
import '../../../models/horario.dart';
import '../../../providers/cancha_provider.dart';
import '../../../providers/sede_provider.dart';
import '../../../models/reserva_recurrente.dart';
import '../../../providers/reserva_recurrente_provider.dart';
import 'agregar_reserva_screen.dart';
import '../../../providers/peticion_provider.dart';
import '../../../models/peticion.dart';

class AdminReservasScreen extends StatefulWidget {
  // ✅ AGREGAR PARÁMETROS PARA MODO SELECTOR
  final bool esModoSelector;
  final String? reservaOriginalId;
  final Function(String sede, String canchaId, String horario, DateTime fecha)? onSeleccionConfirmada;

  const AdminReservasScreen({
    super.key,
    this.esModoSelector = false,
    this.reservaOriginalId,
    this.onSeleccionConfirmada,
  });

  @override
  AdminReservasScreenState createState() => AdminReservasScreenState();
}

class AdminReservasScreenState extends State<AdminReservasScreen>
    with TickerProviderStateMixin {
  String _selectedSedeId = '';
  String _selectedSedeNombre = '';
  Cancha? _selectedCancha;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _viewGrid = true;
  bool _showingRecurrentReservas = false;
  List<ReservaRecurrente> _reservasRecurrentesActivas = [];

  late AnimationController _fadeController;
  late AnimationController _slideController;

  StreamSubscription<QuerySnapshot>? _reservasSubscription;

  List<Cancha> _canchas = [];
  List<Reserva> _reservas = [];
  Map<String, Reserva> _reservedMap = {};
  final List<String> _selectedHours = [];
  List<String> _hours = List.generate(24, (index) {
    final timeOfDay = TimeOfDay(hour: (index + 1) % 24, minute: 0);
    return Horario(hora: timeOfDay).horaFormateada;
  });
  Timer? _debounceTimer;

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);
  final Color _disabledColor = const Color(0xFFDADCE0);
  final Color _reservedColor = const Color(0xFF4CAF50);
  final Color _availableColor = const Color(0xFFEEEEEE);
  final Color _selectedHourColor = const Color(0xFFFFCA28);

  // ✅ REEMPLAZAR las variables de peticiones (líneas ~50-53)
  List<Peticion> _peticionesPendientes = [];
  Map<String, Peticion> _peticionesPorHorario = {};
  StreamSubscription<QuerySnapshot>? _peticionesSubscription;
  Set<String> _peticionesNotificadas = {}; // ✅ NUEVO: Rastrear notificaciones mostradas

  // ✅ REEMPLAZAR el método initState (líneas ~80-95)
  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es', null);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
      _iniciarEscuchaPeticionesEnTiempoReal(); // ✅ CAMBIO: Nuevo método
    });
  }

  Future<void> _initializeData() async {
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    
    try {
      await sedeProvider.fetchSedes();
      
      if (!mounted) return;
      
      if (sedeProvider.sedes.isNotEmpty) {
        setState(() {
          _selectedSedeId = sedeProvider.sedes.first['id'] as String;
          _selectedSedeNombre = sedeProvider.sedes.first['nombre'] as String;
        });
        sedeProvider.setSede(_selectedSedeNombre);
        
        await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
        
        if (_selectedSedeId.isNotEmpty) {
          await _loadCanchas();
        }
      } else {
        setState(() {
          _selectedSedeId = '';
          _selectedSedeNombre = '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al inicializar datos: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ✅ REEMPLAZAR el método dispose (líneas ~135-145)
  @override
  void dispose() {
    _reservasSubscription?.cancel();
    _peticionesSubscription?.cancel(); // ✅ IMPORTANTE: Cancelar stream de peticiones
    _fadeController.dispose();
    _slideController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCanchas() async {
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    
    setState(() {
      _isLoading = true;
      _canchas.clear();
      _selectedCancha = null;
      _selectedHours.clear();
    });

    try {
      await canchaProvider.fetchCanchas(_selectedSedeId);
      
      if (reservaRecurrenteProvider.reservasRecurrentes.isEmpty) {
        await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
      }
      
      if (!mounted) return;

      setState(() {
        _canchas = canchaProvider.canchas.where((c) => c.sedeId == _selectedSedeId).toList();
        _selectedCancha = _canchas.isNotEmpty ? _canchas.first : null;
        _isLoading = false;
      });

      if (_selectedCancha != null) {
        await _loadReservas();
      } else {
        setState(() {
          _reservas.clear();
          _reservedMap.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al cargar canchas: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadReservas() async {
    if (_selectedCancha == null) return;
    
    _reservasSubscription?.cancel();
    setState(() {
      _isLoading = true;
      _reservas.clear();
      _reservedMap.clear();
      _selectedHours.clear();
    });

    try {
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      
      if (reservaRecurrenteProvider.reservasRecurrentes.isEmpty) {
        await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
      }

      final stream = FirebaseFirestore.instance
          .collection('reservas')
          .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate))
          .where('sede', isEqualTo: _selectedSedeId)
          .where('cancha_id', isEqualTo: _selectedCancha!.id)
          .limit(24)
          .snapshots();

      _reservasSubscription = stream.listen(
        (querySnapshot) async {
          try {
            final horarios = await Horario.generarHorarios(
              fecha: _selectedDate,
              canchaId: _selectedCancha!.id,
              sede: _selectedSedeId,
              reservasSnapshot: querySnapshot,
              cancha: _selectedCancha!,
            );
            
            List<Reserva> reservasTemp = [];
            Map<String, Reserva> reservedMapTemp = {};
            
            for (var doc in querySnapshot.docs) {
              try {
                final reserva = await Reserva.fromFirestore(doc);
                final horaNormalizada = Horario.normalizarHora(reserva.horario.horaFormateada);
                reservedMapTemp[horaNormalizada] = reserva;
                reservasTemp.add(reserva);
                debugPrint('📋 Reserva normal: ${reserva.nombre} - $horaNormalizada');
              } catch (e) {
                debugPrint("❌ Error al procesar documento: $e");
              }
            }
            
            final reservasRecurrentes = reservaRecurrenteProvider.obtenerReservasActivasParaFecha(
              _selectedDate, 
              sede: _selectedSedeId, 
              canchaId: _selectedCancha!.id
            );
            
            debugPrint('📅 Fecha: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
            debugPrint('🏟️ Cancha: ${_selectedCancha!.nombre} (${_selectedCancha!.id})');
            debugPrint('🏢 Sede: $_selectedSedeId');
            debugPrint('🔄 Reservas recurrentes encontradas: ${reservasRecurrentes.length}');
            
            for (var reservaRecurrente in reservasRecurrentes) {
              final horaNormalizada = Horario.normalizarHora(reservaRecurrente.horario);
              
              debugPrint('⏰ Procesando recurrente: ${reservaRecurrente.horario} -> $horaNormalizada');
              debugPrint('👤 Cliente: ${reservaRecurrente.clienteNombre}');
              debugPrint('📊 Estado: ${reservaRecurrente.estado}');
              
              if (!reservedMapTemp.containsKey(horaNormalizada)) {
                try {
                  final horario = Horario.fromHoraFormateada(reservaRecurrente.horario);
                  
                  final reservaVirtual = Reserva(
                    id: '${reservaRecurrente.id}_${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                    cancha: _selectedCancha!,
                    fecha: _selectedDate,
                    horario: horario,
                    sede: reservaRecurrente.sede,
                    tipoAbono: reservaRecurrente.montoPagado >= reservaRecurrente.montoTotal 
                        ? TipoAbono.completo : TipoAbono.parcial,
                    montoTotal: reservaRecurrente.montoTotal,
                    montoPagado: reservaRecurrente.montoPagado,
                    nombre: reservaRecurrente.clienteNombre,
                    telefono: reservaRecurrente.clienteTelefono,
                    email: reservaRecurrente.clienteEmail,
                    confirmada: true,
                    reservaRecurrenteId: reservaRecurrente.id,
                    esReservaRecurrente: true,
                    precioPersonalizado: reservaRecurrente.precioPersonalizado,
                    precioOriginal: reservaRecurrente.precioOriginal,
                    descuentoAplicado: reservaRecurrente.descuentoAplicado,
                  );
                  
                  reservedMapTemp[horaNormalizada] = reservaVirtual;
                  reservasTemp.add(reservaVirtual);
                  
                  debugPrint('✅ Reserva virtual creada: ${reservaVirtual.nombre} - $horaNormalizada');
                } catch (e) {
                  debugPrint('❌ Error creando reserva virtual: $e');
                }
              } else {
                debugPrint('⚠️ Horario ya ocupado por reserva normal: $horaNormalizada');
              }
            }
            
            // ✅ REEMPLAZAR líneas después de setState en _loadReservas (línea ~265 aprox)
            // ✅ SOLO dejar esto:
            if (mounted) {
              setState(() {
                _reservas = reservasTemp;
                _reservedMap = reservedMapTemp;
                _hours = horarios.map((h) => h.horaFormateada).toList();
                _isLoading = false;
              });
              
              debugPrint('📊 Total reservas mostradas: ${_reservas.length}');
              debugPrint('📊 Reservas normales: ${_reservas.where((r) => !r.esReservaRecurrente).length}');
              debugPrint('📊 Reservas recurrentes: ${_reservas.where((r) => r.esReservaRecurrente).length}');
      _iniciarEscuchaPeticionesEnTiempoReal();

            }
          } catch (e) {
            debugPrint('❌ Error en stream listener: $e');
            if (mounted) {
              _showErrorSnackBar('Error al procesar reservas: $e');
              setState(() {
                _isLoading = false;
              });
            }
          }
        },
        onError: (e) {
          debugPrint('❌ Error en stream: $e');
          if (mounted) {
            _showErrorSnackBar('Error al cargar reservas: $e');
            setState(() {
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('❌ Error general en _loadReservas: $e');
      if (mounted) {
        _showErrorSnackBar('Error al inicializar carga de reservas: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ✅ AGREGAR este método después de _loadReservas (línea ~350 aprox)
  void _iniciarEscuchaPeticionesEnTiempoReal() {
  _peticionesSubscription?.cancel();
  
  // 🆕 NUEVO: Map para rastrear el último estado conocido de cada petición
  Map<String, EstadoPeticion> ultimosEstadosConocidos = {};
  
  _peticionesSubscription = FirebaseFirestore.instance
      .collection('peticiones')
      .where('estado', whereIn: ['pendiente', 'aprobada', 'rechazada'])
      .snapshots()
      .listen(
    (querySnapshot) {
      if (!mounted) return;
      
      final ahora = DateTime.now();
      final List<Peticion> peticionesPendientes = [];
      final Map<String, Peticion> peticionesPorHorario = {};
      
      // 🎯 OBTENER LA FECHA ACTUAL SELECCIONADA PARA FILTRAR
      final fechaSeleccionadaStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      
      debugPrint('🔍 Procesando peticiones para fecha: $fechaSeleccionadaStr');
      debugPrint('📅 Sede actual: $_selectedSedeId');
      debugPrint('🏟️ Cancha actual: ${_selectedCancha?.id}');
      
      // 🆕 Variables para rastrear cambios reales de estado
      bool huboReservaRecurrenteAprobada = false;
      
      for (var doc in querySnapshot.docs) {
        try {
          final peticion = Peticion.fromFirestore(doc);
          final estadoAnterior = ultimosEstadosConocidos[peticion.id];
          final estadoActual = peticion.estado;
          
          // 🔄 ACTUALIZAR EL ESTADO CONOCIDO
          ultimosEstadosConocidos[peticion.id] = estadoActual;
          
          // ✅ PROCESAR TODOS LOS TIPOS DE PETICIONES DE RESERVAS
          final tipoPeticion = peticion.valoresNuevos['tipo'] as String?;
          final esNuevaReservaNormal = tipoPeticion == 'nueva_reserva_precio_personalizado';
          final esNuevaReservaRecurrente = tipoPeticion == 'nueva_reserva_recurrente_precio_personalizado';
          
          if (esNuevaReservaNormal || esNuevaReservaRecurrente) {
            
            // ✅ DETECTAR CAMBIOS DE ESTADO REALES (solo si cambió desde la última vez)
            if (estadoAnterior != null && estadoAnterior != estadoActual) {
              
              if (peticion.fueAprobada && !_peticionesNotificadas.contains('${peticion.id}_aprobada')) {
                _peticionesNotificadas.add('${peticion.id}_aprobada');
                String mensaje = esNuevaReservaRecurrente 
                    ? '✅ Petición aprobada - se creó una nueva reserva recurrente'
                    : '✅ Petición aprobada - se creó una nueva reserva';
                _mostrarNotificacionPeticionActualizada(mensaje);
                
                // 🔄 MARCAR QUE HUBO UNA RESERVA RECURRENTE APROBADA
                if (esNuevaReservaRecurrente) {
                  huboReservaRecurrenteAprobada = true;
                }
                
                // ✅ RECARGAR RESERVAS INMEDIATAMENTE SOLO PARA RESERVAS NORMALES
                if (esNuevaReservaNormal) {
                  Future.delayed(const Duration(milliseconds: 1000), () {
                    if (mounted) _loadReservas();
                  });
                }
              }
              
              if (peticion.fueRechazada && !_peticionesNotificadas.contains('${peticion.id}_rechazada')) {
                _peticionesNotificadas.add('${peticion.id}_rechazada');
                
                String clienteNombre = 'Cliente';
                if (esNuevaReservaRecurrente) {
                  final datosReserva = peticion.valoresNuevos['datos_reserva_recurrente'] as Map<String, dynamic>? ?? {};
                  clienteNombre = datosReserva['cliente_nombre'] as String? ?? 'Cliente';
                } else {
                  final datosReserva = peticion.valoresNuevos['datos_reserva'] as Map<String, dynamic>? ?? {};
                  clienteNombre = datosReserva['cliente_nombre'] as String? ?? 'Cliente';
                }
                
                String mensaje = esNuevaReservaRecurrente
                    ? '❌ Petición de reserva recurrente de $clienteNombre fue rechazada'
                    : '❌ Petición de $clienteNombre fue rechazada';
                _mostrarNotificacionPeticionActualizada(mensaje);
              }
            }
            
            // 🎯 FILTRAR PETICIONES PENDIENTES SOLO PARA LA FECHA/SEDE/CANCHA ACTUAL
            if (peticion.estaPendiente) {
              bool debeIncluirse = false;
              
              if (esNuevaReservaNormal) {
                // ✅ PARA RESERVAS NORMALES: verificar fecha exacta + sede + cancha
                debeIncluirse = _peticionAplicaParaReservaNormal(peticion, fechaSeleccionadaStr);
              } else if (esNuevaReservaRecurrente) {
                // ✅ PARA RESERVAS RECURRENTES: verificar si aplica para la fecha actual
                debeIncluirse = _peticionAplicaParaReservaRecurrente(peticion, _selectedDate);
              }
              
              if (debeIncluirse) {
                peticionesPendientes.add(peticion);
                
                // ✅ PROCESAR SEGÚN EL TIPO
                if (esNuevaReservaNormal) {
                  _procesarPeticionReservaNormal(peticion, peticionesPorHorario);
                } else if (esNuevaReservaRecurrente) {
                  _procesarPeticionReservaRecurrente(peticion, peticionesPorHorario);
                }
              } else {
                debugPrint('🚫 Petición ${peticion.id} no aplica para la fecha/sede/cancha actual');
              }
            }
          }
        } catch (e) {
          debugPrint('Error procesando petición: $e');
        }
      }
      
      setState(() {
        _peticionesPendientes = peticionesPendientes;
        _peticionesPorHorario = peticionesPorHorario;
      });
      
      // 🔄 REFRESCAR RESERVAS RECURRENTES SI HUBO APROBACIONES
      if (huboReservaRecurrenteAprobada) {
        debugPrint('🔄 Refrescando reservas recurrentes después de aprobación...');
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _refrescarReservasRecurrentesYRecargar();
        });
      }
      
      debugPrint('📊 RESULTADO DEL FILTRADO:');
      debugPrint('   - Peticiones pendientes para esta vista: ${peticionesPendientes.length}');
      debugPrint('   - Horarios con peticiones: ${peticionesPorHorario.length}');
      
      // ✅ LLAMAR AL DEBUG DESPUÉS DE PROCESAR
      _debugPeticionesActuales();
    },
    onError: (error) {
      debugPrint('Error en stream de peticiones: $error');
      if (mounted) {
        _showErrorSnackBar('Error al escuchar peticiones: $error');
      }
    },
  );
}


bool _peticionAplicaParaReservaNormal(Peticion peticion, String fechaSeleccionadaStr) {
  final datosReserva = peticion.valoresNuevos['datos_reserva'] as Map<String, dynamic>?;
  if (datosReserva == null) return false;
  
  final fechaPeticion = datosReserva['fecha'] as String?;
  final sedePeticion = datosReserva['sede'] as String?;
  final canchaPeticion = datosReserva['cancha_id'] as String?;
  
  // 🎯 FILTRO ESTRICTO: fecha, sede y cancha deben coincidir exactamente
  final fechaCoincide = fechaPeticion == fechaSeleccionadaStr;
  final sedeCoincide = sedePeticion == _selectedSedeId;
  final canchaCoincide = canchaPeticion == _selectedCancha?.id;
  
  final aplica = fechaCoincide && sedeCoincide && canchaCoincide;
  
  debugPrint('🔍 Verificando petición reserva normal ${peticion.id}:');
  debugPrint('   - Fecha: $fechaPeticion == $fechaSeleccionadaStr → $fechaCoincide');
  debugPrint('   - Sede: $sedePeticion == $_selectedSedeId → $sedeCoincide');
  debugPrint('   - Cancha: $canchaPeticion == ${_selectedCancha?.id} → $canchaCoincide');
  debugPrint('   - Resultado: $aplica');
  
  return aplica;
}

// 🆕 NUEVO MÉTODO: Verificar si una petición de reserva recurrente aplica para la fecha actual
bool _peticionAplicaParaReservaRecurrente(Peticion peticion, DateTime fechaSeleccionada) {
  final datosReserva = peticion.valoresNuevos['datos_reserva_recurrente'] as Map<String, dynamic>?;
  if (datosReserva == null) return false;
  
  final sedePeticion = datosReserva['sede'] as String?;
  final canchaPeticion = datosReserva['cancha_id'] as String?;
  final diasSemana = datosReserva['dias_semana'] as List?;
  final fechaInicio = datosReserva['fecha_inicio'] as String?;
  final fechaFin = datosReserva['fecha_fin'] as String?;
  
  // ✅ VERIFICAR SEDE Y CANCHA PRIMERO
  if (sedePeticion != _selectedSedeId || canchaPeticion != _selectedCancha?.id) {
    debugPrint('🚫 Petición recurrente ${peticion.id}: sede/cancha no coincide');
    return false;
  }
  
  if (diasSemana == null || fechaInicio == null) {
    debugPrint('🚫 Petición recurrente ${peticion.id}: datos incompletos');
    return false;
  }
  
  try {
    final fechaInicioDateTime = DateTime.parse(fechaInicio);
    DateTime? fechaFinDateTime;
    if (fechaFin != null && fechaFin.isNotEmpty) {
      fechaFinDateTime = DateTime.parse(fechaFin);
    }
    
    // ✅ VERIFICAR CONDICIONES DE FECHA Y DÍA
    final fechaSeleccionadaStr = DateFormat('yyyy-MM-dd').format(fechaSeleccionada);
    final diaSeleccionado = DateFormat('EEEE', 'es').format(fechaSeleccionada).toLowerCase();
    
    // Convertir días de la semana a formato español
    final diasSemanaFormateados = diasSemana.map((dia) {
      final diaStr = dia.toString().toLowerCase();
      switch (diaStr) {
        case 'monday': case 'lunes': return 'lunes';
        case 'tuesday': case 'martes': return 'martes';
        case 'wednesday': case 'miércoles': case 'miercoles': return 'miércoles';
        case 'thursday': case 'jueves': return 'jueves';
        case 'friday': case 'viernes': return 'viernes';
        case 'saturday': case 'sábado': case 'sabado': return 'sábado';
        case 'sunday': case 'domingo': return 'domingo';
        default: return diaStr;
      }
    }).toList();
    
    final fechaEnRango = fechaSeleccionada.isAfter(fechaInicioDateTime.subtract(const Duration(days: 1))) &&
                        (fechaFinDateTime == null || fechaSeleccionada.isBefore(fechaFinDateTime.add(const Duration(days: 1))));
    
    final esDiaValido = diasSemanaFormateados.contains(diaSeleccionado);
    
    // Verificar días excluidos
    final diasExcluidos = datosReserva['dias_excluidos'] as List? ?? [];
    final estaExcluida = diasExcluidos.contains(fechaSeleccionadaStr);
    
    final aplica = fechaEnRango && esDiaValido && !estaExcluida;
    
    debugPrint('🔍 Verificando petición recurrente ${peticion.id}:');
    debugPrint('   - Fecha en rango: $fechaEnRango');
    debugPrint('   - Día válido: $esDiaValido ($diaSeleccionado en $diasSemanaFormateados)');
    debugPrint('   - No excluida: ${!estaExcluida}');
    debugPrint('   - Resultado: $aplica');
    
    return aplica;
  } catch (e) {
    debugPrint('❌ Error verificando petición recurrente ${peticion.id}: $e');
    return false;
  }
}




  void _procesarPeticionReservaNormal(Peticion peticion, Map<String, Peticion> peticionesPorHorario) {
  final datosReserva = peticion.valoresNuevos['datos_reserva'] as Map<String, dynamic>?;
  if (datosReserva == null) return;
  
  final fecha = datosReserva['fecha'] as String?;
  final sede = datosReserva['sede'] as String?;
  final canchaId = datosReserva['cancha_id'] as String?;
  final horarios = datosReserva['horarios'] as List?;
  
  // ✅ VALIDACIÓN ESTRICTA: Solo mostrar si coincide EXACTAMENTE con la pantalla actual
  final fechaSeleccionadaStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
  
  // 🔍 VERIFICACIÓN COMPLETA: fecha, sede y cancha deben coincidir exactamente
  final fechaCoincide = fecha == fechaSeleccionadaStr;
  final sedeCoincide = sede == _selectedSedeId;
  final canchaCoincide = canchaId == _selectedCancha?.id;
  
  debugPrint('🔍 Procesando petición reserva normal:');
  debugPrint('   - ID Petición: ${peticion.id}');
  debugPrint('   - Fecha petición: $fecha');
  debugPrint('   - Fecha seleccionada: $fechaSeleccionadaStr');
  debugPrint('   - Fecha coincide: $fechaCoincide');
  debugPrint('   - Sede petición: $sede');
  debugPrint('   - Sede seleccionada: $_selectedSedeId');
  debugPrint('   - Sede coincide: $sedeCoincide');
  debugPrint('   - Cancha petición: $canchaId');
  debugPrint('   - Cancha seleccionada: ${_selectedCancha?.id}');
  debugPrint('   - Cancha coincide: $canchaCoincide');
  debugPrint('   - Horarios: $horarios');
  
  // ✅ SOLO PROCESAR SI TODOS LOS CRITERIOS COINCIDEN
  if (fechaCoincide && sedeCoincide && canchaCoincide && horarios != null) {
    debugPrint('✅ ¡Petición válida! Agregando a horarios...');
    
    for (var horario in horarios) {
      final horaStr = horario.toString();
      final horaNormalizada = Horario.normalizarHora(horaStr);
      peticionesPorHorario[horaNormalizada] = peticion;
      
      debugPrint('   ✅ Horario agregado: $horaNormalizada');
    }
  } else {
    // 🚫 DEBUG: Explicar por qué NO se procesa la petición
    debugPrint('🚫 Petición NO procesada. Razones:');
    if (!fechaCoincide) {
      debugPrint('   ❌ Fecha no coincide: $fecha ≠ $fechaSeleccionadaStr');
    }
    if (!sedeCoincide) {
      debugPrint('   ❌ Sede no coincide: $sede ≠ $_selectedSedeId');
    }
    if (!canchaCoincide) {
      debugPrint('   ❌ Cancha no coincide: $canchaId ≠ ${_selectedCancha?.id}');
    }
    if (horarios == null) {
      debugPrint('   ❌ No hay horarios en la petición');
    }
  }
}



// ✅ AGREGAR este método después de _procesarPeticionReservaRecurrente para debugging
void _debugPeticionesActuales() {
  debugPrint('🔍 DEBUG PETICIONES ACTUALES:');
  debugPrint('   - Fecha seleccionada: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
  debugPrint('   - Sede seleccionada: $_selectedSedeId');
  debugPrint('   - Cancha seleccionada: ${_selectedCancha?.id} (${_selectedCancha?.nombre})');
  debugPrint('   - Total peticiones pendientes: ${_peticionesPendientes.length}');
  debugPrint('   - Peticiones por horario: ${_peticionesPorHorario.length}');
  
  debugPrint('📋 LISTADO DE TODAS LAS PETICIONES PENDIENTES:');
  for (var peticion in _peticionesPendientes) {
    final tipo = peticion.valoresNuevos['tipo'] as String?;
    debugPrint('   🔸 Petición ${peticion.id}:');
    debugPrint('      - Tipo: $tipo');
    
    if (tipo == 'nueva_reserva_precio_personalizado') {
      final datosReserva = peticion.valoresNuevos['datos_reserva'] as Map<String, dynamic>? ?? {};
      final fechaPeticion = datosReserva['fecha'];
      final sedePeticion = datosReserva['sede'];
      final canchaPeticion = datosReserva['cancha_id'];
      
      debugPrint('      - Fecha: $fechaPeticion ${fechaPeticion == DateFormat('yyyy-MM-dd').format(_selectedDate) ? '✅' : '❌'}');
      debugPrint('      - Sede: $sedePeticion ${sedePeticion == _selectedSedeId ? '✅' : '❌'}');
      debugPrint('      - Cancha: $canchaPeticion ${canchaPeticion == _selectedCancha?.id ? '✅' : '❌'}');
      debugPrint('      - Horarios: ${datosReserva['horarios']}');
      debugPrint('      - Cliente: ${datosReserva['cliente_nombre']}');
    } else if (tipo == 'nueva_reserva_recurrente_precio_personalizado') {
      final datosReserva = peticion.valoresNuevos['datos_reserva_recurrente'] as Map<String, dynamic>? ?? {};
      debugPrint('      - Sede: ${datosReserva['sede']} ${datosReserva['sede'] == _selectedSedeId ? '✅' : '❌'}');
      debugPrint('      - Cancha: ${datosReserva['cancha_id']} ${datosReserva['cancha_id'] == _selectedCancha?.id ? '✅' : '❌'}');
      debugPrint('      - Horario: ${datosReserva['horario']}');
      debugPrint('      - Días: ${datosReserva['dias_semana']}');
      debugPrint('      - Fecha inicio: ${datosReserva['fecha_inicio']}');
      debugPrint('      - Fecha fin: ${datosReserva['fecha_fin']}');
      debugPrint('      - Cliente: ${datosReserva['cliente_nombre']}');
    }
  }
  
  debugPrint('🎯 HORARIOS CON PETICIONES ACTIVAS:');
  _peticionesPorHorario.forEach((horario, peticion) {
    final tipo = peticion.valoresNuevos['tipo'] as String?;
    debugPrint('   ⏰ $horario: Petición ${peticion.id} ($tipo)');
  });
  
  debugPrint('📊 RESUMEN:');
  debugPrint('   - Peticiones mostradas en UI: ${_peticionesPorHorario.length}');
  debugPrint('   - Peticiones totales pendientes: ${_peticionesPendientes.length}');
}


Future<void> _refrescarReservasRecurrentesYRecargar() async {
  if (!mounted) return;
  
  try {
    debugPrint('🔄 Iniciando refresco de reservas recurrentes...');
    
    // 1️⃣ REFRESCAR EL PROVIDER DE RESERVAS RECURRENTES
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
    
    debugPrint('✅ Provider de reservas recurrentes actualizado');
    
    // 2️⃣ RECARGAR LAS RESERVAS DE LA VISTA ACTUAL
    await _loadReservas();
    
    debugPrint('✅ Vista de reservas recargada completamente');
    
    if (mounted) {
      // 3️⃣ MOSTRAR CONFIRMACIÓN VISUAL SUTIL (opcional)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.refresh, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                'Reservas actualizadas',
                style: GoogleFonts.montserrat(fontSize: 14),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    
  } catch (e) {
    debugPrint('❌ Error refrescando reservas recurrentes: $e');
    if (mounted) {
      _showErrorSnackBar('Error actualizando reservas: $e');
    }
  }
}


void _procesarPeticionReservaRecurrente(Peticion peticion, Map<String, Peticion> peticionesPorHorario) {
  final datosReserva = peticion.valoresNuevos['datos_reserva_recurrente'] as Map<String, dynamic>?;
  if (datosReserva == null) return;
  
  final sede = datosReserva['sede'] as String?;
  final canchaId = datosReserva['cancha_id'] as String?;
  final horario = datosReserva['horario'] as String?;
  final diasSemana = datosReserva['dias_semana'] as List?;
  final fechaInicio = datosReserva['fecha_inicio'] as String?;
  final fechaFin = datosReserva['fecha_fin'] as String?;
  
  debugPrint('🔍 Procesando petición reserva recurrente:');
  debugPrint('   - ID Petición: ${peticion.id}');
  debugPrint('   - Sede petición: $sede');
  debugPrint('   - Sede seleccionada: $_selectedSedeId');
  debugPrint('   - Cancha petición: $canchaId');
  debugPrint('   - Cancha seleccionada: ${_selectedCancha?.id}');
  
  // ✅ VERIFICAR SEDE Y CANCHA PRIMERO
  if (sede != _selectedSedeId || canchaId != _selectedCancha?.id) {
    debugPrint('🚫 Petición recurrente no coincide con sede/cancha actual');
    return;
  }
  
  if (horario == null || diasSemana == null || fechaInicio == null) {
    debugPrint('🚫 Datos incompletos en petición recurrente');
    return;
  }
  
  try {
    final fechaInicioDateTime = DateTime.parse(fechaInicio);
    DateTime? fechaFinDateTime;
    if (fechaFin != null && fechaFin.isNotEmpty) {
      fechaFinDateTime = DateTime.parse(fechaFin);
    }
    
    // ✅ VERIFICAR SI LA FECHA SELECCIONADA ESTÁ EN EL RANGO DE LA RESERVA RECURRENTE
    final fechaSeleccionada = _selectedDate;
    final fechaSeleccionadaStr = DateFormat('yyyy-MM-dd').format(fechaSeleccionada);
    final diaSeleccionado = DateFormat('EEEE', 'es').format(fechaSeleccionada).toLowerCase();
    
    // Convertir días de la semana a formato español si están en inglés
    final diasSemanaFormateados = diasSemana.map((dia) {
      final diaStr = dia.toString().toLowerCase();
      switch (diaStr) {
        case 'monday': case 'lunes': return 'lunes';
        case 'tuesday': case 'martes': return 'martes';
        case 'wednesday': case 'miércoles': case 'miercoles': return 'miércoles';
        case 'thursday': case 'jueves': return 'jueves';
        case 'friday': case 'viernes': return 'viernes';
        case 'saturday': case 'sábado': case 'sabado': return 'sábado';
        case 'sunday': case 'domingo': return 'domingo';
        default: return diaStr;
      }
    }).toList();
    
    // ✅ VERIFICAR CONDICIONES PARA MOSTRAR LA PETICIÓN
    final fechaEnRango = fechaSeleccionada.isAfter(fechaInicioDateTime.subtract(const Duration(days: 1))) &&
                        (fechaFinDateTime == null || fechaSeleccionada.isBefore(fechaFinDateTime.add(const Duration(days: 1))));
    
    final esDiaValido = diasSemanaFormateados.contains(diaSeleccionado);
    
    // Verificar días excluidos
    final diasExcluidos = datosReserva['dias_excluidos'] as List? ?? [];
    final estaExcluida = diasExcluidos.contains(fechaSeleccionadaStr);
    
    debugPrint('   - Fecha en rango: $fechaEnRango');
    debugPrint('   - Día válido: $esDiaValido (día: $diaSeleccionado, días válidos: $diasSemanaFormateados)');
    debugPrint('   - Está excluida: $estaExcluida');
    
    // ✅ SOLO AGREGAR SI TODAS LAS CONDICIONES SE CUMPLEN
    if (fechaEnRango && esDiaValido && !estaExcluida) {
      final horaNormalizada = Horario.normalizarHora(horario);
      peticionesPorHorario[horaNormalizada] = peticion;
      
      debugPrint('✅ Petición reserva recurrente agregada para: $horaNormalizada');
      debugPrint('📅 Fecha: $fechaSeleccionadaStr, Día: $diaSeleccionado');
      debugPrint('📋 Cliente: ${datosReserva['cliente_nombre']}');
    } else {
      debugPrint('🚫 Petición recurrente no aplica para la fecha actual');
    }
    
  } catch (e) {
    debugPrint('❌ Error procesando petición reserva recurrente: $e');
  }
}


  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Reintentar',
            textColor: Colors.white,
            onPressed: () => _selectedCancha != null ? _loadReservas() : _loadCanchas(),
          ),
        ),
      );
    }
  }

  void _toggleView() {
    setState(() {
      _viewGrid = !_viewGrid;
      _selectedHours.clear();
    });
    _fadeController.reset();
    _fadeController.forward();
  }

  Future<void> _selectDate(BuildContext context) async {
  final DateTime? newDate = await showDatePicker(
    context: context,
    initialDate: _selectedDate,
    firstDate: DateTime(2020),
    lastDate: DateTime(2030),
    builder: (context, child) {
      return child != null
          ? Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: _secondaryColor,
                  onPrimary: Colors.white,
                  onSurface: _primaryColor,
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: _secondaryColor),
                ),
              ),
              child: child,
            )
          : const SizedBox.shrink();
    },
  );
  
  if (newDate != null && newDate != _selectedDate && mounted) {
    setState(() {
      _selectedDate = newDate;
      _selectedHours.clear();
      _isLoading = true;
    });
    
    // 🆕 LIMPIAR NOTIFICACIONES AL CAMBIAR FECHA
    _peticionesNotificadas.clear();
    
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      _loadReservas();
      // ✅ NUEVO: REINICIAR STREAM DE PETICIONES CUANDO CAMBIA LA FECHA
      // Se ejecutará automáticamente desde _loadReservas()
    });
  }
}



  void _viewReservaDetails(Reserva reserva) {
    if (!mounted) return;
    
    if (reserva.esReservaRecurrente) {
      _mostrarOpcionesReservaRecurrente(reserva);
    } else {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => DetallesReservaScreen(reserva: reserva),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      ).then((_) {
        if (mounted) {
          _loadReservas();
        }
      });
    }
  }

  void _addReserva() {
    if (_selectedCancha == null || _selectedHours.isEmpty) {
      _showErrorSnackBar('Selecciona una cancha y al menos un horario');
      return;
    }

    final horarios = _selectedHours
        .map((horaStr) => Horario.fromHoraFormateada(horaStr))
        .toList();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AgregarReservaScreen(
          cancha: _selectedCancha!,
          sede: _selectedSedeId,
          horarios: horarios,
          fecha: _selectedDate,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ).then((result) async {
      if (result == true && mounted) {
        setState(() {
          _selectedHours.clear();
        });
        await _loadReservas();
      }
    });
  }

  // ✅ REEMPLAZAR el método _toggleHourSelection (líneas ~530 aprox)
  void _toggleHourSelection(String horaStr) {
  setState(() {
    final horaNormalizada = Horario.normalizarHora(horaStr);
    
    // ✅ VERIFICAR SI HAY UNA PETICIÓN PENDIENTE PARA ESTE HORARIO
    if (_peticionesPorHorario.containsKey(horaNormalizada)) {
      final peticion = _peticionesPorHorario[horaNormalizada]!;
      _mostrarOpcionesPeticionPendiente(horaStr, peticion);
      return;
    }
    
    // ✅ VERIFICAR SI ESTÁ RESERVADO
    if (_reservedMap.containsKey(horaNormalizada)) {
      // ✅ EN MODO SELECTOR, MOSTRAR INFO DE RESERVA EXISTENTE
      if (widget.esModoSelector) {
        final reservaExistente = _reservedMap[horaNormalizada]!;
        _mostrarInfoReservaExistente(reservaExistente);
        return;
      } else {
        // ✅ COMPORTAMIENTO NORMAL: ABRIR DETALLES
        final reserva = _reservedMap[horaNormalizada]!;
        _viewReservaDetails(reserva);
        return;
      }
    }

    // ✅ EN MODO SELECTOR, SOLO PERMITIR UN HORARIO SELECCIONADO
    if (widget.esModoSelector) {
      _selectedHours.clear();
      _selectedHours.add(horaNormalizada);
    } else {
      // ✅ COMPORTAMIENTO NORMAL: MÚLTIPLE SELECCIÓN
      if (_selectedHours.contains(horaNormalizada)) {
        _selectedHours.remove(horaNormalizada);
      } else {
        _selectedHours.add(horaNormalizada);
      }
    }
  });
}


  void _mostrarInfoReservaExistente(Reserva reserva) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Horario Ocupado',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Este horario ya está reservado por:',
              style: GoogleFonts.montserrat(),
            ),
            const SizedBox(height: 8),
            Text(
              'Cliente: ${reserva.nombre}',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
            ),
            Text(
              'Horario: ${reserva.horario.horaFormateada}',
              style: GoogleFonts.montserrat(),
            ),
            if (reserva.esReservaRecurrente)
              Text(
                'Tipo: Reserva Recurrente',
                style: GoogleFonts.montserrat(
                  color: const Color(0xFF1A237E),
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Selecciona otro horario disponible.',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido', style: GoogleFonts.montserrat()),
          ),
        ],
      ),
    );
  }

  void _confirmarSeleccion() {
  if (_selectedCancha == null || _selectedHours.isEmpty) {
    _showErrorSnackBar('Selecciona una cancha y al menos un horario');
    return;
  }

  // ✅ SOLO PERMITIR SELECCIÓN DE UN HORARIO EN MODO SELECTOR
  if (_selectedHours.length > 1) {
    _showErrorSnackBar('Solo puedes seleccionar un horario para editar la reserva');
    return;
  }

  final horarioSeleccionado = _selectedHours.first;
  
  // ✅ VERIFICAR QUE NO SEA LA MISMA RESERVA ORIGINAL
  final reservaEnHorario = _reservedMap[horarioSeleccionado];
  if (reservaEnHorario != null && reservaEnHorario.id == widget.reservaOriginalId) {
    _showErrorSnackBar('No puedes seleccionar el mismo horario actual de la reserva');
    return;
  }

  // ✅ VERIFICAR QUE EL HORARIO ESTÉ DISPONIBLE
  if (_reservedMap.containsKey(horarioSeleccionado)) {
    _showErrorSnackBar('El horario seleccionado no está disponible');
    return;
  }

  // ✅ EN LUGAR DE LLAMAR AL CALLBACK, RETORNAR LOS DATOS AL CERRAR LA PANTALLA
  final resultado = {
    'sede': _selectedSedeId,
    'canchaId': _selectedCancha!.id,
    'horario': horarioSeleccionado,
    'fecha': _selectedDate,
  };

  Navigator.of(context).pop(resultado); // ✅ RETORNAR DATOS EN LUGAR DE CALLBACK
}




  void _mostrarOpcionesReservaRecurrente(Reserva reserva) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _disabledColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Reserva Recurrente',
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${reserva.nombre} - ${reserva.horario.horaFormateada}',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                color: _primaryColor.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.event_busy, color: Colors.orange),
              ),
              title: Text(
                'Excluir este día',
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'Liberar horario solo para ${DateFormat('EEEE d MMMM', 'es').format(_selectedDate)}',
                style: GoogleFonts.montserrat(fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _excluirDiaReservaRecurrente(reserva);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _secondaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.info_outline, color: _secondaryColor),
              ),
              title: Text(
                'Ver detalles completos',
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'Gestionar toda la reserva recurrente',
                style: GoogleFonts.montserrat(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _mostrarDetallesReservaRecurrente(reserva);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _excluirDiaReservaRecurrente(Reserva reserva) async {
    if (reserva.reservaRecurrenteId == null) return;
    
    try {
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      await reservaRecurrenteProvider.excluirDiaReservaRecurrente(
        reserva.reservaRecurrenteId!,
        _selectedDate,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Día excluido de la reserva recurrente. El horario ${reserva.horario.horaFormateada} está ahora disponible para ${DateFormat('EEEE d MMMM', 'es').format(_selectedDate)}.',
              style: GoogleFonts.montserrat(),
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 4),
          ),
        );
        
        _loadReservas();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('NO SE PUDO EXCLIR EL DIA, PIDE ACCESO DE CONTROL TOTAL AL SUPERUSUARIO');
      }
    }
  }

  void _mostrarDetallesReservaRecurrente(Reserva reserva) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Reserva Recurrente',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cliente: ${reserva.nombre}', style: GoogleFonts.montserrat()),
            Text('Teléfono: ${reserva.telefono}', style: GoogleFonts.montserrat()),
            Text('Horario: ${reserva.horario.horaFormateada}', style: GoogleFonts.montserrat()),
            Text('Cancha: ${reserva.cancha.nombre}', style: GoogleFonts.montserrat()),
            const SizedBox(height: 8),
            Text(
              'Esta es una reserva recurrente activa.',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: _primaryColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar', style: GoogleFonts.montserrat()),
          ),
        ],
      ),
    );
  }

  void _mostrarReservasRecurrentes() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      
      await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
      
      if (mounted) Navigator.pop(context);
      
      final todasLasReservas = reservaRecurrenteProvider.reservasRecurrentes
          .where((r) => r.sede == _selectedSedeId)
          .toList();

      final reservasActivas = todasLasReservas.where((r) => r.estado == EstadoRecurrencia.activa).toList();
      final reservasCanceladas = todasLasReservas.where((r) => r.estado == EstadoRecurrencia.cancelada).toList();

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _disabledColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.repeat_rounded, color: _secondaryColor),
                      const SizedBox(width: 12),
                      Text(
                        'Reservas Recurrentes',
                        style: GoogleFonts.montserrat(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor,
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${reservasActivas.length} activas',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (reservasCanceladas.isNotEmpty)
                            Text(
                              '${reservasCanceladas.length} canceladas',
                              style: GoogleFonts.montserrat(
                                fontSize: 12,
                                color: Colors.red.withOpacity(0.7),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: todasLasReservas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.repeat, size: 64, color: _disabledColor),
                              const SizedBox(height: 16),
                              Text(
                                'No hay reservas recurrentes',
                                style: GoogleFonts.montserrat(
                                  color: _primaryColor.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: todasLasReservas.length,
                          itemBuilder: (context, index) {
                            final reserva = todasLasReservas[index];
                            return _buildReservaRecurrenteCard(reserva, setModalState);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        _showErrorSnackBar('Error cargando reservas recurrentes: $e');
      }
    }
  }

  Widget _buildReservaRecurrenteCard(ReservaRecurrente reserva, [StateSetter? setModalState]) {
    final bool isActive = reserva.estado == EstadoRecurrencia.activa;
    final Color cardColor = isActive ? const Color(0xFF1A237E) : Colors.grey;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cardColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isActive ? Icons.repeat_rounded : Icons.cancel_outlined,
            color: Colors.white,
          ),
        ),
        title: Text(
          reserva.clienteNombre,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Horario: ${reserva.horario}',
              style: GoogleFonts.montserrat(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
            Text(
              'Días: ${reserva.diasSemana.join(", ")}',
              style: GoogleFonts.montserrat(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
            Text(
              'Estado: ${reserva.estado.name.toUpperCase()}',
              style: GoogleFonts.montserrat(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Precio: COP ${reserva.montoTotal.toInt()}${reserva.precioPersonalizado ? " (Personalizado)" : ""}',
              style: GoogleFonts.montserrat(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: isActive ? PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          color: _backgroundColor,
          onSelected: (value) async {
            if (value == 'eliminar') {
              await _confirmarEliminarReservaRecurrente(reserva);
              
              if (setModalState != null && mounted) {
                try {
                  final provider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
                  await provider.fetchReservasRecurrentes(sede: _selectedSedeId);
                  setModalState(() {});
                } catch (e) {
                  debugPrint('Error actualizando modal: $e');
                }
              }
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'eliminar',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    'Cancelar Futuras',
                    style: GoogleFonts.montserrat(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ) : null,
      ),
    );
  }

  Future<void> _confirmarEliminarReservaRecurrente(ReservaRecurrente reserva) async {
  final ahora = DateTime.now();
  final diaSemanaHoy = DateFormat('EEEE', 'es').format(ahora).toLowerCase();
  final esHoyDiaValido = reserva.diasSemana.contains(diaSemanaHoy);
  final fechaHoyStr = DateFormat('yyyy-MM-dd').format(ahora);
  final yaEstaExcluidoHoy = reserva.diasExcluidos.contains(fechaHoyStr);
  
  String mensajeHoy = '';
  bool mostrarAdvertenciaHoy = false;
  
  if (esHoyDiaValido && !yaEstaExcluidoHoy) {
    try {
      final horarioReserva = Horario.fromHoraFormateada(reserva.horario);
      final horaReservaHoy = DateTime(
        ahora.year, ahora.month, ahora.day,
        horarioReserva.hora.hour, horarioReserva.hora.minute
      );
      
      if (ahora.isBefore(horaReservaHoy)) {
        mensajeHoy = '\n⚠️ IMPORTANTE: Como aún no son las ${reserva.horario}, la reserva de HOY también será cancelada.';
        mostrarAdvertenciaHoy = true;
      } else {
        mensajeHoy = '\n✅ La reserva de hoy (${reserva.horario}) se mantendrá en el inventario porque ya pasó la hora.';
      }
    } catch (e) {
      mensajeHoy = '\n✅ La reserva de hoy se mantendrá en el inventario.';
    }
  } else {
    mensajeHoy = '\n📅 Hoy no hay reserva programada para este horario.';
  }

  final confirmado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        'Cancelar Reservas Futuras',
        style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Estás seguro de que deseas cancelar todas las reservas futuras de ${reserva.clienteNombre}?',
            style: GoogleFonts.montserrat(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: mostrarAdvertenciaHoy ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              mensajeHoy,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: mostrarAdvertenciaHoy ? Colors.orange.shade700 : Colors.blue.shade700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '🗓️ Todas las reservas desde mañana serán canceladas.',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar', style: GoogleFonts.montserrat()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text('Cancelar Futuras', style: GoogleFonts.montserrat()),
        ),
      ],
    ),
  );

  if (confirmado == true) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final provider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      
      await provider.cancelarReservasFuturas(reserva.id);

      // 🔥 AGREGAR AUDITORÍA AQUÍ - Después de cancelar exitosamente
      try {
        // Preparar datos para la auditoría
        final datosReservaCancelada = {
          'id': reserva.id,
          'nombre': reserva.clienteNombre,
          'telefono': reserva.clienteTelefono,
          'correo': reserva.clienteEmail,
          'fecha_inicio': DateFormat('yyyy-MM-dd').format(reserva.fechaInicio),
          'fecha_fin': reserva.fechaFin != null ? DateFormat('yyyy-MM-dd').format(reserva.fechaFin!) : null,
          'horario': reserva.horario,
          'cancha_nombre': reserva.canchaId, // Si tienes el nombre de la cancha, úsalo
          'cancha_id': reserva.canchaId,
          'sede': reserva.sede,
          'montoTotal': reserva.montoTotal,
          'montoPagado': reserva.montoPagado,
          'estado': reserva.estado.toString(),
          'dias_semana': reserva.diasSemana,
          'tipo_recurrencia': reserva.tipoRecurrencia.toString(),
          'precio_personalizado': reserva.precioPersonalizado ?? false,
          'precio_original': reserva.precioOriginal,
          'descuento_aplicado': reserva.descuentoAplicado,
        };

        // Calcular impacto de la cancelación
        final diasFuturosAfectados = _calcularDiasFuturosAfectados(reserva, ahora);
        final impactoFinanciero = _calcularImpactoFinancieroCancelacion(reserva, diasFuturosAfectados);
        
        String motivoCancelacion = 'Cancelación de reservas futuras por solicitud del usuario';
        if (mostrarAdvertenciaHoy) {
          motivoCancelacion += ' - Incluye reserva del día actual';
        }

        await ReservaAuditUtils.auditarEliminacionReserva(
          reservaId: reserva.id,
          datosReserva: datosReservaCancelada,
          motivo: motivoCancelacion,
        );

        // También registrar acción específica para reservas recurrentes
        await AuditProvider.registrarAccion(
          accion: 'cancelar_reservas_futuras_recurrente',
          entidad: 'reserva_recurrente',
          entidadId: reserva.id,
          datosAntiguos: datosReservaCancelada,
          metadatos: {
            'cliente': reserva.clienteNombre,
            'horario': reserva.horario,
            'sede': reserva.sede,
            'dias_semana': reserva.diasSemana,
            'fecha_cancelacion': DateFormat('yyyy-MM-dd HH:mm').format(ahora),
            'incluye_reserva_hoy': mostrarAdvertenciaHoy,
            'dias_futuros_afectados': diasFuturosAfectados,
            'impacto_financiero_estimado': impactoFinanciero,
            'motivo_cancelacion': motivoCancelacion,
            'precio_personalizado': reserva.precioPersonalizado ?? false,
            'descuento_aplicado': reserva.descuentoAplicado ?? 0,
          },
          descripcion: _generarDescripcionCancelacionRecurrente(
            reserva, 
          ),
        );
      } catch (e) {
        debugPrint('⚠️ Error en auditoría de cancelación de reserva recurrente: $e');
        // No interrumpir el flujo si la auditoría falla
      }

      if (mounted) Navigator.pop(context);
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
        String mensajeExito = 'Reservas futuras canceladas correctamente.';
        if (mostrarAdvertenciaHoy) {
          mensajeExito += ' La reserva de hoy también fue cancelada porque aún no era la hora.';
        } else if (esHoyDiaValido && !yaEstaExcluidoHoy) {
          mensajeExito += ' La reserva de hoy se mantiene en el inventario.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mensajeExito,
              style: GoogleFonts.montserrat(),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 5),
          ),
        );
        
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await _loadReservas();
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
        _showErrorSnackBar('NO SE PUDIERON CANCELAR LAS RESERVAS FUTURAS, PIDE ACCESO DE CONTROL TOTAL AL SUPERUSUARIO');
      }
    }
  }
}

// 🔥 AGREGAR ESTAS FUNCIONES AUXILIARES AL FINAL DE TU CLASE

/// Calcular cuántos días futuros serán afectados por la cancelación
int _calcularDiasFuturosAfectados(ReservaRecurrente reserva, DateTime ahora) {
  try {
    final fechaFin = reserva.fechaFin ?? DateTime.now().add(const Duration(days: 365)); // Si no hay fecha fin, asumir 1 año
    final diasHastaFin = fechaFin.difference(ahora).inDays;
    
    if (diasHastaFin <= 0) return 0;
    
    // Calcular aproximadamente cuántas veces ocurre la reserva por semana
    final diasSemanaActivos = reserva.diasSemana.length;
    final semanasHastaFin = (diasHastaFin / 7).ceil();
    
    return diasSemanaActivos * semanasHastaFin;
  } catch (e) {
    return 0;
  }
}

/// Calcular impacto financiero estimado de la cancelación
Map<String, dynamic> _calcularImpactoFinancieroCancelacion(ReservaRecurrente reserva, int diasAfectados) {
  final montoUnitario = reserva.montoTotal;
  final impactoTotal = montoUnitario * diasAfectados;
  
  bool esImpactoAlto = false;
  final alertas = <String>[];
  
  if (impactoTotal >= 500000) {
    alertas.add('Impacto financiero muy alto');
    esImpactoAlto = true;
  } else if (impactoTotal >= 200000) {
    alertas.add('Impacto financiero significativo');
    esImpactoAlto = true;
  } else if (diasAfectados >= 10) {
    alertas.add('Múltiples reservas futuras canceladas');
  }
  
  return {
    'dias_afectados': diasAfectados,
    'monto_unitario': montoUnitario,
    'impacto_total_estimado': impactoTotal,
    'es_impacto_alto': esImpactoAlto,
    'alertas': alertas,
  };
}

/// Generar descripción para la auditoría de cancelación
String _generarDescripcionCancelacionRecurrente(
  ReservaRecurrente reserva, 
) {
  final formatter = NumberFormat('#,##0', 'es_CO');
  final cliente = reserva.clienteNombre;
  
  String descripcion = '';
  
  
  descripcion += 'Reservas futuras de $cliente canceladas';
  
  
  descripcion += ' - ${reserva.diasSemana.length} día(s)/semana';
  
  
  return descripcion;
}

  AppBar buildAppBar() {
  return AppBar(
    title: Text(
      widget.esModoSelector ? 'Seleccionar Nueva Reserva' : 'Reservas',
      style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
    ),
    automaticallyImplyLeading: false,
    backgroundColor: _backgroundColor,
    elevation: 0,
    foregroundColor: _primaryColor,
    actions: [
      // ✅ MOSTRAR BOTÓN CONFIRMAR EN MODO SELECTOR (INCLUSO SIN SELECCIÓN)
      if (widget.esModoSelector) ...[
        Container(
          margin: EdgeInsets.only(right: 16),
          child: ElevatedButton.icon(
            onPressed: _selectedHours.isNotEmpty ? _confirmarSeleccion : null,
            icon: Icon(Icons.check, size: 18),
            label: Text('Confirmar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedHours.isNotEmpty ? _secondaryColor : _disabledColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ],
      // ✅ BOTONES NORMALES SOLO CUANDO NO ES MODO SELECTOR
      if (!widget.esModoSelector) ...[
        Tooltip(
          message: 'Reservas Recurrentes',
          child: Container(
            margin: EdgeInsets.only(right: 4),
            child: IconButton(
              icon: Icon(Icons.repeat_rounded, color: _secondaryColor),
              onPressed: _mostrarReservasRecurrentes,
            ),
          ),
        ),
        Tooltip(
          message: _viewGrid ? 'Vista en Lista' : 'Vista en Calendario',
          child: Container(
            margin: EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Icon(
                _viewGrid ? Icons.view_list_rounded : Icons.calendar_view_month_rounded,
                color: _secondaryColor,
              ),
              onPressed: _toggleView,
            ),
          ),
        ),
      ],
    ],
  );
}


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1200;
        final crossAxisCount = isMobile ? 3 : isTablet ? 4 : 6;
        final childAspectRatio = isMobile ? 1.5 : isTablet ? 1.8 : 1.8;

        return Scaffold(
          appBar: buildAppBar(),
          floatingActionButton: widget.esModoSelector 
            ? null
            : _selectedHours.isNotEmpty
                ? FloatingActionButton(
                    onPressed: _addReserva,
                    backgroundColor: _secondaryColor,
                    child: const Icon(Icons.check, color: Colors.white),
                    tooltip: 'Confirmar selección',
                    mini: isMobile,
                  )
                : null,
          body: Container(
            color: _backgroundColor,
            child: _isLoading
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
                          'Cargando...',
                          style: GoogleFonts.montserrat(
                            color: const Color.fromRGBO(60, 64, 67, 0.6),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.all(isMobile ? 8.0 : 16.0),
                    child: Column(
                      children: [
                        Animate(
                          effects: const [
                            FadeEffect(
                              duration: Duration(milliseconds: 600),
                              curve: Curves.easeOutQuad,
                            ),
                            SlideEffect(
                              begin: Offset(0, -0.2),
                              end: Offset.zero,
                              duration: Duration(milliseconds: 600),
                              curve: Curves.easeOutQuad,
                            ),
                          ],
                          child: _buildSedeYCanchaSelectors(isMobile),
                        ),
                        const SizedBox(height: 16),
                        Animate(
                          effects: const [
                            FadeEffect(
                              duration: Duration(milliseconds: 600),
                              delay: Duration(milliseconds: 200),
                              curve: Curves.easeOutQuad,
                            ),
                            SlideEffect(
                              begin: Offset(0, -0.2),
                              end: Offset.zero,
                              duration: Duration(milliseconds: 600),
                              delay: Duration(milliseconds: 200),
                              curve: Curves.easeOutQuad,
                            ),
                          ],
                          child: _buildFechaSelector(isMobile),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _selectedCancha == null
                              ? Center(
                                  child: Text(
                                    'Selecciona una cancha para ver los horarios',
                                    style: GoogleFonts.montserrat(color: _primaryColor),
                                  ),
                                )
                              : AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  switchInCurve: Curves.easeInOut,
                                  switchOutCurve: Curves.easeInOut,
                                  transitionBuilder: (Widget child, Animation<double> animation) {
                                    return FadeTransition(opacity: animation, child: child);
                                  },
                                  child: _viewGrid
                                      ? _buildGridView(crossAxisCount, childAspectRatio)
                                      : _buildListView(isMobile),
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSedeYCanchaSelectors(bool isMobile) {
    final sedeProvider = Provider.of<SedeProvider>(context);
    final canchaProvider = Provider.of<CanchaProvider>(context);

    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 8.0 : 16.0),
        child: isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdown('Sede', _selectedSedeId, sedeProvider.sedes
                      .map((sede) => DropdownMenuItem<String>(
                            value: sede['id'] as String,
                            child: Text(sede['nombre'] as String),
                          ))
                      .toList(), 
                      (newSedeId) async {
  if (newSedeId != null && newSedeId != _selectedSedeId) {
    final selectedSede = sedeProvider.sedes.firstWhere(
        (sede) => sede['id'] == newSedeId,
        orElse: () => {'nombre': ''});
    
    setState(() {
      _selectedSedeId = newSedeId;
      _selectedSedeNombre = selectedSede['nombre'] as String;
      _selectedCancha = null;
      _selectedHours.clear();
      _isLoading = true;
    });
    
    // 🆕 LIMPIAR NOTIFICACIONES AL CAMBIAR SEDE
    _peticionesNotificadas.clear();
    
    sedeProvider.setSede(_selectedSedeNombre);
    
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
    
    await _loadCanchas();
    // ✅ Las peticiones se reiniciarán automáticamente desde _loadCanchas() -> _loadReservas()
  }

                  }, isMobile),
                  const SizedBox(height: 16),
                  _buildDropdown('Cancha', _selectedCancha, _canchas
                      .where((cancha) => cancha.sedeId == _selectedSedeId)
                      .map((cancha) => DropdownMenuItem<Cancha>(
                            value: cancha,
                            child: Text(cancha.nombre),
                          ))
                      .toList(), (newCancha) {
  if (newCancha != null) {
    setState(() {
      _selectedCancha = newCancha;
      _selectedHours.clear();
      _isLoading = true;
    });
    
    // 🆕 LIMPIAR NOTIFICACIONES AL CAMBIAR CANCHA
    _peticionesNotificadas.clear();
    
    _loadReservas();
  }
}, isMobile, canchaProvider.isLoading),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: _buildDropdown('Sede', _selectedSedeId, sedeProvider.sedes
                        .map((sede) => DropdownMenuItem<String>(
                              value: sede['id'] as String,
                              child: Text(sede['nombre'] as String),
                            ))
                        .toList(), 
                        (newSedeId) async {
  if (newSedeId != null && newSedeId != _selectedSedeId) {
    final selectedSede = sedeProvider.sedes.firstWhere(
        (sede) => sede['id'] == newSedeId,
        orElse: () => {'nombre': ''});
    
    setState(() {
      _selectedSedeId = newSedeId;
      _selectedSedeNombre = selectedSede['nombre'] as String;
      _selectedCancha = null;
      _selectedHours.clear();
      _isLoading = true;
    });
    
    // 🆕 LIMPIAR NOTIFICACIONES AL CAMBIAR SEDE
    _peticionesNotificadas.clear();
    
    sedeProvider.setSede(_selectedSedeNombre);
    
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
    
    await _loadCanchas();
    // ✅ Las peticiones se reiniciarán automáticamente desde _loadCanchas() -> _loadReservas()
  }
                    }, isMobile),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDropdown('Cancha', _selectedCancha, _canchas
                        .where((cancha) => cancha.sedeId == _selectedSedeId)
                        .map((cancha) => DropdownMenuItem<Cancha>(
                              value: cancha,
                              child: Text(cancha.nombre),
                            ))
                        .toList(), 
                        (newCancha) {
  if (newCancha != null) {
    setState(() {
      _selectedCancha = newCancha;
      _selectedHours.clear();
      _isLoading = true;
    });
    
    // 🆕 LIMPIAR NOTIFICACIONES AL CAMBIAR CANCHA
    _peticionesNotificadas.clear();
    
    _loadReservas();
  }
}, isMobile, canchaProvider.isLoading),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDropdown<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    Function(T?) onChanged,
    bool isMobile, [
    bool isLoading = false,
  ]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: isMobile ? 12 : 14,
            fontWeight: FontWeight.w500,
            color: const Color.fromRGBO(60, 64, 67, 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _disabledColor),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: isLoading ? null : value,
              hint: Text(
                isLoading
                    ? 'Cargando...'
                    : items.isEmpty
                        ? 'No hay $label disponibles'
                        : 'Selecciona $label',
                style: GoogleFonts.montserrat(
                  color: const Color.fromRGBO(60, 64, 67, 0.5),
                ),
              ),
              icon: Icon(Icons.keyboard_arrow_down, color: _secondaryColor),
              isExpanded: true,
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontWeight: FontWeight.w500,
                fontSize: isMobile ? 14 : 16,
              ),
              items: items,
              onChanged: isLoading ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFechaSelector(bool isMobile) {
    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _selectDate(context),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 8.0 : 16.0),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: _secondaryColor, size: isMobile ? 20 : 24),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fecha Seleccionada',
                    style: GoogleFonts.montserrat(
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.w500,
                      color: const Color.fromRGBO(60, 64, 67, 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE d MMMM, yyyy', 'es').format(_selectedDate),
                    style: GoogleFonts.montserrat(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: isMobile ? 14 : 16,
                color: const Color.fromRGBO(60, 64, 67, 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridView(int crossAxisCount, double childAspectRatio) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Text(
            'Horarios Disponibles${_selectedHours.isNotEmpty ? ' (${_selectedHours.length} seleccionados)' : ''}',
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _primaryColor,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: childAspectRatio,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _hours.length,
            itemBuilder: (context, index) {
              final horaStr = _hours[index];
              final horaNormalizada = Horario.normalizarHora(horaStr);
              final isReserved = _reservedMap.containsKey(horaNormalizada);
              final isSelected = _selectedHours.contains(horaNormalizada);
              final reserva = isReserved ? _reservedMap[horaNormalizada] : null;
              
              // ✅ VERIFICAR SI HAY PETICIÓN PENDIENTE
              final tienePeticionPendiente = _peticionesPorHorario.containsKey(horaNormalizada);
              final peticion = tienePeticionPendiente ? _peticionesPorHorario[horaNormalizada] : null;

              Color textColor;
              Color shadowColor;
              Color backgroundColor;
              IconData statusIcon;
              String statusText;

              // ✅ PRIORIZAR PETICIONES PENDIENTES
              if (tienePeticionPendiente) {
                textColor = Colors.orange;
                shadowColor = Colors.orange.withOpacity(0.3);
                backgroundColor = Colors.orange.withOpacity(0.1);
                statusIcon = Icons.hourglass_top;
                statusText = 'Pendiente';
              } else if (isReserved) {
                final bool isRecurrent = reserva?.esReservaRecurrente ?? false;
                
                if (isRecurrent) {
                  textColor = const Color(0xFF1A237E);
                  shadowColor = const Color(0xFF1A237E).withOpacity(0.2);
                  backgroundColor = const Color(0xFF1A237E).withOpacity(0.1);
                  statusIcon = Icons.repeat_rounded;
                  statusText = 'Recurrente';
                } else {
                  textColor = _reservedColor;
                  shadowColor = const Color.fromRGBO(76, 175, 80, 0.15);
                  backgroundColor = _reservedColor.withOpacity(0.1);
                  statusIcon = Icons.event_busy;
                  statusText = 'Reservado';
                }
              } else if (isSelected) {
                textColor = _selectedHourColor;
                shadowColor = const Color.fromRGBO(255, 202, 40, 0.2);
                backgroundColor = _selectedHourColor.withOpacity(0.1);
                statusIcon = Icons.check_circle;
                statusText = 'Seleccionado';
              } else {
                textColor = _primaryColor;
                shadowColor = const Color.fromRGBO(60, 64, 67, 0.1);
                backgroundColor = Colors.white;
                statusIcon = Icons.event_available;
                statusText = 'Disponible';
              }

              final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
              double precio = _selectedCancha != null
                  ? (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] is Map<String, dynamic>
                      ? ((_selectedCancha!.preciosPorHorario[day]![horaNormalizada] as Map<String, dynamic>)['precio'] as num?)?.toDouble() ??
                          _selectedCancha!.precio
                      : (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] as num?)?.toDouble() ??
                          _selectedCancha!.precio)
                  : 0.0;

              // ✅ OBTENER PRECIO DE PETICIÓN PENDIENTE
              if (tienePeticionPendiente && peticion != null) {
                precio = peticion.valoresNuevos['precio_aplicado'] as double? ?? precio;
              } else if (isReserved && reserva != null) {
                precio = reserva.montoTotal;
              }

              return Animate(
                effects: [
                  FadeEffect(
                    delay: Duration(milliseconds: 50 * (index % 10)),
                    duration: const Duration(milliseconds: 400),
                  ),
                  ScaleEffect(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1.0, 1.0),
                    delay: Duration(milliseconds: 50 * (index % 10)),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutQuad,
                  ),
                ],
                child: Hero(
                  tag: 'hora_grid_$horaNormalizada',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _toggleHourSelection(horaStr),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: tienePeticionPendiente
                                ? Colors.orange
                                : isReserved
                                    ? (reserva?.confirmada ?? true ? _reservedColor : Colors.red)
                                    : isSelected
                                        ? _selectedHourColor
                                        : const Color.fromRGBO(60, 64, 67, 0.3),
                            width: tienePeticionPendiente ? 2.0 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              blurRadius: tienePeticionPendiente ? 12 : 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              horaStr,
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 12, color: textColor),
                                const SizedBox(width: 4),
                                Text(
                                  statusText,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'COP ${precio.toInt()}${tienePeticionPendiente ? ' (Desc.)' : ''}',
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                            // ✅ INDICADOR ADICIONAL PARA PETICIONES
                            if (tienePeticionPendiente) ...[
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'ESPERANDO',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListView(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Text(
            'Horarios Disponibles${_selectedHours.isNotEmpty ? ' (${_selectedHours.length} seleccionados)' : ''}',
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _primaryColor,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _hours.length,
            itemBuilder: (context, index) {
              final horaStr = _hours[index];
              final horaNormalizada = Horario.normalizarHora(horaStr);
              final isReserved = _reservedMap.containsKey(horaNormalizada);
              final isSelected = _selectedHours.contains(horaNormalizada);
              final reserva = isReserved ? _reservedMap[horaNormalizada] : null;
              
              // ✅ VERIFICAR SI HAY PETICIÓN PENDIENTE
              final tienePeticionPendiente = _peticionesPorHorario.containsKey(horaNormalizada);
              final peticion = tienePeticionPendiente ? _peticionesPorHorario[horaNormalizada] : null;

              Color textColor;
              Color shadowColor;
              Color backgroundColor;
              Color leadingBackgroundColor;
              IconData statusIcon;
              String statusText;
              String subtitleText;

              // ✅ PRIORIZAR PETICIONES PENDIENTES
              if (tienePeticionPendiente) {
                textColor = Colors.orange;
                shadowColor = Colors.orange.withOpacity(0.3);
                backgroundColor = Colors.orange.withOpacity(0.05);
                leadingBackgroundColor = Colors.orange.withOpacity(0.2);
                statusIcon = Icons.hourglass_top;
                statusText = 'Pendiente Confirmación';
                
                final datosReserva = peticion!.valoresNuevos['datos_reserva'] as Map<String, dynamic>? ?? {};
                subtitleText = '${datosReserva['cliente_nombre'] ?? 'Cliente'} - Esperando aprobación';
              } else if (isReserved) {
                final bool isRecurrent = reserva?.esReservaRecurrente ?? false;
                
                if (isRecurrent) {
                  textColor = const Color(0xFF1A237E);
                  shadowColor = const Color(0xFF1A237E).withOpacity(0.2);
                  backgroundColor = const Color(0xFF1A237E).withOpacity(0.05);
                  leadingBackgroundColor = const Color(0xFF1A237E).withOpacity(0.2);
                  statusIcon = Icons.repeat_rounded;
                  statusText = 'Recurrente';
                  subtitleText = 'Reservado por: ${reserva?.nombre ?? "Cliente"}';
                } else {
                  textColor = _reservedColor;
                  shadowColor = const Color.fromRGBO(76, 175, 80, 0.15);
                  backgroundColor = _reservedColor.withOpacity(0.05);
                  leadingBackgroundColor = const Color.fromRGBO(76, 175, 80, 0.2);
                  statusIcon = Icons.event_busy;
                  statusText = 'Reservado';
                  subtitleText = 'Reservado por: ${reserva?.nombre ?? "Cliente"}';
                }
              } else if (isSelected) {
                textColor = _selectedHourColor;
                shadowColor = const Color.fromRGBO(255, 202, 40, 0.2);
                backgroundColor = _selectedHourColor.withOpacity(0.05);
                leadingBackgroundColor = _selectedHourColor;
                statusIcon = Icons.check_circle;
                statusText = 'Seleccionado';
                subtitleText = 'Seleccionado para reservar';
              } else {
                textColor = _primaryColor;
                shadowColor = const Color.fromRGBO(60, 64, 67, 0.1);
                backgroundColor = Colors.white;
                leadingBackgroundColor = _availableColor;
                statusIcon = Icons.event_available;
                statusText = 'Disponible';
                subtitleText = 'Disponible para reservar';
              }

              final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
              double precio = _selectedCancha != null
                  ? (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] is Map<String, dynamic>
                      ? ((_selectedCancha!.preciosPorHorario[day]![horaNormalizada] as Map<String, dynamic>)['precio'] as num?)?.toDouble() ??
                          _selectedCancha!.precio
                      : (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] as num?)?.toDouble() ??
                          _selectedCancha!.precio)
                  : 0.0;

              // ✅ OBTENER PRECIO DE PETICIÓN PENDIENTE
              if (tienePeticionPendiente && peticion != null) {
                precio = peticion.valoresNuevos['precio_aplicado'] as double? ?? precio;
                subtitleText += ' - COP ${precio.toInt()} (Con descuento)';
              } else {
                if (isReserved && reserva != null) {
                  precio = reserva.montoTotal;
                }
                subtitleText += ' - COP ${precio.toInt()}';
              }

              return Animate(
                effects: [
                  FadeEffect(
                    delay: Duration(milliseconds: 50 * (index % 10)),
                    duration: const Duration(milliseconds: 400),
                  ),
                  SlideEffect(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                    delay: Duration(milliseconds: 50 * (index % 10)),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutQuad,
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Hero(
                    tag: 'hora_list_$horaNormalizada',
                    child: Material(
                      color: Colors.transparent,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: tienePeticionPendiente
                                ? Colors.orange
                                : isReserved
                                    ? (reserva?.confirmada ?? true ? _reservedColor : Colors.red)
                                    : isSelected
                                        ? _selectedHourColor
                                        : const Color.fromRGBO(60, 64, 67, 0.3),
                            width: tienePeticionPendiente ? 2.0 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              blurRadius: tienePeticionPendiente ? 10 : 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          onTap: () => _toggleHourSelection(horaStr),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 8.0 : 16.0,
                              vertical: isMobile ? 4.0 : 8.0),
                          leading: Container(
                            width: isMobile ? 36 : 48,
                            height: isMobile ? 36 : 48,
                            decoration: BoxDecoration(
                              color: leadingBackgroundColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Icon(statusIcon, 
                                  size: isMobile ? 12 : 14, 
                                  color: tienePeticionPendiente ? Colors.orange : textColor),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                horaStr,
                                style: GoogleFonts.montserrat(
                                  fontSize: isMobile ? 14 : 16,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              // ✅ BADGE PARA PETICIONES PENDIENTES
                              if (tienePeticionPendiente) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'PENDIENTE',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            subtitleText,
                            style: GoogleFonts.montserrat(
                              fontSize: isMobile ? 12 : 14,
                              color: Color.fromRGBO(
                                (textColor.r * 255.0).round() & 0xff,
                                (textColor.g * 255.0).round() & 0xff,
                                (textColor.b * 255.0).round() & 0xff,
                                0.8,
                              ),
                            ),
                          ),
                          trailing: tienePeticionPendiente
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      color: Colors.orange,
                                      size: isMobile ? 16 : 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Ver',
                                      style: GoogleFonts.montserrat(
                                        fontSize: 12,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                )
                              : isReserved
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.edit, color: _secondaryColor, size: isMobile ? 16 : 20),
                                          onPressed: () => _viewReservaDetails(reserva!),
                                          tooltip: 'Editar',
                                        ),
                                      ],
                                    )
                                  : Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: isMobile ? 12 : 16,
                                      color: Color.fromRGBO(
                                        (textColor.r * 255.0).round() & 0xff,
                                        (textColor.g * 255.0).round() & 0xff,
                                        (textColor.b * 255.0).round() & 0xff,
                                        0.5,
                                      ),
                                    ),
                          titleAlignment: ListTileTitleAlignment.center,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _mostrarOpcionesPeticionPendiente(String horario, Peticion peticion) {
  final tipoPeticion = peticion.valoresNuevos['tipo'] as String?;
  final esReservaRecurrente = tipoPeticion == 'nueva_reserva_recurrente_precio_personalizado';
  
  String clienteNombre = 'Cliente';
  String detalleAdicional = '';
  
  if (esReservaRecurrente) {
    final datosReserva = peticion.valoresNuevos['datos_reserva_recurrente'] as Map<String, dynamic>? ?? {};
    clienteNombre = datosReserva['cliente_nombre'] as String? ?? 'Cliente';
    final diasSemana = datosReserva['dias_semana'] as List? ?? [];
    detalleAdicional = '\nReserva recurrente: ${diasSemana.join(', ')}';
  } else {
    final datosReserva = peticion.valoresNuevos['datos_reserva'] as Map<String, dynamic>? ?? {};
    clienteNombre = datosReserva['cliente_nombre'] as String? ?? 'Cliente';
    final horarios = datosReserva['horarios'] as List? ?? [];
    if (horarios.length > 1) {
      detalleAdicional = '\nReserva múltiple: ${horarios.length} horarios';
    }
  }
  
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _disabledColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Icon(
            esReservaRecurrente ? Icons.repeat_on : Icons.hourglass_top,
            size: 48,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          Text(
            esReservaRecurrente ? 'Petición Reserva Recurrente' : 'Petición Pendiente',
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$clienteNombre - $horario',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              color: _primaryColor.withOpacity(0.7),
            ),
          ),
          if (detalleAdicional.isNotEmpty)
            Text(
              detalleAdicional,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: _primaryColor.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              esReservaRecurrente 
                  ? 'Esta reserva recurrente está esperando confirmación del superadministrador.'
                  : 'Esta reserva está esperando confirmación del superadministrador.',
              style: GoogleFonts.montserrat(
                color: Colors.orange.shade700,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cancel_outlined, color: Colors.red),
            ),
            title: Text(
              'Cancelar Petición',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w500, color: Colors.red),
            ),
            subtitle: Text(
              'Eliminar esta solicitud de reserva',
              style: GoogleFonts.montserrat(fontSize: 12),
            ),
            onTap: () async {
              Navigator.pop(context);
              await _cancelarPeticion(peticion.id);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}



  // ✅ REEMPLAZAR el método _cancelarPeticion completo (líneas ~1100 aprox)
  Future<void> _cancelarPeticion(String peticionId) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Cancelar Petición',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        content: Text(
          '¿Estás seguro de que deseas cancelar esta petición de reserva?',
          style: GoogleFonts.montserrat(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No', style: GoogleFonts.montserrat()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Sí, Cancelar', style: GoogleFonts.montserrat()),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // ✅ ACTUALIZACIÓN CORRECTA DE ESTADO
        await FirebaseFirestore.instance
            .collection('peticiones')
            .doc(peticionId)
            .update({
          'estado': 'cancelada',
          'fecha_respuesta': Timestamp.now(),
          'respuesta_admin': 'Cancelada por el administrador',
          'admin_id': 'admin', // ✅ Usar el ID del admin actual si está disponible
        });

        if (mounted) Navigator.pop(context);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Petición cancelada correctamente',
                style: GoogleFonts.montserrat(),
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
            ),
          );
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          _showErrorSnackBar('Error al cancelar petición: $e');
        }
      }
    }
  }

  void _mostrarNotificacionPeticionActualizada(String mensaje) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.notifications_active, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mensaje,
                  style: GoogleFonts.montserrat(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: _secondaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }
}