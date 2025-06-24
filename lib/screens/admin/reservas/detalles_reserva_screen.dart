import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/reserva.dart';

class DetallesReservaScreen extends StatefulWidget {
  final Reserva reserva;

  const DetallesReservaScreen({super.key, required this.reserva});

  @override
  DetallesReservaScreenState createState() => DetallesReservaScreenState();
}

class DetallesReservaScreenState extends State<DetallesReservaScreen>
    with TickerProviderStateMixin {
  bool isEditing = false;
  late TextEditingController _nombreController;
  late TextEditingController _telefonoController;
  late TextEditingController _emailController;
  late TextEditingController _montoTotalController;
  late TextEditingController _montoPagadoController;
  TipoAbono? _selectedTipo;
  final _formKey = GlobalKey<FormState>();
  late Reserva _currentReserva;

  late AnimationController _fadeController;

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);
  final Color _disabledColor = const Color(0xFFDADCE0);

  @override
  void initState() {
    super.initState();
    _currentReserva = widget.reserva;
    _nombreController =
        TextEditingController(text: widget.reserva.nombre ?? '');
    _telefonoController =
        TextEditingController(text: widget.reserva.telefono ?? '');
    _emailController = TextEditingController(text: widget.reserva.email ?? '');
    // Calcular el monto total dinámico basado en la fecha y horario
    final initialMontoTotal = _calcularMontoTotal(widget.reserva);
    _montoTotalController =
        TextEditingController(text: initialMontoTotal.toStringAsFixed(0));
    _montoPagadoController = TextEditingController(
        text: widget.reserva.montoPagado.toStringAsFixed(0));
    _selectedTipo = widget.reserva.tipoAbono;

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
    _montoTotalController.dispose();
    _montoPagadoController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // Método para calcular el monto total dinámico
  double _calcularMontoTotal(Reserva reserva) {
    final String day =
        DateFormat('EEEE', 'es').format(reserva.fecha).toLowerCase();
    final horaStr = '${reserva.horario.hora.hour}:00';
    final precio = reserva.cancha.preciosPorHorario[day]?[horaStr] ??
        reserva.cancha.precio;
    return precio;
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Por favor, corrige los errores en el formulario.',
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
      return;
    }

    try {
      double montoTotal = double.tryParse(_montoTotalController.text) ??
          _calcularMontoTotal(_currentReserva);
      double montoPagado = double.tryParse(_montoPagadoController.text) ??
          _currentReserva.montoPagado;

      // Validar que el abono no exceda el monto total ni sea menor al mínimo (20000)
      if (montoPagado < 20000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'El abono debe ser al menos 20000.',
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
        return;
      }
      if (montoPagado > montoTotal) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'El abono no puede superar el monto total.',
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
        return;
      }

      // Validar consistencia de tipoAbono
      if (_selectedTipo == TipoAbono.completo && montoPagado != montoTotal) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'El abono debe ser igual al monto total para un pago completo.',
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
        return;
      }
      if (_selectedTipo == TipoAbono.parcial && montoPagado == montoTotal) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'El abono debe ser menor al monto total para un pago parcial.',
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
        return;
      }

      DocumentReference reservaRef = FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reserva.id);

      await reservaRef.update({
        'nombre': _nombreController.text,
        'telefono': _telefonoController.text,
        'email': _emailController.text,
        'montoTotal': montoTotal,
        'montoPagado': montoPagado,
        'tipoAbono': _selectedTipo.toString().split('.').last,
      });

      setState(() {
        _currentReserva = Reserva(
          id: widget.reserva.id,
          cancha: widget.reserva.cancha,
          fecha: widget.reserva.fecha,
          horario: widget.reserva.horario,
          sede: widget.reserva.sede,
          tipoAbono: _selectedTipo!,
          montoTotal: montoTotal,
          montoPagado: montoPagado,
          nombre: _nombreController.text,
          telefono: _telefonoController.text,
          email: _emailController.text,
        );
        isEditing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reserva actualizada exitosamente.',
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
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al actualizar la reserva: $e',
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
    }
  }

  Future<void> _deleteReserva() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Eliminar Reserva',
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _primaryColor,
          ),
        ),
        content: Text(
          '¿Estás seguro que deseas eliminar esta reserva?',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            color: _primaryColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontWeight: FontWeight.w500,
              ),
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
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Eliminar',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('reservas')
            .doc(widget.reserva.id)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Reserva eliminada con éxito.',
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
        }
        Navigator.of(context).pop(true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error al eliminar la reserva: $e',
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detalles de la Reserva',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: _backgroundColor,
        elevation: 0,
        foregroundColor: _primaryColor,
        actions: [
          IconButton(
            icon: Icon(isEditing ? Icons.save : Icons.edit,
                color: _secondaryColor),
            onPressed: () {
              if (isEditing) {
                _saveChanges();
              } else {
                setState(() {
                  isEditing = true;
                });
              }
            },
            tooltip: isEditing ? 'Guardar' : 'Editar',
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: _deleteReserva,
            tooltip: 'Eliminar',
          ),
        ],
      ),
      body: Container(
        color: _backgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildInfoCard()
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

  Widget _buildInfoCard() {
    final reserva = _currentReserva;
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
              'Detalles de la Reserva',
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
                  'Cancha: ${reserva.cancha.nombre}',
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
                  Icons.location_on,
                  color: _secondaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Sede: ${reserva.sede}',
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
                  'Fecha: ${DateFormat('EEEE d MMMM, yyyy', 'es').format(reserva.fecha)}',
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
                  Icons.access_time,
                  color: _secondaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hora: ${reserva.horario.horaFormateada}',
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
              isEditing
                  ? TextFormField(
                      controller: _nombreController,
                      decoration: InputDecoration(
                        labelText: 'Nombre',
                        labelStyle: GoogleFonts.montserrat(
                          color: _primaryColor.withOpacity(0.6),
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
                    )
                  : _buildDetailRow('Nombre', _nombreController.text),
              const SizedBox(height: 16),
              isEditing
                  ? TextFormField(
                      controller: _telefonoController,
                      decoration: InputDecoration(
                        labelText: 'Teléfono',
                        labelStyle: GoogleFonts.montserrat(
                          color: _primaryColor.withOpacity(0.6),
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
                    )
                  : _buildDetailRow('Teléfono', _telefonoController.text),
              const SizedBox(height: 16),
              isEditing
                  ? TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Correo',
                        labelStyle: GoogleFonts.montserrat(
                          color: _primaryColor.withOpacity(0.6),
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
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa el correo';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                            .hasMatch(value)) {
                          return 'Ingresa un correo válido';
                        }
                        return null;
                      },
                    )
                  : _buildDetailRow('Correo', _emailController.text),
              const SizedBox(height: 16),
              isEditing
                  ? TextFormField(
                      controller: _montoTotalController,
                      decoration: InputDecoration(
                        labelText: 'Valor Total',
                        labelStyle: GoogleFonts.montserrat(
                          color: _primaryColor.withOpacity(0.6),
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa el valor total';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Ingresa un número válido';
                        }
                        return null;
                      },
                    )
                  : _buildDetailRow('Valor Total', _montoTotalController.text),
              const SizedBox(height: 16),
              isEditing
                  ? TextFormField(
                      controller: _montoPagadoController,
                      decoration: InputDecoration(
                        labelText: 'Abono',
                        labelStyle: GoogleFonts.montserrat(
                          color: _primaryColor.withOpacity(0.6),
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa el abono';
                        }
                        double? abono = double.tryParse(value);
                        if (abono == null) {
                          return 'Ingresa un número válido';
                        }
                        if (abono < 20000) {
                          return 'El abono debe ser al menos 20000';
                        }
                        double? montoTotal =
                            double.tryParse(_montoTotalController.text);
                        if (montoTotal == null) {
                          return 'El valor total no es válido';
                        }
                        if (abono > montoTotal) {
                          return 'El abono no puede superar el valor total';
                        }
                        return null;
                      },
                    )
                  : _buildDetailRow('Abono', _montoPagadoController.text),
              const SizedBox(height: 16),
              isEditing
                  ? DropdownButtonFormField<TipoAbono>(
                      value: _selectedTipo,
                      decoration: InputDecoration(
                        labelText: 'Estado de pago',
                        labelStyle: GoogleFonts.montserrat(
                          color: _primaryColor.withOpacity(0.6),
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
                      icon: Icon(Icons.keyboard_arrow_down,
                          color: _secondaryColor),
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
                        });
                      },
                    )
                  : _buildDetailRow(
                      'Estado de pago',
                      _selectedTipo == TipoAbono.completo
                          ? 'Completo'
                          : 'Pendiente',
                    ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _primaryColor,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.montserrat(
                fontSize: 16,
                color: _primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
