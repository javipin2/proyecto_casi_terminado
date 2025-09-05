import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/reserva.dart';

class ReservaScreen extends StatefulWidget {
  final Reserva reserva;

  const ReservaScreen({Key? key, required this.reserva}) : super(key: key);

  @override
  State<ReservaScreen> createState() => _ReservaScreenState();
}

class _ReservaScreenState extends State<ReservaScreen> with SingleTickerProviderStateMixin {
  bool _datosValidos = false;
  String? _errorValidacion;
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _abonoController = TextEditingController();
  bool _procesando = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  double _montoPagado = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _montoPagado = widget.reserva.montoPagado;
    _abonoController.text = _montoPagado.toStringAsFixed(0);

    _animationController.forward();
  }

  // Validar datos del formulario en tiempo real
  void _validarDatosFirestore() {
    String? error;
    bool validos = true;

    final nombre = _nombreController.text.trim();
    final telefono = _telefonoController.text.trim();
    final email = _emailController.text.trim();

    if (nombre.isEmpty) {
      error = 'El nombre es requerido';
      validos = false;
    } else if (telefono.length < 10) {
      error = 'El whatsapp debe del titular para enviar la confirmacion de la reserva';
      validos = false;
    } else if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      error = 'Ingresa un correo electrónico válido';
      validos = false;
    }

    setState(() {
      _datosValidos = validos;
      _errorValidacion = error;
    });
  }

  // Enviar mensaje de WhatsApp con los detalles de la reserva
  Future<void> _enviarMensajeWhatsApp(String referencia) async {
  const String numeroTelefono = "+573013435434";
  const String cuentaPago = "BANCOLOMBIA AHORROS⚽   *52400011088* ";
  final String canchaNombre = widget.reserva.cancha.nombre;
  final String fecha = DateFormat('EEEE, d \'de\' MMMM \'de\' yyyy', 'es').format(widget.reserva.fecha);
  final String horario = widget.reserva.horario.horaFormateada;
  final double precioTotal = _calcularPrecioTotalCancha();
  final double abono = _montoPagado;
  final String nombre = _nombreController.text.trim();
  final String telefono = _telefonoController.text.trim();
  final String email = _emailController.text.trim();
  
  final double saldoPendiente = precioTotal - abono;
  final bool esPagoCompleto = saldoPendiente <= 0;

  final String mensaje = """
🏆 *SOLICITUD DE RESERVA DE CANCHA*

📋 *DETALLES DE LA RESERVA:*
🏟️ Cancha: *$canchaNombre*
📅 Fecha: *$fecha*
⏰ Horario: *$horario*

💰 *INFORMACIÓN DE PAGO:*
💵 Precio total: *\$${precioTotal.toStringAsFixed(0)} COP*
💳 ${esPagoCompleto ? 'Pago completo' : 'Abono inicial'}: *\$${abono.toStringAsFixed(0)} COP*
${!esPagoCompleto ? '⚠️ Saldo pendiente: *\$${saldoPendiente.toStringAsFixed(0)} COP*' : ''}

👤 *DATOS DEL CLIENTE:*
📝 Nombre: *$nombre*
📱 Teléfono: *$telefono*
📧 Email: *$email*

💳 *Datos para transferencia:*
$cuentaPago

---
Por favor, confirme la disponibilidad y el proceso de pago.
¡Gracias por contactarnos! 🙌
""";

  // Mostrar diálogo con instrucciones ANTES de abrir WhatsApp
  final bool? debeEnviar = await _mostrarDialogoInstruccionesWhatsApp();
  
  if (debeEnviar == true) {
    final String urlWhatsApp = 'https://api.whatsapp.com/send/?phone=$numeroTelefono&text=${Uri.encodeComponent(mensaje)}&type=phone_number&app_absent=0';
    final Uri url = Uri.parse(urlWhatsApp);

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        
        // Esperar un momento y luego mostrar el diálogo de confirmación
        if (mounted) {
          setState(() {
            _procesando = false;
          });
          _mostrarDialogoReservaPendiente();
        }
      } else {
        throw 'No se pudo abrir WhatsApp';
      }
    } catch (e) {
      if (mounted) {
        _mostrarError('Error al abrir WhatsApp: $e');
        setState(() {
          _procesando = false;
        });
      }
    }
  } else {
    setState(() {
      _procesando = false;
    });
  }
}



