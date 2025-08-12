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
import '../../../../providers/reserva_recurrente_provider.dart';
import '../../../../models/reserva_recurrente.dart';

class SuperuserRegistroReservasScreen extends StatefulWidget {
  const SuperuserRegistroReservasScreen({super.key});

  @override
  SuperuserRegistroReservasScreenState createState() =>
      SuperuserRegistroReservasScreenState();
}

class SuperuserRegistroReservasScreenState
    extends State<SuperuserRegistroReservasScreen> with TickerProviderStateMixin {
  List<Reserva> _reservas = [];
  DateTime? _selectedDate;
  String? _selectedSedeId;
  String? _selectedCanchaId;
  String? _selectedEstado;
  bool _isLoading = false;
  bool _viewTable = true;
  bool _filtersVisible = true;

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
    _selectedDate = DateTime.now();
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
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      
      await Future.wait([
        canchaProvider.fetchAllCanchas(),
        canchaProvider.fetchHorasReservadas(),
        sedeProvider.fetchSedes(),
        reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId),
      ]);

      if (!mounted) return;

      final canchasMap = {
        for (var cancha in canchaProvider.canchas) cancha.id: cancha
      };

      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('reservas')
          .where('confirmada', isEqualTo: true)
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

      QuerySnapshot querySnapshot = await query
          .get()
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw TimeoutException('La consulta a Firestore tardó demasiado');
          });

      if (!mounted) return;

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

          final confirmada = data['confirmada'] as bool? ?? false;
          if (!confirmada) {
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

      if (_selectedDate != null) {
        final fechaInicio = _selectedDate!;
        final fechaFin = _selectedDate!;
        
        final reservasRecurrentes = await reservaRecurrenteProvider
            .generarReservasDesdeRecurrentes(fechaInicio, fechaFin, canchasMap);
        
        final reservasRecurrentesFiltradas = reservasRecurrentes.where((reserva) {
          if (_selectedCanchaId != null && reserva.cancha.id != _selectedCanchaId) {
            return false;
          }
          return true;
        }).toList();
        
        reservasTemp.addAll(reservasRecurrentesFiltradas);
      } else {
        final hoy = DateTime.now();
        final reservasRecurrentes = await reservaRecurrenteProvider
            .generarReservasDesdeRecurrentes(hoy, hoy, canchasMap);
        
        final reservasRecurrentesFiltradas = reservasRecurrentes.where((reserva) {
          if (_selectedCanchaId != null && reserva.cancha.id != _selectedCanchaId) {
            return false;
          }
          return true;
        }).toList();
        
        reservasTemp.addAll(reservasRecurrentesFiltradas);
      }

      if (_selectedEstado != null) {
        reservasTemp = reservasTemp.where((reserva) {
          final estadoReserva = reserva.tipoAbono == TipoAbono.completo ? 'completo' : 'parcial';
          return estadoReserva == _selectedEstado;
        }).toList();
      }

      if (mounted) {
        setState(() {
          _reservas = reservasTemp..sort((a, b) => a.horario.hora.compareTo(b.horario.hora));
        });
        
        debugPrint('📊 Total reservas cargadas: ${_reservas.length}');
        debugPrint('📊 Reservas recurrentes: ${_reservas.where((r) => r.esReservaRecurrente).length}');
        debugPrint('📊 Reservas normales: ${_reservas.where((r) => !r.esReservaRecurrente).length}');
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
            .any((c) => c.id == _selectedCanchaId && (sedeId == null || c.sedeId == sedeId));
        if (!canchaExists) {
          _selectedCanchaId = null;
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadReservasWithFilters();
      }
    });
  }

  void _selectCancha(String? canchaId) {
    if (!mounted) return;
    
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final canchasDisponibles = canchaProvider.canchas
        .where((c) => _selectedSedeId == null || c.sedeId == _selectedSedeId)
        .map((c) => c.id)
        .toList();
    
    final isValidCancha = canchaId == null || canchasDisponibles.contains(canchaId);
    
    setState(() {
      _selectedCanchaId = isValidCancha ? canchaId : null;
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadReservasWithFilters();
      }
    });
  }

  void _selectEstado(String? estado) {
    if (!mounted) return;
    
    const validEstados = [null, 'completo', 'parcial'];
    final isValidEstado = validEstados.contains(estado);
    
    setState(() {
      _selectedEstado = isValidEstado ? estado : null;
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadReservasWithFilters();
      }
    });
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
    
    if (reserva.esReservaRecurrente) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('Reserva Recurrente', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
          content: Text(
            'Esta es una reserva recurrente. ¿Qué deseas hacer?',
            style: GoogleFonts.montserrat(color: _primaryColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancelar'),
              child: Text('Cancelar', style: GoogleFonts.montserrat(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'editar_solo_hoy'),
              child: Text('Editar solo hoy', style: GoogleFonts.montserrat(color: _secondaryColor)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'ver_recurrente'),
              child: Text('Ver reserva recurrente', style: GoogleFonts.montserrat(color: _secondaryColor)),
            ),
          ],
        ),
      );

      if (result == 'ver_recurrente') {
        _mostrarDetallesReservaRecurrente(reserva);
        return;
      } else if (result == 'editar_solo_hoy') {
        _mostrarDialogoExcluirDiaRecurrente(reserva);
        return;
      } else {
        return;
      }
    }

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


  Future<void> _completarPagoReservaRecurrente(Reserva reserva) async {
    if (!mounted) return;
    final _formKey = GlobalKey<FormState>();
    final montoController = TextEditingController(text: reserva.montoTotal.toString());

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Completar Pago - Reserva Recurrente', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reserva recurrente para ${reserva.cancha.nombre} el ${DateFormat('dd/MM/yyyy').format(reserva.fecha)} a las ${reserva.horario.horaFormateada}',
                  style: GoogleFonts.montserrat(color: _primaryColor),
                ),
                const SizedBox(height: 8),
                Text(
                  'Esto actualizará el pago de TODA la reserva recurrente',
                  style: GoogleFonts.montserrat(color: Colors.orange, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: montoController,
                  decoration: InputDecoration(
                    labelText: 'Monto Pagado Total',
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
                    if (monto == null || monto < 0) {
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

    if (result == true && mounted && reserva.reservaRecurrenteId != null) {
      try {
        final nuevoMonto = double.parse(montoController.text.trim());
        final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
        
        // Actualizar la reserva recurrente en Firestore
        await FirebaseFirestore.instance
            .collection('reservas_recurrentes')
            .doc(reserva.reservaRecurrenteId!)
            .update({
          'montoPagado': nuevoMonto,
          'fechaActualizacion': Timestamp.now(),
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('Pago de reserva recurrente actualizado correctamente', style: GoogleFonts.montserrat(color: Colors.white)),
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
          _showErrorSnackBar('Error al actualizar pago de reserva recurrente: $e');
        }
      }
    }

    montoController.dispose();
  }





  Future<void> _deleteReserva(String reservaId) async {
    if (!mounted) return;
    
    final reserva = _reservas.firstWhere((r) => r.id == reservaId, 
                                       orElse: () => throw Exception('Reserva no encontrada'));
    
    if (reserva.esReservaRecurrente) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('Eliminar Reserva Recurrente', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
          content: Text(
            'Esta es una reserva recurrente. ¿Qué deseas hacer?',
            style: GoogleFonts.montserrat(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancelar'),
              child: Text('Cancelar', style: GoogleFonts.montserrat(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'excluir_solo_hoy'),
              child: Text('Excluir solo hoy', style: GoogleFonts.montserrat(color: Colors.orange)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancelar_futuras'),
              child: Text('Cancelar futuras', style: GoogleFonts.montserrat(color: Colors.redAccent)),
            ),
          ],
        ),
      );

      if (result == 'excluir_solo_hoy' && reserva.reservaRecurrenteId != null) {
        _mostrarDialogoExcluirDiaRecurrente(reserva);
      } else if (result == 'cancelar_futuras' && reserva.reservaRecurrenteId != null) {
        final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(

context, listen: false);
        final reservaRecurrente = reservaRecurrenteProvider.reservasRecurrentes
            .firstWhere((r) => r.id == reserva.reservaRecurrenteId!);
        _cancelarReservasRecurrentesFuturas(reservaRecurrente);
      }
      return;
    }
    
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
        
        if (mounted) {
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
        }
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
      ),
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width > 600)
            AnimatedContainer(
              width: _filtersVisible ? 250 : 0,
              duration: const Duration(milliseconds: 300),
              child: _filtersVisible
                  ? _buildFilterPanel()
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
                        value: () {
                          final canchasDisponibles = Provider.of<CanchaProvider>(context, listen: false).canchas
                              .where((cancha) => _selectedSedeId == null || cancha.sedeId == _selectedSedeId)
                              .map((c) => c.id)
                              .toList();
                          return (_selectedCanchaId != null && canchasDisponibles.contains(_selectedCanchaId)) 
                              ? _selectedCanchaId 
                              : null;
                        }(),
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
                        value: () {
                          const validEstados = [null, 'completo', 'parcial'];
                          return validEstados.contains(_selectedEstado) ? _selectedEstado : null;
                        }(),
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
  
  return LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = constraints.maxWidth;
      final columnWidths = _calculateResponsiveColumnWidths(availableWidth);
      final totals = _calculateTotals();
      
      return Column(
        children: [
          // CABECERA FIJA
          Container(
            width: availableWidth,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade300, width: 0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Table(
              columnWidths: {
                0: FixedColumnWidth(columnWidths['cancha']!),
                1: FixedColumnWidth(columnWidths['sede']!),
                2: FixedColumnWidth(columnWidths['fecha']!),
                3: FixedColumnWidth(columnWidths['hora']!),
                4: FixedColumnWidth(columnWidths['cliente']!),
                5: FixedColumnWidth(columnWidths['abono']!),
                6: FixedColumnWidth(columnWidths['restante']!),
                7: FixedColumnWidth(columnWidths['estado']!),
                8: FixedColumnWidth(columnWidths['acciones']!),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                  ),
                  children: [
                    _buildHeaderCell('Cancha', columnWidths['cancha']!, TextAlign.left),
                    _buildHeaderCell('Sede', columnWidths['sede']!, TextAlign.left),
                    _buildHeaderCell('Fecha', columnWidths['fecha']!, TextAlign.center),
                    _buildHeaderCell('Hora', columnWidths['hora']!, TextAlign.center),
                    _buildHeaderCell('Cliente', columnWidths['cliente']!, TextAlign.left),
                    _buildHeaderCell('Abono', columnWidths['abono']!, TextAlign.right),
                    _buildHeaderCell('Restante', columnWidths['restante']!, TextAlign.right),
                    _buildHeaderCell('Estado', columnWidths['estado']!, TextAlign.center),
                    _buildHeaderCell('Acciones', columnWidths['acciones']!, TextAlign.center),
                  ],
                ),
              ],
            ),
          ),
          
          // CONTENIDO CON SCROLL
          Expanded(
            child: Container(
              width: availableWidth,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey.shade300, width: 0.5),
                  right: BorderSide(color: Colors.grey.shade300, width: 0.5),
                ),
              ),
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: {
                    0: FixedColumnWidth(columnWidths['cancha']!),
                    1: FixedColumnWidth(columnWidths['sede']!),
                    2: FixedColumnWidth(columnWidths['fecha']!),
                    3: FixedColumnWidth(columnWidths['hora']!),
                    4: FixedColumnWidth(columnWidths['cliente']!),
                    5: FixedColumnWidth(columnWidths['abono']!),
                    6: FixedColumnWidth(columnWidths['restante']!),
                    7: FixedColumnWidth(columnWidths['estado']!),
                    8: FixedColumnWidth(columnWidths['acciones']!),
                  },
                  children: _reservas.asMap().entries.map((entry) {
                    final index = entry.key;
                    final reserva = entry.value;
                    final montoRestante = reserva.montoTotal - reserva.montoPagado;
                    final horaReserva = reserva.horario.hora;
                    final horasReservadas = canchaProvider.horasReservadasPorCancha(reserva.cancha.id);
                    final isReserved = horasReservadas[reserva.fecha]?.contains(horaReserva) ?? false;

                    return TableRow(
                      decoration: BoxDecoration(
                        color: index % 2 == 0 ? Colors.white : Colors.grey.shade50,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
                        ),
                      ),
                      children: [
                        _buildDataCell(
                          reserva.cancha.nombre,
                          columnWidths['cancha']!,
                          TextAlign.left,
                        ),
                        _buildDataCell(
                          sedeProvider.sedes.firstWhere(
                            (sede) => sede['id'] == reserva.sede,
                            orElse: () => {'nombre': 'N/A'},
                          )['nombre'] as String,
                          columnWidths['sede']!,
                          TextAlign.left,
                        ),
                        _buildDataCell(
                          DateFormat('dd/MM/yy').format(reserva.fecha),
                          columnWidths['fecha']!,
                          TextAlign.center,
                        ),
                        _buildDataCell(
                          reserva.horario.horaFormateada,
                          columnWidths['hora']!,
                          TextAlign.center,
                          textColor: isReserved ? Colors.red : _primaryColor,
                        ),
                        _buildClientCell(reserva, columnWidths['cliente']!),
                        _buildDataCell(
                          '\$${NumberFormat('#,###', 'es').format(reserva.montoPagado.toInt())}',
                          columnWidths['abono']!,
                          TextAlign.right,
                          textColor: _reservedColor,
                        ),
                        _buildDataCell(
                          '\$${NumberFormat('#,###', 'es').format(montoRestante.toInt())}',
                          columnWidths['restante']!,
                          TextAlign.right,
                          textColor: montoRestante > 0 ? Colors.redAccent : _reservedColor,
                        ),
                        _buildStatusCell(reserva, columnWidths['estado']!),
                        _buildActionsCell(reserva, columnWidths['acciones']!),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          
          // FILA DE TOTALES
          if (_reservas.isNotEmpty)
            _buildTotalsRow(columnWidths, totals),
        ],
      );
    },
  );
}

// Nuevo método para construir la fila de totales
Widget _buildTotalsRow(Map<String, double> columnWidths, Map<String, double> totals) {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: _secondaryColor.withOpacity(0.05),
      border: Border.all(color: Colors.grey.shade300, width: 0.5),
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(8),
        bottomRight: Radius.circular(8),
      ),
    ),
    child: Table(
      columnWidths: {
        0: FixedColumnWidth(columnWidths['cancha']!),
        1: FixedColumnWidth(columnWidths['sede']!),
        2: FixedColumnWidth(columnWidths['fecha']!),
        3: FixedColumnWidth(columnWidths['hora']!),
        4: FixedColumnWidth(columnWidths['cliente']!),
        5: FixedColumnWidth(columnWidths['abono']!),
        6: FixedColumnWidth(columnWidths['restante']!),
        7: FixedColumnWidth(columnWidths['estado']!),
        8: FixedColumnWidth(columnWidths['acciones']!),
      },
      children: [
        TableRow(
          children: [
            // Celdas vacías hasta llegar a la columna de cliente
            _buildTotalCell('', columnWidths['cancha']!, TextAlign.left),
            _buildTotalCell('', columnWidths['sede']!, TextAlign.left),
            _buildTotalCell('', columnWidths['fecha']!, TextAlign.center),
            _buildTotalCell('', columnWidths['hora']!, TextAlign.center),
            
            // Celda de "TOTALES"
            _buildTotalLabelCell('TOTALES', columnWidths['cliente']!),
            
            // Total Abonado
            _buildTotalAmountCell(
              '\$${NumberFormat('#,###', 'es').format(totals['totalAbonado']!.toInt())}',
              columnWidths['abono']!,
              _reservedColor,
            ),
            
            // Total Restante
            _buildTotalAmountCell(
              '\$${NumberFormat('#,###', 'es').format(totals['totalRestante']!.toInt())}',
              columnWidths['restante']!,
              totals['totalRestante']! > 0 ? Colors.redAccent : _reservedColor,
            ),
            
            // Total en Caja (se extiende por las últimas dos columnas)
            _buildTotalEnCajaCell(
              '\$${NumberFormat('#,###', 'es').format(totals['totalEnCaja']!.toInt())}',
              columnWidths['estado']! + columnWidths['acciones']!,
            ),
          ],
        ),
      ],
    ),
  );
}

