// lib/screens/admin/reservas/editar_reserva_screen.dart

import 'dart:async';

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
import 'package:reserva_canchas/screens/admin/reservas/admin_reservas_horarios_screen.dart';
import 'package:reserva_canchas/utils/reserva_audit_utils.dart';
import 'package:reserva_canchas/services/lugar_helper.dart';


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
  late TextEditingController _montoPagadoController;
  late TextEditingController _precioTotalController;
  // Removemos _inicioSesionEdicion ya que no se usa
  String? _motivoPrecioPersonalizado;
  Map<String, dynamic> _valoresOriginales = {}; 
  TipoAbono? _selectedTipo;
  final _formKey = GlobalKey<FormState>();
  late Reserva _currentReserva;
  bool _precioEditableActivado = false;
  String? _nuevaSede;
  String? _nuevaCanchaId;
  String? _nuevoHorario;
  final List<Map<String, dynamic>> _horariosDisponibles = [];
  List<Map<String, dynamic>> _canchasDisponibles = [];
  DateTime? _nuevaFecha;
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
  // Removemos la línea que ya no se necesita
    _guardarValoresOriginales();
  _currentReserva = widget.reserva;
  _nuevaFecha = widget.reserva.fecha;
  _nuevaSede = widget.reserva.sede;
  _nuevaCanchaId = widget.reserva.cancha.id;
  _nuevoHorario = widget.reserva.horario.horaFormateada;
  _nombreController = TextEditingController(text: widget.reserva.nombre ?? '');
  _telefonoController = TextEditingController(text: widget.reserva.telefono ?? '');
  _montoPagadoController = TextEditingController(text: widget.reserva.montoPagado.toStringAsFixed(0));
  _precioTotalController = TextEditingController();
  _selectedTipo = widget.reserva.tipoAbono;
  
  _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  
  // Inicialización con debounce para evitar múltiples rebuilds
  _initializeDataWithDebounce();
  
  // Configurar listeners con debounce
  _setupControllersWithDebounce();
}