void _mostrarDialogoReservaPendiente() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.schedule,
                  color: Colors.orange.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⏳ Reserva Pendiente',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    Text(
                      'Esperando confirmación de pago',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade600,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green.shade600, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    '✅ RESERVA CREADA EXITOSAMENTE',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu reserva ha sido guardada y está bloqueada por 10 minutos mientras realizas el pago.\n\nUna vez confirmes el pago por WhatsApp, recibirás la confirmación final.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green.shade700,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ℹ️ Ya puedes cerrar esta pantalla. Te contactaremos por WhatsApp para confirmar tu reserva.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cerrar diálogo
                Navigator.of(context).pop(); // Volver a la pantalla anterior
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Entendido',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );
    },
  );
}




Future<bool?> _mostrarDialogoInstruccionesWhatsApp() async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  FontAwesomeIcons.whatsapp,
                  color: Colors.green,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enviar por WhatsApp',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    Text(
                      'Te conectaremos con nuestro WhatsApp',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade600, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    '📱 INSTRUCCIONES:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Se abrirá WhatsApp con tu mensaje listo\n'
                    '2. Solo presiona el botón ENVIAR ➤\n'
                    '3. En el mensaje estara la cuenta de pago\n'
                    '4. Cancela el valor seleccionado anteriormente'
                    '  y envia el comprobante de pago\n'
                    '5. !!RESERVA LISTA!!',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade700,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '⚠️ IMPORTANTE:  A partir de este momento la reserva está bloqueada por 10 minutos para que puedas realizar el pago en ese lapso de tiempo.\n'
                      'Si no se confirma la reserva en ese tiermpo, se pondra disponible automáticamente.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        FontAwesomeIcons.whatsapp,
                        color: const Color.fromARGB(255, 3, 255, 12),
                        size: 30,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Abrir WhatsApp',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}


  // Guardar reserva pendiente en Firestore
  Future<void> _guardarReservaPendiente(String referencia) async {

  widget.reserva.montoTotal = _calcularPrecioTotalCancha();


  widget.reserva.nombre = _nombreController.text;
  widget.reserva.telefono = _telefonoController.text;
  widget.reserva.email = _emailController.text;
  widget.reserva.montoPagado = _montoPagado;
  widget.reserva.tipoAbono = _montoPagado >= widget.reserva.montoTotal
      ? TipoAbono.completo
      : TipoAbono.parcial;
  widget.reserva.confirmada = false;
  widget.reserva.sede = widget.reserva.cancha.sedeId;

  try {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      // Actualizar estado del bloqueo temporal a 'pendiente'
      final DocumentReference tempRef = FirebaseFirestore.instance
          .collection('reservas_temporales')
          .doc(referencia);
      
      transaction.update(tempRef, {
        'estado': 'pendiente',
        'pago_iniciado': FieldValue.serverTimestamp(),
        // Extender el tiempo de expiración para dar tiempo a la confirmación
        'expira_en': DateTime.now().add(Duration(minutes: 12)).millisecondsSinceEpoch,
      });

      // Guardar la reserva pendiente
      final DocumentReference reservaRef = FirebaseFirestore.instance
          .collection('reservas')
          .doc(referencia);
      
      transaction.set(reservaRef, widget.reserva.toFirestore());
    });

    if (!mounted) return;
    _mostrarDialogoInstruccionesWhatsApp();
  } catch (e) {
    if (mounted) {
      _mostrarError('Error al guardar la reserva pendiente: $e');
      setState(() {
        _procesando = false;
      });
    }
  }
}


  // Mostrar mensaje de error
  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  // Confirmar reserva y enviar a WhatsApp
  Future<void> _confirmarReserva() async {
    if (!mounted) return;
    if (_formKey.currentState!.validate()) {
      setState(() {
        _procesando = true;
      });

      HapticFeedback.mediumImpact();

      try {
        // Validar disponibilidad
        final disponibilidad = await _validarDisponibilidad();
        if (!disponibilidad['disponible']) {
          _mostrarError(disponibilidad['mensaje']);
          setState(() {
            _procesando = false;
          });
          return;
        }

        // Crear bloqueo temporal
        final String? referencia = await _crearBloqueoTemporal();
        if (referencia == null) {
          _mostrarError(
              'No se pudo procesar la reserva. La cancha puede estar ocupada.');
          setState(() {
            _procesando = false;
          });
          return;
        }

        // Guardar reserva pendiente
        await _guardarReservaPendiente(referencia);

        // Enviar mensaje a WhatsApp
        await _enviarMensajeWhatsApp(referencia);
      } catch (e) {
        _mostrarError('Error al procesar la reserva: $e');
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _abonoController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Validar disponibilidad
  Future<Map<String, dynamic>> _validarDisponibilidad() async {
  try {
    // CAMBIO: Usar cancha_id en lugar de cancha.nombre
    final String canchaId = widget.reserva.cancha.id; // Asegúrate de que tienes el ID
    final String fecha = DateFormat('yyyy-MM-dd').format(widget.reserva.fecha);
    final String horario = widget.reserva.horario.horaFormateada;
    final String reservaKey = '${canchaId}_${fecha}_${horario}';

    // 1. Verificar reservas confirmadas con los campos correctos
    final QuerySnapshot reservasExistentes = await FirebaseFirestore.instance
        .collection('reservas')
        .where('cancha_id', isEqualTo: canchaId)  // ✅ Campo correcto
        .where('fecha', isEqualTo: fecha)         // ✅ Campo correcto
        .where('horario', isEqualTo: horario)     // ✅ Campo correcto
        .where('confirmada', isEqualTo: true)     // ✅ Campo correcto
        .get();

    if (reservasExistentes.docs.isNotEmpty) {
      return {
        'disponible': false,
        'mensaje': 'Esta cancha ya fue reservada por otro usuario'
      };
    }

    // 2. Verificar bloqueos temporales
    final int ahora = DateTime.now().millisecondsSinceEpoch;
    
    final QuerySnapshot reservasTemporales = await FirebaseFirestore.instance
        .collection('reservas_temporales')
        .where('reserva_key', isEqualTo: reservaKey)
        .where('expira_en', isGreaterThan: ahora)
        .get();

    if (reservasTemporales.docs.isNotEmpty) {
      return {
        'disponible': false,
        'mensaje': 'Cancha bloqueada temporalmente. Otro usuario está procesando la reserva. Si no se confirma la reserva, se liberará automáticamente.'
      };
    }

    return {'disponible': true};
  } catch (e) {
    return {
      'disponible': false,
      'mensaje': 'Error al verificar disponibilidad: $e'
    };
  }
}



  // Crear bloqueo temporal
  Future<String?> _crearBloqueoTemporal() async {
  try {
    final String referencia = 'reserva-${DateTime.now().millisecondsSinceEpoch}';
    final String canchaId = widget.reserva.cancha.id; // Cambio aquí también
    final String fecha = DateFormat('yyyy-MM-dd').format(widget.reserva.fecha);
    final String horario = widget.reserva.horario.horaFormateada;
    final String reservaKey = '${canchaId}_${fecha}_${horario}';
    final int expiraEn = DateTime.now().add(Duration(minutes: 12)).millisecondsSinceEpoch;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      // Verificar reservas confirmadas
      final QuerySnapshot reservasExistentes = await FirebaseFirestore.instance
          .collection('reservas')
          .where('cancha_id', isEqualTo: canchaId)  // ✅ Campo correcto
          .where('fecha', isEqualTo: fecha)
          .where('horario', isEqualTo: horario)
          .where('confirmada', isEqualTo: true)
          .get();

      if (reservasExistentes.docs.isNotEmpty) {
        throw Exception('Cancha ya reservada');
      }

      // Verificar bloqueos temporales activos
      final int ahora = DateTime.now().millisecondsSinceEpoch;
      final QuerySnapshot bloqueosActivos = await FirebaseFirestore.instance
          .collection('reservas_temporales')
          .where('reserva_key', isEqualTo: reservaKey)
          .where('expira_en', isGreaterThan: ahora)
          .get();

      if (bloqueosActivos.docs.isNotEmpty) {
        throw Exception('Otro usuario está procesando esta reserva');
      }

      // Crear nuevo bloqueo temporal
      final DocumentReference docRef = FirebaseFirestore.instance
          .collection('reservas_temporales')
          .doc(referencia);

      transaction.set(docRef, {
        'referencia': referencia,
        'cancha_id': canchaId,  // ✅ Campo correcto
        'fecha': fecha,
        'horario': horario,
        'reserva_key': reservaKey,
        'monto': _montoPagado,
        'estado': 'bloqueado',
        'timestamp': FieldValue.serverTimestamp(),
        'expira_en': expiraEn,
        'datos_cliente': {
          'nombre': _nombreController.text,
          'telefono': _telefonoController.text,
          'email': _emailController.text,
        }
      });
    });

    return referencia;
  } catch (e) {
    debugPrint('Error al crear bloqueo temporal: $e');
    return null;
  }
}




  // Calcular precio total dinámico
  double _calcularPrecioTotalCancha() {
  final String day = DateFormat('EEEE', 'es').format(widget.reserva.fecha).toLowerCase();
  final String horaStr = widget.reserva.horario.horaFormateada;
  
  final Map<String, Map<String, dynamic>>? dayPrices = widget.reserva.cancha.preciosPorHorario[day];
  
  if (dayPrices == null) {
    return widget.reserva.cancha.precio;
  }

  // Buscar coincidencia exacta primero
  if (dayPrices.containsKey(horaStr)) {
    final config = dayPrices[horaStr];
    if (config is Map<String, dynamic>) {
      return (config['precio'] as num?)?.toDouble() ?? widget.reserva.cancha.precio;
    }
    return (config as num?)?.toDouble() ?? widget.reserva.cancha.precio;
  }

  // Buscar con normalización usando el mismo método que DetallesScreen
  for (final entry in dayPrices.entries) {
    final llave = entry.key;
    final llaveNormalizada = _normalizarHoraFormato(llave);
    final horaNormalizada = _normalizarHoraFormato(horaStr);
    
    if (llaveNormalizada == horaNormalizada) {
      final config = entry.value;
      if (config is Map<String, dynamic>) {
        return (config['precio'] as num?)?.toDouble() ?? widget.reserva.cancha.precio;
      }
      return (config as num?)?.toDouble() ?? widget.reserva.cancha.precio;
    }
  }

  return widget.reserva.cancha.precio;
}

// Agregar este método a ReservaScreen para normalizar horas
String _normalizarHoraFormato(String horaStr) {
  try {
    final dateFormat = DateFormat('h:mm a');
    final dateTime = dateFormat.parse(horaStr.toUpperCase());
    return dateFormat.format(dateTime).toUpperCase();
  } catch (e) {
    debugPrint('Error normalizando hora "$horaStr": $e');
    // Fallback: usar el método de Horario si existe
    return horaStr;
  }
}





  // Mostrar mensaje de validación
  Widget _buildMensajeValidacion() {
    if (_errorValidacion != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_outlined, color: Colors.red.shade600, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorValidacion!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(symbol: "\$", decimalDigits: 0);
    final double precioTotalCancha = _calcularPrecioTotalCancha();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: const Text(
          'Confirmar Reserva',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.grey.shade100],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 4,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.grey[800]!,
                            Colors.grey[900]!,
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.sports_soccer,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.reserva.cancha.nombre,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${DateFormat('EEEE, d MMM yyyy', 'es').format(widget.reserva.fecha)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[300],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInfoItem(
                                title: 'Fecha',
                                value: DateFormat('dd/MM/yyyy')
                                    .format(widget.reserva.fecha),
                                icon: Icons.calendar_today,
                              ),
                              _buildInfoItem(
                                title: 'Hora',
                                value: widget.reserva.horario.horaFormateada,
                                icon: Icons.access_time,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInfoItem(
                                title: 'Precio Total',
                                value: currencyFormat.format(precioTotalCancha),
                                icon: Icons.attach_money,
                              ),
                              _buildInfoItem(
                                title: 'Abono Inicial',
                                value: currencyFormat
                                    .format(widget.reserva.montoPagado),
                                icon: Icons.payment,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Tus datos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _nombreController,
                          label: 'Nombre Completo',
                          icon: Icons.person_outline,
                          keyboardType: TextInputType.text,
                          validatorMsg: 'Por favor ingresa tu nombre',
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _telefonoController,
                          label: 'Whatsapp del titular',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          validatorMsg: 'Por favor ingresa tu teléfono',
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _emailController,
                          label: 'Correo Electrónico',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validatorMsg: 'Por favor ingresa tu correo',
                          extraValidation: (value) {
                            if (value != null &&
                                (value.isEmpty ||
                                    !value.contains('@') ||
                                    !value.contains('.'))) {
                              return 'Ingresa un correo válido';
                            }
                            return null;
                          },
                        ),
                        if (widget.reserva.tipoAbono == TipoAbono.parcial) ...[
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: _abonoController,
                            label: 'Abono (mínimo 20000)',
                            icon: Icons.attach_money,
                            keyboardType: TextInputType.number,
                            validatorMsg: 'Por favor ingresa un abono',
                            extraValidation: (value) {
                              final abono = double.tryParse(value ?? '0') ?? 0;
                              if (abono < 20000) {
                                return 'El abono debe ser al menos 20000';
                              }
                              if (abono > precioTotalCancha) {
                                return 'El abono no puede superar el precio total';
                              }
                              return null;
                            },
                            onChanged: (value) {
                              setState(() {
                                _montoPagado = double.tryParse(value) ??
                                    widget.reserva.montoPagado;
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: 40),
                        _buildMensajeValidacion(),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 55,
                          child: _procesando
                              ? Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withValues(alpha: 0.1),
                                          spreadRadius: 1,
                                          blurRadius: 3,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.grey[800]!),
                                      strokeWidth: 3,
                                    ),
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: _datosValidos ? _confirmarReserva : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _datosValidos ? Colors.grey[850] : Colors.grey[400],
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: _datosValidos ? 4 : 1,
                                    shadowColor: Colors.grey.withValues(alpha: 0.5),
                                  ),
                                  child: Text(
                                    _datosValidos ? 'CONFIRMAR RESERVA' : 'COMPLETA LOS DATOS',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1,
                                      color: _datosValidos ? Colors.white : Colors.white70,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextInputType keyboardType,
    required String validatorMsg,
    String? Function(String?)? extraValidation,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.grey[600],
          fontSize: 15,
        ),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[800]!, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red[400]!, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
      style: TextStyle(
        color: Colors.grey[800],
        fontSize: 16,
      ),
      keyboardType: keyboardType,
      onChanged: (value) {
        _validarDatosFirestore();
        if (onChanged != null) {
          onChanged(value);
        }
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return validatorMsg;
        }
        if (extraValidation != null) {
          return extraValidation(value);
        }
        return null;
      },
    );
  }

}