// Widget para la celda de etiqueta "TOTALES"
Widget _buildTotalLabelCell(String text, double width) {
  return Container(
    width: width,
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    alignment: Alignment.centerRight,
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: _primaryColor,
      ),
      textAlign: TextAlign.right,
    ),
  );
}

// Widget para celdas de montos totales
Widget _buildTotalAmountCell(String amount, double width, Color color) {
  return Container(
    width: width,
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    alignment: Alignment.centerRight,
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: Colors.grey.shade300, width: 0.5),
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          amount,
          style: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 2),
        Container(
          height: 2,
          width: width * 0.6,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    ),
  );
}

// Widget especial para la celda "Total en Caja"
Widget _buildTotalEnCajaCell(String amount, double width) {
  return Container(
    width: width,
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _secondaryColor.withOpacity(0.1),
      border: Border(
        left: BorderSide(color: Colors.grey.shade300, width: 0.5),
      ),
      borderRadius: const BorderRadius.only(
        bottomRight: Radius.circular(8),
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Total en Caja',
          style: GoogleFonts.montserrat(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _primaryColor.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          amount,
          style: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: _secondaryColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Container(
          height: 2,
          width: width * 0.7,
          decoration: BoxDecoration(
            color: _secondaryColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    ),
  );
}

// Widget para celdas vacías en la fila de totales
Widget _buildTotalCell(String text, double width, TextAlign textAlign) {
  return Container(
    width: width,
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    alignment: _getAlignment(textAlign),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: _primaryColor.withOpacity(0.5),
      ),
      textAlign: textAlign,
    ),
  );
}





Map<String, double> _calculateTotals() {
  double totalAbonado = 0;
  double totalRestante = 0;
  double totalEnCaja = 0;

  for (var reserva in _reservas) {
    totalAbonado += reserva.montoPagado;
    totalRestante += (reserva.montoTotal - reserva.montoPagado);
    totalEnCaja += reserva.montoTotal;
  }

  return {
    'totalAbonado': totalAbonado,
    'totalRestante': totalRestante,
    'totalEnCaja': totalEnCaja,
  };
}


// Widget para celdas de cabecera
Widget _buildHeaderCell(String text, double width, TextAlign textAlign) {
  return Container(
    width: width,
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    alignment: _getAlignment(textAlign),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _primaryColor,
      ),
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    ),
  );
}

