import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/cancha.dart';
import '../../../models/reserva.dart';
import '../../../models/horario.dart';
import '../../../providers/cancha_provider.dart';
import '../../../providers/sede_provider.dart';
import 'detalles_reserva_screen.dart';
import 'agregar_reserva_screen.dart';


class AdminReservasScreen extends StatefulWidget {
  const AdminReservasScreen({super.key});

  @override
  AdminReservasScreenState createState() => AdminReservasScreenState();
}

class AdminReservasScreenState extends State<AdminReservasScreen>
    with TickerProviderStateMixin {
  String _selectedSede = 'Sede 1';
  Cancha? _selectedCancha;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _viewGrid = true;

  late AnimationController _fadeController;
  late AnimationController _slideController;

  List<Cancha> _canchas = [];
  List<Reserva> _reservas = [];
  final Map<int, Reserva> _reservedMap = {};
  final List<int> _selectedHours = [];
  final Map<String, QuerySnapshot> _reservasSnapshots = {};
  Timer? _debounceTimer;

  final List<int> _hours = List<int>.generate(19, (index) => index + 5);
  final List<String> _sedes = ['Sede 1', 'Sede 2'];

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);
  final Color _disabledColor = const Color(0xFFDADCE0);
  final Color _reservedColor = const Color(0xFF4CAF50);
  final Color _availableColor = const Color(0xFFEEEEEE);
  final Color _selectedHourColor = const Color(0xFFFFCA28);

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
      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
      setState(() {
        _selectedSede = sedeProvider.selectedSede;
      });
      _loadCanchas();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }


  Future<void> _loadCanchas() async {
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    setState(() {
      _isLoading = true;
      _canchas.clear();
      _selectedCancha = null;
      _selectedHours.clear();
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      try {
        await canchaProvider.fetchCanchas(_selectedSede);
        if (!mounted) return;

        // Filtrar canchas por sede para garantizar que solo se muestren las correspondientes
        final canchasFiltradas = canchaProvider.canchas
            .where((cancha) => cancha.sede == _selectedSede)
            .toList();

        setState(() {
          _canchas = canchasFiltradas;
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
    });
  }

  Future<void> _loadReservas() async {
  if (_selectedCancha == null) return;
  setState(() {
    _isLoading = true;
    _reservas.clear();
    _reservedMap.clear();
    _selectedHours.clear();
  });

  final snapshotKey =
      '${DateFormat('yyyy-MM-dd').format(_selectedDate)}_${_selectedCancha!.id}_$_selectedSede';

  try {
    QuerySnapshot? querySnapshot = _reservasSnapshots[snapshotKey];

    if (querySnapshot == null) {
      for (int i = 0; i < 3; i++) {
        try {
          querySnapshot = await FirebaseFirestore.instance
              .collection('reservas')
              .where('fecha',
                  isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate))
              .where('sede', isEqualTo: _selectedSede)
              .where('cancha_id', isEqualTo: _selectedCancha!.id)
              .get();
          break;
        } catch (e) {
          if (i == 2) rethrow;
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
      if (_reservasSnapshots.length >= 5) {
        _reservasSnapshots.remove(_reservasSnapshots.keys.first);
      }
      _reservasSnapshots[snapshotKey] = querySnapshot!;
    }

    List<Reserva> reservasTemp = [];
    for (var doc in querySnapshot.docs) {
      try {
        final reserva = await Reserva.fromFirestore(doc);
        final hour = reserva.horario.hora.hour;
        _reservedMap[hour] = reserva;
        reservasTemp.add(reserva);
      } catch (e) {
        debugPrint("Error al procesar documento: $e");
      }
    }

    if (mounted) {
      setState(() {
        _reservas = reservasTemp;
      });
    }
  } catch (e) {
    if (mounted) {
      _showErrorSnackBar('Error al cargar reservas: $e');
    }
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _fadeController.reset();
      _fadeController.forward();
    }
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
            onPressed: () =>
                _selectedCancha != null ? _loadReservas() : _loadCanchas(),
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
    DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _secondaryColor,
              onPrimary: Colors.white,
              onSurface: _primaryColor,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _secondaryColor,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (newDate != null && newDate != _selectedDate && mounted) {
      setState(() {
        _selectedDate = newDate;
        _selectedHours.clear();
        _isLoading = true;
      });
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 200), _loadReservas);
    }
  }

  void _viewReservaDetails(Reserva reserva) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            DetallesReservaScreen(reserva: reserva),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ).then((_) => _loadReservas());
  }

  void _addReserva() {
    if (_selectedCancha == null || _selectedHours.isEmpty) {
      _showErrorSnackBar('Selecciona una cancha y al menos un horario');
      return;
    }

    final horarios = _selectedHours
        .map((hour) => Horario(hora: TimeOfDay(hour: hour, minute: 0)))
        .toList();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            AgregarReservaScreen(
          cancha: _selectedCancha!,
          sede: _selectedSede,
          horarios: horarios,
          fecha: _selectedDate,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ).then((result) async {
      if (result == true && mounted) {
        _reservasSnapshots.clear();
        setState(() {
          _selectedHours.clear();
        });
        await _loadReservas();
      }
    });
  }

  void _toggleHourSelection(int hour) {
    setState(() {
      if (_selectedHours.contains(hour)) {
        _selectedHours.remove(hour);
      } else {
        _selectedHours.add(hour);
      }
    });
  }

  void _confirmDelete(Reserva reserva) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Confirmar eliminación'),
        content:
            const Text('¿Estás seguro de que deseas eliminar esta reserva?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancelar',
              style: TextStyle(color: _primaryColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .runTransaction((transaction) async {
                  final docRef = FirebaseFirestore.instance
                      .collection('reservas')
                      .doc(reserva.id);
                  final snapshot = await transaction.get(docRef);
                  if (snapshot.exists) {
                    transaction.delete(docRef);
                  }
                });
                Navigator.pop(context);
                _reservasSnapshots.clear();
                await _loadReservas();
              } catch (e) {
                if (mounted) {
                  _showErrorSnackBar('Error al eliminar la reserva: $e');
                }
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Administración de Reservas',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: _backgroundColor,
        elevation: 0,
        foregroundColor: _primaryColor,
        actions: [
          Tooltip(
            message: _viewGrid ? 'Vista en Lista' : 'Vista en Calendario',
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              child: IconButton(
                icon: Icon(
                  _viewGrid
                      ? Icons.view_list_rounded
                      : Icons.calendar_view_month_rounded,
                  color: _secondaryColor,
                ),
                onPressed: _toggleView,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedHours.isNotEmpty
          ? FloatingActionButton(
              onPressed: _addReserva,
              backgroundColor: _secondaryColor,
              child: const Icon(Icons.check, color: Colors.white),
              tooltip: 'Confirmar selección',
            )
          : null,
      body: Container(
        color: _backgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
                child: _buildSedeYCanchaSelectors(),
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
                child: _buildFechaSelector(),
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
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: _viewGrid ? _buildGridView() : _buildListView(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSedeYCanchaSelectors() {
    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sede',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color.fromRGBO(60, 64, 67, 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _disabledColor),
                      color: Colors.white,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSede,
                        icon: Icon(Icons.keyboard_arrow_down,
                            color: _secondaryColor),
                        isExpanded: true,
                        style: GoogleFonts.montserrat(
                          color: _primaryColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                        items: _sedes
                            .map((sede) => DropdownMenuItem(
                                  value: sede,
                                  child: Text(sede),
                                ))
                            .toList(),
                        onChanged: (newSede) {
                          if (newSede != null && newSede != _selectedSede) {
                            setState(() {
                              _selectedSede = newSede;
                              _selectedCancha = null;
                              _selectedHours.clear();
                              _isLoading = true;
                            });
                            _loadCanchas();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cancha',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color.fromRGBO(60, 64, 67, 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _disabledColor),
                      color: Colors.white,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Cancha>(
                        value: _selectedCancha,
                        hint: Text(
                          _canchas.isEmpty
                              ? 'No hay canchas disponibles'
                              : 'Selecciona Cancha',
                          style: GoogleFonts.montserrat(
                            color: const Color.fromRGBO(60, 64, 67, 0.5),
                          ),
                        ),
                        icon: Icon(Icons.keyboard_arrow_down,
                            color: _secondaryColor),
                        isExpanded: true,
                        style: GoogleFonts.montserrat(
                          color: _primaryColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                        items: _canchas
                            .map((cancha) => DropdownMenuItem<Cancha>(
                                  value: cancha,
                                  child: Text(cancha.nombre),
                                ))
                            .toList(),
                        onChanged: (newCancha) {
                          if (newCancha != null) {
                            setState(() {
                              _selectedCancha = newCancha;
                              _selectedHours.clear();
                              _isLoading = true;
                            });
                            _loadReservas();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFechaSelector() {
    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _selectDate(context),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                color: _secondaryColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fecha Seleccionada',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color.fromRGBO(60, 64, 67, 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE d MMMM, yyyy', 'es').format(_selectedDate),
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: const Color.fromRGBO(60, 64, 67, 0.5),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridView() {
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
        if (_isLoading)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cargando horarios...',
                    style: GoogleFonts.montserrat(
                      color: const Color.fromRGBO(60, 64, 67, 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width > 800 ? 5 : 3,
                childAspectRatio:
                    MediaQuery.of(context).size.width > 800 ? 2 : 1.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _hours.length,
              itemBuilder: (context, index) {
                final hour = _hours[index];
                final now = DateTime.now();
                final isToday = _selectedDate.year == now.year &&
                    _selectedDate.month == now.month &&
                    _selectedDate.day == now.day;
                final isPast = isToday && hour < now.hour;
                final isReserved = _reservedMap.containsKey(hour);
                final isSelected = _selectedHours.contains(hour);
                final reserva = isReserved ? _reservedMap[hour] : null;

                Color bgColor;
                Color textColor;
                IconData statusIcon;
                String statusText;

                if (isPast) {
                  bgColor = const Color.fromRGBO(218, 220, 224, 0.5);
                  textColor = Colors.grey;
                  statusIcon = Icons.history;
                  statusText = 'Pasado';
                } else if (isReserved) {
                  bgColor = const Color.fromRGBO(76, 175, 80, 0.2);
                  textColor = _reservedColor;
                  statusIcon = Icons.event_busy;
                  statusText = 'Reservado';
                } else if (isSelected) {
                  bgColor = _selectedHourColor.withOpacity(0.3);
                  textColor = _selectedHourColor;
                  statusIcon = Icons.check_circle;
                  statusText = 'Seleccionado';
                } else {
                  bgColor = _availableColor;
                  textColor = _primaryColor;
                  statusIcon = Icons.event_available;
                  statusText = 'Disponible';
                }

                final String day = DateFormat('EEEE', 'es')
                    .format(_selectedDate)
                    .toLowerCase();
                final String horaStr = '$hour:00';
                final double precio = _selectedCancha != null
                    ? (_selectedCancha!.preciosPorHorario[day]?[horaStr] ??
                        _selectedCancha!.precio)
                    : 0.0;

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
                    tag: 'hora_grid_$hour',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: isPast || isReserved
                            ? (isReserved
                                ? () => _viewReservaDetails(reserva!)
                                : null)
                            : () => _toggleHourSelection(hour),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isPast
                                  ? _disabledColor
                                  : isReserved
                                      ? _reservedColor
                                      : isSelected
                                          ? _selectedHourColor
                                          : const Color.fromRGBO(
                                              60, 64, 67, 0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isPast
                                    ? Colors.black.withAlpha(13)
                                    : isReserved
                                        ? const Color.fromRGBO(
                                            76, 175, 80, 0.15)
                                        : isSelected
                                            ? const Color.fromRGBO(
                                                255, 202, 40, 0.2)
                                            : const Color.fromRGBO(
                                                60, 64, 67, 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('h:mm a')
                                    .format(DateTime(2022, 1, 1, hour)),
                                style: GoogleFonts.montserrat(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    statusIcon,
                                    size: 14,
                                    color: textColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: GoogleFonts.montserrat(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: textColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'COP ${precio.toStringAsFixed(0)}',
                                style: GoogleFonts.montserrat(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                              ),
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

  Widget _buildListView() {
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
        if (_isLoading)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cargando horarios...',
                    style: GoogleFonts.montserrat(
                      color: const Color.fromRGBO(60, 64, 67, 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _hours.length,
              itemBuilder: (context, index) {
                final hour = _hours[index];
                final now = DateTime.now();
                final isToday = _selectedDate.year == now.year &&
                    _selectedDate.month == now.month &&
                    _selectedDate.day == now.day;
                final isPast = isToday && hour < now.hour;
                final isReserved = _reservedMap.containsKey(hour);
                final isSelected = _selectedHours.contains(hour);
                final reserva = isReserved ? _reservedMap[hour] : null;

                Color bgColor;
                Color textColor;
                IconData statusIcon;
                String statusText;

                if (isPast) {
                  bgColor = const Color.fromRGBO(218, 220, 224, 0.5);
                  textColor = Colors.grey;
                  statusIcon = Icons.history;
                  statusText = 'Pasado';
                } else if (isReserved) {
                  bgColor = const Color.fromRGBO(76, 175, 80, 0.1);
                  textColor = _reservedColor;
                  statusIcon = Icons.event_busy;
                  statusText = 'Reservado';
                } else if (isSelected) {
                  bgColor = _selectedHourColor.withOpacity(0.3);
                  textColor = _selectedHourColor;
                  statusIcon = Icons.check_circle;
                  statusText = 'Seleccionado';
                } else {
                  bgColor = Colors.white;
                  textColor = _primaryColor;
                  statusIcon = Icons.event_available;
                  statusText = 'Disponible';
                }

                final String day = DateFormat('EEEE', 'es')
                    .format(_selectedDate)
                    .toLowerCase();
                final String horaStr = '$hour:00';
                // ignore: unused_local_variable
                final double precio = _selectedCancha != null
                    ? (_selectedCancha!.preciosPorHorario[day]?[horaStr] ??
                        _selectedCancha!.precio)
                    : 0.0;

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
                      tag: 'hora_list_$hour',
                      child: Material(
                        color: Colors.transparent,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isPast
                                  ? _disabledColor
                                  : isReserved
                                      ? _reservedColor
                                      : isSelected
                                          ? _selectedHourColor
                                          : const Color.fromRGBO(
                                              60, 64, 67, 0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isPast
                                    ? Colors.black.withAlpha(13)
                                    : isReserved
                                        ? const Color.fromRGBO(
                                            76, 175, 80, 0.15)
                                        : isSelected
                                            ? const Color.fromRGBO(
                                                255, 202, 40, 0.2)
                                            : const Color.fromRGBO(
                                                60, 64, 67, 0.1),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            onTap: isPast
                                ? null
                                : () {
                                    if (isReserved) {
                                      _viewReservaDetails(reserva!);
                                    } else {
                                      _toggleHourSelection(hour);
                                    }
                                  },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isPast
                                    ? const Color.fromRGBO(218, 220, 224, 0.2)
                                    : isReserved
                                        ? const Color.fromRGBO(76, 175, 80, 0.2)
                                        : isSelected
                                            ? _selectedHourColor
                                                .withOpacity(0.2)
                                            : _availableColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Icon(
                                  statusIcon,
                                  color: textColor,
                                ),
                              ),
                            ),
                            title: Text(
                              DateFormat('h:mm a')
                                  .format(DateTime(2022, 1, 1, hour)),
                              style: GoogleFonts.montserrat(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            subtitle: Text(
                              '$statusText${isReserved ? ' por: ${reserva?.nombre ?? "Cliente"}' : isSelected ? '' : isPast ? '' : ' para reservar'}',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                color: Color.fromRGBO(textColor.red,
                                    textColor.green, textColor.blue, 0.8),
                              ),
                            ),
                            trailing: isReserved && !isPast
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit,
                                            color: _secondaryColor, size: 20),
                                        onPressed: () =>
                                            _viewReservaDetails(reserva!),
                                        tooltip: 'Editar',
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete,
                                            color: Colors.redAccent, size: 20),
                                        onPressed: () =>
                                            _confirmDelete(reserva!),
                                        tooltip: 'Eliminar',
                                      ),
                                    ],
                                  )
                                : Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                    color: Color.fromRGBO(textColor.red,
                                        textColor.green, textColor.blue, 0.5),
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
}
