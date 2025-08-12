import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/cancha.dart';
import '../models/horario.dart';
import '../providers/sede_provider.dart';
import '../providers/cancha_provider.dart';
import '../models/reserva_recurrente.dart';
import '../providers/reserva_recurrente_provider.dart';
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
    _debounceTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadHorarios();
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

        // ✅ CARGAR RESERVAS NORMALES (INCLUYENDO NO CONFIRMADAS)
        final snapshotKey = '$_selectedDate-${widget.cancha.id}-$sedeId';
        QuerySnapshot? reservasSnapshot = _reservasSnapshots[snapshotKey];

        if (reservasSnapshot == null) {
          debugPrint('🔍 Consultando reservas normales...');
          reservasSnapshot = await FirebaseFirestore.instance
              .collection('reservas')
              .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate))
              .where('cancha_id', isEqualTo: widget.cancha.id)
              .where('sede', isEqualTo: sedeId)
              // ✅ REMOVIDO: .where('confirmada', isEqualTo: true) 
              // Para incluir tanto confirmadas como no confirmadas
              .get();
          _reservasSnapshots[snapshotKey] = reservasSnapshot;
          debugPrint('📋 Reservas normales encontradas: ${reservasSnapshot.docs.length}');
        }

        // Generar horarios base
        final nuevosHorarios = await Horario.generarHorarios(
          fecha: _selectedDate,
          canchaId: widget.cancha.id,
          sede: sedeId,
          reservasSnapshot: reservasSnapshot,
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
                  'clienteEmail': reservaRecurrente.clienteEmail,
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
      _debounceTimer = Timer(const Duration(milliseconds: 300), _loadHorarios);
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
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF424242)),
                onPressed: () {
                  if (mounted) Navigator.pop(context);
                },
              ),
            ),
            title: FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                widget.cancha.nombre,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF424242),
                ),
              ),
            ),
            centerTitle: true,
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF424242)),
                  onPressed: () {
                    _reservasSnapshots.clear();
                    _loadHorarios();
                  },
                  tooltip: 'Actualizar horarios',
                ),
              ),
            ],
          ),
          body: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCanchaInfo(),
                    const SizedBox(height: 24),
                    _buildDateSelector(),
                    const SizedBox(height: 8),
                    if (_calendarExpanded) _buildCalendar(),
                    const SizedBox(height: 24),
                    _buildHorariosHeader(),
                    const SizedBox(height: 16),
                    _buildHorariosGrid(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanchaInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              (_updatedCancha?.imagen ?? widget.cancha.imagen).startsWith('http')
                  ? _updatedCancha?.imagen ?? widget.cancha.imagen
                  : 'assets/cancha_demo.png',
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              cacheWidth: 140,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 70,
                  height: 70,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.sports_soccer_outlined, color: Colors.grey),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _updatedCancha?.nombre ?? widget.cancha.nombre,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (_updatedCancha?.techada ?? widget.cancha.techada)
                        ? Colors.blue.shade50
                        : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (_updatedCancha?.techada ?? widget.cancha.techada)
                          ? Colors.blue.shade200
                          : Colors.amber.shade200,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    (_updatedCancha?.techada ?? widget.cancha.techada) ? 'Techada' : 'Al aire libre',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: (_updatedCancha?.techada ?? widget.cancha.techada)
                          ? Colors.blue.shade700
                          : Colors.amber.shade700,
                    ),
                  ),
                ),
                if ((!(_updatedCancha?.disponible ?? widget.cancha.disponible)) &&
                    (_updatedCancha?.motivoNoDisponible ?? widget.cancha.motivoNoDisponible) != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.shade200, width: 1),
                    ),
                    child: Text(
                      _updatedCancha?.motivoNoDisponible ?? widget.cancha.motivoNoDisponible!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: Colors.grey.shade700,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  Provider.of<SedeProvider>(context).selectedSede,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return GestureDetector(
      onTap: (_updatedCancha?.disponible ?? widget.cancha.disponible) ? _toggleCalendar : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Icon(
                Icons.calendar_today_outlined,
                color: Colors.grey.shade800,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fecha seleccionada',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE, d MMMM yyyy', 'es').format(_selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(
              _calendarExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.grey.shade700,
            ),
          ],
        ),
      ),
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Horarios Disponibles',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
            letterSpacing: 0.3,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.shade100),
          ),
          child: Text(
            DateFormat('d MMM', 'es').format(_selectedDate),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.green.shade700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHorariosGrid() {
    if (!(_updatedCancha?.disponible ?? widget.cancha.disponible)) {
      return Expanded(
        child: Center(
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
        ),
      );
    }

    if (_isLoading) {
      return Expanded(
        child: Center(
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
        ),
      );
    }

    if (horarios.isEmpty) {
      return Expanded(
        child: Center(
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
        ),
      );
    }

    // Responsividad mejorada
    return Expanded(
      child: LayoutBuilder(
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
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: childAspectRatio,
            ),
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: horarios.length,
            itemBuilder: (context, index) {
              final horario = horarios[index];
              return _buildHorarioCard(horario, Provider.of<SedeProvider>(context, listen: false).selectedSede);
            },
          );
        },
      ),
    );
  }

  Widget _buildHorarioCard(Horario horario, String sedeNombre) {
    final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
    final String horaStr = horario.horaFormateada;
    final Map<String, Map<String, dynamic>>? dayPrices = (_updatedCancha?.preciosPorHorario ?? widget.cancha.preciosPorHorario)[day];
    final double precio = dayPrices != null && dayPrices.containsKey(horaStr)
        ? (dayPrices[horaStr] is Map<String, dynamic>
            ? (dayPrices[horaStr]!['precio'] as num?)?.toDouble() ?? (_updatedCancha?.precio ?? widget.cancha.precio)
            : (dayPrices[horaStr] as num?)?.toDouble() ?? (_updatedCancha?.precio ?? widget.cancha.precio))
        : (_updatedCancha?.precio ?? widget.cancha.precio);

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
                  color: horario.estado == EstadoHorario.disponible
                      ? const Color(0xFF4CAF50)
                      : horario.estado == EstadoHorario.reservado
                          ? const Color(0xFF1B5E20)
                      : horario.estado == EstadoHorario.procesandoPago  // ✅ NUEVO CASO
                          ? Colors.red.shade600
                      : Colors.grey.shade400,
                  width: 1.5,
                ),
                boxShadow: [
                  if (horario.estado == EstadoHorario.disponible) ...[
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
                        gradient: horario.estado == EstadoHorario.disponible
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
                                child: Container(
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
                                            ? 'Disponible'
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
}