// Widget para celdas de datos
Widget _buildDataCell(
  String text, 
  double width, 
  TextAlign textAlign, 
  {Color? textColor}
) {
  return Container(
    width: width,
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    alignment: _getAlignment(textAlign),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: textColor ?? _primaryColor,
      ),
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    ),
  );
}

// Widget especial para celda de cliente con indicadores
Widget _buildClientCell(Reserva reserva, double width) {
  return Container(
    width: width,
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    alignment: Alignment.centerLeft,
    child: Tooltip(
      message: '${reserva.nombre ?? 'N/A'}\nTeléfono: ${reserva.telefono ?? 'N/A'}',
      child: Row(
        children: [
          Expanded(
            child: Text(
              reserva.nombre ?? 'N/A',
              style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (reserva.esReservaRecurrente)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(Icons.repeat, size: 10, color: Colors.purple),
            ),
          if (reserva.precioPersonalizado)
            Container(
              margin: const EdgeInsets.only(left: 2),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(Icons.star, size: 10, color: Colors.amber[700]),
            ),
        ],
      ),
    ),
  );
}

// Widget para celda de estado
Widget _buildStatusCell(Reserva reserva, double width) {
  return Container(
    width: width,
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    alignment: Alignment.center,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: reserva.tipoAbono == TipoAbono.completo 
            ? _reservedColor.withOpacity(0.15)
            : Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        reserva.tipoAbono == TipoAbono.completo ? 'Completo' : 'Parcial',
        style: GoogleFonts.montserrat(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: reserva.tipoAbono == TipoAbono.completo ? _reservedColor : Colors.orange[700],
        ),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

// Widget para celda de acciones
Widget _buildActionsCell(Reserva reserva, double width) {
  return Container(
    width: width,
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
    alignment: Alignment.center,
    child: _buildActionButtons(reserva, width),
  );
}

// Helper para alineación
Alignment _getAlignment(TextAlign textAlign) {
  switch (textAlign) {
    case TextAlign.left:
      return Alignment.centerLeft;
    case TextAlign.right:
      return Alignment.centerRight;
    case TextAlign.center:
      return Alignment.center;
    default:
      return Alignment.centerLeft;
  }
}



// Cálculo de anchos completamente responsivo
Map<String, double> _calculateResponsiveColumnWidths(double availableWidth) {
  // Definir proporciones ideales para cada columna (suman 1.0)
  const idealProportions = {
    'cancha': 0.14,    // 14%
    'sede': 0.12,      // 12%
    'fecha': 0.09,     // 9%
    'hora': 0.08,      // 8%
    'cliente': 0.20,   // 20% - La más importante
    'abono': 0.10,     // 10%
    'restante': 0.10,  // 10%
    'estado': 0.09,    // 9%
    'acciones': 0.08,  // 8%
  };
  
  // Anchos mínimos absolutos (para pantallas muy pequeñas)
  const minimumWidths = {
    'cancha': 80.0,
    'sede': 70.0,
    'fecha': 65.0,
    'hora': 55.0,
    'cliente': 100.0,
    'abono': 65.0,
    'restante': 65.0,
    'estado': 65.0,
    'acciones': 70.0,
  };
  
  // Anchos máximos (para pantallas muy grandes)
  const maximumWidths = {
    'cancha': 150.0,
    'sede': 120.0,
    'fecha': 90.0,
    'hora': 80.0,
    'cliente': 200.0,
    'abono': 90.0,
    'restante': 90.0,
    'estado': 85.0,
    'acciones': 100.0,
  };
  
  // Calcular anchos basados en proporciones
  Map<String, double> calculatedWidths = {};
  
  for (String column in idealProportions.keys) {
    double proportionalWidth = availableWidth * idealProportions[column]!;
    double minWidth = minimumWidths[column]!;
    double maxWidth = maximumWidths[column]!;
    
    // Aplicar límites mínimos y máximos
    calculatedWidths[column] = proportionalWidth.clamp(minWidth, maxWidth);
  }
  
  // Verificar si el total excede el ancho disponible
  double totalCalculated = calculatedWidths.values.reduce((a, b) => a + b);
  
  if (totalCalculated > availableWidth) {
    // Si excede, reducir proporcionalmente manteniendo los mínimos
    double excessRatio = availableWidth / totalCalculated;
    
    for (String column in calculatedWidths.keys) {
      double newWidth = calculatedWidths[column]! * excessRatio;
      calculatedWidths[column] = newWidth.clamp(minimumWidths[column]!, maximumWidths[column]!);
    }
  } else if (totalCalculated < availableWidth) {
    // Si sobra espacio, distribuirlo proporcionalmente
    double extraSpace = availableWidth - totalCalculated;
    
    // Distribución del espacio extra priorizando cliente y cancha
    const extraDistribution = {
      'cancha': 0.25,
      'sede': 0.15,
      'fecha': 0.05,
      'hora': 0.05,
      'cliente': 0.35,
      'abono': 0.05,
      'restante': 0.05,
      'estado': 0.05,
      'acciones': 0.0,
    };
    
    for (String column in calculatedWidths.keys) {
      double additionalWidth = extraSpace * extraDistribution[column]!;
      calculatedWidths[column] = (calculatedWidths[column]! + additionalWidth)
          .clamp(minimumWidths[column]!, maximumWidths[column]!);
    }
  }
  
  return calculatedWidths;
}

// Formatear moneda de manera más compacta
String _formatCurrency(double amount) {
  final formatter = NumberFormat('#,###', 'es');
  return '\$${formatter.format(amount.toInt())}';
}

// Widget para los botones de acción optimizados por espacio
Widget _buildActionButtons(Reserva reserva, double availableWidth) {
  List<Widget> buttons = [];
  
  // Botón de editar (siempre presente)
  buttons.add(
    _buildMicroActionButton(
      icon: Icons.edit,
      color: _secondaryColor,
      onPressed: () => _editReserva(reserva),
      tooltip: reserva.esReservaRecurrente ? 'Ver opciones recurrentes' : 'Editar',
    ),
  );
  
  // Botón de pago (solo si es parcial)
  if (reserva.tipoAbono == TipoAbono.parcial) {
    buttons.add(
      _buildMicroActionButton(
        icon: Icons.attach_money,
        color: _reservedColor,
        onPressed: () => reserva.esReservaRecurrente 
            ? _completarPagoReservaRecurrente(reserva)
            : _completarPago(reserva),
        tooltip: 'Completar pago',
      ),
    );
  }
  
  // Botón de eliminar (siempre presente)
  buttons.add(
    _buildMicroActionButton(
      icon: Icons.delete,
      color: Colors.redAccent,
      onPressed: () => _deleteReserva(reserva.id),
      tooltip: 'Eliminar',
    ),
  );
  
  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: buttons,
  );
}

// Botones de acción ultra compactos
Widget _buildMicroActionButton({
  required IconData icon,
  required Color color,
  required VoidCallback onPressed,
  required String tooltip,
}) {
  return Tooltip(
    message: tooltip,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      width: 22,
      height: 22,
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Icon(
            icon,
            size: 12,
            color: color,
          ),
        ),
      ),
    ),
  );
}




  Widget _buildListView() {
  final currencyFormat = NumberFormat.currency(symbol: "\$", decimalDigits: 0);
  final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
  final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
  final totals = _calculateTotals();
  
  return Column(
    children: [
      // Lista de reservas
      Expanded(
        child: ListView.builder(
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
                                message: reserva.esReservaRecurrente ? 'Ver opciones recurrentes' : 'Editar datos del cliente',
                                child: IconButton(
                                  icon: Icon(Icons.edit, size: 18, color: _secondaryColor),
                                  onPressed: () => _editReserva(reserva),
                                ),
                              ),
                              if (reserva.tipoAbono == TipoAbono.parcial)
                                Tooltip(
                                  message: reserva.esReservaRecurrente ? 'Completar pago recurrente' : 'Completar pago',
                                  child: IconButton(
                                    icon: Icon(Icons.attach_money, size: 18, color: _reservedColor),
                                    onPressed: () => reserva.esReservaRecurrente 
                                        ? _completarPagoReservaRecurrente(reserva)
                                        : _completarPago(reserva),
                                  ),
                                ),
                              Tooltip(
                                message: reserva.esReservaRecurrente ? 'Opciones de eliminación' : 'Eliminar reserva',
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
                          Expanded(
                            child: Tooltip(
                              message: 'Teléfono: ${reserva.telefono ?? 'N/A'}',
                              child: Text(
                                'Cliente: ${reserva.nombre ?? 'N/A'}',
                                style: GoogleFonts.montserrat(fontSize: 14, color: _primaryColor),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          if (reserva.esReservaRecurrente)
                            Tooltip(
                              message: 'Reserva recurrente',
                              child: Icon(Icons.repeat, size: 16, color: Colors.purple),
                            ),
                          if (reserva.precioPersonalizado)
                            Tooltip(
                              message: 'Precio personalizado (Descuento: \${(reserva.descuentoAplicado ?? 0).toStringAsFixed(0)})',
                              child: Icon(Icons.star, size: 16, color: Colors.amber),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.attach_money, size: 16, color: _secondaryColor),
                          const SizedBox(width: 8),
                          Text('Abono: ${currencyFormat.format(reserva.montoPagado)}', style: GoogleFonts.montserrat(fontSize: 14, color: _reservedColor)),
                          const SizedBox(width: 16),
                          Text('Restante: ${currencyFormat.format(reserva.montoTotal - reserva.montoPagado)}', style: GoogleFonts.montserrat(fontSize: 14, color: (reserva.montoTotal - reserva.montoPagado) > 0 ? Colors.redAccent : _reservedColor)),
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
                      if (reserva.precioPersonalizado) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.discount, size: 16, color: Colors.amber),
                            const SizedBox(width: 8),
                            Text(
                              'Precio original: ${currencyFormat.format(reserva.precioOriginal ?? reserva.montoTotal)}',
                              style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        if ((reserva.descuentoAplicado ?? 0) > 0) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.savings, size: 16, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                'Descuento aplicado: ${currencyFormat.format(reserva.descuentoAplicado!)} (${reserva.porcentajeDescuento.toStringAsFixed(1)}%)',
                                style: GoogleFonts.montserrat(fontSize: 12, color: Colors.green),
                              ),
                            ],
                          ),
                        ],
                      ],
                      if (reserva.esReservaRecurrente) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.repeat, size: 16, color: Colors.purple),
                            const SizedBox(width: 8),
                            Text(
                              'Reserva recurrente - ID: ${reserva.reservaRecurrenteId?.substring(0, 8)}...',
                              style: GoogleFonts.montserrat(fontSize: 12, color: Colors.purple),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      
      // CARD DE TOTALES para vista de lista
      if (_reservas.isNotEmpty)
        _buildTotalsCard(totals),
    ],
  );
}



