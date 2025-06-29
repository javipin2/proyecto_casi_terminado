import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/reserva.dart';
import '../../../../providers/cancha_provider.dart';
import '../../../../providers/sede_provider.dart';

class AdminRegistroReservasScreen extends StatefulWidget {
  const AdminRegistroReservasScreen({super.key});

  @override
  AdminRegistroReservasScreenState createState() =>
      AdminRegistroReservasScreenState();
}

class AdminRegistroReservasScreenState
    extends State<AdminRegistroReservasScreen> with TickerProviderStateMixin {
  List<Reserva> _reservas = [];
  DateTime? _selectedDate;
  String? _selectedSedeId;
  String? _selectedCanchaId;
  String? _selectedEstado;
  bool _isLoading = false;
  bool _viewTable = true;
  bool _filtersVisible = true; // Por defecto visible en pantallas grandes

  late AnimationController _fadeController;
  late AnimationController _slideController;

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
    _selectedDate = DateTime.now(); // Fecha actual por defecto (28/06/2025, 04:18 PM -05)
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReservas();
      _fadeController.forward();
      _slideController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadReservas() async {
    await _loadReservasWithFilters();
  }

  Future<void> _loadReservasWithFilters() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _reservas.clear();
    });
    try {
      final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
      await Future.wait([
        canchaProvider.fetchAllCanchas(),
        canchaProvider.fetchHorasReservadas(),
        sedeProvider.fetchSedes(),
      ]);

      final canchasMap = {
        for (var cancha in canchaProvider.canchas) cancha.id: cancha
      };

      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('reservas')
          .limit(50);

      if (_selectedDate != null) {
        final String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
        query = query.where('fecha', isEqualTo: dateStr);
      }

      if (_selectedSedeId != null) {
        query = query.where('sede', isEqualTo: _selectedSedeId);
      }

      if (_selectedCanchaId != null) {
        query = query.where('cancha_id', isEqualTo: _selectedCanchaId);
      }

      if (_selectedEstado != null && _selectedEstado != 'todos') {
        query = query.where('estado', isEqualTo: _selectedEstado);
      }

      QuerySnapshot querySnapshot = await query
          .get()
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw TimeoutException('La consulta a Firestore tardó demasiado');
          });

      List<Reserva> reservasTemp = [];
      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null ||
              !data.containsKey('fecha') ||
              !data.containsKey('cancha_id') ||
              !data.containsKey('sede') ||
              !data.containsKey('horario')) {
            continue;
          }

          final reserva = Reserva.fromFirestoreWithCanchas(doc, canchasMap);
          if (reserva.cancha.id.isNotEmpty) {
            reservasTemp.add(reserva);
          }
        } catch (e) {
          debugPrint('Error al procesar documento: $e');
        }
      }

      if (mounted) {
        setState(() {
          _reservas = reservasTemp..sort((a, b) => a.horario.hora.compareTo(b.horario.hora));
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

  Future<void> _selectDate(BuildContext context) async {
    final newDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
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
    if (newDate != null && mounted) {
      setState(() {
        _selectedDate = newDate;
        _selectedCanchaId = null;
      });
      await _loadReservasWithFilters();
    }
  }

  void _selectSede(String? sedeId) {
    if (!mounted) return;
    setState(() {
      _selectedSedeId = sedeId;
      if (_selectedCanchaId != null) {
        final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
        final canchaExists = canchaProvider.canchas
            .any((c) => c.id == _selectedCanchaId && c.sedeId == sedeId);
        if (!canchaExists) {
          _selectedCanchaId = null;
        }
      }
    });
    _loadReservasWithFilters();
  }

  void _selectCancha(String? canchaId) {
    if (!mounted) return;
    setState(() {
      _selectedCanchaId = canchaId;
    });
    _loadReservasWithFilters();
  }

  void _selectEstado(String? estado) {
    if (!mounted) return;
    setState(() {
      _selectedEstado = estado;
    });
    _loadReservasWithFilters();
  }

  void _clearFilters() {
    if (!mounted) return;
    setState(() {
      _selectedDate = DateTime.now();
      _selectedSedeId = null;
      _selectedCanchaId = null;
      _selectedEstado = null;
    });
    _loadReservasWithFilters();
  }

  Future<void> _editReserva(Reserva reserva) async {
    if (!mounted) return;
    final _formKey = GlobalKey<FormState>();
    final nombreController = TextEditingController(text: reserva.nombre ?? '');
    final telefonoController = TextEditingController(text: reserva.telefono ?? '');
    final emailController = TextEditingController(text: reserva.email ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Editar Reserva', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nombreController,
                  decoration: InputDecoration(
                    labelText: 'Nombre',
                    prefixIcon: Icon(Icons.person, color: _secondaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: GoogleFonts.montserrat(color: _primaryColor),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Ingrese el nombre' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: telefonoController,
                  decoration: InputDecoration(
                    labelText: 'Teléfono',
                    prefixIcon: Icon(Icons.phone, color: _secondaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: GoogleFonts.montserrat(color: _primaryColor),
                  keyboardType: TextInputType.phone,
                  validator: (value) => value == null || value.trim().isEmpty ? 'Ingrese el teléfono' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Correo',
                    prefixIcon: Icon(Icons.email, color: _secondaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: GoogleFonts.montserrat(color: _primaryColor),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    return emailRegex.hasMatch(value) ? null : 'Ingrese un correo válido';
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _secondaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Guardar', style: GoogleFonts.montserrat(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('reservas')
            .doc(reserva.id)
            .update({
          'nombre': nombreController.text.trim(),
          'telefono': telefonoController.text.trim(),
          'correo': emailController.text.trim(),
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('Reserva actualizada correctamente', style: GoogleFonts.montserrat(color: Colors.white)),
              ],
            ),
            backgroundColor: _reservedColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ),
        );
        await _loadReservasWithFilters();
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Error al editar reserva: $e');
        }
      }
    }

    nombreController.dispose();
    telefonoController.dispose();
    emailController.dispose();
  }

  Future<void> _completarPago(Reserva reserva) async {
    if (!mounted) return;
    final _formKey = GlobalKey<FormState>();
    final montoController = TextEditingController(text: reserva.montoTotal.toString());

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Completar Pago', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reserva para ${reserva.cancha.nombre} el ${DateFormat('dd/MM/yyyy').format(reserva.fecha)} a las ${reserva.horario.horaFormateada}',
                  style: GoogleFonts.montserrat(color: _primaryColor),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: montoController,
                  decoration: InputDecoration(
                    labelText: 'Monto Pagado',
                    prefixIcon: Icon(Icons.attach_money, color: _secondaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: GoogleFonts.montserrat(color: _primaryColor),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingrese el monto';
                    }
                    final monto = double.tryParse(value);
                    if (monto == null || monto <= 0) {
                      return 'Ingrese un monto válido';
                    }
                    if (monto > reserva.montoTotal) {
                      return 'El monto no puede exceder el total (${reserva.montoTotal})';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _reservedColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Confirmar', style: GoogleFonts.montserrat(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final nuevoMonto = double.parse(montoController.text.trim());
        await FirebaseFirestore.instance
            .collection('reservas')
            .doc(reserva.id)
            .update({
          'montoPagado': nuevoMonto,
          'estado': nuevoMonto >= reserva.montoTotal ? 'completo' : 'parcial',
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('Pago actualizado correctamente', style: GoogleFonts.montserrat(color: Colors.white)),
              ],
            ),
            backgroundColor: _reservedColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ),
        );
        await _loadReservasWithFilters();
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Error al actualizar pago: $e');
        }
      }
    }

    montoController.dispose();
  }

  Future<void> _deleteReserva(String reservaId) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Text('Eliminar Reserva', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
            content: Text('¿Estás seguro de eliminar esta reserva?', style: GoogleFonts.montserrat()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancelar', style: GoogleFonts.montserrat(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Eliminar', style: GoogleFonts.montserrat(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('reservas')
            .doc(reservaId)
            .delete();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('Reserva eliminada correctamente', style: GoogleFonts.montserrat(color: Colors.white)),
              ],
            ),
            backgroundColor: _reservedColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ),
        );
        await _loadReservasWithFilters();
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Error al eliminar reserva: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Registro de Reservas', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
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
      ),
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width > 600)
            AnimatedContainer(
              width: _filtersVisible ? 300 : 0,
              duration: const Duration(milliseconds: 300),
              child: _filtersVisible
                  ? _buildFilterPanel()
                  : const SizedBox.shrink(),
            ),
          Expanded(
            child: Container(
              color: _backgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (MediaQuery.of(context).size.width <= 600)
                      _buildFilterToggle(),
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
                          : _reservas.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.event_busy, size: 60, color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text(
                                        _selectedDate == null &&
                                                _selectedSedeId == null &&
                                                _selectedCanchaId == null &&
                                                _selectedEstado == null
                                            ? 'No hay reservas para hoy. Verifica los datos en Firestore.'
                                            : 'No hay reservas que coincidan con los filtros.',
                                        style: GoogleFonts.montserrat(color: _primaryColor, fontSize: 16),
                                        textAlign: TextAlign.center,
                                      ),
                                      TextButton.icon(
                                        onPressed: _clearFilters,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Limpiar filtros'),
                                      ),
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
                                  child: _viewTable && MediaQuery.of(context).size.width > 600
                                      ? _buildDataTable()
                                      : _buildListView(),
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

  Widget _buildFilterToggle() {
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
                    child: _buildFilterContent(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
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
                  label: const Text('Limpiar'),
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
                          _selectedDate == null ? 'Hoy' : DateFormat('EEEE d MMMM, yyyy', 'es').format(_selectedDate!),
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
                        value: _selectedSedeId,
                        hint: Text('Todas las sedes', style: GoogleFonts.montserrat(color: _primaryColor)),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text('Todas las sedes', style: GoogleFonts.montserrat()),
                          ),
                          ...Provider.of<SedeProvider>(context, listen: false).sedes.map((sede) => DropdownMenuItem(
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
                        value: _selectedCanchaId,
                        hint: Text('Todas las canchas', style: GoogleFonts.montserrat(color: _primaryColor)),
                        items: [
                          DropdownMenuItem(value: null, child: Text('Todas las canchas', style: GoogleFonts.montserrat())),
                          ...Provider.of<CanchaProvider>(context, listen: false).canchas
                              .where((cancha) => _selectedSedeId == null || cancha.sedeId == _selectedSedeId)
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
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.payment, color: _secondaryColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estado', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor)),
                      const SizedBox(height: 4),
                      DropdownButton<String>(
                        value: _selectedEstado,
                        hint: Text('Todos los estados', style: GoogleFonts.montserrat(color: _primaryColor)),
                        items: [
                          DropdownMenuItem(value: null, child: Text('Todos los estados', style: GoogleFonts.montserrat())),
                          DropdownMenuItem(value: 'completo', child: Text('Completo', style: GoogleFonts.montserrat())),
                          DropdownMenuItem(value: 'parcial', child: Text('Parcial', style: GoogleFonts.montserrat())),
                        ],
                        onChanged: _selectEstado,
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

  Widget _buildFilterContent() {
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final canchas = _selectedSedeId == null
        ? canchaProvider.canchas
        : canchaProvider.canchas.where((cancha) => cancha.sedeId == _selectedSedeId).toList();

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
                label: const Text('Limpiar'),
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
                        _selectedDate == null ? 'Hoy' : DateFormat('EEEE d MMMM, yyyy', 'es').format(_selectedDate!),
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
                      value: _selectedSedeId,
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
                      value: _selectedCanchaId,
                      hint: Text('Todas las canchas', style: GoogleFonts.montserrat(color: _primaryColor)),
                      items: [
                        DropdownMenuItem(value: null, child: Text('Todas las canchas', style: GoogleFonts.montserrat())),
                        ...canchas.map((cancha) => DropdownMenuItem(
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
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.payment, color: _secondaryColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estado', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor)),
                    const SizedBox(height: 4),
                    DropdownButton<String>(
                      value: _selectedEstado,
                      hint: Text('Todos los estados', style: GoogleFonts.montserrat(color: _primaryColor)),
                      items: [
                        DropdownMenuItem(value: null, child: Text('Todos los estados', style: GoogleFonts.montserrat())),
                        DropdownMenuItem(value: 'completo', child: Text('Completo', style: GoogleFonts.montserrat())),
                        DropdownMenuItem(value: 'parcial', child: Text('Parcial', style: GoogleFonts.montserrat())),
                      ],
                      onChanged: _selectEstado,
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

  Widget _buildDataTable() {
    final currencyFormat = NumberFormat.currency(symbol: "\$", decimalDigits: 0);
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          headingRowHeight: 48,
          dataRowMinHeight: 60,
          dataRowMaxHeight: 60,
          headingTextStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, color: _primaryColor, fontSize: 14),
          dataTextStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w500, color: _primaryColor, fontSize: 13),
          columns: const [
            DataColumn(label: Text('Cancha')),
            DataColumn(label: Text('Sede')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Hora')),
            DataColumn(label: Text('Cliente')),
            DataColumn(label: Text('Teléfono')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Abono')),
            DataColumn(label: Text('Restante')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: _reservas.asMap().entries.map((entry) {
            final reserva = entry.value;
            final montoRestante = reserva.montoTotal - reserva.montoPagado;
            final horaReserva = reserva.horario.hora;
            final horasReservadas = canchaProvider.horasReservadasPorCancha(reserva.cancha.id);
            final isReserved = horasReservadas[reserva.fecha]?.contains(horaReserva) ?? false;

            return DataRow(
              cells: [
                DataCell(Text(reserva.cancha.nombre, style: GoogleFonts.montserrat(fontSize: 13))),
                DataCell(Text(
                  sedeProvider.sedes.firstWhere(
                    (sede) => sede['id'] == reserva.sede,
                    orElse: () => {'nombre': 'Sede desconocida'},
                  )['nombre'] as String,
                  style: GoogleFonts.montserrat(fontSize: 13),
                )),
                DataCell(Text(DateFormat('dd/MM/yyyy').format(reserva.fecha), style: GoogleFonts.montserrat(fontSize: 13))),
                DataCell(Text(
                  '${reserva.horario.horaFormateada} ${isReserved ? '(Reservada)' : ''}',
                  style: GoogleFonts.montserrat(fontSize: 13, color: isReserved ? Colors.red : null),
                )),
                DataCell(Text(reserva.nombre ?? 'N/A', style: GoogleFonts.montserrat(fontSize: 13))),
                DataCell(Text(reserva.telefono ?? 'N/A', style: GoogleFonts.montserrat(fontSize: 13))),
                DataCell(Text(reserva.email ?? 'N/A', style: GoogleFonts.montserrat(fontSize: 13))),
                DataCell(Text(currencyFormat.format(reserva.montoPagado), style: GoogleFonts.montserrat(fontSize: 13, color: _reservedColor))),
                DataCell(Text(
                  currencyFormat.format(montoRestante),
                  style: GoogleFonts.montserrat(fontSize: 13, color: montoRestante > 0 ? Colors.redAccent : _reservedColor),
                )),
                DataCell(Text(
                  reserva.tipoAbono == TipoAbono.completo ? 'Completo' : 'Parcial',
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    color: reserva.tipoAbono == TipoAbono.completo ? _reservedColor : Colors.orange,
                  ),
                )),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Editar datos del cliente',
                      child: IconButton(
                        icon: Icon(Icons.edit, size: 18, color: _secondaryColor),
                        onPressed: () => _editReserva(reserva),
                      ),
                    ),
                    if (reserva.tipoAbono == TipoAbono.parcial)
                      Tooltip(
                        message: 'Completar pago',
                        child: IconButton(
                          icon: Icon(Icons.attach_money, size: 18, color: _reservedColor),
                          onPressed: () => _completarPago(reserva),
                        ),
                      ),
                    Tooltip(
                      message: 'Eliminar reserva',
                      child: IconButton(
                        icon: Icon(Icons.delete, size: 18, color: Colors.redAccent),
                        onPressed: () => _deleteReserva(reserva.id),
                      ),
                    ),
                  ],
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildListView() {
    final currencyFormat = NumberFormat.currency(symbol: "\$", decimalDigits: 0);
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    return ListView.builder(
      itemCount: _reservas.length,
      itemBuilder: (context, index) {
        final reserva = _reservas[index];
        final montoRestante = reserva.montoTotal - reserva.montoPagado;
        final horaReserva = reserva.horario.hora;
        final horasReservadas = canchaProvider.horasReservadasPorCancha(reserva.cancha.id);
        final isReserved = horasReservadas[reserva.fecha]?.contains(horaReserva) ?? false;

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
          child: Card(
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
                          '${reserva.cancha.nombre} - ${sedeProvider.sedes.firstWhere(
                                (sede) => sede['id'] == reserva.sede,
                                orElse: () => {'nombre': 'Sede desconocida'},
                              )['nombre'] as String}',
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _primaryColor,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Editar datos del cliente',
                            child: IconButton(
                              icon: Icon(Icons.edit, size: 18, color: _secondaryColor),
                              onPressed: () => _editReserva(reserva),
                            ),
                          ),
                          if (reserva.tipoAbono == TipoAbono.parcial)
                            Tooltip(
                              message: 'Completar pago',
                              child: IconButton(
                                icon: Icon(Icons.attach_money, size: 18, color: _reservedColor),
                                onPressed: () => _completarPago(reserva),
                              ),
                            ),
                          Tooltip(
                            message: 'Eliminar reserva',
                            child: IconButton(
                              icon: Icon(Icons.delete, size: 18, color: Colors.redAccent),
                              onPressed: () => _deleteReserva(reserva.id),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: _secondaryColor),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('dd/MM/yyyy').format(reserva.fecha),
                        style: GoogleFonts.montserrat(fontSize: 14, color: _primaryColor),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.access_time, size: 16, color: _secondaryColor),
                      const SizedBox(width: 8),
                      Text(
                        '${reserva.horario.horaFormateada} ${isReserved ? '(Reservada)' : ''}',
                        style: GoogleFonts.montserrat(fontSize: 14, color: isReserved ? Colors.red : _secondaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: _secondaryColor),
                      const SizedBox(width: 8),
                      Text('Cliente: ${reserva.nombre ?? 'N/A'}', style: GoogleFonts.montserrat(fontSize: 14, color: _primaryColor)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 16, color: _secondaryColor),
                      const SizedBox(width: 8),
                      Text('Teléfono: ${reserva.telefono ?? 'N/A'}', style: GoogleFonts.montserrat(fontSize: 14, color: _primaryColor)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.email, size: 16, color: _secondaryColor),
                      const SizedBox(width: 8),
                      Text('Email: ${reserva.email ?? 'N/A'}', style: GoogleFonts.montserrat(fontSize: 14, color: _primaryColor)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.attach_money, size: 16, color: _secondaryColor),
                      const SizedBox(width: 8),
                      Text('Abono: ${currencyFormat.format(reserva.montoPagado)}', style: GoogleFonts.montserrat(fontSize: 14, color: _reservedColor)),
                      const SizedBox(width: 16),
                      Text('Restante: ${currencyFormat.format(montoRestante)}', style: GoogleFonts.montserrat(fontSize: 14, color: montoRestante > 0 ? Colors.redAccent : _reservedColor)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info, size: 16, color: _secondaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Estado: ${reserva.tipoAbono == TipoAbono.completo ? 'Completo' : 'Parcial'}',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: reserva.tipoAbono == TipoAbono.completo ? _reservedColor : Colors.orange,
                        ),
                      ),
                    ],
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