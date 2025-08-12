import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../models/cancha.dart';
import '../../../models/horario.dart';
import '../../../models/reserva.dart';
import '../../../models/cliente.dart';
import '../../../models/reserva_recurrente.dart';
import '../../../providers/reserva_recurrente_provider.dart';

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
  late TextEditingController _precioTotalController;
  late TextEditingController _notasController;
  TipoAbono? _selectedTipo;
  bool _isProcessing = false;
  String? _selectedClienteId;
  bool _showAbonoField = true;
  late AnimationController _fadeController;
  bool _precioEditableActivado = false;
  bool _esReservaRecurrente = false;
  List<String> _diasSeleccionados = [];
  DateTime? _fechaFinRecurrencia;
  List<Map<String, dynamic>> _conflictosDetectados = [];
  bool _mostrandoConflictos = false;
  bool _verificandoConflictos = false; // Nueva variable para loading state

  final List<String> _diasSemana = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo'
  ];

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
    _precioTotalController = TextEditingController();
    _notasController = TextEditingController();
    _selectedTipo = TipoAbono.parcial;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inicializarPrecioTotal();
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _abonoController.dispose();
    _precioTotalController.dispose();
    _notasController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  double _calcularMontoTotal() {
    if (_precioEditableActivado && _precioTotalController.text.isNotEmpty) {
      return double.tryParse(_precioTotalController.text) ?? 0.0;
    }

    double total = 0.0;
    for (final horario in widget.horarios) {
      final precio = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
      total += precio;
    }
    return total;
  }

  void _inicializarPrecioTotal() {
    if (!_precioEditableActivado) {
      double total = 0.0;
      for (final horario in widget.horarios) {
        final precio = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
        total += precio;
      }
      _precioTotalController.text = total.toStringAsFixed(0);
    }
  }

  Future<void> _verificarConflictosReservas() async {
    if (!_esReservaRecurrente || widget.horarios.isEmpty || _diasSeleccionados.isEmpty) {
      setState(() {
        _conflictosDetectados = [];
        _verificandoConflictos = false;
      });
      return;
    }

    setState(() {
      _verificandoConflictos = true;
    });

    try {
      final horario = widget.horarios.first;
      final conflictos = <Map<String, dynamic>>[];
      
      // Optimización: Crear una sola consulta compuesta con múltiples fechas
      final fechasAVerificar = <String>[];
      
      for (String dia in _diasSeleccionados) {
        DateTime fechaActual = widget.fecha;
        
        // Encontrar el próximo día de la semana especificado
        while (DateFormat('EEEE', 'es').format(fechaActual).toLowerCase() != dia) {
          fechaActual = fechaActual.add(const Duration(days: 1));
        }

        // Agregar las próximas 8 ocurrencias
        for (int i = 0; i < 8; i++) {
          final fechaVerificar = fechaActual.add(Duration(days: i * 7));
          fechasAVerificar.add(DateFormat('yyyy-MM-dd').format(fechaVerificar));
        }
      }

      // OPTIMIZACIÓN: Una sola consulta con whereIn para múltiples fechas
      if (fechasAVerificar.isNotEmpty) {
        // Firebase permite máximo 10 elementos en whereIn, así que dividimos si es necesario
        final batchSize = 10;
        for (int i = 0; i < fechasAVerificar.length; i += batchSize) {
          final batch = fechasAVerificar.skip(i).take(batchSize).toList();
          
          final querySnapshot = await FirebaseFirestore.instance
              .collection('reservas')
              .where('fecha', whereIn: batch)
              .where('cancha_id', isEqualTo: widget.cancha.id)
              .where('horario', isEqualTo: horario.horaFormateada)
              .get();

          for (final doc in querySnapshot.docs) {
            final data = doc.data();
            final fechaStr = data['fecha'] as String;
            final fecha = DateTime.parse(fechaStr);
            
            conflictos.add({
              'fecha': fecha,
              'fechaStr': DateFormat('dd/MM/yyyy').format(fecha),
              'dia': DateFormat('EEEE', 'es').format(fecha).toLowerCase(),
              'horario': horario.horaFormateada,
              'nombre': data['nombre'] ?? 'Sin nombre',
              'telefono': data['telefono'] ?? 'Sin teléfono',
              'precio': data['valor']?.toDouble() ?? 0.0,
              'reservaId': doc.id,
            });
          }
        }
      }

      setState(() {
        _conflictosDetectados = conflictos;
        _verificandoConflictos = false;
      });
    } catch (e) {
      debugPrint('Error al verificar conflictos: $e');
      setState(() {
        _verificandoConflictos = false;
      });
    }
  }

  Future<void> _crearReserva() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      if (_esReservaRecurrente) {
        await _crearReservaRecurrente();
      } else {
        await _crearReservaNormal();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al crear la${_esReservaRecurrente ? ' reserva recurrente' : widget.horarios.length > 1 ? 's reservas' : ' reserva'}: $e',
            style: GoogleFonts.montserrat(),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _crearReservaNormal() async {
    final distribucionPrecios = _calcularDistribucionPrecio();
    final montoTotalGeneral = _calcularMontoTotal();

    final abonoTotal = _selectedTipo == TipoAbono.completo
        ? montoTotalGeneral
        : double.parse(_abonoController.text);

    final distribucionAbono =
        _calcularDistribucionAbono(abonoTotal, montoTotalGeneral, distribucionPrecios);

    String? grupoReservaId;
    if (widget.horarios.length > 1) {
      grupoReservaId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final List<String> reservasCreadas = [];

    for (final horario in widget.horarios) {
      final precioHora = distribucionPrecios[horario]!;
      final abonoHora = distribucionAbono[horario]!;

      final reserva = Reserva(
        id: '',
        cancha: widget.cancha,
        fecha: widget.fecha,
        horario: horario,
        sede: widget.sede,
        tipoAbono: _selectedTipo!,
        montoTotal: precioHora,
        montoPagado: abonoHora,
        nombre: _nombreController.text,
        telefono: _telefonoController.text,
        email: _emailController.text.isEmpty ? null : _emailController.text,
        confirmada: true,
      );

      final docRef = FirebaseFirestore.instance.collection('reservas').doc();
      final datosReserva = reserva.toFirestore();

      if (grupoReservaId != null) {
        datosReserva['grupo_reserva_id'] = grupoReservaId;
        datosReserva['total_horas_grupo'] = widget.horarios.length;
      }

      if (_precioEditableActivado) {
        final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
        datosReserva['precio_original'] = precioOriginal;
        datosReserva['precio_personalizado'] = true;
        datosReserva['descuento_aplicado'] = precioOriginal - precioHora;
      }

      await docRef.set(datosReserva);
      reservasCreadas.add(docRef.id);
    }

    debugPrint('=== RESUMEN DE RESERVAS CREADAS ===');
    debugPrint('Total de horas: ${widget.horarios.length}');
    debugPrint('ID de grupo: ${grupoReservaId ?? "No aplica (reserva individual)"}');
    debugPrint('Precio personalizado activado: $_precioEditableActivado');
    debugPrint('Monto total: ${montoTotalGeneral.toStringAsFixed(0)}');
    debugPrint('Abono total: ${abonoTotal.toStringAsFixed(0)}');

    for (final horario in widget.horarios) {
      final precioHora = distribucionPrecios[horario]!;
      final abonoHora = distribucionAbono[horario]!;
      debugPrint(
          '${horario.horaFormateada}: Precio=${precioHora.toStringAsFixed(0)}, Abono=${abonoHora.toStringAsFixed(0)}');
    }
    debugPrint('Reservas creadas: ${reservasCreadas.length}');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reserva${widget.horarios.length > 1 ? 's' : ''} creada${widget.horarios.length > 1 ? 's' : ''} exitosamente.${_precioEditableActivado ? ' Descuento aplicado.' : ''}${grupoReservaId != null ? ' ID de grupo: $grupoReservaId' : ''}',
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

    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _crearReservaRecurrente() async {
    if (widget.horarios.length > 1) {
      throw Exception('Las reservas recurrentes solo admiten un horario por vez');
    }

    final horario = widget.horarios.first;
    final montoTotal = _calcularMontoTotal();
    final montoPagado = _selectedTipo == TipoAbono.completo
        ? montoTotal
        : double.parse(_abonoController.text);

    // ✅ CALCULAR PRECIO ORIGINAL Y DESCUENTO SI ESTÁ ACTIVADO
    double? precioOriginal;
    double? descuentoAplicado;
    bool precioPersonalizado = false;

    if (_precioEditableActivado && _precioTotalController.text.isNotEmpty) {
      precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
      final precioPersonalizadoValor = double.tryParse(_precioTotalController.text) ?? 0.0;
      descuentoAplicado = precioOriginal - precioPersonalizadoValor;
      precioPersonalizado = true;
    }

    // ✅ CREAR LISTA DE DÍAS EXCLUIDOS BASADA EN CONFLICTOS
    final List<String> diasExcluidos = [];
    for (var conflicto in _conflictosDetectados) {
      final fechaConflicto = DateFormat('yyyy-MM-dd').format(conflicto['fecha']);
      diasExcluidos.add(fechaConflicto);
    }

    final reservaRecurrente = ReservaRecurrente(
      id: '',
      clienteId: _selectedClienteId ?? '',
      clienteNombre: _nombreController.text,
      clienteTelefono: _telefonoController.text,
      clienteEmail: _emailController.text.isEmpty ? null : _emailController.text,
      canchaId: widget.cancha.id,
      sede: widget.sede,
      horario: horario.horaFormateada,
      diasSemana: _diasSeleccionados,
      tipoRecurrencia: TipoRecurrencia.semanal, // Fijo como semanal
      estado: EstadoRecurrencia.activa,
      fechaInicio: widget.fecha,
      fechaFin: _fechaFinRecurrencia,
      montoTotal: montoTotal,
      montoPagado: montoPagado,
      diasExcluidos: diasExcluidos,
      fechaCreacion: DateTime.now(),
      fechaActualizacion: DateTime.now(),
      notas: _notasController.text.isEmpty ? null : _notasController.text,
      precioPersonalizado: precioPersonalizado,
      precioOriginal: precioOriginal,
      descuentoAplicado: descuentoAplicado,
    );

    final reservaRecurrenteProvider =
        Provider.of<ReservaRecurrenteProvider>(context, listen: false);
    final reservaRecurrenteId =
        await reservaRecurrenteProvider.crearReservaRecurrente(reservaRecurrente);

    if (!mounted) return;

    final mensajeDescuento = precioPersonalizado && (descuentoAplicado ?? 0) > 0 
        ? ' Con descuento de COP ${descuentoAplicado!.toStringAsFixed(0)} por reserva.'
        : '';

    final mensajeConflictos = _conflictosDetectados.isNotEmpty
        ? ' Se excluyeron ${_conflictosDetectados.length} fecha(s) con reservas existentes.'
        : '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reserva recurrente creada exitosamente. Los horarios se aplicarán automáticamente según la programación.$mensajeDescuento$mensajeConflictos',
          style: GoogleFonts.montserrat(),
        ),
        backgroundColor: _secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 5),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  double _redondearANumeroLimpio(double valor) {
    if (valor < 1000) {
      return (valor / 100).round() * 100.0;
    } else if (valor < 10000) {
      return (valor / 500).round() * 500.0;
    } else if (valor < 50000) {
      return (valor / 1000).round() * 1000.0;
    } else {
      return (valor / 2500).round() * 2500.0;
    }
  }

  Map<Horario, double> _calcularDistribucionPrecio() {
    final Map<Horario, double> distribucion = {};

    if (_precioEditableActivado && _precioTotalController.text.isNotEmpty) {
      final precioPersonalizado = double.tryParse(_precioTotalController.text) ?? 0.0;

      final Map<Horario, double> preciosOriginales = {};
      double totalOriginal = 0.0;

      for (final horario in widget.horarios) {
        final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
        preciosOriginales[horario] = precioOriginal;
        totalOriginal += precioOriginal;
      }

      if (totalOriginal > 0) {
        double sumaDistribuida = 0.0;
        List<double> preciosTemporales = [];

        for (int i = 0; i < widget.horarios.length - 1; i++) {
          final horario = widget.horarios[i];
          final precioOriginal = preciosOriginales[horario]!;
          final proporcion = precioOriginal / totalOriginal;
          final precioDistribuido = precioPersonalizado * proporcion;

          final precioRedondeado = _redondearANumeroLimpio(precioDistribuido);
          preciosTemporales.add(precioRedondeado);
          sumaDistribuida += precioRedondeado;
        }

        final precioUltimoHorario = precioPersonalizado - sumaDistribuida;
        preciosTemporales.add(precioUltimoHorario);

        for (int i = 0; i < widget.horarios.length; i++) {
          distribucion[widget.horarios[i]] = preciosTemporales[i];
        }
      } else {
        final precioPorHora = precioPersonalizado / widget.horarios.length;
        final precioRedondeado = _redondearANumeroLimpio(precioPorHora);
        double sumaDistribuida = 0.0;

        for (int i = 0; i < widget.horarios.length - 1; i++) {
          distribucion[widget.horarios[i]] = precioRedondeado;
          sumaDistribuida += precioRedondeado;
        }

        distribucion[widget.horarios.last] = precioPersonalizado - sumaDistribuida;
      }
    } else {
      for (final horario in widget.horarios) {
        distribucion[horario] =
            Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
      }
    }

    return distribucion;
  }

  Map<Horario, double> _calcularDistribucionAbono(
      double abonoTotal, double montoTotalGeneral, Map<Horario, double> distribucionPrecios) {
    final Map<Horario, double> distribucionAbono = {};
    double sumaAbonos = 0.0;
    List<double> abonosTemporales = [];

    for (int i = 0; i < widget.horarios.length - 1; i++) {
      final horario = widget.horarios[i];
      final precioHora = distribucionPrecios[horario]!;

      final proporcionAbono =
          montoTotalGeneral > 0 ? (precioHora / montoTotalGeneral) : (1.0 / widget.horarios.length);
      final abonoHora = abonoTotal * proporcionAbono;

      final abonoRedondeado = _redondearANumeroLimpio(abonoHora);
      abonosTemporales.add(abonoRedondeado);
      sumaAbonos += abonoRedondeado;
    }

    final abonoUltimoHorario = abonoTotal - sumaAbonos;
    abonosTemporales.add(abonoUltimoHorario);

    for (int i = 0; i < widget.horarios.length; i++) {
      distribucionAbono[widget.horarios[i]] = abonosTemporales[i];
    }

    return distribucionAbono;
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

  Widget _buildRecurrenciaToggle() {
    final puedeActivarRecurrencia = widget.horarios.length == 1;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _esReservaRecurrente
            ? _secondaryColor.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _esReservaRecurrente
              ? _secondaryColor.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.repeat,
                color: _esReservaRecurrente 
                    ? _secondaryColor 
                    : puedeActivarRecurrencia 
                        ? Colors.grey 
                        : Colors.grey.withOpacity(0.5),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reserva Recurrente',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: puedeActivarRecurrencia 
                            ? _primaryColor 
                            : _primaryColor.withOpacity(0.5),
                      ),
                    ),
                    Text(
                      puedeActivarRecurrencia
                          ? 'Selecciona días de la semana para repetir'
                          : 'Solo disponible para un horario',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: puedeActivarRecurrencia 
                            ? _primaryColor.withOpacity(0.6)
                            : Colors.orange.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _esReservaRecurrente,
                onChanged: puedeActivarRecurrencia ? (value) {
                  setState(() {
                    _esReservaRecurrente = value;
                    if (value) {
                      final diaSemanaActual =
                          DateFormat('EEEE', 'es').format(widget.fecha).toLowerCase();
                      _diasSeleccionados = [diaSemanaActual];
                      // Verificar conflictos inmediatamente
                      _verificarConflictosReservas();
                    } else {
                      _diasSeleccionados.clear();
                      _conflictosDetectados.clear();
                    }
                  });
                } : null,
                activeColor: _secondaryColor,
              ),
            ],
          ),
          if (!puedeActivarRecurrencia) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Las reservas recurrentes requieren seleccionar exactamente un horario',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecurrenciaSection() {
    if (!_esReservaRecurrente) return const SizedBox.shrink();

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
              'Configuración de Recurrencia Semanal',
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Días de la semana',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _diasSemana.map((dia) {
                final isSelected = _diasSeleccionados.contains(dia);
                return FilterChip(
                  label: Text(
                    dia.substring(0, 3).toUpperCase(),
                    style: GoogleFonts.montserrat(
                      color: isSelected ? Colors.white : _primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _diasSeleccionados.add(dia);
                      } else {
                        _diasSeleccionados.remove(dia);
                      }
                      // Verificar conflictos inmediatamente al cambiar días
                      _verificarConflictosReservas();
                    });
                  },
                  selectedColor: _secondaryColor,
                  backgroundColor: _cardColor,
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Indicador de carga para verificación de conflictos
            if (_verificandoConflictos) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _secondaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _secondaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Verificando conflictos...',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: _secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_conflictosDetectados.isNotEmpty && !_verificandoConflictos) ...[
              _buildConflictosWidget(),
              const SizedBox(height: 16),
            ],
            _buildPrecioEditableSection(),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final fecha = await showDatePicker(
                  context: context,
                  initialDate: _fechaFinRecurrencia ?? widget.fecha.add(const Duration(days: 30)),
                  firstDate: widget.fecha,
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (fecha != null) {
                  setState(() {
                    _fechaFinRecurrencia = fecha;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: _disabledColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: _secondaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fecha fin (opcional)',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              color: _primaryColor.withOpacity(0.6),
                            ),
                          ),
                          Text(
                            _fechaFinRecurrencia != null
                                ? DateFormat('dd/MM/yyyy').format(_fechaFinRecurrencia!)
                                : 'Sin fecha límite',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_fechaFinRecurrencia != null)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _fechaFinRecurrencia = null;
                          });
                        },
                        icon: const Icon(Icons.clear),
                        color: Colors.grey,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notasController,
              decoration: InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Ej: Cliente fijo todos los martes',
                labelStyle: GoogleFonts.montserrat(color: _primaryColor.withOpacity(0.6)),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictosWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_outlined, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conflictos detectados (${_conflictosDetectados.length})',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[700],
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _mostrandoConflictos = !_mostrandoConflictos;
                  });
                },
                child: Text(
                  _mostrandoConflictos ? 'Ocultar' : 'Ver detalles',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: _secondaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_mostrandoConflictos) ...[
            const SizedBox(height: 8),
            Text(
              'Estas fechas serán excluidas automáticamente:',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.orange[700],
              ),
            ),
            const SizedBox(height: 8),
            ...(_conflictosDetectados.take(5).map((conflicto) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${conflicto['fechaStr']} - ${conflicto['horario']}',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _primaryColor,
                          ),
                        ),
                        Text(
                          '${conflicto['nombre']} - COP ${NumberFormat('#,###', 'es_CO').format((conflicto['precio'] as double).toInt())}',
                          style: GoogleFonts.montserrat(
                            fontSize: 11,
                            color: _primaryColor.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ))),
            if (_conflictosDetectados.length > 5)
              Text(
                'Y ${_conflictosDetectados.length - 5} más...',
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: Colors.orange[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: _secondaryColor, size: 20),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            color: _primaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 16,
              color: _primaryColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHorariosSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _disabledColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time, color: _secondaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Hora${widget.horarios.length > 1 ? 's seleccionadas' : ' seleccionada'}:',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: widget.horarios.map((horario) {
              final precio = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _secondaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _secondaryColor.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _secondaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          horario.horaFormateada,
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _primaryColor,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _secondaryColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        'COP ${NumberFormat('#,###', 'es_CO').format(precio.toInt())}',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _secondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPrecioEditableSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _precioEditableActivado
            ? _secondaryColor.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _precioEditableActivado
              ? _secondaryColor.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.edit_outlined,
                color: _precioEditableActivado ? _secondaryColor : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Precio personalizado (descuentos)',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _primaryColor,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _precioEditableActivado,
                onChanged: (value) {
                  setState(() {
                    _precioEditableActivado = value;
                    if (value) {
                      _inicializarPrecioTotal();
                    }
                  });
                },
                activeColor: _secondaryColor,
              ),
            ],
          ),
          if (_precioEditableActivado) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _precioTotalController,
              decoration: InputDecoration(
                labelText: 'Nuevo precio total',
                prefixText: 'COP ',
                suffixIcon: Icon(Icons.attach_money, color: _secondaryColor),
                labelStyle: GoogleFonts.montserrat(
                  color: _primaryColor.withOpacity(0.7),
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
                  borderSide: BorderSide(color: _secondaryColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalSection(double total) {
    final hasDiscount = _precioEditableActivado && _precioTotalController.text.isNotEmpty;
    double originalTotal = 0.0;

    if (hasDiscount) {
      for (final horario in widget.horarios) {
        originalTotal += Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _secondaryColor.withOpacity(0.1),
            _secondaryColor.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _secondaryColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          if (hasDiscount && originalTotal > total) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Precio original:',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  'COP ${NumberFormat('#,###', 'es_CO').format(originalTotal.toInt())}',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.grey[600],
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Descuento:',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '- COP ${NumberFormat('#,###', 'es_CO').format((originalTotal - total).toInt())}',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.monetization_on, color: _secondaryColor, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Total a pagar:',
                    style: GoogleFonts.montserrat(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                ],
              ),
              Text(
                'COP ${NumberFormat('#,###', 'es_CO').format(total.toInt())}',
                style: GoogleFonts.montserrat(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: hasDiscount && originalTotal > total ? Colors.green[700] : _secondaryColor,
                ),
              ),
            ],
          ),
        ],
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
            const SizedBox(height: 16),
            _buildInfoRow(Icons.sports_soccer, 'Cancha', widget.cancha.nombre),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.calendar_today, 'Fecha',
                DateFormat('EEEE d MMMM, yyyy', 'es').format(widget.fecha)),
            const SizedBox(height: 16),
            _buildHorariosSection(),
            const SizedBox(height: 16),
            _buildPrecioEditableSection(),
            const SizedBox(height: 12),
            _buildDistribucionPreview(),
            const SizedBox(height: 12),
            _buildTotalSection(total),
          ],
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
              stream: FirebaseFirestore.instance.collection('clientes').snapshots(),
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
                      valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
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
                    ...clientes.map ((cliente) => DropdownMenuItem<String>(
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
                      orElse: () => Cliente(id: '', nombre: '', telefono: '', correo: null),
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

  Widget _buildDistribucionPreview() {
    if (!_precioEditableActivado || _precioTotalController.text.isEmpty) {
      return const SizedBox.shrink();
    }

    final distribucion = _calcularDistribucionPrecio();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.fromRGBO(
            (_secondaryColor.r * 255).toInt(),
            (_secondaryColor.g * 255).toInt(),
            (_secondaryColor.b * 255).toInt(),
            0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Color.fromRGBO(
              (_secondaryColor.r * 255).toInt(),
              (_secondaryColor.g * 255).toInt(),
              (_secondaryColor.b * 255).toInt(),
              0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: _secondaryColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Distribución del precio personalizado:',
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...distribucion.entries.map((entry) {
            final horario = entry.key;
            final precio = entry.value;
            final precioOriginal = Reserva.calcularMontoTotal(widget.cancha, widget.fecha, horario);
            final descuento = precioOriginal - precio;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    horario.horaFormateada,
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: _primaryColor,
                    ),
                  ),
                  Row(
                    children: [
                      if (descuento > 0) ...[
                        Text(
                          'COP ${precioOriginal.toStringAsFixed(0)}',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        'COP ${precio.toStringAsFixed(0)}',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: descuento > 0 ? Colors.green : _primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _calcularMontoTotal();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agregar ${_esReservaRecurrente ? 'Reserva Recurrente' : 'Reserva'}${!_esReservaRecurrente && widget.horarios.length > 1 ? 's' : ''}',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
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
                        valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
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
                    Card(
                      elevation: 0,
                      color: _cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildRecurrenciaToggle(),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                        .slideY(
                            begin: -0.2,
                            end: 0,
                            duration: 600.ms,
                            curve: Curves.easeOutQuad),
                    const SizedBox(height: 16),
                    if (_esReservaRecurrente) ...[
                      _buildRecurrenciaSection()
                          .animate()
                          .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                          .slideY(
                              begin: -0.2,
                              end: 0,
                              duration: 600.ms,
                              curve: Curves.easeOutQuad),
                      const SizedBox(height: 16),
                    ],
                    if (!_esReservaRecurrente) ...[
                      _buildInfoCard(total)
                          .animate()
                          .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                          .slideY(
                              begin: -0.2,
                              end: 0,
                              duration: 600.ms,
                              curve: Curves.easeOutQuad),
                      const SizedBox(height: 16),
                    ],
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
              if (_esReservaRecurrente) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _secondaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _secondaryColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: _secondaryColor, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Configuración de Reserva Recurrente',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_diasSeleccionados.isNotEmpty)
                        Text(
                          'Días: ${_diasSeleccionados.join(', ')}',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: _primaryColor.withOpacity(0.7),
                          ),
                        ),
                      Text(
                        'Horario: ${widget.horarios.first.horaFormateada}',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: _primaryColor.withOpacity(0.7),
                        ),
                      ),
                      Text(
                        'Total: COP ${_calcularMontoTotal().toStringAsFixed(0)}',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(value)) {
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
                onPressed: (_esReservaRecurrente && widget.horarios.length > 1) ||
                        (_esReservaRecurrente && _diasSeleccionados.isEmpty)
                    ? null
                    : _crearReserva,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _esReservaRecurrente
                      ? 'Crear Reserva Recurrente'
                      : 'Confirmar Reserva${widget.horarios.length > 1 ? 's' : ''}',
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