Widget _buildTotalsCard(Map<String, double> totals) {
  return Container(
    margin: const EdgeInsets.only(top: 16),
    child: Card(
      elevation: 4,
      color: _secondaryColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _secondaryColor.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Título
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calculate, color: _secondaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'RESUMEN FINANCIERO',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Fila de totales
            Row(
              children: [
                // Total Abonado
                Expanded(
  child: _buildTotalSummaryItem(
    'Total Abonado',
    '${NumberFormat('#,###', 'es').format(totals['totalAbonado']!.toInt())}',
    _reservedColor,
    Icons.account_balance_wallet,
  ),
),

                
                // Separador
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey.shade300,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                
                // Total Restante
                Expanded(
                  child: _buildTotalSummaryItem(
                    'Total Restante',
                    '${NumberFormat('#,###', 'es').format(totals['totalRestante']!.toInt())}',
                    totals['totalRestante']! > 0 ? Colors.redAccent : _reservedColor,
                    Icons.pending_actions,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Separador horizontal
            Container(
              height: 1,
              color: Colors.grey.shade300,
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),
            
            // Total en Caja (destacado)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _secondaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _secondaryColor.withOpacity(0.3), width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.monetization_on, color: _secondaryColor, size: 24),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      Text(
                        'TOTAL EN CAJA',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${NumberFormat('#,###', 'es').format(totals['totalEnCaja']!.toInt())}',
                        style: GoogleFonts.montserrat(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Información adicional
            const SizedBox(height: 12),
            Text(
              '${_reservas.length} reserva${_reservas.length != 1 ? 's' : ''} encontrada${_reservas.length != 1 ? 's' : ''}',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: _primaryColor.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Widget para items individuales del resumen
Widget _buildTotalSummaryItem(String label, String amount, Color color, IconData icon) {
  return Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _primaryColor.withOpacity(0.7),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        amount,
        style: GoogleFonts.montserrat(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    ],
  );
}




  void _mostrarDetallesReservaRecurrente(Reserva reserva) async {
    if (reserva.reservaRecurrenteId == null) return;
    
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    final reservaRecurrente = reservaRecurrenteProvider.reservasRecurrentes
        .firstWhere((r) => r.id == reserva.reservaRecurrenteId, 
                   orElse: () => throw Exception('Reserva recurrente no encontrada'));

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Detalles Reserva Recurrente', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cliente: ${reservaRecurrente.clienteNombre}', style: GoogleFonts.montserrat()),
              Text('Teléfono: ${reservaRecurrente.clienteTelefono}', style: GoogleFonts.montserrat()),
              if (reservaRecurrente.clienteEmail != null)
                Text('Email: ${reservaRecurrente.clienteEmail}', style: GoogleFonts.montserrat()),
              const SizedBox(height: 8),
              Text('Días: ${reservaRecurrente.diasSemana.join(", ")}', style: GoogleFonts.montserrat()),
              Text('Horario: ${reservaRecurrente.horario}', style: GoogleFonts.montserrat()),
              Text('Estado: ${reservaRecurrente.estado.name}', style: GoogleFonts.montserrat()),
              const SizedBox(height: 8),
              Text('Desde: ${DateFormat('dd/MM/yyyy').format(reservaRecurrente.fechaInicio)}', style: GoogleFonts.montserrat()),
              if (reservaRecurrente.fechaFin != null)
                Text('Hasta: ${DateFormat('dd/MM/yyyy').format(reservaRecurrente.fechaFin!)}', style: GoogleFonts.montserrat()),
              const SizedBox(height: 8),
              if (reservaRecurrente.precioPersonalizado) ...[
                Text('Precio personalizado: Sí', style: GoogleFonts.montserrat(color: Colors.orange)),
                if (reservaRecurrente.precioOriginal != null)
                  Text('Precio original: \$${reservaRecurrente.precioOriginal!.toStringAsFixed(0)}', 
                       style: GoogleFonts.montserrat()),
                if (reservaRecurrente.descuentoAplicado != null)
                  Text('Descuento: \$${reservaRecurrente.descuentoAplicado!.toStringAsFixed(0)}', 
                       style: GoogleFonts.montserrat(color: Colors.green)),
              ],
              Text('Monto total: \$${reservaRecurrente.montoTotal.toStringAsFixed(0)}', 
                   style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar', style: GoogleFonts.montserrat(color: Colors.grey)),
          ),
          if (reservaRecurrente.estado == EstadoRecurrencia.activa)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _cancelarReservasRecurrentesFuturas(reservaRecurrente);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Cancelar futuras', style: GoogleFonts.montserrat(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  void _mostrarDialogoExcluirDiaRecurrente(Reserva reserva) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Excluir día específico', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
        content: Text(
          'Esto excluirá la reserva recurrente solo para el día ${DateFormat('dd/MM/yyyy').format(reserva.fecha)}.',
          style: GoogleFonts.montserrat(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Excluir día', style: GoogleFonts.montserrat(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted && reserva.reservaRecurrenteId != null) {
      try {
        final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
        await reservaRecurrenteProvider.excluirDiaReservaRecurrente(
          reserva.reservaRecurrenteId!, 
          reserva.fecha
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('Día excluido de la reserva recurrente', style: GoogleFonts.montserrat(color: Colors.white)),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ),
        );
        
        await _loadReservasWithFilters();
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Error al excluir día: $e');
        }
      }
    }
  }

  void _cancelarReservasRecurrentesFuturas(ReservaRecurrente reservaRecurrente) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Cancelar reservas futuras', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
        content: Text(
          'Esto cancelará todas las reservas futuras de esta reserva recurrente, pero mantendrá las del pasado.',
          style: GoogleFonts.montserrat(),
        ),
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
            child: Text('Confirmar', style: GoogleFonts.montserrat(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
        await reservaRecurrenteProvider.cancelarReservasFuturas(reservaRecurrente.id);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('Reservas futuras canceladas', style: GoogleFonts.montserrat(color: Colors.white)),
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
          _showErrorSnackBar('Error al cancelar reservas futuras: $e');
        }
      }
    }
  }
}