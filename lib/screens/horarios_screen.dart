import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/cancha.dart';
import '../models/horario.dart';
import '../providers/sede_provider.dart';
import '../providers/cancha_provider.dart';
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
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadHorarios();
  }

  Future<void> _loadHorarios() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    _debounceTimer?.cancel();

    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final sedeSeleccionada = sedeProvider.selectedSede;
    final sede = sedeProvider.sedes.firstWhere(
      (s) => s['nombre'] == sedeSeleccionada,
      orElse: () => {'id': '', 'nombre': sedeSeleccionada},
    );
    final sedeId = sede['id'] as String;

    final snapshotKey = '${DateFormat('yyyy-MM-dd').format(_selectedDate)}_${widget.cancha.id}_$sedeId';

    try {
      QuerySnapshot? reservasSnapshot = _reservasSnapshots[snapshotKey];

      if (reservasSnapshot == null) {
        reservasSnapshot = await FirebaseFirestore.instance
            .collection('reservas')
            .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate))
            .where('cancha_id', isEqualTo: widget.cancha.id)
            .where('sede', isEqualTo: sedeId)
            .get();
        _reservasSnapshots[snapshotKey] = reservasSnapshot;
        print(
            'Reservas encontradas para sedeId=$sedeId, canchaId=${widget.cancha.id}, fecha=${DateFormat('yyyy-MM-dd').format(_selectedDate)}: ${reservasSnapshot.docs.length}');
        for (var doc in reservasSnapshot.docs) {
          print('Reserva ${doc.id}: ${doc.data()}');
        }
      }

      if (!mounted) return;

      final nuevosHorarios = await Horario.generarHorarios(
        fecha: _selectedDate,
        canchaId: widget.cancha.id,
        sede: sedeId,
        reservasSnapshot: reservasSnapshot,
      );

      if (!mounted) return;

      setState(() {
        horarios = nuevosHorarios;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar horarios: $e'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
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
    return Container(
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

    return Expanded(
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
        ),
        physics: const BouncingScrollPhysics(),
        itemCount: horarios.length,
        itemBuilder: (context, index) {
          final horario = horarios[index];
          return _buildHorarioCard(horario, Provider.of<SedeProvider>(context, listen: false).selectedSede);
        },
      ),
    );
  }

  Widget _buildHorarioCard(Horario horario, String sedeNombre) {
    final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
    final String horaStr = '${horario.hora.hour}:00';
    final Map<String, double>? dayPrices = (_updatedCancha?.preciosPorHorario ?? widget.cancha.preciosPorHorario)[day];
    final double precio = dayPrices != null && dayPrices.containsKey(horaStr)
        ? dayPrices[horaStr] ?? (_updatedCancha?.precio ?? widget.cancha.precio)
        : _updatedCancha?.precio ?? widget.cancha.precio;

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
      child: InkWell(
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
          if (mounted) {
            Navigator.push<bool>(
              context,
              PageRouteBuilder(
                pageBuilder: (_, animation, __) {
                  return FadeTransition(
                    opacity: animation,
                    child: horario.estado == EstadoHorario.disponible
                        ? DetallesScreen(
                            cancha: widget.cancha,
                            fecha: _selectedDate,
                            horario: horario,
                            sede: sedeId,
                          )
                        : ReservaDetallesScreen(
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
            ? Colors.red.shade100.withAlpha(50)
            : Colors.green.shade100.withAlpha(50),
        highlightColor: horario.estado == EstadoHorario.reservado
            ? Colors.red.shade200.withAlpha(30)
            : Colors.green.shade200.withAlpha(30),
        child: Container(
          decoration: BoxDecoration(
            gradient: horario.estado == EstadoHorario.reservado
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color.fromARGB(255, 134, 134, 134),
                      const Color.fromARGB(255, 243, 243, 243),
                    ],
                  )
                : null,
            color: horario.estado == EstadoHorario.disponible
                ? Colors.white
                : horario.estado == EstadoHorario.vencido
                    ? Colors.grey.shade300
                    : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: horario.estado == EstadoHorario.disponible
                  ? Colors.green.shade300
                  : horario.estado == EstadoHorario.reservado
                      ? const Color.fromARGB(255, 168, 168, 168)
                      : Colors.grey.shade400,
              width: 1.5,
            ),
            boxShadow: [
              if (horario.estado == EstadoHorario.disponible)
                BoxShadow(
                  color: Colors.green.withAlpha(26),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              if (horario.estado == EstadoHorario.reservado)
                BoxShadow(
                  color: const Color.fromARGB(255, 77, 77, 77).withAlpha(50),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  horario.horaFormateada,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: horario.estado == EstadoHorario.disponible
                        ? Colors.green.shade700
                        : Colors.black54,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(precio),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: horario.estado == EstadoHorario.disponible
                        ? Colors.green.shade700
                        : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: horario.estado == EstadoHorario.disponible
                        ? Colors.green.shade50
                        : horario.estado == EstadoHorario.reservado
                            ? Colors.red.shade50
                            : Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    horario.estado == EstadoHorario.disponible
                        ? 'Disponible'
                        : horario.estado == EstadoHorario.reservado
                            ? 'Reservado'
                            : 'Vencido',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: horario.estado == EstadoHorario.disponible
                          ? Colors.green.shade700
                          : horario.estado == EstadoHorario.reservado
                              ? const Color.fromARGB(255, 0, 0, 0)
                              : Colors.black38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}