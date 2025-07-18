import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/cancha.dart';
import '../../../models/horario.dart';
import '../../../models/reserva.dart';
import '../../../models/cliente.dart';

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
  late TextEditingController _emailController;
  late TextEditingController _abonoController;
  TipoAbono? _selectedTipo;
  bool _isProcessing = false;
  String? _selectedClienteId;
  bool _showAbonoField = true;

  late AnimationController _fadeController;

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
    _emailController = TextEditingController();
    _abonoController = TextEditingController(text: '0');
    _selectedTipo = TipoAbono.parcial;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _abonoController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  double _calcularMontoTotal() {
    double total = 0.0;
    for (final horario in widget.horarios) {
      final precio = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
      total += precio;
      debugPrint('Horario: ${horario.horaFormateada}, Precio: $precio, Total parcial: $total');
    }
    return total;
  }

  Future<void> _crearReserva() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final montoTotal = _calcularMontoTotal();
      final abono = _selectedTipo == TipoAbono.completo
          ? montoTotal
          : double.parse(_abonoController.text);
      final abonoPorHora = widget.horarios.isNotEmpty ? abono / widget.horarios.length : 0.0;

      // Crear una reserva por cada horario
      for (final horario in widget.horarios) {
        final montoHora = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
        final reserva = Reserva(
          id: '',
          cancha: widget.cancha,
          fecha: widget.fecha,
          horario: horario,
          sede: widget.sede,
          tipoAbono: _selectedTipo!,
          montoTotal: montoHora,
          montoPagado: _selectedTipo == TipoAbono.completo ? montoHora : abonoPorHora,
          nombre: _nombreController.text,
          telefono: _telefonoController.text,
          email: _emailController.text.isEmpty ? null : _emailController.text,
          confirmada: false,
        );

        final docRef = FirebaseFirestore.instance.collection('reservas').doc();
        await docRef.set(reserva.toFirestore());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reserva${widget.horarios.length > 1 ? 's' : ''} creada${widget.horarios.length > 1 ? 's' : ''} exitosamente.',
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
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al crear la${widget.horarios.length > 1 ? 's' : ''} reserva${widget.horarios.length > 1 ? 's' : ''}: $e',
              style: GoogleFonts.montserrat(),
            ),
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
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _seleccionarCliente(Cliente? cliente) {
    if (cliente != null) {
      setState(() {
        _selectedClienteId = cliente.id;
        _nombreController.text = cliente.nombre;
        _telefonoController.text = cliente.telefono;
        _emailController.text = cliente.correo ?? '';
      });
    } else {
      setState(() {
        _selectedClienteId = null;
        _nombreController.clear();
        _telefonoController.clear();
        _emailController.clear();
        _abonoController.text = '0';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _calcularMontoTotal();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agregar Reserva${widget.horarios.length > 1 ? 's' : ''}',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
          ),
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
                        valueColor:
                            AlwaysStoppedAnimation<Color>(_secondaryColor),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Procesando...',
                        style: GoogleFonts.montserrat(
                          color: Color.fromRGBO(
                              (_primaryColor.r * 255).toInt(),
                              (_primaryColor.g * 255).toInt(),
                              (_primaryColor.b * 255).toInt(),
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
                    _buildInfoCard(total)
                        .animate()
                        .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                        .slideY(
                            begin: -0.2,
                            end: 0,
                            duration: 600.ms,
                            curve: Curves.easeOutQuad),
                    const SizedBox(height: 16),
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
            StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('clientes').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Error al cargar clientes: ${snapshot.error}',
                    style: GoogleFonts.montserrat(color: Colors.redAccent),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_secondaryColor),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Text(
                    'No hay clientes registrados.',
                    style: GoogleFonts.montserrat(color: _primaryColor),
                  );
                }
                final clientes = snapshot.data!.docs
                    .map((doc) => Cliente.fromFirestore(doc))
                    .toList();
                return DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Seleccionar Cliente',
                    labelStyle: GoogleFonts.montserrat(
                      color: Color.fromRGBO(
                          (_primaryColor.r * 255).toInt(),
                          (_primaryColor.g * 255).toInt(),
                          (_primaryColor.b * 255).toInt(),
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
                    ...clientes.map((cliente) => DropdownMenuItem<String>(
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
                      orElse: () => Cliente(
                          id: '', nombre: '', telefono: '', correo: null),
                    );
                    _seleccionarCliente(
                        selectedCliente.id.isEmpty ? null : selectedCliente);
                  },
                  icon: Icon(Icons.keyboard_arrow_down, color: _secondaryColor),
                );
              },
            ),
          ],
        ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.sports_soccer,
                  color: _secondaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Cancha: ${widget.cancha.nombre}',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: _secondaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Fecha: ${DateFormat('EEEE d MMMM, yyyy', 'es').format(widget.fecha)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.access_time,
                  color: _secondaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hora${widget.horarios.length > 1 ? 's' : ''}:',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          color: _primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: widget.horarios.map((horario) {
                          final precio = Reserva.calcularMontoTotal(
                              widget.cancha, widget.fecha, horario);
                          return Chip(
                            label: Text(
                              '${horario.horaFormateada} (COP ${precio.toStringAsFixed(0)})',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                color: _primaryColor,
                              ),
                            ),
                            backgroundColor: Color.fromRGBO(
                                (_secondaryColor.r * 255).toInt(),
                                (_secondaryColor.g * 255).toInt(),
                                (_secondaryColor.b * 255).toInt(),
                                0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: Color.fromRGBO(
                                    (_secondaryColor.r * 255).toInt(),
                                    (_secondaryColor.g * 255).toInt(),
                                    (_secondaryColor.b * 255).toInt(),
                                    0.3),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.monetization_on,
                  color: _secondaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Valor Total: COP ${total.toStringAsFixed(0)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ],
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
              TextFormField(
                controller: _nombreController,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  labelStyle: GoogleFonts.montserrat(
                    color: Color.fromRGBO(
                        (_primaryColor.r * 255).toInt(),
                        (_primaryColor.g * 255).toInt(),
                        (_primaryColor.b * 255).toInt(),
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
                        (_primaryColor.r * 255).toInt(),
                        (_primaryColor.g * 255).toInt(),
                        (_primaryColor.b * 255).toInt(),
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Correo',
                  labelStyle: GoogleFonts.montserrat(
                    color: Color.fromRGBO(
                        (_primaryColor.r * 255).toInt(),
                        (_primaryColor.g * 255).toInt(),
                        (_primaryColor.b * 255).toInt(),
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
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                        .hasMatch(value)) {
                      return 'Ingresa un correo válido';
                    }
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
                          (_primaryColor.r * 255).toInt(),
                          (_primaryColor.g * 255).toInt(),
                          (_primaryColor.b * 255).toInt(),
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
                        (_primaryColor.r * 255).toInt(),
                        (_primaryColor.g * 255).toInt(),
                        (_primaryColor.b * 255).toInt(),
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
              ElevatedButton(
                onPressed: _crearReserva,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _secondaryColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Confirmar Reserva${widget.horarios.length > 1 ? 's' : ''}',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}