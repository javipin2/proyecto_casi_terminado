import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reserva_canchas/screens/admin/reservas/admin_detalles_reservas.dart';
import '../../../models/cancha.dart';
import '../../../models/reserva.dart';
import '../../../models/horario.dart';
import '../../../providers/cancha_provider.dart';
import '../../../providers/sede_provider.dart';
import '../../../models/reserva_recurrente.dart';
import '../../../providers/reserva_recurrente_provider.dart';
import 'agregar_reserva_screen.dart';

class AdminReservasScreen extends StatefulWidget {
  // ✅ AGREGAR PARÁMETROS PARA MODO SELECTOR
  final bool esModoSelector;
  final String? reservaOriginalId;
  final Function(String sede, String canchaId, String horario, DateTime fecha)? onSeleccionConfirmada;

  const AdminReservasScreen({
    super.key,
    this.esModoSelector = false,
    this.reservaOriginalId,
    this.onSeleccionConfirmada,
  });

  @override
  AdminReservasScreenState createState() => AdminReservasScreenState();
}

class AdminReservasScreenState extends State<AdminReservasScreen>
    with TickerProviderStateMixin {
  String _selectedSedeId = '';
  String _selectedSedeNombre = '';
  Cancha? _selectedCancha;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _viewGrid = true;
  bool _showingRecurrentReservas = false;
  List<ReservaRecurrente> _reservasRecurrentesActivas = [];

  late AnimationController _fadeController;
  late AnimationController _slideController;

  StreamSubscription<QuerySnapshot>? _reservasSubscription;

  List<Cancha> _canchas = [];
  List<Reserva> _reservas = [];
  Map<String, Reserva> _reservedMap = {};
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
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    
    try {
      await sedeProvider.fetchSedes();
      
      if (!mounted) return;
      
      if (sedeProvider.sedes.isNotEmpty) {
        setState(() {
          _selectedSedeId = sedeProvider.sedes.first['id'] as String;
          _selectedSedeNombre = sedeProvider.sedes.first['nombre'] as String;
        });
        sedeProvider.setSede(_selectedSedeNombre);
        
        await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
        
        if (_selectedSedeId.isNotEmpty) {
          await _loadCanchas();
        }
      } else {
        setState(() {
          _selectedSedeId = '';
          _selectedSedeNombre = '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al inicializar datos: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
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
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    
    setState(() {
      _isLoading = true;
      _canchas.clear();
      _selectedCancha = null;
      _selectedHours.clear();
    });

    try {
      await canchaProvider.fetchCanchas(_selectedSedeId);
      
      if (reservaRecurrenteProvider.reservasRecurrentes.isEmpty) {
        await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
      }
      
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

    try {
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      
      if (reservaRecurrenteProvider.reservasRecurrentes.isEmpty) {
        await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
      }

      final stream = FirebaseFirestore.instance
          .collection('reservas')
          .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate))
          .where('sede', isEqualTo: _selectedSedeId)
          .where('cancha_id', isEqualTo: _selectedCancha!.id)
          .limit(24)
          .snapshots();

      _reservasSubscription = stream.listen(
        (querySnapshot) async {
          try {
            final horarios = await Horario.generarHorarios(
              fecha: _selectedDate,
              canchaId: _selectedCancha!.id,
              sede: _selectedSedeId,
              reservasSnapshot: querySnapshot,
              cancha: _selectedCancha!,
            );
            
            List<Reserva> reservasTemp = [];
            Map<String, Reserva> reservedMapTemp = {};
            
            for (var doc in querySnapshot.docs) {
              try {
                final reserva = await Reserva.fromFirestore(doc);
                final horaNormalizada = Horario.normalizarHora(reserva.horario.horaFormateada);
                reservedMapTemp[horaNormalizada] = reserva;
                reservasTemp.add(reserva);
                debugPrint('📋 Reserva normal: ${reserva.nombre} - $horaNormalizada');
              } catch (e) {
                debugPrint("❌ Error al procesar documento: $e");
              }
            }
            
            final reservasRecurrentes = reservaRecurrenteProvider.obtenerReservasActivasParaFecha(
              _selectedDate, 
              sede: _selectedSedeId, 
              canchaId: _selectedCancha!.id
            );
            
            debugPrint('📅 Fecha: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
            debugPrint('🏟️ Cancha: ${_selectedCancha!.nombre} (${_selectedCancha!.id})');
            debugPrint('🏢 Sede: $_selectedSedeId');
            debugPrint('🔄 Reservas recurrentes encontradas: ${reservasRecurrentes.length}');
            
            for (var reservaRecurrente in reservasRecurrentes) {
              final horaNormalizada = Horario.normalizarHora(reservaRecurrente.horario);
              
              debugPrint('⏰ Procesando recurrente: ${reservaRecurrente.horario} -> $horaNormalizada');
              debugPrint('👤 Cliente: ${reservaRecurrente.clienteNombre}');
              debugPrint('📊 Estado: ${reservaRecurrente.estado}');
              
              if (!reservedMapTemp.containsKey(horaNormalizada)) {
                try {
                  final horario = Horario.fromHoraFormateada(reservaRecurrente.horario);
                  
                  final reservaVirtual = Reserva(
                    id: '${reservaRecurrente.id}_${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                    cancha: _selectedCancha!,
                    fecha: _selectedDate,
                    horario: horario,
                    sede: reservaRecurrente.sede,
                    tipoAbono: reservaRecurrente.montoPagado >= reservaRecurrente.montoTotal 
                        ? TipoAbono.completo : TipoAbono.parcial,
                    montoTotal: reservaRecurrente.montoTotal,
                    montoPagado: reservaRecurrente.montoPagado,
                    nombre: reservaRecurrente.clienteNombre,
                    telefono: reservaRecurrente.clienteTelefono,
                    email: reservaRecurrente.clienteEmail,
                    confirmada: true,
                    reservaRecurrenteId: reservaRecurrente.id,
                    esReservaRecurrente: true,
                    precioPersonalizado: reservaRecurrente.precioPersonalizado,
                    precioOriginal: reservaRecurrente.precioOriginal,
                    descuentoAplicado: reservaRecurrente.descuentoAplicado,
                  );
                  
                  reservedMapTemp[horaNormalizada] = reservaVirtual;
                  reservasTemp.add(reservaVirtual);
                  
                  debugPrint('✅ Reserva virtual creada: ${reservaVirtual.nombre} - $horaNormalizada');
                } catch (e) {
                  debugPrint('❌ Error creando reserva virtual: $e');
                }
              } else {
                debugPrint('⚠️ Horario ya ocupado por reserva normal: $horaNormalizada');
              }
            }
            
            if (mounted) {
              setState(() {
                _reservas = reservasTemp;
                _reservedMap = reservedMapTemp;
                _hours = horarios.map((h) => h.horaFormateada).toList();
                _isLoading = false;
              });
              
              debugPrint('📊 Total reservas mostradas: ${_reservas.length}');
              debugPrint('📊 Reservas normales: ${_reservas.where((r) => !r.esReservaRecurrente).length}');
              debugPrint('📊 Reservas recurrentes: ${_reservas.where((r) => r.esReservaRecurrente).length}');
            }
          } catch (e) {
            debugPrint('❌ Error en stream listener: $e');
            if (mounted) {
              _showErrorSnackBar('Error al procesar reservas: $e');
              setState(() {
                _isLoading = false;
              });
            }
          }
        },
        onError: (e) {
          debugPrint('❌ Error en stream: $e');
          if (mounted) {
            _showErrorSnackBar('Error al cargar reservas: $e');
            setState(() {
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('❌ Error general en _loadReservas: $e');
      if (mounted) {
        _showErrorSnackBar('Error al inicializar carga de reservas: $e');
        setState(() {
          _isLoading = false;
        });
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
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
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
    
    if (reserva.esReservaRecurrente) {
      _mostrarOpcionesReservaRecurrente(reserva);
    } else {
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
      
      // ✅ VERIFICAR SI ESTÁ RESERVADO
      if (_reservedMap.containsKey(horaNormalizada)) {
        // ✅ EN MODO SELECTOR, MOSTRAR INFO DE RESERVA EXISTENTE
        if (widget.esModoSelector) {
          final reservaExistente = _reservedMap[horaNormalizada]!;
          _mostrarInfoReservaExistente(reservaExistente);
          return;
        } else {
          // ✅ COMPORTAMIENTO NORMAL: ABRIR DETALLES
          return;
        }
      }

      // ✅ EN MODO SELECTOR, SOLO PERMITIR UN HORARIO SELECCIONADO
      if (widget.esModoSelector) {
        _selectedHours.clear();
        _selectedHours.add(horaNormalizada);
      } else {
        // ✅ COMPORTAMIENTO NORMAL: MÚLTIPLE SELECCIÓN
        if (_selectedHours.contains(horaNormalizada)) {
          _selectedHours.remove(horaNormalizada);
        } else {
          _selectedHours.add(horaNormalizada);
        }
      }
    });
  }

  void _mostrarInfoReservaExistente(Reserva reserva) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Horario Ocupado',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Este horario ya está reservado por:',
              style: GoogleFonts.montserrat(),
            ),
            const SizedBox(height: 8),
            Text(
              'Cliente: ${reserva.nombre}',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
            ),
            Text(
              'Horario: ${reserva.horario.horaFormateada}',
              style: GoogleFonts.montserrat(),
            ),
            if (reserva.esReservaRecurrente)
              Text(
                'Tipo: Reserva Recurrente',
                style: GoogleFonts.montserrat(
                  color: const Color(0xFF1A237E),
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Selecciona otro horario disponible.',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido', style: GoogleFonts.montserrat()),
          ),
        ],
      ),
    );
  }

  void _confirmarSeleccion() {
  if (_selectedCancha == null || _selectedHours.isEmpty) {
    _showErrorSnackBar('Selecciona una cancha y al menos un horario');
    return;
  }

  // ✅ SOLO PERMITIR SELECCIÓN DE UN HORARIO EN MODO SELECTOR
  if (_selectedHours.length > 1) {
    _showErrorSnackBar('Solo puedes seleccionar un horario para editar la reserva');
    return;
  }

  final horarioSeleccionado = _selectedHours.first;
  
  // ✅ VERIFICAR QUE NO SEA LA MISMA RESERVA ORIGINAL
  final reservaEnHorario = _reservedMap[horarioSeleccionado];
  if (reservaEnHorario != null && reservaEnHorario.id == widget.reservaOriginalId) {
    _showErrorSnackBar('No puedes seleccionar el mismo horario actual de la reserva');
    return;
  }

  // ✅ VERIFICAR QUE EL HORARIO ESTÉ DISPONIBLE
  if (_reservedMap.containsKey(horarioSeleccionado)) {
    _showErrorSnackBar('El horario seleccionado no está disponible');
    return;
  }

  // ✅ EN LUGAR DE LLAMAR AL CALLBACK, RETORNAR LOS DATOS AL CERRAR LA PANTALLA
  final resultado = {
    'sede': _selectedSedeId,
    'canchaId': _selectedCancha!.id,
    'horario': horarioSeleccionado,
    'fecha': _selectedDate,
  };

  Navigator.of(context).pop(resultado); // ✅ RETORNAR DATOS EN LUGAR DE CALLBACK
}




  void _mostrarOpcionesReservaRecurrente(Reserva reserva) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _disabledColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Reserva Recurrente',
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${reserva.nombre} - ${reserva.horario.horaFormateada}',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                color: _primaryColor.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.event_busy, color: Colors.orange),
              ),
              title: Text(
                'Excluir este día',
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'Liberar horario solo para ${DateFormat('EEEE d MMMM', 'es').format(_selectedDate)}',
                style: GoogleFonts.montserrat(fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _excluirDiaReservaRecurrente(reserva);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _secondaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.info_outline, color: _secondaryColor),
              ),
              title: Text(
                'Ver detalles completos',
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'Gestionar toda la reserva recurrente',
                style: GoogleFonts.montserrat(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _mostrarDetallesReservaRecurrente(reserva);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _excluirDiaReservaRecurrente(Reserva reserva) async {
    if (reserva.reservaRecurrenteId == null) return;
    
    try {
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      await reservaRecurrenteProvider.excluirDiaReservaRecurrente(
        reserva.reservaRecurrenteId!,
        _selectedDate,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Día excluido de la reserva recurrente. El horario ${reserva.horario.horaFormateada} está ahora disponible para ${DateFormat('EEEE d MMMM', 'es').format(_selectedDate)}.',
              style: GoogleFonts.montserrat(),
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 4),
          ),
        );
        
        _loadReservas();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al excluir día: $e');
      }
    }
  }

  void _mostrarDetallesReservaRecurrente(Reserva reserva) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Reserva Recurrente',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cliente: ${reserva.nombre}', style: GoogleFonts.montserrat()),
            Text('Teléfono: ${reserva.telefono}', style: GoogleFonts.montserrat()),
            Text('Horario: ${reserva.horario.horaFormateada}', style: GoogleFonts.montserrat()),
            Text('Cancha: ${reserva.cancha.nombre}', style: GoogleFonts.montserrat()),
            const SizedBox(height: 8),
            Text(
              'Esta es una reserva recurrente activa.',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: _primaryColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar', style: GoogleFonts.montserrat()),
          ),
        ],
      ),
    );
  }

  void _mostrarReservasRecurrentes() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
      
      await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
      
      if (mounted) Navigator.pop(context);
      
      final todasLasReservas = reservaRecurrenteProvider.reservasRecurrentes
          .where((r) => r.sede == _selectedSedeId)
          .toList();

      final reservasActivas = todasLasReservas.where((r) => r.estado == EstadoRecurrencia.activa).toList();
      final reservasCanceladas = todasLasReservas.where((r) => r.estado == EstadoRecurrencia.cancelada).toList();

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _disabledColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.repeat_rounded, color: _secondaryColor),
                      const SizedBox(width: 12),
                      Text(
                        'Reservas Recurrentes',
                        style: GoogleFonts.montserrat(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor,
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${reservasActivas.length} activas',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (reservasCanceladas.isNotEmpty)
                            Text(
                              '${reservasCanceladas.length} canceladas',
                              style: GoogleFonts.montserrat(
                                fontSize: 12,
                                color: Colors.red.withOpacity(0.7),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: todasLasReservas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.repeat, size: 64, color: _disabledColor),
                              const SizedBox(height: 16),
                              Text(
                                'No hay reservas recurrentes',
                                style: GoogleFonts.montserrat(
                                  color: _primaryColor.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: todasLasReservas.length,
                          itemBuilder: (context, index) {
                            final reserva = todasLasReservas[index];
                            return _buildReservaRecurrenteCard(reserva, setModalState);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        _showErrorSnackBar('Error cargando reservas recurrentes: $e');
      }
    }
  }

  Widget _buildReservaRecurrenteCard(ReservaRecurrente reserva, [StateSetter? setModalState]) {
    final bool isActive = reserva.estado == EstadoRecurrencia.activa;
    final Color cardColor = isActive ? const Color(0xFF1A237E) : Colors.grey;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cardColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isActive ? Icons.repeat_rounded : Icons.cancel_outlined,
            color: Colors.white,
          ),
        ),
        title: Text(
          reserva.clienteNombre,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Horario: ${reserva.horario}',
              style: GoogleFonts.montserrat(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
            Text(
              'Días: ${reserva.diasSemana.join(", ")}',
              style: GoogleFonts.montserrat(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
            Text(
              'Estado: ${reserva.estado.name.toUpperCase()}',
              style: GoogleFonts.montserrat(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Precio: COP ${reserva.montoTotal.toInt()}${reserva.precioPersonalizado ? " (Personalizado)" : ""}',
              style: GoogleFonts.montserrat(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: isActive ? PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          color: _backgroundColor,
          onSelected: (value) async {
            if (value == 'eliminar') {
              await _confirmarEliminarReservaRecurrente(reserva);
              
              if (setModalState != null && mounted) {
                try {
                  final provider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
                  await provider.fetchReservasRecurrentes(sede: _selectedSedeId);
                  setModalState(() {});
                } catch (e) {
                  debugPrint('Error actualizando modal: $e');
                }
              }
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'eliminar',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    'Cancelar Futuras',
                    style: GoogleFonts.montserrat(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ) : null,
      ),
    );
  }

  Future<void> _confirmarEliminarReservaRecurrente(ReservaRecurrente reserva) async {
    final ahora = DateTime.now();
    final diaSemanaHoy = DateFormat('EEEE', 'es').format(ahora).toLowerCase();
    final esHoyDiaValido = reserva.diasSemana.contains(diaSemanaHoy);
    final fechaHoyStr = DateFormat('yyyy-MM-dd').format(ahora);
    final yaEstaExcluidoHoy = reserva.diasExcluidos.contains(fechaHoyStr);
    
    String mensajeHoy = '';
    bool mostrarAdvertenciaHoy = false;
    
    if (esHoyDiaValido && !yaEstaExcluidoHoy) {
      try {
        final horarioReserva = Horario.fromHoraFormateada(reserva.horario);
        final horaReservaHoy = DateTime(
          ahora.year, ahora.month, ahora.day,
          horarioReserva.hora.hour, horarioReserva.hora.minute
        );
        
        if (ahora.isBefore(horaReservaHoy)) {
          mensajeHoy = '\n⚠️ IMPORTANTE: Como aún no son las ${reserva.horario}, la reserva de HOY también será cancelada.';
          mostrarAdvertenciaHoy = true;
        } else {
          mensajeHoy = '\n✅ La reserva de hoy (${reserva.horario}) se mantendrá en el inventario porque ya pasó la hora.';
        }
      } catch (e) {
        mensajeHoy = '\n✅ La reserva de hoy se mantendrá en el inventario.';
      }
    } else {
      mensajeHoy = '\n📅 Hoy no hay reserva programada para este horario.';
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Cancelar Reservas Futuras',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Estás seguro de que deseas cancelar todas las reservas futuras de ${reserva.clienteNombre}?',
              style: GoogleFonts.montserrat(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: mostrarAdvertenciaHoy ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                mensajeHoy,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: mostrarAdvertenciaHoy ? Colors.orange.shade700 : Colors.blue.shade700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '🗓️ Todas las reservas desde mañana serán canceladas.',
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Cancelar Futuras', style: GoogleFonts.montserrat()),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        final provider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
        
        await provider.cancelarReservasFuturas(reserva.id);
        
        if (mounted) Navigator.pop(context);
        
        if (mounted) Navigator.pop(context);
        
        if (mounted) {
          String mensajeExito = 'Reservas futuras canceladas correctamente.';
          if (mostrarAdvertenciaHoy) {
            mensajeExito += ' La reserva de hoy también fue cancelada porque aún no era la hora.';
          } else if (esHoyDiaValido && !yaEstaExcluidoHoy) {
            mensajeExito += ' La reserva de hoy se mantiene en el inventario.';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                mensajeExito,
                style: GoogleFonts.montserrat(),
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
              duration: const Duration(seconds: 5),
            ),
          );
          
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            await _loadReservas();
          }
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        
        if (mounted) {
          _showErrorSnackBar('Error al cancelar reservas futuras: $e');
        }
      }
    }
  }

  AppBar buildAppBar() {
  return AppBar(
    title: Text(
      widget.esModoSelector ? 'Seleccionar Nueva Reserva' : 'Reservas',
      style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
    ),
    automaticallyImplyLeading: false,
    backgroundColor: _backgroundColor,
    elevation: 0,
    foregroundColor: _primaryColor,
    actions: [
      // ✅ MOSTRAR BOTÓN CONFIRMAR EN MODO SELECTOR (INCLUSO SIN SELECCIÓN)
      if (widget.esModoSelector) ...[
        Container(
          margin: EdgeInsets.only(right: 16),
          child: ElevatedButton.icon(
            onPressed: _selectedHours.isNotEmpty ? _confirmarSeleccion : null,
            icon: Icon(Icons.check, size: 18),
            label: Text('Confirmar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedHours.isNotEmpty ? _secondaryColor : _disabledColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ],
      // ✅ BOTONES NORMALES SOLO CUANDO NO ES MODO SELECTOR
      if (!widget.esModoSelector) ...[
        Tooltip(
          message: 'Reservas Recurrentes',
          child: Container(
            margin: EdgeInsets.only(right: 4),
            child: IconButton(
              icon: Icon(Icons.repeat_rounded, color: _secondaryColor),
              onPressed: _mostrarReservasRecurrentes,
            ),
          ),
        ),
        Tooltip(
          message: _viewGrid ? 'Vista en Lista' : 'Vista en Calendario',
          child: Container(
            margin: EdgeInsets.only(right: 16),
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
    ],
  );
}


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1200;
        final crossAxisCount = isMobile ? 3 : isTablet ? 4 : 6;
        final childAspectRatio = isMobile ? 1.5 : isTablet ? 1.8 : 1.8;

        return Scaffold(
          appBar: buildAppBar(),
          floatingActionButton: widget.esModoSelector 
            ? null
            : _selectedHours.isNotEmpty
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
                      
                      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
                      await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
                      
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
                        
                        final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
                        await reservaRecurrenteProvider.fetchReservasRecurrentes(sede: _selectedSedeId);
                        
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
              final isReserved = _reservedMap.containsKey(horaNormalizada);
              final isSelected = _selectedHours.contains(horaNormalizada);
              final reserva = isReserved ? _reservedMap[horaNormalizada] : null;

              Color textColor;
              Color shadowColor;
              IconData statusIcon;
              String statusText;

              if (isReserved) {
                final bool isRecurrent = reserva?.esReservaRecurrente ?? false;
                
                if (isRecurrent) {
                  textColor = const Color(0xFF1A237E);
                  shadowColor = const Color(0xFF1A237E).withOpacity(0.2);
                  statusIcon = Icons.repeat_rounded;
                  statusText = 'Recurrente';
                } else {
                  textColor = _reservedColor;
                  shadowColor = const Color.fromRGBO(76, 175, 80, 0.15);
                  statusIcon = Icons.event_busy;
                  statusText = 'Reservado';
                }
              } else if (isSelected) {
                textColor = _selectedHourColor;
                shadowColor = const Color.fromRGBO(255, 202, 40, 0.2);
                statusIcon = Icons.check_circle;
                statusText = 'Seleccionado';
              } else {
                textColor = _primaryColor;
                shadowColor = const Color.fromRGBO(60, 64, 67, 0.1);
                statusIcon = Icons.event_available;
                statusText = 'Disponible';
              }

              final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
              double precio = _selectedCancha != null
                  ? (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] is Map<String, dynamic>
                      ? ((_selectedCancha!.preciosPorHorario[day]![horaNormalizada] as Map<String, dynamic>)['precio'] as num?)?.toDouble() ??
                          _selectedCancha!.precio
                      : (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] as num?)?.toDouble() ??
                          _selectedCancha!.precio)
                  : 0.0;

              if (isReserved && reserva != null) {
                precio = reserva.montoTotal;
              }

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
                      onTap: isReserved 
                          ? () => _viewReservaDetails(reserva!) 
                          : () => _toggleHourSelection(horaStr),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isReserved
                                ? (reserva?.confirmada ?? true ? _reservedColor : Colors.red)
                                : isSelected
                                    ? _selectedHourColor
                                    : const Color.fromRGBO(60, 64, 67, 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
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
              final isReserved = _reservedMap.containsKey(horaNormalizada);
              final isSelected = _selectedHours.contains(horaNormalizada);
              final reserva = isReserved ? _reservedMap[horaNormalizada] : null;

              Color textColor;
              Color shadowColor;
              Color leadingBackgroundColor;
              IconData statusIcon;
              String statusText;

              if (isReserved) {
                final bool isRecurrent = reserva?.esReservaRecurrente ?? false;
                
                if (isRecurrent) {
                  textColor = const Color(0xFF1A237E);
                  shadowColor = const Color(0xFF1A237E).withOpacity(0.2);
                  leadingBackgroundColor = const Color(0xFF1A237E).withOpacity(0.2);
                  statusIcon = Icons.repeat_rounded;
                  statusText = 'Recurrente';
                } else {
                  textColor = _reservedColor;
                  shadowColor = const Color.fromRGBO(76, 175, 80, 0.15);
                  leadingBackgroundColor = const Color.fromRGBO(76, 175, 80, 0.2);
                  statusIcon = Icons.event_busy;
                  statusText = 'Reservado';
                }
              } else if (isSelected) {
                textColor = _selectedHourColor;
                shadowColor = const Color.fromRGBO(255, 202, 40, 0.2);
                leadingBackgroundColor = _selectedHourColor;
                statusIcon = Icons.check_circle;
                statusText = 'Seleccionado';
              } else {
                textColor = _primaryColor;
                shadowColor = const Color.fromRGBO(60, 64, 67, 0.1);
                leadingBackgroundColor = _availableColor;
                statusIcon = Icons.event_available;
                statusText = 'Disponible';
              }

              final String day = DateFormat('EEEE', 'es').format(_selectedDate).toLowerCase();
              double precio = _selectedCancha != null
                  ? (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] is Map<String, dynamic>
                      ? ((_selectedCancha!.preciosPorHorario[day]![horaNormalizada] as Map<String, dynamic>)['precio'] as num?)?.toDouble() ??
                          _selectedCancha!.precio
                      : (_selectedCancha!.preciosPorHorario[day]?[horaNormalizada] as num?)?.toDouble() ??
                          _selectedCancha!.precio)
                  : 0.0;

              if (isReserved && reserva != null) {
                precio = reserva.montoTotal;
              }

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
                            color: isReserved
                                ? (reserva?.confirmada ?? true ? _reservedColor : Colors.red)
                                : isSelected
                                    ? _selectedHourColor
                                    : const Color.fromRGBO(60, 64, 67, 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          onTap: () {
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
                              color: leadingBackgroundColor,
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
                            '$statusText${isReserved ? ' por: ${reserva?.nombre ?? "Cliente"}' : isSelected ? '' : ' para reservar'} - COP ${precio.toInt()}',
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
                          trailing: isReserved
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