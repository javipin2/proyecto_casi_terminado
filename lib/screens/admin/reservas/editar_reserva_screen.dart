// lib/screens/admin/reservas/editar_reserva_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/models/cancha.dart';
import 'package:reserva_canchas/providers/reserva_recurrente_provider.dart';
import 'package:reserva_canchas/models/reserva.dart';
import 'package:reserva_canchas/models/horario.dart';
import 'package:reserva_canchas/providers/peticion_provider.dart';
import 'package:reserva_canchas/screens/admin/reservas/admin_reservas_horarios_screen.dart';

class EditarReservaScreen extends StatefulWidget {
  final Reserva reserva;
  final Map<String, dynamic>? grupoInfo;
  final bool isGrupoReserva;
  final bool esSuperAdmin;
  final bool esAdmin;

  const EditarReservaScreen({
    super.key,
    required this.reserva,
    this.grupoInfo,
    this.isGrupoReserva = false,
    this.esSuperAdmin = false,
    this.esAdmin = false,
  });

  @override
  EditarReservaScreenState createState() => EditarReservaScreenState();
}

class EditarReservaScreenState extends State<EditarReservaScreen> with TickerProviderStateMixin {
  late TextEditingController _nombreController;
  late TextEditingController _telefonoController;
  late TextEditingController _emailController;
  late TextEditingController _montoPagadoController;
  late TextEditingController _precioTotalController;
  TipoAbono? _selectedTipo;
  final _formKey = GlobalKey<FormState>();
  late Reserva _currentReserva;
  bool _precioEditableActivado = false;
  String? _nuevaSede;
  String? _nuevaCanchaId;
  String? _nuevoHorario;
  List<Map<String, dynamic>> _horariosDisponibles = [];
  List<Map<String, dynamic>> _canchasDisponibles = [];
  DateTime? _nuevaFecha;
  Map<String, dynamic> _valoresOriginales = {};
  late AnimationController _fadeController;
  bool _isLoading = true;
  bool _dataLoaded = false;
  double? _montoTotalCalculado;
  bool _isSaving = false;

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,##0', 'es_CO');
    return 'COP ${formatter.format(amount)}';
  }

  @override