void _initializeDataWithDebounce() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      if (widget.esAdmin || widget.esSuperAdmin) {
        // Sin peticiones: los cambios se aplican siempre directamente
      }
      _initializeData();
    }
  });
}


  void _setupControllersWithDebounce() {
  // Eliminamos los listeners problemáticos que causan setState en cada tecla
  // Los campos de texto funcionarán sin necesidad de listeners adicionales
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
        // Eliminamos los listeners que causan setState en cada tecla
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
        if (widget.esSuperAdmin)
          Container(
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
          )
        else if (widget.esAdmin)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade600]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  'ADMIN',
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
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

  // Eliminamos el método _onFieldChanged que causaba setState innecesario

  void _guardarValoresOriginales() {
    _valoresOriginales = {
      'nombre': widget.reserva.nombre,
      'telefono': widget.reserva.telefono,
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


  List<String> _obtenerCamposModificados() {
    final valoresActuales = _obtenerValoresActuales();
    final camposModificados = <String>[];
    
    _valoresOriginales.forEach((key, oldValue) {
      final newValue = valoresActuales[key];
      if (oldValue != newValue) {
        if (key == 'valor' || key == 'montoPagado') {
          final oldDouble = (oldValue as num?)?.toDouble() ?? 0.0;
          final newDouble = (newValue as num?)?.toDouble() ?? 0.0;
          if ((oldDouble - newDouble).abs() > 0.01) {
            camposModificados.add(key);
          }
        } else {
          camposModificados.add(key);
        }
      }
    });
    
    return camposModificados;
  }

  Future<bool> _verificarControlTotalActivo() async {
    return widget.esSuperAdmin || widget.esAdmin;
  }



  Future<void> _cargarCanchasDisponibles(String sede) async {
    if (!mounted) return;
    debugPrint('Cargando canchas para sede: $sede');
    try {
      // Obtener lugarId del usuario autenticado
      final lugarId = await LugarHelper.getLugarId();
      if (lugarId == null) {
        debugPrint('EditarReservaScreen: No se pudo obtener lugarId');
        return;
      }

      final canchasSnapshot = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sedeId', isEqualTo: sede)
          .where('lugarId', isEqualTo: lugarId) // ✅ Agregar filtrado por lugarId
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
    _nombreController.dispose();
    _telefonoController.dispose();
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

    // ✅ NUEVO: Validar montos negativos
    if (montoTotal < 0) {
      if (!mounted) return;
      _mostrarError('El monto total no puede ser negativo.');
      setState(() { _isSaving = false; });
      return;
    }
    if (montoPagado < 0) {
      if (!mounted) return;
      _mostrarError('El abono no puede ser negativo.');
      setState(() { _isSaving = false; });
      return;
    }
    
    // Validaciones de montos ACTUALIZADAS
    if (montoPagado > 0 && montoPagado > montoTotal) {
      if (!mounted) return;
      _mostrarError('El abono no puede superar el monto total.');
      setState(() { _isSaving = false; });
      return;
    }
    if (_selectedTipo == TipoAbono.completo && montoPagado > 0 && montoPagado != montoTotal) {
      if (!mounted) return;
      _mostrarError('El abono debe ser igual al monto total para un pago completo.');
      setState(() { _isSaving = false; });
      return;
    }
    if (_selectedTipo == TipoAbono.parcial && montoPagado > 0 && montoPagado == montoTotal) {
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

    // Aplicar cambios directamente (sin peticiones)
    debugPrint('🚀 Aplicando cambios directamente...');
    await _aplicarCambiosDirectamente();
    
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
    
    // Detectar cambio significativo de precio para solicitar motivo
    final precioOriginal = (_valoresOriginales['valor'] as num?)?.toDouble() ?? 0.0;
    final precioNuevo = (valoresActuales['valor'] as num?)?.toDouble() ?? 0.0;
    final porcentajeCambio = precioOriginal > 0 ? 
        ((precioNuevo - precioOriginal) / precioOriginal * 100).abs() : 0.0;
    
    // Solicitar motivo para cambios significativos de precio
    if (_precioEditableActivado && porcentajeCambio >= 15) {
      await _solicitarMotivoPrecioPersonalizado();
      
      if (_motivoPrecioPersonalizado == null || _motivoPrecioPersonalizado!.isEmpty) {
        setState(() { _isSaving = false; });
        _mostrarError('Se requiere especificar un motivo para el cambio de precio');
        return;
      }
    }

    // Validar disponibilidad para cambios importantes
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

    // Preparar datos para actualización
    final updateData = await _prepararDatosActualizacion(
      valoresActuales, 
      precioOriginal, 
      porcentajeCambio
    );

    debugPrint('📡 Actualizando reserva ${widget.reserva.id}');
    debugPrint('🔍 Cambios detectados: ${_obtenerCamposModificados().join(', ')}');
    debugPrint('📊 Porcentaje cambio precio: ${porcentajeCambio.toStringAsFixed(1)}%');
    
    // Ejecutar actualización en Firestore
    await FirebaseFirestore.instance
        .collection('reservas')
        .doc(widget.reserva.id)
        .update(updateData);

    // 🔥 AUDITORÍA UNIFICADA - Usar SOLO ReservaAuditUtils (eliminar duplicación)
    await _crearAuditoriaUnificada(valoresActuales, porcentajeCambio);

    if (!mounted) return;
    
    setState(() { _isSaving = false; });

    // Mensaje contextual según el nivel de cambios
    String mensaje = _generarMensajeExito(porcentajeCambio);
    _mostrarExito(mensaje);
    Navigator.of(context).pop(true);

  } catch (e) {
    debugPrint('❌ Error aplicando cambios: $e');
    await _manejarErrorActualizacion(e);
  }
}


// 🔥 NUEVO MÉTODO - Auditoría unificada
// 🔥 MÉTODO ACTUALIZADO - Auditoría unificada con descripción mejorada
  Future<void> _crearAuditoriaUnificada(
  Map<String, dynamic> valoresActuales,
  double porcentajeCambio
) async {
  try {
    final precioOriginal = (_valoresOriginales['valor'] as num?)?.toDouble() ?? 0.0;
    final precioNuevo = (valoresActuales['valor'] as num?)?.toDouble() ?? 0.0;
    final esPrecioPersonalizado = _precioEditableActivado;
    final descuento = esPrecioPersonalizado && precioNuevo < precioOriginal ? 
        (precioOriginal - precioNuevo) : 0.0;

    // Preparar datos ANTIGUOS para auditoría (formato consistente)
    final datosAntiguos = {
      'nombre': _valoresOriginales['nombre'],
      'telefono': _valoresOriginales['telefono'],
      'valor': precioOriginal,
      'montoPagado': _valoresOriginales['montoPagado'],
      'precio_personalizado': _valoresOriginales['precio_personalizado'] ?? false,
      'precio_original': _valoresOriginales['precio_original'],
      'cancha_nombre': widget.reserva.cancha.nombre,
      'cancha_id': _valoresOriginales['cancha_id'],
      'sede': _valoresOriginales['sede'],
      'fecha': _valoresOriginales['fecha'],
      'horario': _valoresOriginales['horario'],
      'confirmada': _valoresOriginales['confirmada'],
      'tipo': 'reserva_normal',
    };

    // Preparar datos NUEVOS para auditoría (formato consistente)
    final datosNuevos = {
      'nombre': valoresActuales['nombre'],
      'telefono': valoresActuales['telefono'],
      'valor': precioNuevo,
      'montoPagado': valoresActuales['montoPagado'],
      'precio_personalizado': esPrecioPersonalizado,
      'precio_original': esPrecioPersonalizado ? precioOriginal : null,
      'descuento_aplicado': descuento > 0 ? descuento : null,
      'cancha_nombre': widget.reserva.cancha.nombre,
      'cancha_id': valoresActuales['cancha_id'],
      'sede': valoresActuales['sede'],
      'fecha': valoresActuales['fecha'],
      'horario': valoresActuales['horario'],
      'confirmada': valoresActuales['confirmada'],
      'tipo': 'reserva_normal',
    };

    // 🆕 ANÁLISIS DE CAMBIOS para generar descripción mejorada
    final analisisCambios = _analizarCambiosDetalladamente(
      datosAntiguos, 
      datosNuevos, 
      porcentajeCambio
    );

    // 🔥 USAR SOLO ReservaAuditUtils - sistema unificado (sin descripción personalizada para usar la lógica mejorada)
    await ReservaAuditUtils.auditarEdicionReserva(
      reservaId: widget.reserva.id,
      datosAntiguos: datosAntiguos,
      datosNuevos: datosNuevos,
      // Sin descripcionPersonalizada para usar la lógica mejorada de ReservaAuditUtils
      metadatosAdicionales: {
        // Información del contexto de edición
        'metodo_edicion': 'edicion_pantalla_completa',
        'usuario_tipo': widget.esSuperAdmin ? 'super_admin' : (widget.esAdmin ? 'admin' : 'usuario'),
        'interfaz_origen': 'editar_reserva_screen',
        'timestamp_edicion': DateTime.now().millisecondsSinceEpoch,
        
        // Control total y motivo de cambio de precio
        'control_total_activo': await _verificarControlTotalActivo(),
        'motivo_precio_personalizado': _motivoPrecioPersonalizado,
        
        // 🆕 ANÁLISIS DE CAMBIOS DETALLADO
        'analisis_cambios': analisisCambios,
        
        // Contexto financiero detallado
        'contexto_financiero': {
          'diferencia_precio': precioNuevo - precioOriginal,
          'es_aumento': precioNuevo > precioOriginal,
          'es_descuento': precioNuevo < precioOriginal,
          'monto_descuento': descuento,
          'impacto_financiero': _calcularImpactoFinanciero(precioOriginal, precioNuevo),
          'porcentaje_cambio': porcentajeCambio,
        },
        
        // Información contextual de la reserva
        'informacion_reserva': {
          'dias_hasta_reserva': widget.reserva.fecha.difference(DateTime.now()).inDays,
          'es_reserva_proxima': widget.reserva.fecha.difference(DateTime.now()).inDays <= 3,
          'horario_peak': _esHorarioPeak(widget.reserva.horario.horaFormateada),
          'fin_de_semana': _esFechaFinDeSemana(widget.reserva.fecha),
        },
        
        // Análisis de cambios detectados (mantener compatibilidad)
        'cambios_multiples': _obtenerCamposModificados().length > 2,
        'campos_modificados': _obtenerCamposModificados(),
        'cambios_criticos_detectados': [
          if (porcentajeCambio >= 50) 'precio_critico',
          if (valoresActuales['fecha'] != _valoresOriginales['fecha']) 'cambio_fecha',
          if (valoresActuales['horario'] != _valoresOriginales['horario']) 'cambio_horario',
          if (valoresActuales['cancha_id'] != _valoresOriginales['cancha_id']) 'cambio_cancha',
        ],
        
        // Información de validación
        'requirio_motivo_precio': _motivoPrecioPersonalizado != null,
      },
      tipoEdicion: 'edicion_completa',
    );

    debugPrint('✅ Auditoría unificada creada exitosamente con descripción mejorada');
    debugPrint('📝 Auditoría de edición registrada usando ReservaAuditUtils');

  } catch (e) {
    debugPrint('⚠️ Error en auditoría unificada: $e');
    // No fallar la operación por error de auditoría
  }
}

// 🆕 MÉTODO AUXILIAR - Análisis detallado de cambios
  Map<String, dynamic> _analizarCambiosDetalladamente(
  Map<String, dynamic> datosAntiguos,
  Map<String, dynamic> datosNuevos,
  double porcentajeCambio,
) {
  final cambiosDetectados = <String>[];
  
  // Detectar cambios específicos
  if (datosNuevos['nombre'] != datosAntiguos['nombre']) {
    cambiosDetectados.add('Cambio de cliente');
  }
  
  if (datosNuevos['telefono'] != datosAntiguos['telefono']) {
    cambiosDetectados.add('Cambio de teléfono');
  }
  
  if (datosNuevos['fecha'] != datosAntiguos['fecha']) {
    cambiosDetectados.add('Cambio de fecha');
  }
  
  if (datosNuevos['horario'] != datosAntiguos['horario']) {
    cambiosDetectados.add('Cambio de horario');
  }
  
  if (datosNuevos['cancha_id'] != datosAntiguos['cancha_id']) {
    cambiosDetectados.add('Cambio de cancha');
  }
  
  if (datosNuevos['sede'] != datosAntiguos['sede']) {
    cambiosDetectados.add('Cambio de sede');
  }
  
  if (porcentajeCambio > 0) {
    if (porcentajeCambio >= 50) {
      cambiosDetectados.add('Cambio crítico de precio');
    } else if (porcentajeCambio >= 15) {
      cambiosDetectados.add('Cambio significativo de precio');
    } else {
      cambiosDetectados.add('Ajuste de precio');
    }
  }
  
  if (datosNuevos['montoPagado'] != datosAntiguos['montoPagado']) {
    cambiosDetectados.add('Cambio en monto pagado');
  }
  
  if (datosNuevos['confirmada'] != datosAntiguos['confirmada']) {
    cambiosDetectados.add(datosNuevos['confirmada'] == true ? 'Confirmación' : 'Desconfirmación');
  }

  // ✅ ELIMINADO: Cálculo de nivel de riesgo duplicado
  // El nivel de riesgo se calcula correctamente en ReservaAuditUtils
  // usando el sistema unificado de umbrales
  
  return {
    'cambios_detectados': cambiosDetectados,
    'total_cambios': cambiosDetectados.length,
    'porcentaje_cambio_precio': porcentajeCambio,
  };
}



  String _calcularImpactoFinanciero(double precioOriginal, double precioNuevo) {
  final diferencia = (precioNuevo - precioOriginal).abs();
  if (diferencia >= 100000) return 'muy_alto';
  if (diferencia >= 50000) return 'alto';
  if (diferencia >= 20000) return 'medio';
  return 'bajo';
  }

  bool _esHorarioPeak(String horario) {
  final regex = RegExp(r'(\d{1,2}):(\d{2})');
  final match = regex.firstMatch(horario);
  if (match != null) {
    final hora = int.parse(match.group(1)!);
    return hora >= 18 && hora <= 22; // Consistente con ReservaAuditUtils
  }
  return false;
  }

  bool _esFechaFinDeSemana(DateTime fecha) {
  return fecha.weekday == DateTime.friday || 
         fecha.weekday == DateTime.saturday || 
         fecha.weekday == DateTime.sunday;
  }


  String _generarMensajeExito(double porcentajeCambio) {
  if (porcentajeCambio >= 50) {
    return '🚨 CAMBIO CRÍTICO aplicado - Reserva actualizada y auditada';
  } else if (porcentajeCambio >= 30) {
    return '⚠️ Cambio significativo aplicado - Reserva actualizada';
  } else if (porcentajeCambio >= 15) {
    return '📝 Cambio moderado aplicado - Reserva actualizada';
  } else if (_obtenerCamposModificados().length > 2) {
    return '📋 Múltiples cambios aplicados - Reserva actualizada';
  } else {
    return '✅ Reserva actualizada correctamente';
  }
  }



  // 5. AGREGAR estos métodos nuevos:

  Future<void> _solicitarMotivoPrecioPersonalizado() async {
    final TextEditingController motivoController = TextEditingController();
    
    final motivo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Precio Personalizado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Se detectó un cambio significativo en el precio. Por favor, especifica el motivo:'),
            SizedBox(height: 16),
            TextField(
              controller: motivoController,
              decoration: InputDecoration(
                labelText: 'Motivo del cambio',
                hintText: 'Ej: Descuento por cliente frecuente, promoción especial, etc.',
              ),
              maxLines: 2,
              autofocus: true,
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Este motivo será registrado en la auditoría del sistema',
                style: TextStyle(fontSize: 12, color: Colors.orange[700]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final motivoTexto = motivoController.text.trim();
              if (motivoTexto.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Por favor, especifica un motivo'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(context, motivoTexto);
            },
            child: Text('Confirmar'),
          ),
        ],
      ),
    );
    
    _motivoPrecioPersonalizado = motivo;
  }

  Future<Map<String, dynamic>> _prepararDatosActualizacion(
    Map<String, dynamic> valoresActuales, 
    double precioOriginal, 
    double porcentajeCambio
  ) async {
    final updateData = <String, dynamic>{
      'nombre': valoresActuales['nombre'],
      'telefono': valoresActuales['telefono'],
      'valor': valoresActuales['valor'],
      'montoPagado': valoresActuales['montoPagado'],
      'estado': valoresActuales['estado'],
      'confirmada': valoresActuales['confirmada'],
      'precio_personalizado': _precioEditableActivado,
      'fechaActualizacion': Timestamp.now(),
      'usuario_modificacion': FirebaseAuth.instance.currentUser?.uid,
      'version_auditoria': '2.0',
    };

    // Datos de precio personalizado
    if (_precioEditableActivado) {
      updateData.addAll({
        'precio_original': precioOriginal,
        'motivo_precio_personalizado': _motivoPrecioPersonalizado,
        'porcentaje_cambio_precio': porcentajeCambio,
        'fecha_cambio_precio': Timestamp.now(),
      });
    }

    // Cambios de ubicación/tiempo
    final cambiosImportantes = 
        valoresActuales['fecha'] != _valoresOriginales['fecha'] ||
        valoresActuales['cancha_id'] != _valoresOriginales['cancha_id'] ||
        valoresActuales['horario'] != _valoresOriginales['horario'] ||
        valoresActuales['sede'] != _valoresOriginales['sede'];

    if (cambiosImportantes) {
      updateData.addAll({
        'fecha': valoresActuales['fecha'],
        'sede': valoresActuales['sede'],
        'cancha_id': valoresActuales['cancha_id'],
        'horario': valoresActuales['horario'],
      });

      // Actualizar info de cancha si cambió
      if (valoresActuales['cancha_id'] != _valoresOriginales['cancha_id']) {
        final nuevaCancha = await _obtenerDatosCancha(valoresActuales['cancha_id']);
        if (nuevaCancha != null) {
          updateData['cancha_nombre'] = nuevaCancha['nombre'];
          updateData['cancha_precio'] = nuevaCancha['precio'];
        }
      }

      // Actualizar horarios
      updateData['horarios'] = [valoresActuales['horario']];
    }

    return updateData;
  }


  Future<void> _manejarErrorActualizacion(dynamic error) async {
    if (!mounted) return;
    
    setState(() { _isSaving = false; });
    
    String mensajeError = 'Error al actualizar la reserva';
    if (error.toString().contains('permission-denied')) {
      mensajeError = 'Sin permisos suficientes. Verifica que el control total esté activado.';
    } else if (error.toString().contains('not-found')) {
      mensajeError = 'La reserva no fue encontrada.';
    } else if (error.toString().contains('network')) {
      mensajeError = 'Error de conexión. Verifica tu internet.';
    }
    
    // Registrar error en auditoría
    try {
      await ReservaAuditUtils.auditarEdicionReserva(
        reservaId: widget.reserva.id,
        datosAntiguos: _valoresOriginales,
        datosNuevos: _obtenerValoresActuales(),
        descripcionPersonalizada: 'ERROR en edición: $mensajeError',
        metadatosAdicionales: {
          'error_tipo': 'actualizacion_fallida',
          'error_detalle': error.toString(),
          'timestamp_error': DateTime.now().millisecondsSinceEpoch,
        },
        tipoEdicion: 'error',
      );
    } catch (e) {
      debugPrint('Error registrando error en auditoría: $e');
    }
    
    _mostrarError('$mensajeError: ${error.toString()}');
  }


  Future<bool> _verificarDisponibilidadCompleta(
    DateTime fecha,
    String canchaId,
    String horario,
  ) async {
    try {
      // Obtener lugarId del usuario autenticado
      final lugarId = await LugarHelper.getLugarId();
      if (lugarId == null) {
        debugPrint('EditarReservaScreen: No se pudo obtener lugarId para verificar disponibilidad');
        return false;
      }

      // Verificar reservas normales
      final reservasNormales = await FirebaseFirestore.instance
          .collection('reservas')
          .where('cancha_id', isEqualTo: canchaId)
          .where('fecha', isEqualTo: DateFormat('yyyy-MM-dd').format(fecha))
          .where('horario', isEqualTo: horario)
          .where('lugarId', isEqualTo: lugarId) // ✅ Agregar filtrado por lugarId
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
                  Text('Cancha: $_nuevaCanchaId'),
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
            child: SizedBox(
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
                          // Eliminamos el onChanged que causaba setState en cada tecla
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
    labelText: 'Nombre Completo',
    prefixIcon: const Icon(Icons.person),
    hintText: 'Ingresa el nombre del cliente',
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    filled: true,
    fillColor: Colors.grey.shade50,
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
    hintText: '3001234567',
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    filled: true,
    fillColor: Colors.grey.shade50,
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
  controller: _montoPagadoController,
  decoration: InputDecoration(
    labelText: 'Abono',
    prefixText: 'COP ',
    prefixIcon: const Icon(Icons.attach_money),
    hintText: '0',
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    filled: true,
    fillColor: Colors.grey.shade50,
  ),
  keyboardType: TextInputType.number,
  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
  validator: (value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresa el abono (puede ser 0)';
    }
    double? abono = double.tryParse(value);
    if (abono == null) {
      return 'Ingresa un número válido';
    }
    if (abono < 0) {
      return 'El abono no puede ser negativo';
    }
    // ELIMINADO: Restricción de mínimo 20000
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
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    filled: true,
    fillColor: Colors.grey.shade50,
  ),
  items: [
    DropdownMenuItem(
      value: TipoAbono.parcial,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.orange.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Pendiente'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: TipoAbono.completo,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.green.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Completo'),
        ],
      ),
    ),
  ],
  onChanged: (value) {
    setState(() {
      _selectedTipo = value;
    });
  },
),

            const SizedBox(height: 24),
            
            Container(
  width: double.infinity,
  height: 56,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    gradient: _isSaving 
        ? LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade400])
        : LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.8),
            ],
          ),
    boxShadow: _isSaving ? [] : [
      BoxShadow(
        color: Theme.of(context).primaryColor.withOpacity(0.3),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  child: ElevatedButton(
    onPressed: _isSaving ? null : _saveChanges,
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    child: _isSaving 
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Guardando cambios...',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.save, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                'Guardar Cambios',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
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
}