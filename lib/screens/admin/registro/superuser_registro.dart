import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reserva_canchas/providers/peticion_provider.dart';
import '../../../../models/reserva.dart';
import '../../../../providers/cancha_provider.dart';
import '../../../../providers/sede_provider.dart';
import '../../../../providers/reserva_recurrente_provider.dart';
import '../../../../models/reserva_recurrente.dart';
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'dart:async';

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
  bool _totalesColapsados = true;

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

      Provider.of<PeticionProvider>(context, listen: false).iniciarEscuchaControlTotal();
      
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    Provider.of<PeticionProvider>(context, listen: false).detenerEscuchaControlTotal();
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
    
    // 🔥 PASO 1: Cargar reservas individuales existentes
    Set<String> reservasIndividualesNormales = {}; // 🔥 CAMBIO: Solo las que NO son personalizaciones
    Set<String> reservasIndividualesPersonalizadas = {}; // 🔥 NUEVO: Las que SÍ son personalizaciones
    
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
          
          // 🔥 NUEVA LÓGICA: Separar reservas individuales normales de personalizaciones
          String claveReserva = '${DateFormat('yyyy-MM-dd').format(reserva.fecha)}_${reserva.cancha.id}_${reserva.horario.horaFormateada}';
          
          // 🔥 Verificar si es una personalización de día específico
          final esPrecioIndependiente = data['precio_independiente_de_recurrencia'] as bool? ?? false;
          
          if (esPrecioIndependiente) {
            reservasIndividualesPersonalizadas.add(claveReserva);
            debugPrint('📝 Reserva individual PERSONALIZADA cargada: $claveReserva - Precio: ${reserva.montoTotal}');
          } else {
            reservasIndividualesNormales.add(claveReserva);
            debugPrint('📝 Reserva individual NORMAL cargada: $claveReserva - Precio: ${reserva.montoTotal}');
          }
        }
      } catch (e) {
        debugPrint('Error al procesar documento: $e');
      }
    }

    // 🔥 PASO 2: Generar reservas recurrentes (ya incluye precios personalizados internamente)
    if (_selectedDate != null) {
      final fechaInicio = _selectedDate!;
      final fechaFin = _selectedDate!;
      
      // 🔥 NUEVA LLAMADA: Ahora el método internamente maneja precios personalizados
      final reservasRecurrentes = await reservaRecurrenteProvider
          .generarReservasDesdeRecurrentes(fechaInicio, fechaFin, canchasMap);
      
      // 🔥 NUEVA LÓGICA DE FILTRADO
      final reservasRecurrentesFiltradas = reservasRecurrentes.where((reserva) {
        if (_selectedCanchaId != null && reserva.cancha.id != _selectedCanchaId) {
          return false;
        }
        
        String claveReserva = '${DateFormat('yyyy-MM-dd').format(reserva.fecha)}_${reserva.cancha.id}_${reserva.horario.horaFormateada}';
        
        // 🔥 NUEVA LÓGICA: Solo bloquear si existe una reserva individual NORMAL (no personalizada)
        if (reservasIndividualesNormales.contains(claveReserva)) {
          debugPrint('⚠️ Saltando reserva recurrente porque ya existe individual NORMAL: $claveReserva');
          return false; // Bloquear porque hay una reserva individual completamente independiente
        }
        
        // 🔥 Si existe una personalización, NO bloquear porque la recurrente ya viene con el precio correcto
        if (reservasIndividualesPersonalizadas.contains(claveReserva)) {
          debugPrint('✅ Permitiendo reserva recurrente CON precio personalizado: $claveReserva - Precio: ${reserva.montoTotal}');
        } else {
          debugPrint('✅ Agregando reserva recurrente NORMAL: $claveReserva - Precio: ${reserva.montoTotal}');
        }
        
        return true;
      }).toList();
      
      reservasTemp.addAll(reservasRecurrentesFiltradas);
      
    } else {
      // 🔥 PARA FECHAS NO ESPECÍFICAS (mostrar hoy)
      final hoy = DateTime.now();
      final reservasRecurrentes = await reservaRecurrenteProvider
          .generarReservasDesdeRecurrentes(hoy, hoy, canchasMap);
      
      final reservasRecurrentesFiltradas = reservasRecurrentes.where((reserva) {
        if (_selectedCanchaId != null && reserva.cancha.id != _selectedCanchaId) {
          return false;
        }
        
        String claveReserva = '${DateFormat('yyyy-MM-dd').format(reserva.fecha)}_${reserva.cancha.id}_${reserva.horario.horaFormateada}';
        
        // 🔥 MISMA LÓGICA: Solo bloquear reservas individuales NORMALES
        if (reservasIndividualesNormales.contains(claveReserva)) {
          debugPrint('⚠️ Saltando reserva recurrente porque ya existe individual NORMAL: $claveReserva');
          return false;
        }
        
        if (reservasIndividualesPersonalizadas.contains(claveReserva)) {
          debugPrint('✅ Permitiendo reserva recurrente CON precio personalizado: $claveReserva - Precio: ${reserva.montoTotal}');
        } else {
          debugPrint('✅ Agregando reserva recurrente NORMAL: $claveReserva - Precio: ${reserva.montoTotal}');
        }
        
        return true;
      }).toList();
      
      reservasTemp.addAll(reservasRecurrentesFiltradas);
    }

    // 🔥 PASO 3: Aplicar filtro de estado (sin cambios)
    if (_selectedEstado != null) {
      reservasTemp = reservasTemp.where((reserva) {
        final estadoReserva = reserva.tipoAbono == TipoAbono.completo ? 'completo' : 'parcial';
        return estadoReserva == _selectedEstado;
      }).toList();
    }

    // 🔥 PASO 4: Eliminar duplicados finales (por si acaso)
    Map<String, Reserva> reservasUnicas = {};
    for (var reserva in reservasTemp) {
      String claveUnica = '${DateFormat('yyyy-MM-dd').format(reserva.fecha)}_${reserva.cancha.id}_${reserva.horario.horaFormateada}';
      
      // 🔥 Priorizar reservas individuales sobre recurrentes en caso de conflicto
      if (reservasUnicas.containsKey(claveUnica)) {
        final existente = reservasUnicas[claveUnica]!;
        // Si la existente es recurrente y la nueva es individual, reemplazar
        if (existente.esReservaRecurrente && !reserva.esReservaRecurrente) {
          reservasUnicas[claveUnica] = reserva;
          debugPrint('🔄 Reemplazando recurrente con individual para: $claveUnica');
        }
        // Si ambas son del mismo tipo, mantener la existente
      } else {
        reservasUnicas[claveUnica] = reserva;
      }
    }

    if (mounted) {
      setState(() {
        _reservas = reservasUnicas.values.toList()
          ..sort((a, b) => a.horario.hora.compareTo(b.horario.hora));
      });
      
      debugPrint('📊 === RESUMEN FINAL ===');
      debugPrint('📊 Total reservas cargadas: ${_reservas.length}');
      debugPrint('📊 Reservas recurrentes: ${_reservas.where((r) => r.esReservaRecurrente).length}');
      debugPrint('📊 Reservas normales: ${_reservas.where((r) => !r.esReservaRecurrente).length}');
      debugPrint('📊 Reservas con precio personalizado: ${_reservas.where((r) => r.precioPersonalizado).length}');
      debugPrint('📊 Reservas individuales normales que bloquean: ${reservasIndividualesNormales.length}');
      debugPrint('📊 Reservas individuales personalizadas: ${reservasIndividualesPersonalizadas.length}');
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
            child: Text('Editar solo este día', style: GoogleFonts.montserrat(color: _secondaryColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'ver_recurrente'),
            child: Text('Ver reserva recurrente', style: GoogleFonts.montserrat(color: _secondaryColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'editar_precio_recurrente'),
            child: Text('Editar toda la recurrencia', style: GoogleFonts.montserrat(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (result == 'ver_recurrente') {
      _mostrarDetallesReservaRecurrente(reserva);
      return;
    } else if (result == 'editar_solo_hoy') {
      await _editarReservaDiaEspecifico(reserva);
      return;
    } else if (result == 'editar_precio_recurrente') {
      await _editarPrecioReservaRecurrente(reserva);
      return;
    } else {
      return; // Usuario canceló
    }
  }

  // Editar reserva normal (con sistema de peticiones integrado)
  await _editarReservaNormal(reserva);
}


Future<void> _editarReservaDiaEspecifico(Reserva reserva) async {
  if (!mounted || reserva.reservaRecurrenteId == null) {
    debugPrint('❌ No se puede editar: mounted=$mounted, reservaRecurrenteId=${reserva.reservaRecurrenteId}');
    return;
  }

  debugPrint('🔄 Iniciando edición de día específico para reserva: ${reserva.id}');
  debugPrint('🔄 ReservaRecurrenteId: ${reserva.reservaRecurrenteId}');

  final formKey = GlobalKey<FormState>();
  final nombreController = TextEditingController(text: reserva.nombre ?? '');
  final telefonoController = TextEditingController(text: reserva.telefono ?? '');
  final emailController = TextEditingController(text: reserva.email ?? '');
  final precioController = TextEditingController(text: reserva.montoTotal.toString());

  // 🔥 OBTENER ESTADO DEL CONTROL TOTAL
  final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
  final puedeHacerCambiosDirectos = await peticionProvider.puedeHacerCambiosDirectos();

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Row(
        children: [
          Text('Editar Solo Este Día', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          // 🔥 INDICADOR DE MODO
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              puedeHacerCambiosDirectos ? 'DIRECTO' : 'PETICIÓN',
              style: GoogleFonts.montserrat(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: puedeHacerCambiosDirectos ? Colors.green.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔥 BANNER INFORMATIVO COMBINADO
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Esto editará solo la reserva de este día específico',
                            style: GoogleFonts.montserrat(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            puedeHacerCambiosDirectos ? Icons.edit : Icons.request_page,
                            color: puedeHacerCambiosDirectos ? Colors.green.shade600 : Colors.orange.shade600,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              puedeHacerCambiosDirectos 
                                  ? 'Los cambios se aplicarán inmediatamente'
                                  : 'Se creará una petición para revisión',
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: puedeHacerCambiosDirectos ? Colors.green.shade700 : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Información de la reserva
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _secondaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${reserva.cancha.nombre} - ${DateFormat('dd/MM/yyyy').format(reserva.fecha)}', 
                         style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
                    Text('Horario: ${reserva.horario.horaFormateada}', 
                         style: GoogleFonts.montserrat()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Datos del cliente
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
              const SizedBox(height: 12),
              
              // Precio total
              TextFormField(
                controller: precioController,
                decoration: InputDecoration(
                  labelText: 'Precio Total',
                  prefixIcon: Icon(Icons.attach_money, color: Colors.orange),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.orange.withOpacity(0.05),
                  helperText: reserva.precioPersonalizado 
                      ? 'Precio original: \$${NumberFormat('#,###', 'es').format((reserva.precioOriginal ?? reserva.montoTotal).toInt())}'
                      : 'Precio estándar de la cancha',
                  helperStyle: GoogleFonts.montserrat(fontSize: 11),
                ),
                style: GoogleFonts.montserrat(color: _primaryColor, fontWeight: FontWeight.w600),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingrese el precio';
                  }
                  final precio = double.tryParse(value);
                  if (precio == null || precio <= 0) {
                    return 'Ingrese un precio válido';
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
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, true);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: puedeHacerCambiosDirectos ? _secondaryColor : Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            puedeHacerCambiosDirectos ? 'Editar Solo Este Día' : 'Crear Petición',
            style: GoogleFonts.montserrat(color: Colors.white),
          ),
        ),
      ],
    ),
  );

  if (result == true && mounted) {
    try {
      debugPrint('✅ Usuario confirmó la edición del día específico');
      
      final nuevoPrecio = double.parse(precioController.text.trim());
      final precioOriginal = reserva.precioOriginal ?? reserva.montoTotal;
      final esPrecioPersonalizado = nuevoPrecio != precioOriginal;
      final descuento = esPrecioPersonalizado ? (precioOriginal - nuevoPrecio) : 0.0;
      
      debugPrint('💰 Nuevo precio: $nuevoPrecio');
      debugPrint('💰 Precio original: $precioOriginal');
      debugPrint('💰 Es precio personalizado: $esPrecioPersonalizado');
      
      // Calcular nuevo monto pagado proporcionalmente si había abono
      double nuevoMontoPagado = reserva.montoPagado;
      if (reserva.montoPagado > 0 && reserva.montoTotal != nuevoPrecio) {
        final proporcion = reserva.montoPagado / reserva.montoTotal;
        nuevoMontoPagado = nuevoPrecio * proporcion;
        nuevoMontoPagado = nuevoMontoPagado > nuevoPrecio ? nuevoPrecio : nuevoMontoPagado;
      }

      // 🔥 PREPARAR VALORES PARA PETICIÓN/CAMBIO DIRECTO
      final valoresAntiguos = {
        'nombre': reserva.nombre ?? '',
        'telefono': reserva.telefono ?? '',
        'correo': reserva.email ?? '',
        'valor': reserva.montoTotal,
        'montoPagado': reserva.montoPagado,
        'precio_personalizado': reserva.precioPersonalizado,
        'precio_original': reserva.precioOriginal,
        'reservaRecurrenteId': reserva.reservaRecurrenteId,
        'fecha': DateFormat('yyyy-MM-dd').format(reserva.fecha),
        'horario': reserva.horario.horaFormateada,
        'cancha_id': reserva.cancha.id,
        'tipo': 'reserva_recurrente_dia_especifico',
      };

      final valoresNuevos = {
        'nombre': nombreController.text.trim(),
        'telefono': telefonoController.text.trim(),
        'correo': emailController.text.trim(),
        'valor': nuevoPrecio,
        'montoPagado': nuevoMontoPagado,
        'precio_personalizado': esPrecioPersonalizado,
        'precio_original': esPrecioPersonalizado ? precioOriginal : null,
        'descuento_aplicado': esPrecioPersonalizado && descuento > 0 ? descuento : null,
        'reservaRecurrenteId': reserva.reservaRecurrenteId,
        'fecha': DateFormat('yyyy-MM-dd').format(reserva.fecha),
        'horario': reserva.horario.horaFormateada,
        'cancha_id': reserva.cancha.id,
        'tipo': 'reserva_recurrente_dia_especifico',
      };

      if (puedeHacerCambiosDirectos) {
        // 🔥 MODO DIRECTO: Aplicar cambios inmediatamente
        debugPrint('🔥 APLICANDO CAMBIOS DIRECTOS PARA DÍA ESPECÍFICO');
        
        debugPrint('🔥 PASO 1: Buscando la reserva individual existente para este día...');
        
        // 🔥 NUEVO ENFOQUE: Buscar la reserva individual que ya existe para este día
        QuerySnapshot reservaIndividualSnapshot = await FirebaseFirestore.instance
            .collection('reservas')
            .where('reservaRecurrenteId', isEqualTo: reserva.reservaRecurrenteId)
            .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(reserva.fecha))
            .where('horario', isEqualTo: reserva.horario.horaFormateada)
            .where('cancha_id', isEqualTo: reserva.cancha.id)
            .limit(1)
            .get();

        if (reservaIndividualSnapshot.docs.isNotEmpty) {
          // ✅ CASO 1: Ya existe una reserva individual para este día - EDITARLA
          debugPrint('✅ Reserva individual encontrada, editando...');
          
          final docReserva = reservaIndividualSnapshot.docs.first;
          
          Map<String, dynamic> updateData = {
            'nombre': nombreController.text.trim(),
            'telefono': telefonoController.text.trim(),
            'correo': emailController.text.trim(),
            'montoTotal': nuevoPrecio,
            'valor': nuevoPrecio,
            'montoPagado': nuevoMontoPagado,
            'estado': nuevoMontoPagado >= nuevoPrecio ? 'completo' : 'parcial',
            'precioPersonalizado': esPrecioPersonalizado,
            'precio_personalizado': esPrecioPersonalizado, // Snake case para compatibilidad
            'precio_original': esPrecioPersonalizado ? precioOriginal : null,
            'descuento_aplicado': esPrecioPersonalizado && descuento > 0 ? descuento : null,
            'fecha_edicion_individual': Timestamp.now(),
            'precio_independiente_de_recurrencia': true,
          };
          
          await docReserva.reference.update(updateData);
          debugPrint('✅ Reserva individual actualizada correctamente');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '✅ Cambios aplicados solo para este día. El resto de la recurrencia mantiene sus valores originales.',
                      style: GoogleFonts.montserrat(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
              duration: const Duration(seconds: 4),
            ),
          );
          
        } else {
          // ✅ CASO 2: No existe reserva individual - Crear una nueva (caso raro, pero por seguridad)
          debugPrint('⚠️ No se encontró reserva individual, creando una nueva...');
          
          // Primero excluir el día de la recurrencia
          final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
          await reservaRecurrenteProvider.excluirDiaReservaRecurrente(
            reserva.reservaRecurrenteId!, 
            reserva.fecha
          );
          
          // Crear nueva reserva individual
          final nuevaReservaData = {
            'cancha_id': reserva.cancha.id,
            'sede': reserva.sede,
            'fecha': DateFormat('yyyy-MM-dd').format(reserva.fecha),
            'horario': reserva.horario.horaFormateada,
            'nombre': nombreController.text.trim(),
            'telefono': telefonoController.text.trim(),
            'correo': emailController.text.trim(),
            'montoTotal': nuevoPrecio,  // 🔥 Campo principal
            'valor': nuevoPrecio,       // 🔥 Campo de compatibilidad
            'montoPagado': nuevoMontoPagado,
            'estado': nuevoMontoPagado >= nuevoPrecio ? 'completo' : 'parcial',
            'confirmada': true,
            'created_at': Timestamp.now(),
            'precioPersonalizado': esPrecioPersonalizado,
            'precio_personalizado': esPrecioPersonalizado, // Snake case para compatibilidad
            'precio_original': esPrecioPersonalizado ? precioOriginal : null,
            'descuento_aplicado': esPrecioPersonalizado && descuento > 0 ? descuento : null,
            'reserva_recurrente_original': reserva.reservaRecurrenteId,
            'fecha_conversion_individual': Timestamp.now(),
            'esReservaRecurrente': false,
            'precio_independiente_de_recurrencia': true, // 🔥 ESTE ES EL CAMPO CLAVE
          };

          // Agregar campos de grupo si es reserva grupal
          if (reserva.grupoReservaId != null) {
            nuevaReservaData.addAll({
              'grupo_reserva_id': reserva.grupoReservaId,
              'total_horas_grupo': reserva.totalHorasGrupo ?? 1,
            });
          }

          await FirebaseFirestore.instance
              .collection('reservas')
              .add(nuevaReservaData);
          
          debugPrint('✅ Nueva reserva individual creada');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Reserva individual creada para este día con precio personalizado',
                      style: GoogleFonts.montserrat(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
      } else {
        // 🔥 MODO PETICIÓN: Crear petición para aprobación
        debugPrint('🔥 CREANDO PETICIÓN PARA EDICIÓN DE DÍA ESPECÍFICO');
        
        final peticionId = await peticionProvider.crearPeticion(
          reservaId: reserva.id,
          valoresAntiguos: valoresAntiguos,
          valoresNuevos: valoresNuevos,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.send, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Petición creada exitosamente. Esperando aprobación.',
                    style: GoogleFonts.montserrat(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      
      debugPrint('🔄 Recargando reservas...');
      await _loadReservasWithFilters();
      debugPrint('✅ Proceso completado exitosamente');
      
    } catch (e) {
      debugPrint('❌ Error en _editarReservaDiaEspecifico: $e');
      if (mounted) {
        _showErrorSnackBar('Error al editar reserva: $e');
      }
    }
  } else {
    debugPrint('❌ Usuario canceló o diálogo retornó resultado inesperado: $result');
  }

  nombreController.dispose();
  telefonoController.dispose();
  emailController.dispose();
  precioController.dispose();
}




Future<void> _editarReservaNormal(Reserva reserva) async {
  final formKey = GlobalKey<FormState>();
  final nombreController = TextEditingController(text: reserva.nombre ?? '');
  final telefonoController = TextEditingController(text: reserva.telefono ?? '');
  final emailController = TextEditingController(text: reserva.email ?? '');
  final precioController = TextEditingController(text: reserva.montoTotal.toString());

  // 🔥 OBTENER ESTADO DEL CONTROL TOTAL
  final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
  final puedeHacerCambiosDirectos = await peticionProvider.puedeHacerCambiosDirectos();

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Row(
        children: [
          Text('Editar Reserva', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          // 🔥 INDICADOR DE MODO
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              puedeHacerCambiosDirectos ? 'DIRECTO' : 'PETICIÓN',
              style: GoogleFonts.montserrat(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: puedeHacerCambiosDirectos ? Colors.green.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔥 BANNER INFORMATIVO COMBINADO
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Esto editará la reserva',
                            style: GoogleFonts.montserrat(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            puedeHacerCambiosDirectos ? Icons.edit : Icons.request_page,
                            color: puedeHacerCambiosDirectos ? Colors.green.shade600 : Colors.orange.shade600,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              puedeHacerCambiosDirectos 
                                  ? 'Los cambios se aplicarán inmediatamente'
                                  : 'Se creará una petición para revisión',
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: puedeHacerCambiosDirectos ? Colors.green.shade700 : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Información de la reserva
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _secondaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${reserva.cancha.nombre} - ${DateFormat('dd/MM/yyyy').format(reserva.fecha)}', 
                         style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
                    Text('Horario: ${reserva.horario.horaFormateada}', 
                         style: GoogleFonts.montserrat()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Datos del cliente
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
              const SizedBox(height: 12),
              
              // Precio total
              TextFormField(
                controller: precioController,
                decoration: InputDecoration(
                  labelText: 'Precio Total',
                  prefixIcon: Icon(Icons.attach_money, color: Colors.orange),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.orange.withOpacity(0.05),
                  helperText: reserva.precioPersonalizado 
                      ? 'Precio original: \$${NumberFormat('#,###', 'es').format((reserva.precioOriginal ?? reserva.montoTotal).toInt())}'
                      : 'Precio estándar de la cancha',
                  helperStyle: GoogleFonts.montserrat(fontSize: 11),
                ),
                style: GoogleFonts.montserrat(color: _primaryColor, fontWeight: FontWeight.w600),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingrese el precio';
                  }
                  final precio = double.tryParse(value);
                  if (precio == null || precio <= 0) {
                    return 'Ingrese un precio válido';
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
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, true);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: puedeHacerCambiosDirectos ? _secondaryColor : Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            puedeHacerCambiosDirectos ? 'Guardar' : 'Crear Petición',
            style: GoogleFonts.montserrat(color: Colors.white),
          ),
        ),
      ],
    ),
  );

  if (result == true && mounted) {
    try {
      final nuevoPrecio = double.parse(precioController.text.trim());
      final precioOriginal = reserva.precioOriginal ?? reserva.montoTotal;
      final esPrecioPersonalizado = nuevoPrecio != precioOriginal;
      final descuento = esPrecioPersonalizado ? (precioOriginal - nuevoPrecio) : 0.0;
      
      // ✅ MANTENER EL ABONO ORIGINAL - NO RECALCULAR PROPORCIONALMENTE
      double nuevoMontoPagado = reserva.montoPagado; // Mantener el abono tal como está

      // 🔥 PREPARAR VALORES PARA PETICIÓN/CAMBIO DIRECTO
      final valoresAntiguos = {
        'nombre': reserva.nombre ?? '',
        'telefono': reserva.telefono ?? '',
        'correo': reserva.email ?? '',
        'valor': reserva.montoTotal,
        'montoPagado': reserva.montoPagado,
        'precio_personalizado': reserva.precioPersonalizado,
        'precio_original': reserva.precioOriginal,
        'tipo': 'reserva_normal',
      };

      final valoresNuevos = {
        'nombre': nombreController.text.trim(),
        'telefono': telefonoController.text.trim(),
        'correo': emailController.text.trim(),
        'valor': nuevoPrecio,
        'montoPagado': nuevoMontoPagado,
        'precio_personalizado': esPrecioPersonalizado,
        'precio_original': esPrecioPersonalizado ? precioOriginal : null,
        'descuento_aplicado': esPrecioPersonalizado && descuento > 0 ? descuento : null,
        'tipo': 'reserva_normal',
      };

      if (puedeHacerCambiosDirectos) {
        // ✅ CORRECCIÓN: Usar los nombres de campos correctos según toFirestore()
        Map<String, dynamic> updateData = {
          'nombre': nombreController.text.trim(),
          'telefono': telefonoController.text.trim(),
          'correo': emailController.text.trim(),
          'valor': nuevoPrecio,                    // ✅ Usar 'valor' en vez de 'montoTotal'
          'montoPagado': nuevoMontoPagado,
          // ✅ Actualizar el estado según la lógica del modelo
          'estado': nuevoMontoPagado >= nuevoPrecio ? 'completo' : 'parcial',
        };

        // ✅ GESTIÓN CORRECTA DE PRECIOS PERSONALIZADOS
        if (esPrecioPersonalizado) {
          updateData.addAll({
            'precio_personalizado': true,          // ✅ Usar snake_case como en toFirestore()
            'precio_original': precioOriginal,
            'descuento_aplicado': descuento > 0 ? descuento : null,
          });
        } else {
          updateData.addAll({
            'precio_personalizado': false,
            'precio_original': null,
            'descuento_aplicado': null,
          });
        }

        // ✅ ACTUALIZAR EN FIRESTORE
        await FirebaseFirestore.instance
            .collection('reservas')
            .doc(reserva.id)
            .update(updateData);

        // ✅ MENSAJE DE ÉXITO
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
      } else {
        // 🔥 MODO PETICIÓN: Crear petición para aprobación
        debugPrint('🔥 CREANDO PETICIÓN PARA EDICIÓN DE RESERVA NORMAL');
        
        final peticionId = await peticionProvider.crearPeticion(
          reservaId: reserva.id,
          valoresAntiguos: valoresAntiguos,
          valoresNuevos: valoresNuevos,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.send, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Petición creada exitosamente. Esperando aprobación.',
                    style: GoogleFonts.montserrat(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      
      // ✅ RECARGAR DATOS
      await _loadReservasWithFilters();
      
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al editar reserva: $e');
      }
    }
  }

  // Limpiar controladores
  nombreController.dispose();
  telefonoController.dispose();
  emailController.dispose();
  precioController.dispose();
}



Future<void> _editarPrecioReservaRecurrente(Reserva reserva) async {
  if (!mounted || reserva.reservaRecurrenteId == null) return;
  
  final formKey = GlobalKey<FormState>();
  final precioController = TextEditingController(text: reserva.montoTotal.toString());

  // 🔥 OBTENER ESTADO DEL CONTROL TOTAL
  final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
  final puedeHacerCambiosDirectos = await peticionProvider.puedeHacerCambiosDirectos();

  // Obtener la reserva recurrente completa de la base de datos
  DocumentSnapshot? reservaRecurrenteDoc;
  try {
    reservaRecurrenteDoc = await FirebaseFirestore.instance
        .collection('reservas_recurrentes')
        .doc(reserva.reservaRecurrenteId!)
        .get();
    
    if (!reservaRecurrenteDoc.exists) {
      _showErrorSnackBar('No se encontró la reserva recurrente');
      return;
    }
  } catch (e) {
    _showErrorSnackBar('Error al obtener reserva recurrente: $e');
    return;
  }

  final reservaRecurrenteData = reservaRecurrenteDoc.data() as Map<String, dynamic>;
  final precioPersonalizadoActual = reservaRecurrenteData['precioPersonalizado'] as bool? ?? false;
  final precioOriginalActual = reservaRecurrenteData['precioOriginal'] as double?;
  final montoTotalActual = reservaRecurrenteData['montoTotal'] as double? ?? 0.0;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Row(
        children: [
          Text(
            'Editar Precio - Reserva Recurrente', 
            style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          // 🔥 INDICADOR DE MODO
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              puedeHacerCambiosDirectos ? 'DIRECTO' : 'PETICIÓN',
              style: GoogleFonts.montserrat(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: puedeHacerCambiosDirectos ? Colors.green.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔥 BANNER INFORMATIVO COMBINADO
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.repeat, color: Colors.purple),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Esto cambiará el precio de TODA la reserva recurrente',
                            style: GoogleFonts.montserrat(
                              color: Colors.purple,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: puedeHacerCambiosDirectos ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            puedeHacerCambiosDirectos ? Icons.edit : Icons.request_page,
                            color: puedeHacerCambiosDirectos ? Colors.green.shade600 : Colors.orange.shade600,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              puedeHacerCambiosDirectos 
                                  ? 'Los cambios se aplicarán a toda la recurrencia inmediatamente'
                                  : 'Se creará una petición para cambios en toda la recurrencia',
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: puedeHacerCambiosDirectos ? Colors.green.shade700 : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Información de la reserva
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _secondaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cancha: ${reserva.cancha.nombre}', 
                         style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
                    Text('Horario: ${reserva.horario.horaFormateada}', 
                         style: GoogleFonts.montserrat()),
                    Text('Cliente: ${reservaRecurrenteData['clienteNombre'] ?? 'N/A'}', 
                         style: GoogleFonts.montserrat()),
                    Text('Días: ${(reservaRecurrenteData['diasSemana'] as List<dynamic>?)?.join(', ') ?? 'N/A'}', 
                         style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Campo de precio
              TextFormField(
                controller: precioController,
                decoration: InputDecoration(
                  labelText: 'Nuevo Precio Total',
                  prefixIcon: Icon(Icons.attach_money, color: Colors.orange),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.orange.withOpacity(0.05),
                  helperText: (precioPersonalizadoActual && precioOriginalActual != null)
                      ? 'Precio original: ${NumberFormat('#,###', 'es').format(precioOriginalActual.toInt())}'
                      : 'Precio actual: ${NumberFormat('#,###', 'es').format(montoTotalActual.toInt())}',
                  helperStyle: GoogleFonts.montserrat(fontSize: 11),
                ),
                style: GoogleFonts.montserrat(color: _primaryColor, fontWeight: FontWeight.w600),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingrese el nuevo precio';
                  }
                  final precio = double.tryParse(value);
                  if (precio == null || precio <= 0) {
                    return 'Ingrese un precio válido';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 12),
              
              // Información adicional
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ℹ️ Esta acción actualizará:',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      puedeHacerCambiosDirectos
                          ? '• El documento de la reserva recurrente\n• Todas las reservas individuales generadas'
                          : '• Se creará una petición para aprobación\n• Los cambios se aplicarán tras aprobación',
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        color: Colors.blue[600],
                      ),
                    ),
                  ],
                ),
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
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, true);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: puedeHacerCambiosDirectos ? Colors.orange : Colors.orange.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            puedeHacerCambiosDirectos ? 'Actualizar Precio' : 'Crear Petición',
            style: GoogleFonts.montserrat(color: Colors.white),
          ),
        ),
      ],
    ),
  );

  if (result == true && mounted) {
    try {
      final nuevoPrecio = double.parse(precioController.text.trim());
      
      // Determinar el precio original correcto
      double precioOriginal;
      if (precioPersonalizadoActual && precioOriginalActual != null) {
        precioOriginal = precioOriginalActual;
      } else {
        precioOriginal = montoTotalActual;
      }
      
      final esPrecioPersonalizado = nuevoPrecio != precioOriginal;
      final descuento = esPrecioPersonalizado ? (precioOriginal - nuevoPrecio) : 0.0;
      
      // Calcular nuevo monto pagado proporcionalmente
      final montoPagadoActual = reservaRecurrenteData['montoPagado'] as double? ?? 0.0;
      double nuevoMontoPagado = montoPagadoActual;
      if (montoPagadoActual > 0 && montoTotalActual != nuevoPrecio && montoTotalActual > 0) {
        final proporcion = montoPagadoActual / montoTotalActual;
        nuevoMontoPagado = nuevoPrecio * proporcion;
        nuevoMontoPagado = nuevoMontoPagado > nuevoPrecio ? nuevoPrecio : nuevoMontoPagado;
      }

      // 🔥 PREPARAR VALORES PARA PETICIÓN/CAMBIO DIRECTO
      final valoresAntiguos = {
        'reservaRecurrenteId': reserva.reservaRecurrenteId!,
        'montoTotal': montoTotalActual,
        'montoPagado': montoPagadoActual,
        'precioPersonalizado': precioPersonalizadoActual,
        'precioOriginal': precioOriginalActual,
        'tipo': 'reserva_recurrente_precio',
      };

      final valoresNuevos = {
        'reservaRecurrenteId': reserva.reservaRecurrenteId!,
        'montoTotal': nuevoPrecio,
        'montoPagado': nuevoMontoPagado,
        'precioPersonalizado': esPrecioPersonalizado,
        'precioOriginal': esPrecioPersonalizado ? precioOriginal : null,
        'descuentoAplicado': esPrecioPersonalizado && descuento > 0 ? descuento : null,
        'tipo': 'reserva_recurrente_precio',
      };

      if (puedeHacerCambiosDirectos) {
        // 🔥 MODO DIRECTO: Aplicar cambios inmediatamente
        debugPrint('🔥 APLICANDO CAMBIOS DIRECTOS A RESERVA RECURRENTE');

        // Preparar datos para actualizar en la reserva recurrente
        Map<String, dynamic> updateDataRecurrente = {
          'montoTotal': nuevoPrecio,
          'montoPagado': nuevoMontoPagado,
          'fechaActualizacion': Timestamp.now(),
        };

        if (esPrecioPersonalizado) {
          updateDataRecurrente.addAll({
            'precioPersonalizado': true,
            'precio_personalizado': true, // Snake case para compatibilidad
            'precioOriginal': precioOriginal,
            'precio_original': precioOriginal, // Snake case para compatibilidad
            'descuentoAplicado': descuento > 0 ? descuento : null,
            'descuento_aplicado': descuento > 0 ? descuento : null, // Snake case para compatibilidad
          });
        } else {
          updateDataRecurrente.addAll({
            'precioPersonalizado': false,
            'precio_personalizado': false,
            'precioOriginal': null,
            'precio_original': null,
            'descuentoAplicado': null,
            'descuento_aplicado': null,
          });
        }

        // Actualizar el documento de la reserva recurrente
        await FirebaseFirestore.instance
            .collection('reservas_recurrentes')
            .doc(reserva.reservaRecurrenteId!)
            .update(updateDataRecurrente);

        // Buscar y actualizar todas las reservas individuales asociadas
        final reservasIndividualesSnapshot = await FirebaseFirestore.instance
            .collection('reservas')
            .where('reservaRecurrenteId', isEqualTo: reserva.reservaRecurrenteId)
            .get();

        if (reservasIndividualesSnapshot.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          
          for (var doc in reservasIndividualesSnapshot.docs) {
            final reservaData = doc.data();
            final montoPagadoIndividual = reservaData['montoPagado'] as double? ?? 0.0;
            final montoTotalIndividual = reservaData['montoTotal'] as double? ?? 0.0;
            
            // Solo actualizar reservas que no tengan precio independiente
            final tienePrecioIndependiente = reservaData['precio_independiente_de_recurrencia'] as bool? ?? false;
            
            if (!tienePrecioIndependiente) {
              // Calcular nuevo monto pagado individual proporcionalmente
              double nuevoMontoPagadoIndividual = montoPagadoIndividual;
              if (montoPagadoIndividual > 0 && montoTotalIndividual != nuevoPrecio && montoTotalIndividual > 0) {
                final proporcionIndividual = montoPagadoIndividual / montoTotalIndividual;
                nuevoMontoPagadoIndividual = nuevoPrecio * proporcionIndividual;
                nuevoMontoPagadoIndividual = nuevoMontoPagadoIndividual > nuevoPrecio ? nuevoPrecio : nuevoMontoPagadoIndividual;
              }
              
              Map<String, dynamic> updateDataIndividual = {
                'montoTotal': nuevoPrecio,
                'valor': nuevoPrecio, // Para compatibilidad
                'montoPagado': nuevoMontoPagadoIndividual,
                'estado': nuevoMontoPagadoIndividual >= nuevoPrecio ? 'completo' : 'parcial',
              };

              if (esPrecioPersonalizado) {
                updateDataIndividual.addAll({
                  'precioPersonalizado': true,
                  'precio_personalizado': true, // Snake case para compatibilidad
                  'precioOriginal': precioOriginal,
                  'precio_original': precioOriginal, // Snake case para compatibilidad
                  'descuentoAplicado': descuento > 0 ? descuento : null,
                  'descuento_aplicado': descuento > 0 ? descuento : null, // Snake case para compatibilidad
                });
              } else {
                updateDataIndividual.addAll({
                  'precioPersonalizado': false,
                  'precio_personalizado': false,
                  'precioOriginal': null,
                  'precio_original': null,
                  'descuentoAplicado': null,
                  'descuento_aplicado': null,
                });
              }

              batch.update(doc.reference, updateDataIndividual);
            }
          }

          await batch.commit();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✅ Precio de la reserva recurrente y ${reservasIndividualesSnapshot.docs.length} reserva(s) individual(es) actualizado correctamente',
                    style: GoogleFonts.montserrat(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 3),
          ),
        );

      } else {
        // 🔥 MODO PETICIÓN: Crear petición para aprobación
        debugPrint('🔥 CREANDO PETICIÓN PARA CAMBIO DE PRECIO EN RESERVA RECURRENTE');
        
        final peticionId = await peticionProvider.crearPeticion(
          reservaId: reserva.id,
          valoresAntiguos: valoresAntiguos,
          valoresNuevos: valoresNuevos,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.request_page, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '📋 Petición creada para cambio de precio en reserva recurrente.\n\nID: ${peticionId.substring(0, 8)}...\nEstado: Esperando aprobación',
                    style: GoogleFonts.montserrat(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      await _loadReservasWithFilters();
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al procesar cambio de precio de reserva recurrente: $e');
      }
    }
  }

  precioController.dispose();
}



  Future<void> _completarPago(Reserva reserva) async {
  if (!mounted) return;
  
  final montoRestante = reserva.montoTotal - reserva.montoPagado;
  
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text('Completar Pago', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reserva: ${reserva.cancha.nombre}',
            style: GoogleFonts.montserrat(color: _primaryColor, fontWeight: FontWeight.w600),
          ),
          Text(
            'Fecha: ${DateFormat('dd/MM/yyyy').format(reserva.fecha)} - ${reserva.horario.horaFormateada}',
            style: GoogleFonts.montserrat(color: _primaryColor),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _secondaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total:', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
                    Text('\$${NumberFormat('#,###', 'es').format(reserva.montoTotal.toInt())}', 
                         style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pagado:', style: GoogleFonts.montserrat()),
                    Text('\$${NumberFormat('#,###', 'es').format(reserva.montoPagado.toInt())}', 
                         style: GoogleFonts.montserrat(color: _reservedColor)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('A pagar:', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    Text('\$${NumberFormat('#,###', 'es').format(montoRestante.toInt())}', 
                         style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '¿Confirmar pago completo de la reserva?',
            style: GoogleFonts.montserrat(color: _primaryColor),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar', style: GoogleFonts.montserrat(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: _reservedColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text('Confirmar Pago', style: GoogleFonts.montserrat(color: Colors.white)),
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
        'montoPagado': reserva.montoTotal, // Pagar el total completo
        'estado': 'completo',
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text('Pago completado correctamente', style: GoogleFonts.montserrat(color: Colors.white)),
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
        _showErrorSnackBar('Error al completar pago: $e');
      }
    }
  }
}



  Future<void> _completarPagoReservaRecurrente(Reserva reserva) async {
  if (!mounted || reserva.reservaRecurrenteId == null) return;
  
  // Obtener datos actuales de la reserva recurrente
  DocumentSnapshot? reservaRecurrenteDoc;
  try {
    reservaRecurrenteDoc = await FirebaseFirestore.instance
        .collection('reservas_recurrentes')
        .doc(reserva.reservaRecurrenteId!)
        .get();
    
    if (!reservaRecurrenteDoc.exists) {
      _showErrorSnackBar('No se encontró la reserva recurrente');
      return;
    }
  } catch (e) {
    _showErrorSnackBar('Error al obtener reserva recurrente: $e');
    return;
  }

  final reservaRecurrenteData = reservaRecurrenteDoc.data() as Map<String, dynamic>;
  final montoTotalRecurrente = reservaRecurrenteData['montoTotal'] as double? ?? 0.0;
  final montoPagadoRecurrente = reservaRecurrenteData['montoPagado'] as double? ?? 0.0;
  final montoRestante = montoTotalRecurrente - montoPagadoRecurrente;
  
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text('Completar Pago - Reserva Recurrente', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.repeat, color: Colors.purple, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esta acción actualizará el pago de TODA la reserva recurrente',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: Colors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Reserva: ${reserva.cancha.nombre}',
            style: GoogleFonts.montserrat(color: _primaryColor, fontWeight: FontWeight.w600),
          ),
          Text(
            'Cliente: ${reservaRecurrenteData['clienteNombre'] ?? 'N/A'}',
            style: GoogleFonts.montserrat(color: _primaryColor),
          ),
          Text(
            'Días: ${(reservaRecurrenteData['diasSemana'] as List<dynamic>?)?.join(', ') ?? 'N/A'}',
            style: GoogleFonts.montserrat(color: _primaryColor),
          ),
          Text(
            'Horario: ${reservaRecurrenteData['horario'] ?? reserva.horario.horaFormateada}',
            style: GoogleFonts.montserrat(color: _primaryColor),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _secondaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total:', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
                    Text('\$${NumberFormat('#,###', 'es').format(montoTotalRecurrente.toInt())}', 
                         style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pagado:', style: GoogleFonts.montserrat()),
                    Text('\$${NumberFormat('#,###', 'es').format(montoPagadoRecurrente.toInt())}', 
                         style: GoogleFonts.montserrat(color: _reservedColor)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('A pagar:', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    Text('\$${NumberFormat('#,###', 'es').format(montoRestante.toInt())}', 
                         style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '¿Confirmar pago completo de todas las reservas recurrentes?',
            style: GoogleFonts.montserrat(color: _primaryColor),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar', style: GoogleFonts.montserrat(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: _reservedColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text('Confirmar Pago', style: GoogleFonts.montserrat(color: Colors.white)),
        ),
      ],
    ),
  );

  if (result == true && mounted) {
    try {
      // Actualizar la reserva recurrente principal
      await FirebaseFirestore.instance
          .collection('reservas_recurrentes')
          .doc(reserva.reservaRecurrenteId!)
          .update({
        'montoPagado': montoTotalRecurrente, // Pagar el total completo
        'fechaActualizacion': Timestamp.now(),
      });

      // Buscar y actualizar todas las reservas individuales asociadas
      final reservasIndividualesSnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .where('reservaRecurrenteId', isEqualTo: reserva.reservaRecurrenteId)
          .get();

      if (reservasIndividualesSnapshot.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        
        for (var doc in reservasIndividualesSnapshot.docs) {
          final reservaData = doc.data();
          final montoTotalIndividual = reservaData['montoTotal'] as double? ?? montoTotalRecurrente;
          
          batch.update(doc.reference, {
            'montoPagado': montoTotalIndividual, // Pagar el total de cada reserva individual
            'estado': 'completo',
          });
        }

        await batch.commit();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pago de reserva recurrente y ${reservasIndividualesSnapshot.docs.length} reserva(s) individual(es) completado correctamente',
                  style: GoogleFonts.montserrat(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: _reservedColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 3),
        ),
      );
      
      await _loadReservasWithFilters();
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al completar pago de reserva recurrente: $e');
      }
    }
  }
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

Widget _buildTotalEnCajaCell(String amount, double width) {
  return Container(
    width: width,
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), // Reducido padding
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
      mainAxisSize: MainAxisSize.min, // Agregado
      children: [
        Text(
          'Total en Caja',
          style: GoogleFonts.montserrat(
            fontSize: 9, // Reducido de 10 a 9
            fontWeight: FontWeight.w600,
            color: _primaryColor.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          amount,
          style: GoogleFonts.montserrat(
            fontSize: 12, // Reducido de 14 a 12
            fontWeight: FontWeight.bold,
            color: _secondaryColor,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1), // Reducido
        Container(
          height: 2,
          width: (width * 0.7).clamp(20.0, 60.0), // Limitado el ancho
          decoration: BoxDecoration(
            color: _secondaryColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(1),
          ),
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
  // Proporciones ajustadas para dar más espacio a "Total en Caja"
  const idealProportions = {
    'cancha': 0.14,    // 14%
    'sede': 0.11,      // 11% (reducido)
    'fecha': 0.08,     // 8% (reducido)
    'hora': 0.08,      // 8%
    'cliente': 0.19,   // 19% (reducido)
    'abono': 0.10,     // 10%
    'restante': 0.10,  // 10%
    'estado': 0.08,    // 8% (reducido)
    'acciones': 0.12,  // 12% (aumentado para "Total en Caja")
  };
  
  // Anchos mínimos ajustados
  const minimumWidths = {
    'cancha': 80.0,
    'sede': 65.0,      // Reducido
    'fecha': 60.0,     // Reducido
    'hora': 55.0,
    'cliente': 90.0,   // Reducido
    'abono': 65.0,
    'restante': 65.0,
    'estado': 60.0,    // Reducido
    'acciones': 90.0,  // Aumentado
  };
  
  // Anchos máximos ajustados
  const maximumWidths = {
    'cancha': 140.0,
    'sede': 110.0,     // Reducido
    'fecha': 85.0,     // Reducido
    'hora': 75.0,
    'cliente': 180.0,  // Reducido
    'abono': 85.0,
    'restante': 85.0,
    'estado': 75.0,    // Reducido
    'acciones': 120.0, // Aumentado
  };
  
  // Resto de la lógica permanece igual...
  Map<String, double> calculatedWidths = {};
  
  for (String column in idealProportions.keys) {
    double proportionalWidth = availableWidth * idealProportions[column]!;
    double minWidth = minimumWidths[column]!;
    double maxWidth = maximumWidths[column]!;
    
    calculatedWidths[column] = proportionalWidth.clamp(minWidth, maxWidth);
  }
  
  double totalCalculated = calculatedWidths.values.reduce((a, b) => a + b);
  
  if (totalCalculated > availableWidth) {
    double excessRatio = availableWidth / totalCalculated;
    
    for (String column in calculatedWidths.keys) {
      double newWidth = calculatedWidths[column]! * excessRatio;
      calculatedWidths[column] = newWidth.clamp(minimumWidths[column]!, maximumWidths[column]!);
    }
  } else if (totalCalculated < availableWidth) {
    double extraSpace = availableWidth - totalCalculated;
    
    // Distribución ajustada del espacio extra
    const extraDistribution = {
      'cancha': 0.20,
      'sede': 0.10,
      'fecha': 0.05,
      'hora': 0.05,
      'cliente': 0.25,
      'abono': 0.10,
      'restante': 0.10,
      'estado': 0.05,
      'acciones': 0.10,  // Más espacio para acciones
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
  // AGREGAR ESTA LÍNEA AL INICIO
  final peticionProvider = Provider.of<PeticionProvider>(context, listen: true);
  
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
  
  // Botón de eliminar (ahora siempre visible, sin validación de roles)
  buttons.add(
    _buildMicroActionButton(
      icon: Icons.delete,
      color: Colors.redAccent,
      onPressed: () => _deleteReserva(reserva.id),
      tooltip: 'Eliminar',
    ),
  );
  
  // Nuevo botón de impresión para facturas de cada hora jugada
  buttons.add(
    _buildMicroActionButton(
      icon: Icons.print,
      color: Colors.blue,
      onPressed: () => _imprimirFactura(reserva),
      tooltip: 'Imprimir factura',
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
                      // Botón de eliminar (ahora siempre visible, sin validación de roles)
                      Tooltip(
                        message: reserva.esReservaRecurrente ? 'Opciones de eliminación' : 'Eliminar reserva',
                        child: IconButton(
                          icon: Icon(Icons.delete, size: 18, color: Colors.redAccent),
                          onPressed: () => _deleteReserva(reserva.id),
                        ),
                      ),
                      // Nuevo botón de impresión para facturas de cada hora jugada
                      Tooltip(
                        message: 'Imprimir factura',
                        child: IconButton(
                          icon: Icon(Icons.print, size: 18, color: Colors.blue),
                          onPressed: () => _imprimirFactura(reserva),
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
      
      // CARD DE TOTALES COLAPSABLE para vista de lista
      if (_reservas.isNotEmpty)
        _buildTotalesColapsables(totals),
    ],
  );
}


Future _imprimirFactura(Reserva reserva) async {
  try {
    // AUMENTAMOS EL ANCHO: de 32 a 48 caracteres para mejor aprovechamiento
    int anchoFactura = 48;
    
    // Función para centrar texto con el nuevo ancho
    String centrarTexto(String texto, [int? ancho]) {
      ancho ??= anchoFactura;
      if (texto.length >= ancho) return texto;
      int espaciosIzq = ((ancho - texto.length) / 2).floor();
      return ' ' * espaciosIzq + texto;
    }
    
    // Función para justificar texto con el nuevo ancho
    String justificarTexto(String izq, String der, [int? ancho]) {
      ancho ??= anchoFactura;
      int espacios = ancho - izq.length - der.length;
      if (espacios < 1) espacios = 1;
      return izq + ' ' * espacios + der;
    }
    
    // Crear líneas de separación más anchas
    String lineaGuiones = '-' * anchoFactura;
    String lineaPuntos = '.' * anchoFactura;
    String lineaIguales = '=' * anchoFactura;
    
    // 🔥 CALCULAR TODOS LOS VALORES ANTES DEL HTML
    final valorOriginal = reserva.precioPersonalizado && reserva.precioOriginal != null 
      ? reserva.precioOriginal! 
      : reserva.montoTotal;
    
    final descuento = reserva.descuentoAplicado ?? 0.0;
    final totalFinal = reserva.montoTotal;
    final abonado = reserva.montoPagado;
    final pendiente = totalFinal - abonado;
    
    // 🔥 CREAR TODAS LAS SECCIONES COMO VARIABLES SEPARADAS
    final tituloFactura = centrarTexto('*** FACTURA DE RESERVA ***');
    final nombreEmpresa = centrarTexto('CANCHAS LA JUGADA');
    
    final infoClienteTitulo = centrarTexto('INFORMACION DEL CLIENTE');
    final clienteNombre = justificarTexto('Cliente:', reserva.nombre ?? 'N/A');
    final clienteTelefono = justificarTexto('Telefono:', reserva.telefono ?? 'N/A');
    
    final detallesTitulo = centrarTexto('DETALLES DE LA RESERVA');
    final detalleCancha = justificarTexto('Cancha Deportiva:', reserva.cancha.nombre);
    final detalleFecha = justificarTexto('Fecha de Reserva:', DateFormat('dd/MM/yyyy').format(reserva.fecha));
    final detalleHorario = justificarTexto('Horario:', reserva.horario.horaFormateada);
    final detalleDuracion = justificarTexto('Duracion:', '1 Hora');
    final detalleEmision = justificarTexto('Fecha de Emision:', DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()));
    
    final financieroTitulo = centrarTexto('RESUMEN FINANCIERO');
    final financieroValor = justificarTexto('Valor por Hora:', '\$${NumberFormat('#,###', 'es').format(valorOriginal.toInt())}');
    final financieroSubtotal = justificarTexto('Subtotal:', '\$${NumberFormat('#,###', 'es').format(valorOriginal.toInt())}');
    final financieroDescuento = justificarTexto('Descuentos:', descuento > 0 ? '-\$${NumberFormat('#,###', 'es').format(descuento.toInt())}' : '\$0');
    final financieroTotal = justificarTexto('TOTAL A PAGAR:', '\$${NumberFormat('#,###', 'es').format(totalFinal.toInt())}');
    final financieroAbonado = justificarTexto('MONTO ABONADO:', '\$${NumberFormat('#,###', 'es').format(abonado.toInt())}');
    final financieroPendiente = justificarTexto('SALDO PENDIENTE:', '\$${NumberFormat('#,###', 'es').format(pendiente.toInt())}');
    
    final agradecimiento1 = centrarTexto('¡¡¡ GRACIAS POR ELEGIRNOS !!!');
    final agradecimiento2 = centrarTexto('ESPERAMOS VERTE PRONTO');
    
    final infoTitulo = centrarTexto('INFORMACION IMPORTANTE');
    final info1 = centrarTexto(' Conserve este comprobante como prueba de pago');
    final info2 = centrarTexto(' Para cualquier reclamo presente este documento');
    final info3 = centrarTexto(' Llegue 10 minutos antes de su horario reservado');
    final info4 = centrarTexto(' Cancelaciones con 2 horas de anticipacion');
    
    final fechaHora = centrarTexto(DateFormat('dd/MM/yyyy - HH:mm:ss', 'es_ES').format(DateTime.now()));
    
    // 🔥 HTML COMPLETAMENTE LIMPIO - SIN INTERPOLACIONES COMPLEJAS
    final StringBuffer htmlBuffer = StringBuffer();
    
    htmlBuffer.write('''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        @page { 
            size: A4 portrait; 
            margin: 10mm; 
        }
        body { 
            font-family: 'Courier New', monospace; 
            font-size: 12px; 
            margin: 0; 
            padding: 10px;
            white-space: pre;
            color: black;
            background: white;
            max-width: 100%;
            line-height: 1.2;
        }
        .header {
            text-align: center;
            margin-bottom: 15px;
        }
        .logo {
            max-width: 180px;
            max-height: 80px;
            margin: 10px auto;
            display: block;
        }
        .section {
            margin: 12px 0;
        }
        .no-print { 
            display: none !important; 
        }
        @media print {
            body { 
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
                font-size: 11px;
            }
            .no-print { 
                display: none !important; 
            }
            @page {
                margin: 8mm;
            }
        }
    </style>
</head>
<body>''');

    // 🔥 AGREGAR CONTENIDO LÍNEA POR LÍNEA - SIN ESPACIOS INICIALES
    htmlBuffer.write(' ');
    htmlBuffer.write('\n');
    htmlBuffer.write(tituloFactura);
    htmlBuffer.write('\n\n');
    htmlBuffer.write(nombreEmpresa);
    htmlBuffer.write('\n\n\n');
    
    htmlBuffer.write('<div class="section">\n');
    htmlBuffer.write(lineaIguales);
    htmlBuffer.write('\n');
    htmlBuffer.write(infoClienteTitulo);
    htmlBuffer.write('\n');
    htmlBuffer.write(lineaGuiones);
    htmlBuffer.write('\n');
    htmlBuffer.write(clienteNombre);
    htmlBuffer.write('\n');
    htmlBuffer.write(clienteTelefono);
    htmlBuffer.write('\n');
    htmlBuffer.write('</div>\n\n');
    
    htmlBuffer.write('<div class="section">\n');
    htmlBuffer.write(lineaIguales);
    htmlBuffer.write('\n');
    htmlBuffer.write(detallesTitulo);
    htmlBuffer.write('\n');
    htmlBuffer.write(lineaGuiones);
    htmlBuffer.write('\n');
    htmlBuffer.write(detalleCancha);
    htmlBuffer.write('\n');
    htmlBuffer.write(detalleFecha);
    htmlBuffer.write('\n');
    htmlBuffer.write(detalleHorario);
    htmlBuffer.write('\n');
    htmlBuffer.write(detalleDuracion);
    htmlBuffer.write('\n');
    htmlBuffer.write(detalleEmision);
    htmlBuffer.write('\n');
    htmlBuffer.write('</div>\n\n');
    
    htmlBuffer.write('<div class="section">\n');
    htmlBuffer.write(lineaIguales);
    htmlBuffer.write('\n');
    htmlBuffer.write(financieroTitulo);
    htmlBuffer.write('\n');
    htmlBuffer.write(lineaGuiones);
    htmlBuffer.write('\n');
    htmlBuffer.write(financieroValor);
    htmlBuffer.write('\n');
    htmlBuffer.write(financieroSubtotal);
    htmlBuffer.write('\n');
    htmlBuffer.write(financieroDescuento);
    htmlBuffer.write('\n');
    htmlBuffer.write(lineaPuntos);
    htmlBuffer.write('\n');
    htmlBuffer.write(financieroTotal);
    htmlBuffer.write('\n');
    htmlBuffer.write(financieroAbonado);
    htmlBuffer.write('\n');
    htmlBuffer.write(lineaPuntos);
    htmlBuffer.write('\n');
    htmlBuffer.write(financieroPendiente);
    htmlBuffer.write('\n');
    htmlBuffer.write(lineaGuiones);
    htmlBuffer.write('\n');
    htmlBuffer.write('</div>\n\n');
    
    htmlBuffer.write(centrarTexto(''));
    htmlBuffer.write('\n');
    htmlBuffer.write(agradecimiento1);
    htmlBuffer.write('\n');
    htmlBuffer.write(agradecimiento2);
    htmlBuffer.write('\n');
    htmlBuffer.write(centrarTexto(''));
    htmlBuffer.write('\n\n');
    
    htmlBuffer.write('<div class="section">\n');
    htmlBuffer.write(lineaPuntos);
    htmlBuffer.write('\n');
    htmlBuffer.write(infoTitulo);
    htmlBuffer.write('\n');
    htmlBuffer.write(lineaPuntos);
    htmlBuffer.write('\n');
    htmlBuffer.write(info1);
    htmlBuffer.write('\n');
    htmlBuffer.write(info2);
    htmlBuffer.write('\n');
    htmlBuffer.write(info3);
    htmlBuffer.write('\n');
    htmlBuffer.write(info4);
    htmlBuffer.write('\n');
    htmlBuffer.write(lineaPuntos);
    htmlBuffer.write('\n');
    htmlBuffer.write('</div>\n\n');
    
    htmlBuffer.write(centrarTexto(''));
    htmlBuffer.write('\n');
    htmlBuffer.write(centrarTexto(''));
    htmlBuffer.write('\n');
    htmlBuffer.write(fechaHora);
    htmlBuffer.write('\n\n');
    
    // Agregar espacios en blanco
    for (int i = 0; i < 10; i++) {
      htmlBuffer.write(centrarTexto(''));
      htmlBuffer.write('\n');
    }
    
    htmlBuffer.write('''
<script class="no-print">
function imprimir() {
    var elementos = document.querySelectorAll('script, style[data-hide], link[data-hide]');
    elementos.forEach(function(el) {
        el.style.display = 'none';
    });
    
    document.body.style.fontSize = '11px';
    document.body.style.maxWidth = '100%';
    document.body.style.padding = '5px';
    
    setTimeout(function() {
        window.print();
    }, 800);
}

if (document.readyState === 'complete') {
    setTimeout(imprimir, 1000);
} else {
    window.addEventListener('load', function() {
        setTimeout(imprimir, 1000);
    });
}

window.addEventListener('afterprint', function() {
    setTimeout(function() {
        if (window.opener) {
            window.close();
        }
    }, 1500);
});

console.log = function() {};
console.error = function() {};
console.warn = function() {};
</script>

</body>
</html>''');

    // 🔥 CONVERTIR BUFFER A STRING Y LIMPIAR CARACTERES PROBLEMÁTICOS
    String facturaHTML = htmlBuffer.toString();
    
    // 🔥 LIMPIAR CUALQUIER BOM O CARÁCTER INVISIBLE AL INICIO
    facturaHTML = facturaHTML.replaceAll('\uFEFF', ''); // BOM UTF-8
    facturaHTML = facturaHTML.replaceAll('\u200B', ''); // Zero width space
    facturaHTML = facturaHTML.replaceAll('\u00A0', ' '); // Non-breaking space
    
    // Verificar que inicia correctamente
    if (!facturaHTML.startsWith('<!DOCTYPE html>')) {
      print('⚠️ Advertencia: HTML no inicia correctamente');
      print('Primeros caracteres: ${facturaHTML.codeUnits.take(10).toList()}');
      
      // Buscar dónde inicia realmente el DOCTYPE
      int docTypeIndex = facturaHTML.indexOf('<!DOCTYPE html>');
      if (docTypeIndex > 0) {
        facturaHTML = facturaHTML.substring(docTypeIndex);
        print('✅ HTML corregido desde posición $docTypeIndex');
      }
    }
    
    // Verificar que no hay caracteres raros al inicio
    print('🔍 Primeros 50 caracteres del HTML limpio:');
    print(facturaHTML.substring(0, 50));
    
    // Crear blob con encoding específico
    final blob = html.Blob([facturaHTML], 'text/html; charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    // Ventana más grande para la factura más ancha
    final windowFeatures = [
      'width=600',
      'height=800',
      'left=100',
      'top=50',
      'scrollbars=yes',
      'resizable=yes',
      'menubar=no',
      'toolbar=no',
      'location=no',
      'status=no',
      'directories=no',
    ].join(',');
    
    final ventanaImpresion = html.window.open(
      url,
      '_blank',
      windowFeatures
    );
    
    Timer(Duration(seconds: 8), () {
      try {
        html.Url.revokeObjectUrl(url);
      } catch (e) {
        // Ignorar errores de limpieza
      }
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.print, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Factura Lista para Imprimir',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green[700],
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    
      
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Error de Impresión', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              SizedBox(height: 4),
              Text('Verificar conexión y configuración de impresora', style: TextStyle(fontSize: 12)),
            ],
          ),
          backgroundColor: Colors.red[700],
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
}

// 5. NUEVO WIDGET para totales colapsables en móvil
Widget _buildTotalesColapsables(Map<String, double> totals) {
  return Container(
    margin: const EdgeInsets.only(top: 8),
    child: Card(
      elevation: 3,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _secondaryColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Agregado
        children: [
          // BOTÓN PARA COLAPSAR/EXPANDIR
          InkWell(
            onTap: () {
              setState(() {
                _totalesColapsados = !_totalesColapsados;
              });
            },
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded( // Agregado Expanded
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet, color: _secondaryColor, size: 18), // Reducido tamaño
                        const SizedBox(width: 8),
                        Flexible( // Cambiado de Text directo a Flexible
                          child: Text(
                            'RESUMEN FINANCIERO',
                            style: GoogleFonts.montserrat(
                              fontSize: 13, // Reducido de 14 a 13
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_totalesColapsados)
                        Flexible( // Agregado Flexible
                          child: Text(
                            '\$${NumberFormat('#,###', 'es').format(totals['totalEnCaja']!.toInt())}',
                            style: GoogleFonts.montserrat(
                              fontSize: 13, // Reducido de 14 a 13
                              fontWeight: FontWeight.bold,
                              color: _secondaryColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        _totalesColapsados ? Icons.expand_more : Icons.expand_less,
                        color: _secondaryColor,
                        size: 20, // Tamaño específico
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // CONTENIDO EXPANDIBLE
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _totalesColapsados 
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // Agregado
                      children: [
                        // Separador
                        Container(
                          height: 1,
                          color: Colors.grey.shade300,
                          margin: const EdgeInsets.only(bottom: 16),
                        ),
                        
                        // Fila de totales
                        IntrinsicHeight( // Agregado para altura uniforme
                          child: Row(
                            children: [
                              // Total Abonado
                              Expanded(
                                child: _buildTotalSummaryItem(
                                  'Total Abonado',
                                  '\$${NumberFormat('#,###', 'es').format(totals['totalAbonado']!.toInt())}',
                                  _reservedColor,
                                  Icons.account_balance_wallet,
                                ),
                              ),
                              
                              // Separador vertical
                              Container(
                                width: 1,
                                color: Colors.grey.shade300,
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              
                              // Total Restante
                              Expanded(
                                child: _buildTotalSummaryItem(
                                  'Total Restante',
                                  '\$${NumberFormat('#,###', 'es').format(totals['totalRestante']!.toInt())}',
                                  totals['totalRestante']! > 0 ? Colors.redAccent : _reservedColor,
                                  Icons.pending_actions,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Total en Caja (destacado) - Corregido
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _secondaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _secondaryColor.withOpacity(0.3), width: 1),
                          ),
                          child: Column( // Cambiado de Row a Column para mejor control
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.monetization_on, color: _secondaryColor, size: 22), // Reducido tamaño
                                  const SizedBox(width: 8),
                                  Flexible( // Agregado Flexible
                                    child: Text(
                                      'TOTAL EN CAJA',
                                      style: GoogleFonts.montserrat(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _primaryColor.withOpacity(0.7),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '\$${NumberFormat('#,###', 'es').format(totals['totalEnCaja']!.toInt())}',
                                style: GoogleFonts.montserrat(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _secondaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
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
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}




// Widget para items individuales del resumen
Widget _buildTotalSummaryItem(String label, String amount, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 4), // Agregado padding
    child: Column(
      mainAxisSize: MainAxisSize.min, // Agregado
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // Agregado
          children: [
            Icon(icon, color: color, size: 14), // Reducido tamaño
            const SizedBox(width: 4),
            Flexible( // Agregado Flexible
              child: Text(
                label,
                style: GoogleFonts.montserrat(
                  fontSize: 11, // Reducido de 12 a 11
                  fontWeight: FontWeight.w600,
                  color: _primaryColor.withOpacity(0.7),
                ),
                maxLines: 2, // Permitir 2 líneas
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: GoogleFonts.montserrat(
            fontSize: 14, // Reducido de 16 a 14
            fontWeight: FontWeight.bold,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    ),
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