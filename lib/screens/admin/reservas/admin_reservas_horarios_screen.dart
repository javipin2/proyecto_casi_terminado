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
  String _selectedSedeId = '';
  String _selectedSedeNombre = '';
  Cancha? _selectedCancha;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true; // Inicialmente true para evitar renderizado parcial
  bool _viewGrid = true;

  late AnimationController _fadeController;
  late AnimationController _slideController;

  StreamSubscription<QuerySnapshot>? _reservasSubscription;

  List<Cancha> _canchas = [];
  List<Reserva> _reservas = [];
  final Map<String, Reserva> _reservedMap = {};
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
      sedeProvider.fetchSedes().then((_) {
        if (!mounted) return;
        setState(() {
          if (sedeProvider.sedes.isNotEmpty) {
            _selectedSedeId = sedeProvider.sedes.first['id'] as String;
            _selectedSedeNombre = sedeProvider.sedes.first['nombre'] as String;
            sedeProvider.setSede(_selectedSedeNombre);
          } else {
            _selectedSedeId = '';
            _selectedSedeNombre = '';
          }
        });
        if (_selectedSedeId.isNotEmpty) {
          _loadCanchas();
        } else {
          setState(() {
            _isLoading = false; // Si no hay sedes, no cargamos más
          });
        }
      }).catchError((e) {
        if (mounted) {
          _showErrorSnackBar('Error al cargar sedes: $e');
          setState(() {
            _isLoading = false;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _reservasSubscription?.cancel();
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

    try {
      await canchaProvider.fetchCanchas(_selectedSedeId);
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

    final stream = FirebaseFirestore.instance
        .collection('reservas')
        .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate))
        .where('sede', isEqualTo: _selectedSedeId)
        .where('cancha_id', isEqualTo: _selectedCancha!.id)
        .limit(24)
        .snapshots();

    _reservasSubscription = stream.listen(
      (querySnapshot) async {
        final horarios = await Horario.generarHorarios(
          fecha: _selectedDate,
          canchaId: _selectedCancha!.id,
          sede: _selectedSedeId,
          reservasSnapshot: querySnapshot,
          cancha: _selectedCancha!,
        );
        List<Reserva> reservasTemp = [];
        for (var doc in querySnapshot.docs) {
          try {
            final reserva = await Reserva.fromFirestore(doc);
            final horaNormalizada = Horario.normalizarHora(reserva.horario.horaFormateada);
            _reservedMap[horaNormalizada] = reserva;
            reservasTemp.add(reserva);
          } catch (e) {
            debugPrint("Error al procesar documento: $e");
          }
        }
        if (mounted) {
          setState(() {
            _reservas = reservasTemp;
            _hours = horarios.map((h) => h.horaFormateada).toList();
            _isLoading = false;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          _showErrorSnackBar('Error al cargar reservas: $e');
          setState(() {
            _isLoading = false;
          });
        }
      },
    );
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
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 200), _loadReservas);
    }
  }

  void _viewReservaDetails(Reserva reserva) {
    if (!mounted) return;
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

  void _toggleHourSelection(String horaStr) {
    setState(() {
      final horaNormalizada = Horario.normalizarHora(horaStr);
      if (_reservedMap.containsKey(horaNormalizada)) return;
      if (_selectedHours.contains(horaNormalizada)) {
        _selectedHours.remove(horaNormalizada);
      } else {
        _selectedHours.add(horaNormalizada);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1200;
        final crossAxisCount = isMobile ? 3 : isTablet ? 4 : 6; // 3 columnas en móvil
        final childAspectRatio = isMobile ? 1.5 : isTablet ? 1.8 : 1.8;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Reservas',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
            ),
            backgroundColor: _backgroundColor,
            elevation: 0,
            foregroundColor: _primaryColor,
            actions: [
              Tooltip(
                message: _viewGrid ? 'Vista en Lista' : 'Vista en Calendario',
                child: Container(
                  margin: EdgeInsets.only(right: isMobile ? 8 : 16),
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
          ),
          floatingActionButton: _selectedHours.isNotEmpty
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
                      .toList(), (newSedeId) async {
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
                      sedeProvider.setSede(_selectedSedeNombre);
                      await _loadCanchas();
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
                        .toList(), (newSedeId) async {
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
                        sedeProvider.setSede(_selectedSedeNombre);
                        await _loadCanchas();
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
                        .toList(), (newCancha) {
                      if (newCancha != null) {
                        setState(() {
                          _selectedCancha = newCancha;
                          _selectedHours.clear();
                          _isLoading = true;
                        });
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
              final horaObj = Horario.fromHoraFormateada(horaStr);
              final isPast = horaObj.estaVencida(_selectedDate);
              final isReserved = _reservedMap.containsKey(horaNormalizada);
              final isSelected = _selectedHours.contains(horaNormalizada);
              final reserva = isReserved ? _reservedMap[horaNormalizada] : null;

              Color textColor;
              IconData statusIcon;
              String statusText;

              if (isPast) {
                textColor = Colors.grey;
                statusIcon = Icons.history;
                statusText = 'Pasado';
              } else if (isReserved) {
                textColor = _reservedColor;
                statusIcon = Icons.event_busy;
                statusText = 'Reservado';
              } else if (isSelected) {
                textColor = _selectedHourColor;
                statusIcon = Icons.check_circle;
                statusText = 'Seleccionado';
              } else {
                textColor = _primaryColor;
                statusIcon = Icons.event_available;
                statusText = 'Disponible';
              }

              final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
              final double precio = _selectedCancha != null
                  ? (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] is Map<String, dynamic>
                      ? ((_selectedCancha!.preciosPorHorario[day]![horaNormalizada] as Map<String, dynamic>)['precio'] as num?)?.toDouble() ??
                          _selectedCancha!.precio
                      : (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] as num?)?.toDouble() ??
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
                  tag: 'hora_grid_$horaNormalizada',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isPast || isReserved
                          ? (isReserved ? () => _viewReservaDetails(reserva!) : null)
                          : () => _toggleHourSelection(horaStr),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPast
                                ? _disabledColor
                                : isReserved
                                    ? _reservedColor
                                    : isSelected
                                        ? _selectedHourColor
                                        : const Color.fromRGBO(60, 64, 67, 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isPast
                                  ? Colors.black.withAlpha(13)
                                  : isReserved
                                      ? const Color.fromRGBO(76, 175, 80, 0.15)
                                      : isSelected
                                          ? const Color.fromRGBO(255, 202, 40, 0.2)
                                          : const Color.fromRGBO(60, 64, 67, 0.1),
                              blurRadius: 8,
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
                              'COP ${precio.toInt()}',
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
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
              final horaObj = Horario.fromHoraFormateada(horaStr);
              final isPast = horaObj.estaVencida(_selectedDate);
              final isReserved = _reservedMap.containsKey(horaNormalizada);
              final isSelected = _selectedHours.contains(horaNormalizada);
              final reserva = isReserved ? _reservedMap[horaNormalizada] : null;

              Color textColor;
              IconData statusIcon;
              String statusText;

              if (isPast) {
                textColor = Colors.grey;
                statusIcon = Icons.history;
                statusText = 'Pasado';
              } else if (isReserved) {
                textColor = _reservedColor;
                statusIcon = Icons.event_busy;
                statusText = 'Reservado';
              } else if (isSelected) {
                textColor = _selectedHourColor;
                statusIcon = Icons.check_circle;
                statusText = 'Seleccionado';
              } else {
                textColor = _primaryColor;
                statusIcon = Icons.event_available;
                statusText = 'Disponible';
              }

              final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
              final double precio = _selectedCancha != null
                  ? (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] is Map<String, dynamic>
                      ? ((_selectedCancha!.preciosPorHorario[day]![horaNormalizada] as Map<String, dynamic>)['precio'] as num?)?.toDouble() ??
                          _selectedCancha!.precio
                      : (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] as num?)?.toDouble() ??
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
                    tag: 'hora_list_$horaNormalizada',
                    child: Material(
                      color: Colors.transparent,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPast
                                ? _disabledColor
                                : isReserved
                                    ? _reservedColor
                                    : isSelected
                                        ? _selectedHourColor
                                        : const Color.fromRGBO(60, 64, 67, 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isPast
                                  ? Colors.black.withAlpha(13)
                                  : isReserved
                                      ? const Color.fromRGBO(76, 175, 80, 0.15)
                                      : isSelected
                                          ? const Color.fromRGBO(255, 202, 40, 0.2)
                                          : const Color.fromRGBO(60, 64, 67, 0.1),
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
                                    _toggleHourSelection(horaStr);
                                  }
                                },
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
                              color: isPast
                                  ? const Color.fromRGBO(218, 220, 224, 0.2)
                                  : isReserved
                                      ? const Color.fromRGBO(76, 175, 80, 0.2)
                                      : isSelected
                                          ? _selectedHourColor
                                          : _availableColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Icon(statusIcon, size: isMobile ? 12 : 14, color: textColor),
                            ),
                          ),
                          title: Text(
                            horaStr,
                            style: GoogleFonts.montserrat(
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          subtitle: Text(
                            '$statusText${isReserved ? ' por: ${reserva?.nombre ?? "Cliente"}' : isSelected ? '' : isPast ? '' : ' para reservar'} - COP ${precio.toInt()}',
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
                          trailing: isReserved && !isPast
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
}