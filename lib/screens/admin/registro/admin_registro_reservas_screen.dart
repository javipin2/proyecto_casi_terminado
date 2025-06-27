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
  bool _isLoading = false;
  bool _viewTable = true;

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

      Query<Map<String, dynamic>> query =
          FirebaseFirestore.instance.collection('reservas');

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

      QuerySnapshot querySnapshot = await query
          .get()
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw TimeoutException('La consulta a Firestore tardó demasiado');
          });

      print(
          'Reservas encontradas para sedeId=$_selectedSedeId, canchaId=$_selectedCanchaId, fecha=${_selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : "todas"}: ${querySnapshot.docs.length}');
      for (var doc in querySnapshot.docs) {
        print('Reserva ${doc.id}: ${doc.data()}');
      }

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
    if (!mounted) return;
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
              style: TextButton.styleFrom(
                foregroundColor: _secondaryColor,
              ),
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
      // Resetear cancha si no pertenece a la nueva sede
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

  void _clearFilters() {
    if (!mounted) return;
    setState(() {
      _selectedDate = null;
      _selectedSedeId = null;
      _selectedCanchaId = null;
    });
    _loadReservasWithFilters();
  }

  Future<void> _editReserva(Reserva reserva) async {
    if (!mounted) return;
    final nombreController = TextEditingController(text: reserva.nombre ?? '');
    final telefonoController =
        TextEditingController(text: reserva.telefono ?? '');
    final emailController = TextEditingController(text: reserva.email ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar Reserva', style: GoogleFonts.montserrat()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nombreController,
                  decoration: InputDecoration(labelText: 'Nombre')),
              TextField(
                  controller: telefonoController,
                  decoration: InputDecoration(labelText: 'Teléfono'),
                  keyboardType: TextInputType.phone),
              TextField(
                  controller: emailController,
                  decoration: InputDecoration(labelText: 'Correo'),
                  keyboardType: TextInputType.emailAddress),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Guardar', style: GoogleFonts.montserrat()),
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

  Future<void> _deleteReserva(String reservaId) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Eliminar Reserva', style: GoogleFonts.montserrat()),
            content: Text('¿Estás seguro de eliminar esta reserva?',
                style: GoogleFonts.montserrat()),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancelar', style: GoogleFonts.montserrat())),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Eliminar', style: GoogleFonts.montserrat())),
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
        title: Text('Registro de Reservas',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
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
                    _viewTable
                        ? Icons.view_list_rounded
                        : Icons.table_chart_rounded,
                    color: _secondaryColor),
                onPressed: _toggleView,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: _backgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Animate(
                effects: [
                  FadeEffect(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutQuad),
                  SlideEffect(
                      begin: const Offset(0, -0.2),
                      end: Offset.zero,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutQuad),
                ],
                child: _buildFilterSection(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    _secondaryColor)),
                            const SizedBox(height: 16),
                            Text('Cargando reservas...',
                                style: GoogleFonts.montserrat(
                                    color: _primaryColor, fontSize: 16)),
                          ],
                        ),
                      )
                    : _reservas.isEmpty
                        ? Center(
                            child: Text(
                              _selectedDate == null &&
                                      _selectedSedeId == null &&
                                      _selectedCanchaId == null
                                  ? 'No hay reservas para hoy. Verifica los datos en Firestore.'
                                  : 'No hay reservas que coincidan con los filtros seleccionados.',
                              style: GoogleFonts.montserrat(color: _primaryColor),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            switchInCurve: Curves.easeInOut,
                            switchOutCurve: Curves.easeInOut,
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              return FadeTransition(
                                  opacity: animation, child: child);
                            },
                            child: _viewTable &&
                                    MediaQuery.of(context).size.width > 600
                                ? _buildDataTable()
                                : _buildListView(),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    final canchaProvider = Provider.of<CanchaProvider>(context);
    final sedeProvider = Provider.of<SedeProvider>(context);
    final canchas = _selectedSedeId == null
        ? canchaProvider.canchas
        : canchaProvider.canchas
            .where((cancha) => cancha.sedeId == _selectedSedeId)
            .toList();

    if (canchas.isEmpty && _selectedSedeId != null) {
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
                'No hay canchas disponibles para la sede seleccionada',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    color: _secondaryColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Filtrar por Fecha',
                          style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color.fromRGBO(60, 64, 67, 0.6))),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _selectDate(context),
                        child: Text(
                          _selectedDate == null
                              ? 'Hoy'
                              : DateFormat('EEEE d MMMM, yyyy', 'es')
                                  .format(_selectedDate!),
                          style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedDate != null)
                  IconButton(
                      icon: Icon(Icons.clear, color: Colors.redAccent),
                      onPressed: _clearFilters,
                      tooltip: 'Limpiar filtros'),
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
                      Text('Filtrar por Sede',
                          style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color.fromRGBO(60, 64, 67, 0.6))),
                      const SizedBox(height: 4),
                      DropdownButton<String>(
                        value: _selectedSedeId,
                        hint: Text('Todas las sedes',
                            style: GoogleFonts.montserrat(color: _primaryColor)),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text('Todas las sedes',
                                style: GoogleFonts.montserrat()),
                          ),
                          ...sedeProvider.sedes.map((sede) => DropdownMenuItem(
                                value: sede['id'] as String,
                                child: Text(sede['nombre'] as String,
                                    style: GoogleFonts.montserrat()),
                              )),
                        ],
                        onChanged: _selectSede,
                        style: GoogleFonts.montserrat(color: _primaryColor),
                        icon: Icon(Icons.keyboard_arrow_down,
                            color: _secondaryColor),
                        underline: Container(height: 1, color: _disabledColor),
                        isExpanded: true,
                      ),
                    ],
                  ),
                ),
                if (_selectedSedeId != null)
                  IconButton(
                      icon: Icon(Icons.clear, color: Colors.redAccent),
                      onPressed: _clearFilters,
                      tooltip: 'Limpiar filtros'),
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
                      Text('Filtrar por Cancha',
                          style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color.fromRGBO(60, 64, 67, 0.6))),
                      const SizedBox(height: 4),
                      DropdownButton<String>(
                        value: _selectedCanchaId,
                        hint: Text('Todas las canchas',
                            style: GoogleFonts.montserrat(color: _primaryColor)),
                        items: [
                          DropdownMenuItem(
                              value: null,
                              child: Text('Todas las canchas',
                                  style: GoogleFonts.montserrat())),
                          ...canchas.map((cancha) => DropdownMenuItem(
                              value: cancha.id,
                              child: Text(cancha.nombre,
                                  style: GoogleFonts.montserrat()))),
                        ],
                        onChanged: _selectCancha,
                        style: GoogleFonts.montserrat(color: _primaryColor),
                        icon: Icon(Icons.keyboard_arrow_down,
                            color: _secondaryColor),
                        underline: Container(height: 1, color: _disabledColor),
                        isExpanded: true,
                      ),
                    ],
                  ),
                ),
                if (_selectedCanchaId != null)
                  IconButton(
                      icon: Icon(Icons.clear, color: Colors.redAccent),
                      onPressed: _clearFilters,
                      tooltip: 'Limpiar filtros'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    final currencyFormat =
        NumberFormat.currency(symbol: "\$", decimalDigits: 0);
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          headingRowHeight: 56,
          dataRowMinHeight: 72,
          dataRowMaxHeight: 72,
          headingTextStyle: GoogleFonts.montserrat(
              fontWeight: FontWeight.w600, color: _primaryColor, fontSize: 14),
          dataTextStyle: GoogleFonts.montserrat(
              fontWeight: FontWeight.w500, color: _primaryColor, fontSize: 13),
          columns: const [
            DataColumn(label: Text('Cancha')),
            DataColumn(label: Text('Sede')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Horario')),
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
            final horasReservadas =
                canchaProvider.horasReservadasPorCancha(reserva.cancha.id);
            final isReserved =
                horasReservadas[reserva.fecha]?.contains(horaReserva) ?? false;

            return DataRow(
              cells: [
                DataCell(Text(reserva.cancha.nombre)),
                DataCell(Text(
                  sedeProvider.sedes.firstWhere(
                    (sede) => sede['id'] == reserva.sede,
                    orElse: () => {'nombre': reserva.sede},
                  )['nombre'] as String,
                )),
                DataCell(Text(DateFormat('dd/MM/yyyy').format(reserva.fecha))),
                DataCell(Text(
                    '${reserva.horario.horaFormateada} ${isReserved ? '(Reservada)' : ''}',
                    style: TextStyle(color: isReserved ? Colors.red : null))),
                DataCell(Text(reserva.nombre ?? 'N/A')),
                DataCell(Text(reserva.telefono ?? 'N/A')),
                DataCell(Text(reserva.email ?? 'N/A')),
                DataCell(Text(currencyFormat.format(reserva.montoPagado),
                    style: TextStyle(color: _reservedColor))),
                DataCell(Text(currencyFormat.format(montoRestante),
                    style: TextStyle(
                        color: montoRestante > 0
                            ? Colors.redAccent
                            : _reservedColor))),
                DataCell(Text(
                    reserva.tipoAbono == TipoAbono.completo
                        ? 'Completo'
                        : 'Parcial',
                    style: TextStyle(
                        color: reserva.tipoAbono == TipoAbono.completo
                            ? _reservedColor
                            : Colors.orange))),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: Icon(Icons.edit, color: _secondaryColor),
                        onPressed: () => _editReserva(reserva)),
                    IconButton(
                        icon: Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => _deleteReserva(reserva.id)),
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
    final currencyFormat =
        NumberFormat.currency(symbol: "\$", decimalDigits: 0);
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    return ListView.builder(
      itemCount: _reservas.length,
      itemBuilder: (context, index) {
        final reserva = _reservas[index];
        final montoRestante = reserva.montoTotal - reserva.montoPagado;
        final horaReserva = reserva.horario.hora;
        final horasReservadas =
            canchaProvider.horasReservadasPorCancha(reserva.cancha.id);
        final isReserved =
            horasReservadas[reserva.fecha]?.contains(horaReserva) ?? false;

        return Animate(
          effects: [
            FadeEffect(
                delay: Duration(milliseconds: 50 * (index % 10)),
                duration: const Duration(milliseconds: 400)),
            SlideEffect(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
                delay: Duration(milliseconds: 50 * (index % 10)),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutQuad),
          ],
          child: Card(
            elevation: 0,
            color: _cardColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(
                '${reserva.cancha.nombre} - ${sedeProvider.sedes.firstWhere(
                      (sede) => sede['id'] == reserva.sede,
                      orElse: () => {'nombre': reserva.sede},
                    )['nombre'] as String}',
                style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _primaryColor),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                      'Fecha: ${DateFormat('dd/MM/yyyy').format(reserva.fecha)}',
                      style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: Color.fromRGBO(60, 64, 67, 0.8))),
                  Text(
                      'Horario: ${reserva.horario.horaFormateada} ${isReserved ? '(Reservada)' : ''}',
                      style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: isReserved
                              ? Colors.red
                              : Color.fromRGBO(60, 64, 67, 0.8))),
                  Text('Cliente: ${reserva.nombre ?? 'N/A'}',
                      style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: Color.fromRGBO(60, 64, 67, 0.8))),
                  Text('Teléfono: ${reserva.telefono ?? 'N/A'}',
                      style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: Color.fromRGBO(60, 64, 67, 0.8))),
                  Text('Email: ${reserva.email ?? 'N/A'}',
                      style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: Color.fromRGBO(60, 64, 67, 0.8))),
                  Text('Abono: ${currencyFormat.format(reserva.montoPagado)}',
                      style: GoogleFonts.montserrat(
                          fontSize: 14, color: _reservedColor)),
                  Text('Restante: ${currencyFormat.format(montoRestante)}',
                      style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: montoRestante > 0
                              ? Colors.redAccent
                              : _reservedColor)),
                  Text(
                      'Estado: ${reserva.tipoAbono == TipoAbono.completo ? 'Completo' : 'Parcial'}',
                      style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: reserva.tipoAbono == TipoAbono.completo
                              ? _reservedColor
                              : Colors.orange)),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: Icon(Icons.edit, color: _secondaryColor),
                      onPressed: () => _editReserva(reserva)),
                  IconButton(
                      icon: Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () => _deleteReserva(reserva.id)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}