void initState() {
  super.initState();
  _currentReserva = widget.reserva;
  _nuevaFecha = widget.reserva.fecha;
  _nuevaSede = widget.reserva.sede;
  _nuevaCanchaId = widget.reserva.cancha.id;
  _nuevoHorario = widget.reserva.horario.horaFormateada;
  _nombreController = TextEditingController(text: widget.reserva.nombre ?? '');
  _telefonoController = TextEditingController(text: widget.reserva.telefono ?? '');
  _emailController = TextEditingController(text: widget.reserva.email ?? '');
  _montoPagadoController = TextEditingController(text: widget.reserva.montoPagado.toStringAsFixed(0));
  _precioTotalController = TextEditingController();
  _selectedTipo = widget.reserva.tipoAbono;
  _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  
  // Inicializar escucha del provider
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (widget.esAdmin || widget.esSuperAdmin) {
      final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
      peticionProvider.iniciarEscuchaControlTotal();
      // 🆕 AÑADIR: Cargar configuración inicial
      peticionProvider.cargarConfiguracionControl();
    }
  });
  
  _initializeData();
}

  Future<void> _initializeData() async {
    try {
      _guardarValoresOriginales();
      await Future.wait([
        _verificarPrecioPersonalizado(),
        _cargarCanchasDisponibles(_nuevaSede!),
      ]).timeout(const Duration(seconds: 15));
      _montoTotalCalculado = await _calcularMontoTotal(_currentReserva);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dataLoaded = true;
        });
        _fadeController.forward();
        _nombreController.addListener(_onFieldChanged);
        _telefonoController.addListener(_onFieldChanged);
        _emailController.addListener(_onFieldChanged);
        _montoPagadoController.addListener(_onFieldChanged);
      }
    } catch (e) {
      debugPrint('Error inicializando datos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dataLoaded = true;
        });
        _fadeController.forward();
      }
    }
  }

  AppBar buildAppBar() {
    return AppBar(
      title: Text(widget.isGrupoReserva ? 'Editar Reserva Grupal' : 'Editar Reserva'),
      actions: [
        // Mostrar estado de permisos con mejor feedback
        Consumer<PeticionProvider>(
          builder: (context, peticionProvider, child) {
            if (widget.esSuperAdmin) {
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple.shade400, Colors.purple.shade600],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.admin_panel_settings, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'SUPER',
                      style: GoogleFonts.montserrat(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            } else if (widget.esAdmin) {
              final controlActivado = peticionProvider.controlTotalActivado;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: controlActivado 
                          ? LinearGradient(colors: [Colors.green.shade400, Colors.green.shade600])
                          : LinearGradient(colors: [Colors.orange.shade400, Colors.orange.shade600]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (controlActivado ? Colors.green : Colors.orange).withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          controlActivado ? Icons.admin_panel_settings : Icons.pending_actions,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          controlActivado ? 'DIRECTO' : 'PETICIÓN',
                          style: GoogleFonts.montserrat(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
        IconButton(
          icon: _isSaving 
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                )
              : const Icon(Icons.save),
          onPressed: _isSaving ? null : _saveChanges,
          tooltip: _isSaving ? 'Guardando...' : 'Guardar cambios',
        ),
      ],
    );
  }

  void _onFieldChanged() {
    if (_dataLoaded) {
      setState(() {});
    }
  }

  void _guardarValoresOriginales() {
    _valoresOriginales = {
      'nombre': widget.reserva.nombre,
      'telefono': widget.reserva.telefono,
      'correo': widget.reserva.email,
      'fecha': DateFormat('yyyy-MM-dd').format(widget.reserva.fecha),
      'horario': widget.reserva.horario.horaFormateada,
      'valor': widget.reserva.montoTotal,
      'montoPagado': widget.reserva.montoPagado,
      'estado': widget.reserva.tipoAbono == TipoAbono.completo ? 'completo' : 'parcial',
      'cancha_id': widget.reserva.cancha.id,
      'sede': widget.reserva.sede,
      'confirmada': widget.reserva.confirmada,
    };
  }

  Map<String, dynamic> _obtenerValoresActuales() {
    return {
      'nombre': _nombreController.text.trim(),
      'telefono': _telefonoController.text.trim(),
      'correo': _emailController.text.trim(),
      'fecha': DateFormat('yyyy-MM-dd').format(_nuevaFecha ?? _currentReserva.fecha),
      'horario': _nuevoHorario ?? _currentReserva.horario.horaFormateada,
      'valor': _precioEditableActivado 
          ? _calcularMontoPersonalizado() 
          : (_montoTotalCalculado ?? _currentReserva.montoTotal),
      'montoPagado': double.tryParse(_montoPagadoController.text) ?? _currentReserva.montoPagado,
      'estado': _selectedTipo == TipoAbono.completo ? 'completo' : 'parcial',
      'cancha_id': _nuevaCanchaId ?? _currentReserva.cancha.id,
      'sede': _nuevaSede ?? _currentReserva.sede,
      'confirmada': _currentReserva.confirmada,
    };
  }

  bool _hayCambios() {
    if (!_dataLoaded) return false;
    
    final valoresActuales = _obtenerValoresActuales();
    
    // Comparar cada valor de manera más precisa
    for (final key in _valoresOriginales.keys) {
      final valorOriginal = _valoresOriginales[key];
      final valorActual = valoresActuales[key];
      
      // Manejar comparaciones especiales
      if (key == 'valor' || key == 'montoPagado') {
        final originalDouble = (valorOriginal as num?)?.toDouble() ?? 0.0;
        final actualDouble = (valorActual as num?)?.toDouble() ?? 0.0;
        if ((originalDouble - actualDouble).abs() > 0.01) {
          return true;
        }
      } else if (valorOriginal != valorActual) {
        return true;
      }
    }
    
    return false;
  }

  Future<void> _cargarCanchasDisponibles(String sede) async {
    if (!mounted) return;
    debugPrint('Cargando canchas para sede: $sede');
    try {
      final canchasSnapshot = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sedeId', isEqualTo: sede)
          .get()
          .timeout(const Duration(seconds: 10));
      final canchas = canchasSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nombre': data['nombre'] ?? 'Sin nombre',
          'precio': data['precio'] ?? 0.0,
        };
      }).toList();
      if (mounted) {
        setState(() {
          _canchasDisponibles = canchas;
          if (_nuevaCanchaId != null && !canchas.any((c) => c['id'] == _nuevaCanchaId)) {
            _nuevaCanchaId = null;
            _nuevoHorario = null;
            _horariosDisponibles.clear();
          }
        });
      }
    } catch (e) {
      debugPrint('Error cargando canchas: $e');
      if (mounted) {
        setState(() {
          _canchasDisponibles = [];
          _nuevaCanchaId = null;
          _nuevoHorario = null;
          _horariosDisponibles.clear();
        });
      }
    }
  }

  Future<void> _abrirSelectorReserva() async {
    try {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => AdminReservasScreen(
            esModoSelector: true,
            reservaOriginalId: widget.reserva.id,
          ),
        ),
      );

      if (result != null && mounted) {
        await _actualizarDatosSeleccionados(result);
      }
    } catch (e) {
      debugPrint('Error al abrir selector de reserva: $e');
      _mostrarError('Error al abrir el selector. Intenta de nuevo.');
    }
  }

  Future<void> _actualizarDatosSeleccionados(Map<String, dynamic> datosSeleccionados) async {
    try {
      setState(() {
        _nuevaSede = datosSeleccionados['sede'] as String;
        _nuevaCanchaId = datosSeleccionados['canchaId'] as String;
        _nuevoHorario = datosSeleccionados['horario'] as String;
        _nuevaFecha = datosSeleccionados['fecha'] as DateTime;
      });
      
      await _cargarCanchasDisponibles(_nuevaSede!);
      
      await _recalcularPrecioConNuevosDatos();
      
      _mostrarExito('Datos actualizados. Revisa la información y presiona "Guardar" para confirmar los cambios.');
    } catch (e) {
      debugPrint('Error actualizando datos seleccionados: $e');
      _mostrarError('Error al actualizar los datos seleccionados.');
    }
  }

  Future<void> _recalcularPrecioConNuevosDatos() async {
    if (_nuevaCanchaId == null || _nuevoHorario == null || _nuevaFecha == null) return;
    
    try {
      final canchaDoc = await FirebaseFirestore.instance
          .collection('canchas')
          .doc(_nuevaCanchaId!)
          .get();
      
      if (canchaDoc.exists) {
        final cancha = Cancha.fromFirestore(canchaDoc);
        final horario = Horario.fromHoraFormateada(_nuevoHorario!);
        
        final nuevoPrecio = Reserva.calcularMontoTotal(cancha, _nuevaFecha!, horario);
        
        setState(() {
          _montoTotalCalculado = nuevoPrecio;
          if (!_precioEditableActivado) {
            // El precio se mostrará automáticamente en la UI
          }
        });
      }
    } catch (e) {
      debugPrint('Error recalculando precio: $e');
    }
  }

  @override
  void dispose() {
    // Detener escucha del provider
    if (widget.esAdmin || widget.esSuperAdmin) {
      try {
        Provider.of<PeticionProvider>(context, listen: false).detenerEscuchaControlTotal();
      } catch (e) {
        debugPrint('Error deteniendo escucha: $e');
      }
    }
    
    _nombreController.removeListener(_onFieldChanged);
    _telefonoController.removeListener(_onFieldChanged);
    _emailController.removeListener(_onFieldChanged);
    _montoPagadoController.removeListener(_onFieldChanged);
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _montoPagadoController.dispose();
    _precioTotalController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<double> _calcularMontoTotal(Reserva reserva) async {
    DateFormat('EEEE', 'es').format(reserva.fecha).toLowerCase();
    Cancha cancha = reserva.cancha;
    if (cancha.preciosPorHorario.isEmpty || cancha.precio == 0) {
      try {
        final canchaDoc = await FirebaseFirestore.instance
            .collection('canchas')
            .doc(reserva.cancha.id)
            .get();
        if (canchaDoc.exists) {
          cancha = Cancha.fromFirestore(canchaDoc);
        }
      } catch (e) {
        debugPrint('Error al cargar cancha: $e');
      }
    }
    double montoTotal = 0.0;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(reserva.id)
          .get();
      List<String> horarios = [];
      if (doc.exists && doc.data() != null) {
        final data = doc.data();
        horarios = (data?['horarios'] as List<dynamic>?)?.cast<String>() ?? [reserva.horario.horaFormateada];
      } else {
        horarios = [reserva.horario.horaFormateada];
      }
      for (var horarioStr in horarios) {
        try {
          final time = DateFormat('h:mm a').parse(horarioStr);
          final horario = Horario(hora: TimeOfDay(hour: time.hour, minute: time.minute));
          final precio = Reserva.calcularMontoTotal(cancha, reserva.fecha, horario);
          montoTotal += precio;
        } catch (e) {
          debugPrint('Error al parsear hora: $horarioStr, error: $e');
          montoTotal += cancha.precio;
        }
      }
    } catch (e) {
      debugPrint('Error Firestore: $e');
      montoTotal = Reserva.calcularMontoTotal(cancha, reserva.fecha, reserva.horario);
    }
    return montoTotal;
  }

  Future<void> _verificarPrecioPersonalizado() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reserva.id)
          .get()
          .timeout(const Duration(seconds: 5));
      if (doc.exists && doc.data() != null && mounted) {
        final data = doc.data()!;
        final precioPersonalizado = data['precio_personalizado'] as bool?;
        final montoTotal = data['valor'] as double?;
        if (precioPersonalizado == true && montoTotal != null) {
          setState(() {
            _precioEditableActivado = true;
            _precioTotalController.text = montoTotal.toStringAsFixed(0);
          });
        }
      }
    } catch (e) {
      debugPrint('Error verificando precio personalizado: $e');
    }
  }

  double _calcularMontoPersonalizado() {
    if (_precioEditableActivado && _precioTotalController.text.isNotEmpty) {
      return double.tryParse(_precioTotalController.text) ?? 0.0;
    }
    return _montoTotalCalculado ?? _currentReserva.montoTotal;
  }

  // 🔥 MÉTODO PRINCIPAL CORREGIDO - Lógica de guardado simplificada
  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      if (!mounted) return;
      _mostrarError('Por favor, corrige los errores en el formulario.');
      return;
    }
    
    if (FirebaseAuth.instance.currentUser == null) {
      if (!mounted) return;
      _mostrarError('Debes iniciar sesión como administrador para editar reservas.');
      return;
    }
    
    setState(() {
      _isSaving = true;
    });

    try {
      // Validaciones básicas
      double montoTotal = _precioEditableActivado
          ? _calcularMontoPersonalizado()
          : (_montoTotalCalculado ?? await _calcularMontoTotal(_currentReserva));
      double montoPagado = double.tryParse(_montoPagadoController.text) ?? _currentReserva.montoPagado;
      
      // Validaciones de montos
      if (montoPagado < 20000) {
        if (!mounted) return;
        _mostrarError('El abono debe ser al menos 20000.');
        setState(() { _isSaving = false; });
        return;
      }
      if (montoPagado > montoTotal) {
        if (!mounted) return;
        _mostrarError('El abono no puede superar el monto total.');
        setState(() { _isSaving = false; });
        return;
      }
      if (_selectedTipo == TipoAbono.completo && montoPagado != montoTotal) {
        if (!mounted) return;
        _mostrarError('El abono debe ser igual al monto total para un pago completo.');
        setState(() { _isSaving = false; });
        return;
      }
      if (_selectedTipo == TipoAbono.parcial && montoPagado == montoTotal) {
        if (!mounted) return;
        _mostrarError('El abono debe ser menor al monto total para un pago parcial.');
        setState(() { _isSaving = false; });
        return;
      }
      
      if (!_hayCambios()) {
        if (!mounted) return;
        _mostrarError('No se detectaron cambios para guardar.');
        setState(() { _isSaving = false; });
        return;
      }

      final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
      
      // 🆕 LÓGICA SIMPLIFICADA: Verificar permisos
      bool puedeHacerCambiosDirectos = false;
      
      if (widget.esSuperAdmin) {
        puedeHacerCambiosDirectos = true;
        debugPrint('✅ SuperAdmin: Cambios directos permitidos');
      } else if (widget.esAdmin) {
        // Para admins, verificar el estado del control total
        await peticionProvider.cargarConfiguracionControl();
        puedeHacerCambiosDirectos = peticionProvider.controlTotalActivado;
        debugPrint('🔧 Admin: Control total = ${peticionProvider.controlTotalActivado}');
      }
      
      if (puedeHacerCambiosDirectos) {
        debugPrint('🚀 Aplicando cambios directamente...');
        await _aplicarCambiosDirectamente();
      } else {
        debugPrint('📝 Creando petición...');
        await _crearPeticionCambios();
      }
      
    } catch (e) {
      debugPrint('Error al procesar cambios: $e');
      if (!mounted) return;
      _mostrarError('Error al procesar los cambios: $e');
      setState(() { _isSaving = false; });
    }
  }

  // 🔥 MÉTODO CORREGIDO - Aplicar cambios directos
  Future<void> _aplicarCambiosDirectamente() async {
    try {
      final valoresActuales = _obtenerValoresActuales();
      
      // Validar disponibilidad si hay cambios de fecha, cancha o horario
      final cambiosImportantes = 
          valoresActuales['fecha'] != _valoresOriginales['fecha'] ||
          valoresActuales['cancha_id'] != _valoresOriginales['cancha_id'] ||
          valoresActuales['horario'] != _valoresOriginales['horario'] ||
          valoresActuales['sede'] != _valoresOriginales['sede'];

      if (cambiosImportantes) {
        final disponible = await _verificarDisponibilidadCompleta(
          DateTime.parse(valoresActuales['fecha']),
          valoresActuales['cancha_id'],
          valoresActuales['horario'],
        );

        if (!disponible) {
          final continuar = await _mostrarDialogoConflictoHorario();
          if (!continuar) {
            setState(() { _isSaving = false; });
            return;
          }
        }
      }

      // Preparar datos para actualización - MEJORADO
      final updateData = <String, dynamic>{
        'nombre': valoresActuales['nombre'],
        'telefono': valoresActuales['telefono'],
        'correo': valoresActuales['correo'],
        'valor': valoresActuales['valor'],
        'montoPagado': valoresActuales['montoPagado'],
        'estado': valoresActuales['estado'],
        'confirmada': valoresActuales['confirmada'],
        'precio_personalizado': _precioEditableActivado,
        'fechaActualizacion': Timestamp.now(),
        'usuario_modificacion': FirebaseAuth.instance.currentUser?.uid,
      };

      // Añadir cambios de fecha, sede, cancha y horario si los hay
      if (cambiosImportantes) {
        updateData.addAll({
          'fecha': valoresActuales['fecha'],
          'sede': valoresActuales['sede'],
          'cancha_id': valoresActuales['cancha_id'],
          'horario': valoresActuales['horario'],
        });

        // Si cambió la cancha, actualizar también la información de la cancha
        if (valoresActuales['cancha_id'] != _valoresOriginales['cancha_id']) {
          final nuevaCancha = await _obtenerDatosCancha(valoresActuales['cancha_id']);
          if (nuevaCancha != null) {
            updateData['cancha_nombre'] = nuevaCancha['nombre'];
            updateData['cancha_precio'] = nuevaCancha['precio'];
          }
        }
      }

      // Obtener horarios existentes para mantener compatibilidad
      final doc = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reserva.id)
          .get();

      if (doc.exists && doc.data() != null) {
        final horarios = (doc.data()!['horarios'] as List<dynamic>?)?.cast<String>() ?? 
                       [valoresActuales['horario']];
        
        // Actualizar horarios si cambió el horario principal
        if (valoresActuales['horario'] != _valoresOriginales['horario']) {
          updateData['horarios'] = [valoresActuales['horario']];
        } else {
          updateData['horarios'] = horarios;
        }
      } else {
        updateData['horarios'] = [valoresActuales['horario']];
      }

      // 🚀 Ejecutar actualización en Firestore
      debugPrint('📡 Actualizando reserva ${widget.reserva.id} con datos: ${updateData.keys}');
      
      await FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reserva.id)
          .update(updateData);

      // Crear log de auditoría
      await _crearLogAuditoria('EDICION_DIRECTA', valoresActuales);

      if (!mounted) return;
      
      setState(() {
        _isSaving = false;
      });

      _mostrarExito('✅ Reserva actualizada exitosamente${widget.esSuperAdmin ? " (SuperAdmin)" : " (Control Total)"}.');
      Navigator.of(context).pop(true);

    } catch (e) {
      debugPrint('❌ Error al aplicar cambios directamente: $e');
      if (!mounted) return;
      
      setState(() {
        _isSaving = false;
      });
      
      // Mensaje de error más específico
      String mensajeError = 'Error al actualizar la reserva';
      if (e.toString().contains('permission-denied')) {
        mensajeError = 'Sin permisos suficientes. Verifica que el control total esté activado.';
      } else if (e.toString().contains('not-found')) {
        mensajeError = 'La reserva no fue encontrada.';
      }
      
      _mostrarError('$mensajeError: $e');
    }
  }

  Future<bool> _verificarDisponibilidadCompleta(
    DateTime fecha,
    String canchaId,
    String horario,
  ) async {
    try {
      // Verificar reservas normales
      final reservasNormales = await FirebaseFirestore.instance
          .collection('reservas')
          .where('cancha_id', isEqualTo: canchaId)
          .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(fecha))
          .where('horario', isEqualTo: horario)
          .get();

      // Filtrar la reserva actual
      final reservasConflicto = reservasNormales.docs
          .where((doc) => doc.id != widget.reserva.id)
          .toList();

      if (reservasConflicto.isNotEmpty) {
        return false; // Hay conflicto con reservas normales
      }

      // Verificar reservas recurrentes
      final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(
        context, 
        listen: false
      );

      final reservasRecurrentesActivas = reservaRecurrenteProvider
          .obtenerReservasActivasParaFecha(
        fecha,
        sede: _nuevaSede,
        canchaId: canchaId,
      );

      final horarioNormalizado = Horario.normalizarHora(horario);
      final tieneConflictoRecurrente = reservasRecurrentesActivas.any((reserva) {
        return Horario.normalizarHora(reserva.horario) == horarioNormalizado;
      });

      return !tieneConflictoRecurrente;

    } catch (e) {
      debugPrint('Error verificando disponibilidad: $e');
      return true; // En caso de error, permitir el cambio
    }
  }

  /// **Obtener datos actualizados de la cancha**
  Future<Map<String, dynamic>?> _obtenerDatosCancha(String canchaId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('canchas')
          .doc(canchaId)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return {
          'nombre': data['nombre'] ?? 'Sin nombre',
          'precio': data['precio'] ?? 0.0,
          'preciosPorHorario': data['preciosPorHorario'] ?? {},
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error obteniendo datos de cancha: $e');
      return null;
    }
  }

  /// **Mostrar diálogo de conflicto de horario**
  Future<bool> _mostrarDialogoConflictoHorario() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Text('Conflicto de Horario'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ya existe una reserva para esta cancha en la fecha y hora seleccionadas.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fecha: ${DateFormat('EEEE d MMMM, yyyy', 'es').format(_nuevaFecha!)}'),
                  Text('Cancha: ${_nuevaCanchaId}'),
                  Text('Horario: $_nuevoHorario'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ Este cambio podría crear una doble reserva. ¿Deseas continuar de todos modos?',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// **Crear log de auditoría**
  Future<void> _crearLogAuditoria(
    String tipoAccion, 
    Map<String, dynamic> valoresNuevos
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('audit_logs')
          .add({
        'tipo_accion': tipoAccion,
        'usuario_id': user.uid,
        'usuario_email': user.email,
        'reserva_id': widget.reserva.id,
        'valores_anteriores': _valoresOriginales,
        'valores_nuevos': valoresNuevos,
        'fecha': Timestamp.now(),
        'control_total_activo': Provider.of<PeticionProvider>(context, listen: false).controlTotalActivado,
        'es_superadmin': widget.esSuperAdmin,
      });
    } catch (e) {
      debugPrint('Error creando log de auditoría: $e');
    }
  }

  Future<void> _crearPeticionCambios() async {
    try {
      final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
      final valoresActuales = _obtenerValoresActuales();
      final peticionId = await peticionProvider.crearPeticion(
        reservaId: widget.reserva.id,
        valoresAntiguos: _valoresOriginales,
        valoresNuevos: valoresActuales,
      );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      await _mostrarDialogoPeticionCreada(peticionId);
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Error al crear petición: $e');
      if (!mounted) return;
      _mostrarError('Error al crear la petición: $e');
      setState(() { _isSaving = false; });
    }
  }

  Future<void> _mostrarDialogoPeticionCreada(String peticionId) async {
    final cambiosRealizados = _obtenerResumenCambios();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.pending_actions,
                  color: Colors.orange.shade700,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Petición Enviada Exitosamente'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu petición de cambios ha sido enviada y está pendiente de aprobación.',
                  style: GoogleFonts.montserrat(fontSize: 16),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ID de Petición: ${peticionId.substring(0, 12)}...',
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      if (cambiosRealizados.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Cambios solicitados:',
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        ...cambiosRealizados.map((cambio) => Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 2),
                          child: Text(
                            '• $cambio',
                            style: GoogleFonts.montserrat(fontSize: 14),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '¿Qué pasa ahora?',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. Un superadministrador revisará tus cambios\n'
                        '2. Recibirás una notificación con la decisión\n'
                        '3. Si se aprueba, los cambios se aplicarán automáticamente',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'Entendido',
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  List<String> _obtenerResumenCambios() {
    final valoresOriginales = _valoresOriginales;
    final valoresActuales = _obtenerValoresActuales();
    List<String> cambios = [];
    valoresActuales.forEach((key, newValue) {
      final oldValue = valoresOriginales[key];
      if (oldValue != newValue) {
        switch (key) {
          case 'nombre':
            cambios.add('Nombre: "$oldValue" → "$newValue"');
            break;
          case 'telefono':
            cambios.add('Teléfono: "$oldValue" → "$newValue"');
            break;
          case 'correo':
            cambios.add('Correo: "$oldValue" → "$newValue"');
            break;
          case 'fecha':
            try {
              final oldDate = DateFormat('dd/MM/yyyy').format(DateFormat('yyyy-MM-dd').parse(oldValue.toString()));
              final newDate = DateFormat('dd/MM/yyyy').format(DateFormat('yyyy-MM-dd').parse(newValue.toString()));
              cambios.add('Fecha: $oldDate → $newDate');
            } catch (e) {
              cambios.add('Fecha modificada');
            }
            break;
          case 'valor':
            final formatter = NumberFormat('#,##0', 'es_CO');
            final oldVal = (oldValue as num?)?.toDouble() ?? 0;
            final newVal = (newValue as num?)?.toDouble() ?? 0;
            cambios.add('Valor: COP ${formatter.format(oldVal)} → COP ${formatter.format(newVal)}');
            break;
          case 'montoPagado':
            final formatter = NumberFormat('#,##0', 'es_CO');
            final oldVal = (oldValue as num?)?.toDouble() ?? 0;
            final newVal = (newValue as num?)?.toDouble() ?? 0;
            cambios.add('Abono: COP ${formatter.format(oldVal)} → COP ${formatter.format(newVal)}');
            break;
          case 'estado':
            final oldEstado = oldValue == 'completo' ? 'Completo' : 'Pendiente';
            final newEstado = newValue == 'completo' ? 'Completo' : 'Pendiente';
            cambios.add('Estado: $oldEstado → $newEstado');
            break;
          case 'cancha_id':
            cambios.add('Cancha modificada');
            break;
          case 'sede':
            cambios.add('Sede: $oldValue → $newValue');
            break;
          case 'horario':
            cambios.add('Horario: $oldValue → $newValue');
            break;
        }
      }
    });
    return cambios;
  }

  Future<bool> _confirmarSalidaConCambios() async {
    if (!_hayCambios()) return true;
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Text('Cambios sin guardar'),
          ],
        ),
        content: Text(
          'Tienes cambios sin guardar. ¿Estás seguro que deseas salir sin guardar?',
          style: GoogleFonts.montserrat(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Salir sin guardar',
              style: GoogleFonts.montserrat(color: Colors.red),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(context).pop(false);
              _saveChanges();
            },
            child: const Text('Guardar y salir'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mensaje,
                style: GoogleFonts.montserrat(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mensaje,
                style: GoogleFonts.montserrat(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Localizations(
      locale: const Locale('es', 'ES'),
      delegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: WillPopScope(
        onWillPop: _confirmarSalidaConCambios,
        child: Scaffold(
          appBar: buildAppBar(),
          body: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Cargando datos de la reserva...',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        // Indicador de cambios pendientes
                        if (_hayCambios())
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.edit_note, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Tienes cambios sin guardar',
                                    style: GoogleFonts.montserrat(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                                Icon(Icons.warning, color: Colors.orange.shade600, size: 20),
                              ],
                            ),
                          ).animate().fadeIn().slideY(begin: -0.2, end: 0),
                        
                        _buildInfoEditCard(),
                        const SizedBox(height: 16),
                        _buildFormEditCard(),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildInfoEditCard() {
    return FutureBuilder<double>(
      future: _calcularMontoTotal(_currentReserva),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            child: Container(
              height: 200,
              child: const Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error cargando información: ${snapshot.error}',
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        
        final montoTotal = snapshot.data ?? 0.0;
        
        final hayNuevosDatos = _nuevaFecha != widget.reserva.fecha ||
            _nuevaSede != widget.reserva.sede ||
            _nuevaCanchaId != widget.reserva.cancha.id ||
            _nuevoHorario != widget.reserva.horario.horaFormateada;
        
        return Card(
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Información de la Reserva',
                      style: GoogleFonts.montserrat(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                if (hayNuevosDatos) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange.shade50, Colors.orange.shade100],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'CAMBIOS PENDIENTES',
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Los siguientes cambios se aplicarán al guardar:',
                          style: GoogleFonts.montserrat(
                            color: Colors.orange.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _abrirSelectorReserva,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.edit_calendar,
                                    color: Theme.of(context).primaryColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Modificar Fecha, Sede, Cancha y Horario',
                                    style: GoogleFonts.montserrat(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (!hayNuevosDatos) ...[
                              _buildInfoRow('Fecha:', DateFormat('EEEE d MMMM, yyyy', 'es').format(widget.reserva.fecha)),
                              _buildInfoRow('Sede:', widget.reserva.sede),
                              _buildInfoRow('Cancha:', widget.reserva.cancha.nombre),
                              _buildInfoRow('Horario:', widget.reserva.horario.horaFormateada),
                            ] else ...[
                              _buildComparacionDatos('Fecha:', 
                                DateFormat('EEEE d MMMM, yyyy', 'es').format(widget.reserva.fecha),
                                DateFormat('EEEE d MMMM, yyyy', 'es').format(_nuevaFecha!)),
                              
                              _buildComparacionDatos('Sede:', widget.reserva.sede, _nuevaSede!),
                              
                              FutureBuilder<String>(
                                future: _obtenerNombreCancha(_nuevaCanchaId!),
                                builder: (context, snapshot) {
                                  return _buildComparacionDatos('Cancha:', 
                                    widget.reserva.cancha.nombre, 
                                    snapshot.data ?? 'Cargando...');
                                },
                              ),
                              
                              _buildComparacionDatos('Horario:', 
                                widget.reserva.horario.horaFormateada, 
                                _nuevoHorario!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Switch para precio editable
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Editar precio total',
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.w500,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ),
                          Switch(
                            value: _precioEditableActivado,
                            onChanged: (value) {
                              setState(() {
                                _precioEditableActivado = value;
                                if (value && _precioTotalController.text.isEmpty) {
                                  _precioTotalController.text = (_montoTotalCalculado ?? montoTotal).toStringAsFixed(0);
                                }
                              });
                            },
                            activeColor: Colors.blue.shade600,
                          ),
                        ],
                      ),
                      if (_precioEditableActivado) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _precioTotalController,
                          decoration: InputDecoration(
                            labelText: 'Precio Total Personalizado',
                            prefixText: 'COP ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.blue.shade600),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa el precio total';
                            }
                            final parsedValue = double.tryParse(value);
                            if (parsedValue == null || parsedValue <= 0) {
                              return 'Ingresa un precio válido';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            setState(() {});
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade50, Colors.green.shade100],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.attach_money, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Valor Total: ${_formatCurrency(_precioEditableActivado ? _calcularMontoPersonalizado() : (_montoTotalCalculado ?? montoTotal))}',
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: Colors.green.shade800,
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
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.montserrat(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparacionDatos(String label, String valorOriginal, String valorNuevo) {
    final bool hayCambio = valorOriginal != valorNuevo;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hayCambio) 
                  Text(
                    valorOriginal,
                    style: GoogleFonts.montserrat(),
                  )
                else ...[
                  Text(
                    valorOriginal,
                    style: GoogleFonts.montserrat(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.arrow_forward, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          valorNuevo,
                          style: GoogleFonts.montserrat(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _obtenerNombreCancha(String canchaId) async {
    try {
      final cancha = _canchasDisponibles.firstWhere(
        (c) => c['id'] == canchaId,
        orElse: () => <String, dynamic>{},
      );
      
      if (cancha.isNotEmpty) {
        return cancha['nombre'] as String;
      }
      
      final doc = await FirebaseFirestore.instance
          .collection('canchas')
          .doc(canchaId)
          .get();
      
      if (doc.exists && doc.data() != null) {
        return doc.data()!['nombre'] as String? ?? 'Sin nombre';
      }
      
      return 'Cancha no encontrada';
    } catch (e) {
      debugPrint('Error obteniendo nombre de cancha: $e');
      return 'Error cargando nombre';
    }
  }

  Widget _buildFormEditCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person_outline,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Información del Cliente',
                  style: GoogleFonts.montserrat(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            TextFormField(
              controller: _nombreController,
              decoration: InputDecoration(
                labelText: 'Nombre',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
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
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
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
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa el correo';
                }
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(value)) {
                  return 'Ingresa un correo válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _montoPagadoController,
              decoration: InputDecoration(
                labelText: 'Abono',
                prefixText: 'COP ',
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
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
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            DropdownButtonFormField<TipoAbono>(
              value: _selectedTipo,
              decoration: InputDecoration(
                labelText: 'Estado de pago',
                prefixIcon: const Icon(Icons.payment),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: TipoAbono.parcial,
                  child: Text('Pendiente'),
                ),
                DropdownMenuItem(
                  value: TipoAbono.completo,
                  child: Text('Completo'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedTipo = value;
                });
              },
            ),
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSaving 
                      ? Colors.grey.shade400 
                      : Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: _isSaving ? 0 : 4,
                ),
                child: _isSaving 
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Guardando...',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Guardar Cambios',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}