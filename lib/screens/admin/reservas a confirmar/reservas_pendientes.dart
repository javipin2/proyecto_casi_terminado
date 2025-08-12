import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/models/reserva.dart';
import 'package:reserva_canchas/providers/reserva_provider.dart';
import 'package:reserva_canchas/providers/cancha_provider.dart';
import 'package:reserva_canchas/providers/sede_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

class Confirmar extends StatefulWidget {
  const Confirmar({super.key});

  @override
  State<Confirmar> createState() => _ConfirmarState();
}

class _ConfirmarState extends State<Confirmar> with TickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  String? _selectedSede;
  String? _selectedCancha;
  bool _isLoading = false;
  bool _filtersVisible = true; // Por defecto visible en pantallas grandes
  bool _viewTable = true; // Por defecto tabla en pantallas grandes
  late TabController _tabController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  bool _useDateFilter = false; // NUEVA VARIABLE
  static const int _reservasPorPagina = 15;
  final List<DocumentSnapshot> _reservasConfirmadas = [];
  DocumentSnapshot? _ultimoDocumentoConfirmadas;
  bool _hayMasReservasConfirmadas = true;
  bool _cargandoMasReservas = false;
  final ScrollController _scrollControllerConfirmadas = ScrollController();

  // Colores definidos para consistencia visual
  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);
  final Color _disabledColor = const Color(0xFFDADCE0);
  final Color _reservedColor = const Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es', null);
    _tabController = TabController(length: 2, vsync: this);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    // AGREGAR ESTAS LÍNEAS:
    _scrollControllerConfirmadas.addListener(_onScrollConfirmadas);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SedeProvider>(context, listen: false).fetchSedes();
      _limpiarReservasTemporalesExpiradas();
      _cargarReservasConfirmadas(); // AGREGAR ESTA LÍNEA
      _fadeController.forward();
      _slideController.forward();
    });
  }
  
  
  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _scrollControllerConfirmadas.dispose(); // AGREGAR ESTA LÍNEA
    super.dispose();
  }



  void _onScrollConfirmadas() {
    if (_scrollControllerConfirmadas.position.pixels >=
        _scrollControllerConfirmadas.position.maxScrollExtent - 200) {
      if (_hayMasReservasConfirmadas && !_cargandoMasReservas) {
        _cargarMasReservasConfirmadas();
      }
    }
  }

  Future<void> _cargarReservasConfirmadas() async {
    if (_cargandoMasReservas) return;
    
    setState(() {
      _cargandoMasReservas = true;
    });

    try {
      Query query = _buildQueryConfirmadas();
      
      final snapshot = await query.limit(_reservasPorPagina).get();
      
      if (mounted) {
        setState(() {
          _reservasConfirmadas.clear();
          _reservasConfirmadas.addAll(snapshot.docs);
          _ultimoDocumentoConfirmadas = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hayMasReservasConfirmadas = snapshot.docs.length == _reservasPorPagina;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar reservas confirmadas: $e');
      if (mounted) {
        _showErrorSnackBar('Error al cargar reservas: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargandoMasReservas = false;
        });
      }
    }
  }

  Future<void> _cargarMasReservasConfirmadas() async {
    if (_cargandoMasReservas || _ultimoDocumentoConfirmadas == null) return;
    
    setState(() {
      _cargandoMasReservas = true;
    });

    try {
      Query query = _buildQueryConfirmadas();
      
      final snapshot = await query
          .startAfterDocument(_ultimoDocumentoConfirmadas!)
          .limit(_reservasPorPagina)
          .get();
      
      if (mounted) {
        setState(() {
          _reservasConfirmadas.addAll(snapshot.docs);
          _ultimoDocumentoConfirmadas = snapshot.docs.isNotEmpty ? snapshot.docs.last : _ultimoDocumentoConfirmadas;
          _hayMasReservasConfirmadas = snapshot.docs.length == _reservasPorPagina;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar más reservas: $e');
      if (mounted) {
        _showErrorSnackBar('Error al cargar más reservas: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargandoMasReservas = false;
        });
      }
    }
  }

  Query _buildQueryConfirmadas() {
    Query query = FirebaseFirestore.instance
        .collection('reservas')
        .where('confirmada', isEqualTo: true);

    // Solo aplicar filtro de fecha si está activo
    if (_useDateFilter) {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      query = query.where('fecha', isEqualTo: dateStr);
    }

    if (_selectedSede != null) {
      query = query.where('sede', isEqualTo: _selectedSede);
    }
    if (_selectedCancha != null) {
      query = query.where('cancha_id', isEqualTo: _selectedCancha);
    }

    // Ordenar por fecha y hora
    query = query.orderBy('fecha').orderBy('horario');
    
    return query;
  }

  void _reiniciarPaginacionConfirmadas() {
    setState(() {
      _reservasConfirmadas.clear();
      _ultimoDocumentoConfirmadas = null;
      _hayMasReservasConfirmadas = true;
      _cargandoMasReservas = false;
    });
    _cargarReservasConfirmadas();
  }





  String formatearFecha(DateTime fecha) {
    try {
      return DateFormat('EEEE, d MMMM yyyy', 'es').format(fecha);
    } catch (e) {
      return DateFormat('EEEE, d MMMM yyyy').format(fecha);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
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
                style: TextButton.styleFrom(foregroundColor: _secondaryColor),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null && mounted) {
        setState(() {
          _selectedDate = picked;
          _useDateFilter = true; // ACTIVAR FILTRO DE FECHA
          _selectedCancha = null;
          debugPrint('Fecha seleccionada: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
        });
        _reiniciarPaginacionConfirmadas(); // AGREGAR ESTA LÍNEA
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al seleccionar la fecha: $e');
      }
      debugPrint('Error en _selectDate: $e');
    }
  }


  Future<void> _limpiarReservasTemporalesExpiradas() async {
    try {
      final int ahora = DateTime.now().millisecondsSinceEpoch;
      final QuerySnapshot reservasExpiradas = await FirebaseFirestore.instance
          .collection('reservas_temporales')
          .where('expira_en', isLessThan: ahora)
          .get();

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in reservasExpiradas.docs) {
        batch.delete(doc.reference);
      }

      if (reservasExpiradas.docs.isNotEmpty) {
        await batch.commit();
        debugPrint('Limpiadas ${reservasExpiradas.docs.length} reservas temporales expiradas');
      }
    } catch (e) {
      debugPrint('Error al limpiar reservas temporales expiradas: $e');
    }
  }

  Future<void> _aceptarReserva(String reservaId, ReservaProvider provider) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final reservaRef = FirebaseFirestore.instance.collection('reservas').doc(reservaId);
        transaction.update(reservaRef, {'confirmada': true});
      });
      if (mounted) {
        _showSuccessSnackBar('Reserva aceptada exitosamente');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al aceptar la reserva: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rechazarReserva(String reservaId, ReservaProvider provider) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Confirmar Rechazo',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, color: _primaryColor),
          ),
          content: Text(
            '¿Está seguro de que desea rechazar esta reserva? Esta acción no se puede deshacer.',
            style: GoogleFonts.montserrat(fontSize: 14, color: Colors.grey[700]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancelar',
                style: GoogleFonts.montserrat(color: _secondaryColor, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              child: Text('Rechazar', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final reservaRef = FirebaseFirestore.instance.collection('reservas').doc(reservaId);
          final tempRef = FirebaseFirestore.instance.collection('reservas_temporales').doc(reservaId);
          transaction.delete(reservaRef);
          transaction.delete(tempRef);
        });
        if (mounted) {
          _showSuccessSnackBar('Reserva rechazada exitosamente');
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Error al rechazar la reserva: $e');
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: GoogleFonts.montserrat(color: Colors.white))),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: GoogleFonts.montserrat(color: Colors.white))),
          ],
        ),
        backgroundColor: _reservedColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleView() {
    if (!mounted) return;
    setState(() {
      _viewTable = !_viewTable;
    });
    _fadeController.reset();
    _fadeController.forward();
  }

  void _toggleFilters() {
    if (!mounted) return;
    setState(() {
      _filtersVisible = !_filtersVisible;
    });
  }

  void _selectSede(String? sedeId) {
    if (!mounted) return;
    setState(() {
      _selectedSede = sedeId;
      _selectedCancha = null; // Limpiar cancha al cambiar sede
      final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
      if (sedeId != null) {
        canchaProvider.fetchCanchas(sedeId);
      } else {
        canchaProvider.fetchAllCanchas();
      }
    });
    _reiniciarPaginacionConfirmadas(); // AGREGAR ESTA LÍNEA
  }


  void _selectCancha(String? canchaId) {
    if (!mounted) return;
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final canchasDisponibles = canchaProvider.canchas
        .where((c) => _selectedSede == null || c.sedeId == _selectedSede)
        .map((c) => c.id)
        .toList();
    final isValidCancha = canchaId == null || canchasDisponibles.contains(canchaId);
    setState(() {
      _selectedCancha = isValidCancha ? canchaId : null;
    });
    _reiniciarPaginacionConfirmadas(); // AGREGAR ESTA LÍNEA
  }

  void _clearFilters() {
    if (!mounted) return;
    setState(() {
      _selectedDate = DateTime.now();
      _selectedSede = null;
      _selectedCancha = null;
      _useDateFilter = false; // DESACTIVAR FILTRO DE FECHA
    });
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    canchaProvider.fetchAllCanchas();
    _reiniciarPaginacionConfirmadas(); // AGREGAR ESTA LÍNEA
  }


  @override
  Widget build(BuildContext context) {
    final formattedDate = formatearFecha(_selectedDate);
    final sedeProvider = Provider.of<SedeProvider>(context);
    final canchaProvider = Provider.of<CanchaProvider>(context);

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text('Gestión de Reservas', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: false,
        backgroundColor: _backgroundColor,
        elevation: 0,
        foregroundColor: _primaryColor,
        actions: [
          Tooltip(
            message: _viewTable ? 'Vista en Lista' : 'Vista en Tabla',
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              child: IconButton(
                icon: Icon(
                  _viewTable ? Icons.view_list_rounded : Icons.table_chart_rounded,
                  color: _secondaryColor,
                ),
                onPressed: _toggleView,
              ),
            ),
          ),
          if (MediaQuery.of(context).size.width > 600)
            Tooltip(
              message: _filtersVisible ? 'Ocultar Filtros' : 'Mostrar Filtros',
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                child: IconButton(
                  icon: Icon(
                    _filtersVisible ? Icons.filter_list_off : Icons.filter_list,
                    color: _secondaryColor,
                  ),
                  onPressed: _toggleFilters,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: _cardColor,
            child: TabBar(
              controller: _tabController,
              labelColor: _secondaryColor,
              unselectedLabelColor: _disabledColor,
              indicatorColor: _secondaryColor,
              indicatorWeight: 3,
              labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pending_actions, size: 20, color: _secondaryColor),
                      const SizedBox(width: 6),
                      Text('Pendientes', style: GoogleFonts.montserrat()),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 20, color: _secondaryColor),
                      const SizedBox(width: 6),
                      Text('Confirmadas', style: GoogleFonts.montserrat()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width > 600)
            AnimatedContainer(
              width: _filtersVisible ? 250 : 0,
              duration: const Duration(milliseconds: 300),
              child: _filtersVisible
                  ? _buildFilterPanel(formattedDate, sedeProvider, canchaProvider)
                  : const SizedBox.shrink(),
            ),
          Expanded(
            child: Container(
              color: _backgroundColor,
              child: Padding(
                padding: EdgeInsets.all(_filtersVisible && MediaQuery.of(context).size.width > 600 ? 8.0 : 16.0),
                child: Column(
                  children: [
                    if (MediaQuery.of(context).size.width <= 600)
                      _buildFilterToggle(formattedDate, sedeProvider, canchaProvider),
                    const SizedBox(height: 16),
                    Expanded(
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
                                  Text('Cargando reservas...', style: GoogleFonts.montserrat(color: _primaryColor, fontSize: 16)),
                                ],
                              ),
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              switchInCurve: Curves.easeInOut,
                              switchOutCurve: Curves.easeInOut,
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                              child: TabBarView(
                                key: ValueKey(_viewTable),
                                controller: _tabController,
                                children: [
                                  _buildReservasPendientes(),
                                  _buildReservasConfirmadas(),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToggle(String formattedDate, SedeProvider sedeProvider, CanchaProvider canchaProvider) {
    return Card(
      elevation: 2,
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.filter_list, color: _secondaryColor),
            title: Text('Filtros', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, color: _primaryColor)),
            trailing: Icon(_filtersVisible ? Icons.expand_less : Icons.expand_more, color: _secondaryColor),
            onTap: _toggleFilters,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _filtersVisible
                ? SingleChildScrollView(
                    child: _buildFilterContent(formattedDate, sedeProvider, canchaProvider),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(String formattedDate, SedeProvider sedeProvider, CanchaProvider canchaProvider) {
    return Card(
      elevation: 2,
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(right: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filtros',
                  style: GoogleFonts.montserrat(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear, size: 18),
                  label: Text('Limpiar', style: GoogleFonts.montserrat()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: _primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, color: _secondaryColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fecha', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor)),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _selectDate(context),
                        child: Text(
                          _useDateFilter ? formattedDate : 'Todas las fechas',
                          style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: _primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.store, color: _secondaryColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sede', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor)),
                      const SizedBox(height: 4),
                      DropdownButton<String>(
                        value: _selectedSede,
                        hint: Text('Todas las sedes', style: GoogleFonts.montserrat(color: _primaryColor)),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text('Todas las sedes', style: GoogleFonts.montserrat()),
                          ),
                          ...sedeProvider.sedes.map((sede) => DropdownMenuItem(
                                value: sede['id'] as String,
                                child: Text(sede['nombre'] as String, style: GoogleFonts.montserrat()),
                              )),
                        ],
                        onChanged: _selectSede,
                        style: GoogleFonts.montserrat(color: _primaryColor),
                        icon: Icon(Icons.keyboard_arrow_down, color: _secondaryColor),
                        underline: Container(height: 1, color: _disabledColor),
                        isExpanded: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.sports_soccer, color: _secondaryColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cancha', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor)),
                      const SizedBox(height: 4),
                      DropdownButton<String>(
                        value: () {
                          final canchasDisponibles = canchaProvider.canchas
                              .where((c) => _selectedSede == null || c.sedeId == _selectedSede)
                              .map((c) => c.id)
                              .toList();
                          return canchasDisponibles.contains(_selectedCancha) ? _selectedCancha : null;
                        }(),
                        hint: Text('Todas las canchas', style: GoogleFonts.montserrat(color: _primaryColor)),
                        items: [
                          DropdownMenuItem(value: null, child: Text('Todas las canchas', style: GoogleFonts.montserrat())),
                          ...canchaProvider.canchas
                              .where((cancha) => _selectedSede == null || cancha.sedeId == _selectedSede)
                              .map((cancha) => DropdownMenuItem(
                                    value: cancha.id,
                                    child: Text(cancha.nombre, style: GoogleFonts.montserrat()),
                                  )),
                        ],
                        onChanged: _selectCancha,
                        style: GoogleFonts.montserrat(color: _primaryColor),
                        icon: Icon(Icons.keyboard_arrow_down, color: _secondaryColor),
                        underline: Container(height: 1, color: _disabledColor),
                        isExpanded: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterContent(String formattedDate, SedeProvider sedeProvider, CanchaProvider canchaProvider) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filtros',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear, size: 18),
                label: Text('Limpiar', style: GoogleFonts.montserrat()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade300,
                  foregroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: _secondaryColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fecha', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor)),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _selectDate(context),
                      child: Text(
                        _useDateFilter ? formattedDate : 'Todas las fechas',
                        style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: _primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.store, color: _secondaryColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sede', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor)),
                    const SizedBox(height: 4),
                    DropdownButton<String>(
                      value: _selectedSede,
                      hint: Text('Todas las sedes', style: GoogleFonts.montserrat(color: _primaryColor)),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Todas las sedes', style: GoogleFonts.montserrat()),
                        ),
                        ...sedeProvider.sedes.map((sede) => DropdownMenuItem(
                              value: sede['id'] as String,
                              child: Text(sede['nombre'] as String, style: GoogleFonts.montserrat()),
                            )),
                      ],
                      onChanged: _selectSede,
                      style: GoogleFonts.montserrat(color: _primaryColor),
                      icon: Icon(Icons.keyboard_arrow_down, color: _secondaryColor),
                      underline: Container(height: 1, color: _disabledColor),
                      isExpanded: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.sports_soccer, color: _secondaryColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cancha', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor)),
                    const SizedBox(height: 4),
                    DropdownButton<String>(
                      value: () {
                        final canchasDisponibles = canchaProvider.canchas
                            .where((c) => _selectedSede == null || c.sedeId == _selectedSede)
                            .map((c) => c.id)
                            .toList();
                        return canchasDisponibles.contains(_selectedCancha) ? _selectedCancha : null;
                      }(),
                      hint: Text('Todas las canchas', style: GoogleFonts.montserrat(color: _primaryColor)),
                      items: [
                        DropdownMenuItem(value: null, child: Text('Todas las canchas', style: GoogleFonts.montserrat())),
                        ...canchaProvider.canchas
                            .where((cancha) => _selectedSede == null || cancha.sedeId == _selectedSede)
                            .map((cancha) => DropdownMenuItem(
                                  value: cancha.id,
                                  child: Text(cancha.nombre, style: GoogleFonts.montserrat()),
                                )),
                      ],
                      onChanged: _selectCancha,
                      style: GoogleFonts.montserrat(color: _primaryColor),
                      icon: Icon(Icons.keyboard_arrow_down, color: _secondaryColor),
                      underline: Container(height: 1, color: _disabledColor),
                      isExpanded: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReservasPendientes() {
    return _buildReservasTable(isPendientes: true);
  }

  Widget _buildReservasConfirmadas() {
    final currencyFormat = NumberFormat.currency(symbol: "\$", decimalDigits: 0);
    
    if (_cargandoMasReservas && _reservasConfirmadas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
            ),
            const SizedBox(height: 16),
            Text('Cargando reservas...', style: GoogleFonts.montserrat(color: _primaryColor, fontSize: 16)),
          ],
        ),
      );
    }

    if (_reservasConfirmadas.isEmpty && !_cargandoMasReservas) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'No hay reservas confirmadas',
        subtitle: 'Las reservas aceptadas aparecerán aquí',
      );
    }

    // Ordenar reservas por fecha y hora
    final reservasOrdenadas = List<DocumentSnapshot>.from(_reservasConfirmadas);
    reservasOrdenadas.sort((a, b) {
      final dataA = a.data() as Map<String, dynamic>;
      final dataB = b.data() as Map<String, dynamic>;
      
      // Ordenar por fecha primero
      final fechaA = dataA['fecha'] as String? ?? '';
      final fechaB = dataB['fecha'] as String? ?? '';
      final fechaComparison = fechaA.compareTo(fechaB);
      
      if (fechaComparison != 0) {
        return fechaComparison;
      }
      
      // Si las fechas son iguales, ordenar por hora
      final horaA = dataA['horario'] as String? ?? '0:00';
      final horaB = dataB['horario'] as String? ?? '0:00';
      return horaA.compareTo(horaB);
    });

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _viewTable && MediaQuery.of(context).size.width > 600
          ? _buildDesktopTableConfirmadas(reservasOrdenadas, currencyFormat)
          : _buildMobileListViewConfirmadas(reservasOrdenadas, currencyFormat),
    );
  }


  Widget _buildReservasTable({required bool isPendientes}) {
  final currencyFormat = NumberFormat.currency(symbol: "\$", decimalDigits: 0);

  return StreamBuilder<QuerySnapshot>(
    stream: _buildQueryStream(isPendientes),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
              ),
              const SizedBox(height: 16),
              Text('Cargando reservas...', style: GoogleFonts.montserrat(color: _primaryColor, fontSize: 16)),
            ],
          ),
        );
      }

      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 60, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Error: ${snapshot.error}', style: GoogleFonts.montserrat(color: _primaryColor, fontSize: 16)),
            ],
          ),
        );
      }

      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
        return _buildEmptyState(
          icon: isPendientes ? Icons.pending_actions : Icons.check_circle_outline,
          title: isPendientes ? 'No hay reservas pendientes' : 'No hay reservas confirmadas',
          subtitle: isPendientes
              ? 'Las nuevas reservas aparecerán aquí para su confirmación'
              : 'Las reservas aceptadas aparecerán aquí',
        );
      }

      final docs = snapshot.data!.docs.toList();
      docs.sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;
        
        // Ordenar por fecha primero
        final fechaA = dataA['fecha'] as String? ?? '';
        final fechaB = dataB['fecha'] as String? ?? '';
        final fechaComparison = fechaA.compareTo(fechaB);
        
        if (fechaComparison != 0) {
          return fechaComparison;
        }
        
        // Si las fechas son iguales, ordenar por hora
        final horaA = dataA['horario'] as String? ?? '0:00';
        final horaB = dataB['horario'] as String? ?? '0:00';
        return horaA.compareTo(horaB);
      });

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _viewTable && MediaQuery.of(context).size.width > 600
            ? _buildDesktopTable(docs, isPendientes, currencyFormat)
            : _buildMobileListView(docs, isPendientes, currencyFormat),
      );
    },
  );
}


  Widget _buildMobileListView(List<DocumentSnapshot> docs, bool isPendientes, NumberFormat currencyFormat) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        return Animate(
          effects: [
            FadeEffect(delay: Duration(milliseconds: 50 * (index % 10)), duration: const Duration(milliseconds: 400)),
            SlideEffect(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
              delay: Duration(milliseconds: 50 * (index % 10)),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutQuad,
            ),
          ],
          child: _buildMobileCard(doc, isPendientes, currencyFormat, index),
        );
      },
    );
  }


  Widget _buildMobileListViewConfirmadas(List<DocumentSnapshot> docs, NumberFormat currencyFormat) {
    return ListView.builder(
      controller: _scrollControllerConfirmadas,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: docs.length + (_hayMasReservasConfirmadas ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == docs.length) {
          return _buildLoadingIndicator();
        }
        
        final doc = docs[index];
        return Animate(
          effects: [
            FadeEffect(delay: Duration(milliseconds: 50 * (index % 10)), duration: const Duration(milliseconds: 400)),
            SlideEffect(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
              delay: Duration(milliseconds: 50 * (index % 10)),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutQuad,
            ),
          ],
          child: _buildMobileCard(doc, false, currencyFormat, index),
        );
      },
    );
  }

  Widget _buildDesktopTableConfirmadas(List<DocumentSnapshot> docs, NumberFormat currencyFormat) {
  return Column(
    children: [
      Expanded(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final isSmallDesktop = availableWidth < 800;
              final isMediumDesktop = availableWidth >= 800 && availableWidth < 1200;
              
              return SingleChildScrollView(
                controller: _scrollControllerConfirmadas,
                child: Container(
                  width: availableWidth,
                  child: Column(
                    children: [
                      DataTable(
                        columnSpacing: isSmallDesktop ? 8 : 16,
                        headingRowHeight: 48,
                        dataRowMinHeight: 60,
                        dataRowMaxHeight: 60,
                        headingTextStyle: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w600, 
                          color: _primaryColor, 
                          fontSize: isSmallDesktop ? 12 : 14
                        ),
                        dataTextStyle: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w500, 
                          color: _primaryColor, 
                          fontSize: isSmallDesktop ? 11 : 13
                        ),
                        columns: _buildResponsiveColumns(false, isSmallDesktop, isMediumDesktop),
                        rows: docs.asMap().entries.map((entry) {
                          final index = entry.key;
                          final doc = entry.value;
                          final data = doc.data() as Map<String, dynamic>? ?? {};

                          return DataRow(
                            color: MaterialStateProperty.resolveWith<Color?>(
                              (Set<MaterialState> states) {
                                return index % 2 == 0 ? _cardColor : Colors.white;
                              },
                            ),
                            cells: _buildResponsiveCells(
                              doc, 
                              index, 
                              data, 
                              false, 
                              currencyFormat, 
                              isSmallDesktop, 
                              isMediumDesktop
                            ),
                          );
                        }).toList(),
                      ),
                      if (_hayMasReservasConfirmadas)
                        _buildLoadingIndicator(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}

List<DataColumn> _buildResponsiveColumns(bool isPendientes, bool isSmallDesktop, bool isMediumDesktop) {
  final columns = <DataColumn>[
    DataColumn(
      label: SizedBox(
        width: isSmallDesktop ? 30 : 40,
        child: Text('#', style: GoogleFonts.montserrat())
      )
    ),
    DataColumn(
      label: SizedBox(
        width: isSmallDesktop ? 70 : 90,
        child: Text('Fecha', style: GoogleFonts.montserrat())
      )
    ),
    DataColumn(
      label: SizedBox(
        width: isSmallDesktop ? 80 : 120,
        child: Text('Cancha', style: GoogleFonts.montserrat())
      )
    ),
    DataColumn(
      label: SizedBox(
        width: isSmallDesktop ? 60 : 80,
        child: Text('Hora', style: GoogleFonts.montserrat())
      )
    ),
  ];

  // En pantallas pequeñas, combinamos cliente con totales
  if (isSmallDesktop) {
    columns.add(
      DataColumn(
        label: Expanded(
          child: Text('Cliente / Montos', style: GoogleFonts.montserrat())
        )
      )
    );
  } else {
    columns.addAll([
      DataColumn(
        label: SizedBox(
          width: isMediumDesktop ? 120 : 150,
          child: Text('Cliente', style: GoogleFonts.montserrat())
        )
      ),
      DataColumn(
        label: SizedBox(
          width: 80,
          child: Text('Total', style: GoogleFonts.montserrat())
        ), 
        numeric: true
      ),
      DataColumn(
        label: SizedBox(
          width: 80,
          child: Text('Pagado', style: GoogleFonts.montserrat())
        ), 
        numeric: true
      ),
    ]);
  }

  columns.add(
    DataColumn(
      label: SizedBox(
        width: isSmallDesktop ? 80 : 100,
        child: Text('Estado', style: GoogleFonts.montserrat())
      )
    )
  );

  if (isPendientes) {
    columns.add(
      DataColumn(
        label: SizedBox(
          width: isSmallDesktop ? 90 : 120,
          child: Text('Acciones', style: GoogleFonts.montserrat())
        )
      )
    );
  }

  return columns;
}

List<DataCell> _buildResponsiveCells(
  DocumentSnapshot doc, 
  int index, 
  Map<String, dynamic> data, 
  bool isPendientes, 
  NumberFormat currencyFormat, 
  bool isSmallDesktop, 
  bool isMediumDesktop
) {
  final cells = <DataCell>[
    DataCell(
      SizedBox(
        width: isSmallDesktop ? 30 : 40,
        child: _buildIndexCell(index + 1)
      )
    ),
    DataCell(
      SizedBox(
        width: isSmallDesktop ? 70 : 90,
        child: _buildDateCell(data['fecha']?.toString() ?? '')
      )
    ),
    DataCell(
      SizedBox(
        width: isSmallDesktop ? 80 : 120,
        child: _buildFutureCell(doc, (reserva) => _buildResponsiveCanchaCell(
          reserva?.cancha.nombre ?? data['cancha_nombre']?.toString() ?? 'Sin nombre',
          isSmallDesktop
        ))
      )
    ),
    DataCell(
      SizedBox(
        width: isSmallDesktop ? 60 : 80,
        child: _buildFutureCell(doc, (reserva) => _buildTimeCell(
          reserva?.horario.horaFormateada ?? data['horario']?.toString() ?? 'Sin horario'
        ))
      )
    ),
  ];

  // En pantallas pequeñas, combinamos cliente con montos
  if (isSmallDesktop) {
    cells.add(
      DataCell(
        Expanded(
          child: _buildFutureCell(doc, (reserva) => _buildCombinedClientMoneyCell(
            reserva?.nombre ?? data['nombre']?.toString() ?? 'Sin nombre',
            currencyFormat.format(reserva?.montoTotal ?? data['monto_total'] ?? 0),
            currencyFormat.format(reserva?.montoPagado ?? data['monto_pagado'] ?? 0)
          ))
        )
      )
    );
  } else {
    cells.addAll([
      DataCell(
        SizedBox(
          width: isMediumDesktop ? 120 : 150,
          child: _buildFutureCell(doc, (reserva) => _buildResponsiveClientCell(
            reserva?.nombre ?? data['nombre']?.toString() ?? 'Sin nombre',
            isMediumDesktop
          ))
        )
      ),
      DataCell(
        SizedBox(
          width: 80,
          child: _buildFutureCell(doc, (reserva) => _buildMoneyCell(
            currencyFormat.format(reserva?.montoTotal ?? data['monto_total'] ?? 0), 
            Colors.orange
          ))
        )
      ),
      DataCell(
        SizedBox(
          width: 80,
          child: _buildFutureCell(doc, (reserva) => _buildMoneyCell(
            currencyFormat.format(reserva?.montoPagado ?? data['monto_pagado'] ?? 0), 
            _reservedColor
          ))
        )
      ),
    ]);
  }

  cells.add(
    DataCell(
      SizedBox(
        width: isSmallDesktop ? 80 : 100,
        child: _buildResponsiveStatusChip(isPendientes, isSmallDesktop)
      )
    )
  );

  if (isPendientes) {
    cells.add(
      DataCell(
        SizedBox(
          width: isSmallDesktop ? 90 : 120,
          child: _buildResponsiveDesktopActions(doc.id, isSmallDesktop)
        )
      )
    );
  }

  return cells;
}

Widget _buildResponsiveCanchaCell(String nombre, bool isSmall) {
  return Text(
    nombre,
    style: GoogleFonts.montserrat(
      fontWeight: FontWeight.w600,
      fontSize: isSmall ? 12 : 14,
      color: _primaryColor,
    ),
    overflow: TextOverflow.ellipsis,
    maxLines: isSmall ? 1 : 2,
  );
}

Widget _buildResponsiveClientCell(String nombre, bool isMedium) {
  return Row(
    children: [
      if (!isMedium) ...[
        CircleAvatar(
          radius: 12,
          backgroundColor: _disabledColor,
          child: Text(
            nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              color: _primaryColor,
            ),
          ),
        ),
        const SizedBox(width: 6),
      ],
      Flexible(
        child: Text(
          nombre,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w500,
            fontSize: isMedium ? 12 : 14,
            color: _primaryColor,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    ],
  );
}

Widget _buildCombinedClientMoneyCell(String nombre, String total, String pagado) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        nombre,
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: _primaryColor,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      const SizedBox(height: 2),
      Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                total,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  color: Colors.orange[700],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: _reservedColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                pagado,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  color: _reservedColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}





  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_cargandoMasReservas) ...[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Cargando más reservas...',
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontSize: 14,
              ),
            ),
          ] else if (_hayMasReservasConfirmadas) ...[
            ElevatedButton.icon(
              onPressed: _cargarMasReservasConfirmadas,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('Cargar más', style: GoogleFonts.montserrat()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }





  Widget _buildMobileCard(DocumentSnapshot doc, bool isPendientes, NumberFormat currencyFormat, int index) {
    return FutureBuilder<Reserva?>(
      future: _safeFromFirestore(doc),
      builder: (context, reservaSnapshot) {
        if (reservaSnapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }
        if (reservaSnapshot.hasError) {
          return _buildErrorCard(reservaSnapshot.error.toString());
        }
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final reserva = reservaSnapshot.data;

        return Card(
          elevation: 2,
          color: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        reserva?.cancha.nombre ?? data['cancha_nombre']?.toString() ?? 'Sin nombre',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor,
                        ),
                      ),
                    ),
                    _buildStatusChip(isPendientes),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: _secondaryColor),
                    const SizedBox(width: 8),
                    Text(
                      () {
                        try {
                          final fechaStr = data['fecha']?.toString() ?? '';
                          if (fechaStr.isNotEmpty) {
                            final DateTime date = DateFormat('yyyy-MM-dd').parse(fechaStr);
                            return DateFormat('dd/MM/yyyy').format(date);
                          }
                          return DateFormat('dd/MM/yyyy').format(_selectedDate);
                        } catch (e) {
                          return DateFormat('dd/MM/yyyy').format(_selectedDate);
                        }
                      }(),
                      style: GoogleFonts.montserrat(fontSize: 14, color: _primaryColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: _secondaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cliente: ${reserva?.nombre ?? data['nombre']?.toString() ?? 'Sin nombre'}',
                        style: GoogleFonts.montserrat(fontSize: 14, color: _primaryColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.attach_money, size: 16, color: _secondaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Total: ${currencyFormat.format(reserva?.montoTotal ?? data['monto_total'] ?? 0)}',
                      style: GoogleFonts.montserrat(fontSize: 14, color: _reservedColor),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Pagado: ${currencyFormat.format(reserva?.montoPagado ?? data['monto_pagado'] ?? 0)}',
                      style: GoogleFonts.montserrat(fontSize: 14, color: _reservedColor),
                    ),
                  ],
                ),
                if (isPendientes) ...[
                  const SizedBox(height: 12),
                  _buildActionButtons(doc.id, Provider.of<ReservaProvider>(context, listen: false)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopTable(List<DocumentSnapshot> docs, bool isPendientes, NumberFormat currencyFormat) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.all(8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isSmallDesktop = availableWidth < 800;
        final isMediumDesktop = availableWidth >= 800 && availableWidth < 1200;
        
        return SingleChildScrollView(
          child: Container(
            width: availableWidth,
            child: DataTable(
              columnSpacing: isSmallDesktop ? 8 : 16,
              headingRowHeight: 48,
              dataRowMinHeight: 60,
              dataRowMaxHeight: 60,
              headingTextStyle: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600, 
                color: _primaryColor, 
                fontSize: isSmallDesktop ? 12 : 14
              ),
              dataTextStyle: GoogleFonts.montserrat(
                fontWeight: FontWeight.w500, 
                color: _primaryColor, 
                fontSize: isSmallDesktop ? 11 : 13
              ),
              columns: _buildResponsiveColumns(isPendientes, isSmallDesktop, isMediumDesktop),
              rows: docs.asMap().entries.map((entry) {
                final index = entry.key;
                final doc = entry.value;
                final data = doc.data() as Map<String, dynamic>? ?? {};

                return DataRow(
                  color: MaterialStateProperty.resolveWith<Color?>(
                    (Set<MaterialState> states) {
                      return index % 2 == 0 ? _cardColor : Colors.white;
                    },
                  ),
                  cells: _buildResponsiveCells(
                    doc, 
                    index, 
                    data, 
                    isPendientes, 
                    currencyFormat, 
                    isSmallDesktop, 
                    isMediumDesktop
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    ),
  );
}


  Widget _buildDateCell(String fecha) {
  String fechaFormateada = '';
  try {
    if (fecha.isNotEmpty) {
      final DateTime date = DateFormat('yyyy-MM-dd').parse(fecha);
      fechaFormateada = DateFormat('dd/MM').format(date); // Formato más compacto
    }
  } catch (e) {
    fechaFormateada = fecha;
  }
  
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.blue[50],
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      fechaFormateada,
      style: GoogleFonts.montserrat(
        fontWeight: FontWeight.w600,
        fontSize: 11,
        color: Colors.blue[700],
      ),
      overflow: TextOverflow.ellipsis,
    ),
  );
}

// Nuevo método para el chip de estado responsivo
Widget _buildResponsiveStatusChip(bool isPendientes, bool isSmall) {
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: isSmall ? 6 : 10, 
      vertical: isSmall ? 3 : 5
    ),
    decoration: BoxDecoration(
      color: isPendientes ? Colors.orange[100] : _reservedColor.withOpacity(0.1),
      borderRadius: BorderRadius.circular(isSmall ? 12 : 16),
      border: Border.all(
        color: isPendientes ? Colors.orange[300]! : _reservedColor,
        width: 1,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: isSmall ? 6 : 8,
          height: isSmall ? 6 : 8,
          decoration: BoxDecoration(
            color: isPendientes ? Colors.orange[600] : _reservedColor,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: isSmall ? 3 : 6),
        Flexible(
          child: Text(
            isPendientes ? 'Pendiente' : (isSmall ? 'OK' : 'Confirmada'),
            style: GoogleFonts.montserrat(
              fontSize: isSmall ? 9 : 11,
              fontWeight: FontWeight.w600,
              color: isPendientes ? Colors.orange[800] : _reservedColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// Nuevo método para acciones responsivas
Widget _buildResponsiveDesktopActions(String reservaId, bool isSmall) {
  final provider = Provider.of<ReservaProvider>(context, listen: false);
  
  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        icon: Icon(Icons.close_rounded, size: isSmall ? 16 : 18),
        tooltip: 'Rechazar',
        onPressed: _isLoading ? null : () => _rechazarReserva(reservaId, provider),
        style: IconButton.styleFrom(
          backgroundColor: Colors.red[50],
          foregroundColor: Colors.red[600],
          padding: EdgeInsets.all(isSmall ? 6 : 8),
          minimumSize: Size(isSmall ? 28 : 32, isSmall ? 28 : 32),
        ),
      ),
      SizedBox(width: isSmall ? 4 : 8),
      IconButton(
        icon: Icon(Icons.check_rounded, size: isSmall ? 16 : 18),
        tooltip: 'Aceptar',
        onPressed: _isLoading ? null : () => _aceptarReserva(reservaId, provider),
        style: IconButton.styleFrom(
          backgroundColor: _reservedColor.withOpacity(0.1),
          foregroundColor: _reservedColor,
          padding: EdgeInsets.all(isSmall ? 6 : 8),
          minimumSize: Size(isSmall ? 28 : 32, isSmall ? 28 : 32),
        ),
      ),
    ],
  );
}




  Widget _buildStatusChip(bool isPendientes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPendientes ? Colors.orange[100] : _reservedColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPendientes ? Colors.orange[300]! : _reservedColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isPendientes ? Colors.orange[600] : _reservedColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isPendientes ? 'Pendiente' : 'Confirmada',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isPendientes ? Colors.orange[800] : _reservedColor,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildActionButtons(String reservaId, ReservaProvider provider) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _rechazarReserva(reservaId, provider),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text('Rechazar', style: GoogleFonts.montserrat()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[50],
              foregroundColor: Colors.red[700],
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.red[200]!),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _aceptarReserva(reservaId, provider),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text('Aceptar', style: GoogleFonts.montserrat()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _reservedColor,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              shadowColor: Colors.green[200],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndexCell(int index) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _secondaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          '#$index',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: _secondaryColor,
          ),
        ),
      ),
    );
  }


  Widget _buildTimeCell(String hora) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _secondaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        hora,
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: _secondaryColor,
        ),
      ),
    );
  }


  Widget _buildMoneyCell(String amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        amount,
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFutureCell(DocumentSnapshot doc, Widget Function(Reserva?) builder) {
    return FutureBuilder<Reserva?>(
      future: _safeFromFirestore(doc),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return builder(snapshot.data);
      },
    );
  }

  Future<Reserva?> _safeFromFirestore(DocumentSnapshot doc) async {
    try {
      return await Reserva.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error al crear Reserva desde Firestore: $e');
      return null;
    }
  }

  Widget _buildLoadingCard() {
    return Card(
      elevation: 2,
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      elevation: 2,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red[200]!, width: 1),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $error', style: GoogleFonts.montserrat(color: Colors.red[600])),
      ),
    );
  }


  Stream<QuerySnapshot> _buildQueryStream(bool isPendientes) {
  debugPrint('Consulta Firestore - useDateFilter: $_useDateFilter, sede: $_selectedSede, cancha: $_selectedCancha');
  
  Query query = FirebaseFirestore.instance
      .collection('reservas')
      .where('confirmada', isEqualTo: isPendientes ? false : true);

  // Solo aplicar filtro de fecha si está activo
  if (_useDateFilter) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    query = query.where('fecha', isEqualTo: dateStr);
    debugPrint('Aplicando filtro de fecha: $dateStr');
  }

  if (_selectedSede != null) {
    query = query.where('sede', isEqualTo: _selectedSede);
  }
  if (_selectedCancha != null) {
    query = query.where('cancha_id', isEqualTo: _selectedCancha);
  }

  return query.snapshots();
}


  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.montserrat(color: _primaryColor, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.montserrat(color: Colors.grey[600], fontSize: 14, height: 1.5),
            textAlign: TextAlign.center,
          ),
          TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.refresh),
            label: Text('Limpiar filtros', style: GoogleFonts.montserrat()),
          ),
        ],
      ),
    );
  }
}