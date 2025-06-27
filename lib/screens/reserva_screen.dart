import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';
import '../models/reserva.dart';
import 'package:flutter/foundation.dart';

class ReservaScreen extends StatefulWidget {
  final Reserva reserva;

  const ReservaScreen({Key? key, required this.reserva}) : super(key: key);

  @override
  State<ReservaScreen> createState() => _ReservaScreenState();
}

class _ReservaScreenState extends State<ReservaScreen>
    with SingleTickerProviderStateMixin {
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

  // Para el polling automático
  Timer? _pollingTimer;
  String? _referenciaActual;
  int _intentosVerificacion = 0;
  static const int _maxIntentos =
      20; // 5 minutos de verificación (cada 15 segundos)

  StreamSubscription? _cancelacionListener;

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
    error = 'El teléfono debe tener al menos 10 dígitos';
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

  // Función para generar la signature según Wompi
  String generarSignature({
    required String publicKey,
    required String currency,
    required int amountInCents,
    required String reference,
    required String redirectUrl,
    required String integrityKey,
  }) {
    final concatenatedString =
        reference + amountInCents.toString() + currency + integrityKey;
    final bytes = utf8.encode(concatenatedString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Función mejorada para verificar el pago con Wompi
  Future<Map<String, dynamic>> verificarPagoWompi(String referencia) async {
    const String privateKey = 'prv_test_VAdwOa5pjSAspqzu3PvfjiPJZEuK1Nsi';
    final url = Uri.parse(
        'https://sandbox.wompi.co/v1/transactions?reference=$referencia');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $privateKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          String status = data['data'][0]['status'];
          String? paymentMethod = data['data'][0]['payment_method']?['type'];
          int? amountInCents = data['data'][0]['amount_in_cents'];

          return {
            'success': true,
            'approved': status == 'APPROVED',
            'status': status,
            'paymentMethod': paymentMethod,
            'amount': amountInCents != null ? amountInCents / 100 : 0,
            'transactionId': data['data'][0]['id'],
          };
        }
        return {'success': false, 'approved': false, 'status': 'NOT_FOUND'};
      } else {
        return {'success': false, 'approved': false, 'status': 'API_ERROR'};
      }
    } catch (e) {
      return {
        'success': false,
        'approved': false,
        'status': 'NETWORK_ERROR',
        'error': e.toString()
      };
    }
  }

  // Función para iniciar el pago con Wompi
  Future<void> lanzarPagoWompi({
    required int valorEnPesos,
    required String referencia,
  }) async {
    const String publicKey = 'pub_test_B3OQlsCmfebI3TnPfjcLdr994aC83tss';
    const String integrityKey =
        'test_integrity_emhhIGsqGPwxmauVNpLWZy6mOUSdCrJA';
    final int valorEnCentavos = valorEnPesos * 100;
    const String redirectUrl = 'https://proyecto-20bae.web.app/';
    const String currency = 'COP';

    final signature = generarSignature(
      publicKey: publicKey,
      currency: currency,
      amountInCents: valorEnCentavos,
      reference: referencia,
      redirectUrl: redirectUrl,
      integrityKey: integrityKey,
    );

    final baseUrl = 'https://checkout.wompi.co/p/';
    final params = {
      'public-key': publicKey,
      'currency': currency,
      'amount-in-cents': valorEnCentavos.toString(),
      'reference': referencia,
      'redirect-url': redirectUrl,
      'signature:integrity': signature,
    };

    final queryString = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final fullUrl = '$baseUrl?$queryString';
    final url = Uri.parse(fullUrl);

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);

        // Iniciar verificación automática
        _iniciarVerificacionAutomatica(referencia);
      } else {
        throw 'No se pudo abrir el navegador';
      }
    } catch (e) {
      if (mounted) {
        _mostrarError('Error al iniciar el pago: $e');
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  // Nueva función para verificación automática con polling
  void _iniciarVerificacionAutomatica(String referencia) {
    _referenciaActual = referencia;
    _intentosVerificacion = 0;

    if (mounted) {
      _mostrarDialogoVerificacionAutomatica();
    }

    // Actualizar el documento temporal
    _crearDocumentoTemporalReserva(referencia);

    // LISTENER MÁS ESPECÍFICO - Solo escucha cambios relevantes
    _cancelacionListener = FirebaseFirestore.instance
        .collection('reservas_temporales')
        .doc(referencia)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;

      if (doc.exists) {
        // ignore: unnecessary_cast
        final data = doc.data() as Map<String, dynamic>?;
        final estado = data?['estado'];

        if (estado == 'cancelado_por_otro_pago') {
          _pollingTimer?.cancel();
          _cancelacionListener?.cancel();
          _mostrarPagoCancelado();
        }
      }
    });

    // Polling para verificar el pago
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _intentosVerificacion++;

      try {
        final resultado = await verificarPagoWompi(referencia);

        if (resultado['approved'] == true) {
          timer.cancel();
          _cancelacionListener?.cancel();
          await _procesarPagoExitoso(resultado);
        } else if (resultado['status'] == 'DECLINED') {
          timer.cancel();
          _cancelacionListener?.cancel();
          await _liberarBloqueo(referencia);
          _mostrarPagoRechazado();
        } else if (_intentosVerificacion >= _maxIntentos) {
          timer.cancel();
          _cancelacionListener?.cancel();
          await _liberarBloqueo(referencia);
          _mostrarTimeoutVerificacion();
        }
      } catch (e) {
        print('Error en verificación automática: $e');
      }
    });
  }

  // Crear documento temporal para tracking
  Future<void> _crearDocumentoTemporalReserva(String referencia) async {
    try {
      // Solo actualizar el estado de 'bloqueado' a 'pendiente'
      await FirebaseFirestore.instance
          .collection('reservas_temporales')
          .doc(referencia)
          .update({
        'estado': 'pendiente',
        'pago_iniciado': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error al actualizar documento temporal: $e');
    }
  }

  // Procesar pago exitoso automáticamente
  Future<void> _procesarPagoExitoso(Map<String, dynamic> resultadoPago) async {
    try {
      final String canchaNombre = widget.reserva.cancha.nombre;
      final String fecha =
          DateFormat('yyyy-MM-dd').format(widget.reserva.fecha);
      final String horario = widget.reserva.horario.horaFormateada;
      final String reservaKey = '${canchaNombre}_${fecha}_${horario}';

      // Actualizar documento temporal actual como pagado
      await FirebaseFirestore.instance
          .collection('reservas_temporales')
          .doc(_referenciaActual!)
          .update({
        'estado': 'pagado',
        'transaction_id': resultadoPago['transactionId'],
        'payment_method': resultadoPago['paymentMethod'],
        'processed_at': FieldValue.serverTimestamp(),
      });

      // CANCELAR TODOS LOS OTROS INTENTOS DE PAGO - CONSULTA OPTIMIZADA
      final QuerySnapshot otrosBloqueos = await FirebaseFirestore.instance
          .collection('reservas_temporales')
          .where('reserva_key', isEqualTo: reservaKey)
          .get();

      // Procesar cancelaciones en lote para mejor performance
      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (QueryDocumentSnapshot doc in otrosBloqueos.docs) {
        if (doc.id != _referenciaActual) {
          final data = doc.data() as Map<String, dynamic>;
          final estado = data['estado'];

          // Solo cancelar estados activos
          if (estado == 'bloqueado' || estado == 'pendiente') {
            batch.update(doc.reference, {
              'estado': 'cancelado_por_otro_pago',
              'cancelado_en': FieldValue.serverTimestamp(),
              'motivo_cancelacion': 'Otro usuario completó el pago primero',
            });
          }
        }
      }

      // Ejecutar todas las cancelaciones de una vez
      await batch.commit();

      // Guardar reserva definitiva
      await _guardarReservaFinal();
    } catch (e) {
      print('Error al procesar pago exitoso: $e');
      if (mounted) {
        _mostrarError('Error al procesar el pago: $e');
      }
    }
  }

  // Guardar reserva final
  Future<void> _guardarReservaFinal() async {
  // Actualizar los datos de la reserva
  widget.reserva.nombre = _nombreController.text;
  widget.reserva.telefono = _telefonoController.text;
  widget.reserva.email = _emailController.text;
  widget.reserva.montoPagado = _montoPagado;
  widget.reserva.tipoAbono = _montoPagado >= widget.reserva.montoTotal
      ? TipoAbono.completo
      : TipoAbono.parcial;
  widget.reserva.confirmada = true;
  widget.reserva.sede = widget.reserva.cancha.sedeId; // Usar el ID de la sede

  try {
    // Guardar reserva confirmada
    await FirebaseFirestore.instance
        .collection('reservas')
        .add(widget.reserva.toFirestore());

    // Eliminar documento temporal
    if (_referenciaActual != null) {
      await FirebaseFirestore.instance
          .collection('reservas_temporales')
          .doc(_referenciaActual!)
          .delete();
    }

    if (!mounted) return;

    // Cerrar diálogo y mostrar éxito
    Navigator.of(context).pop(); // Cerrar diálogo de verificación

    _mostrarExito();

    // Navegar de vuelta después de un momento
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    });
  } catch (e) {
    if (mounted) {
      Navigator.of(context).pop(); // Cerrar diálogo
      _mostrarError('Error al guardar la reserva: $e');
    }
  }
}


  // Diálogos y mensajes mejorados
  void _mostrarDialogoVerificacionAutomatica() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Verificando Pago'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Estamos verificando tu pago automáticamente.\nTu reserva se confirmará en cuanto el pago sea procesado.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Referencia: ${_referenciaActual ?? ""}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _pollingTimer?.cancel();
                Navigator.of(context).pop();
                setState(() {
                  _procesando = false;
                });
              },
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  void _mostrarPagoRechazado() {
    if (!mounted) return;
    Navigator.of(context).pop(); // Cerrar diálogo de verificación

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 8),
              const Text('Pago Rechazado'),
            ],
          ),
          content: const Text(
            'Tu pago ha sido rechazado. Por favor, intenta nuevamente con otra forma de pago.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _procesando = false;
                });
              },
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  void _mostrarTimeoutVerificacion() {
    if (!mounted) return;
    Navigator.of(context).pop(); // Cerrar diálogo de verificación

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.access_time, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('Verificación Pausada'),
            ],
          ),
          content: const Text(
            'La verificación automática ha sido pausada. Si completaste el pago, tu reserva se procesará en breve. Puedes contactarnos si tienes dudas.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _procesando = false;
                });
              },
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  void _mostrarExito() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text("¡Reserva confirmada automáticamente!")),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(10),
        duration: const Duration(seconds: 3),
      ),
    );
  }

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

  Future<void> _confirmarReserva() async {
    if (!mounted) return;
    if (_formKey.currentState!.validate()) {
      setState(() {
        _procesando = true;
      });

      HapticFeedback.mediumImpact();

      try {
        // PASO 1: Validar disponibilidad
        final disponibilidad = await _validarDisponibilidad();
        if (!disponibilidad['disponible']) {
          _mostrarError(disponibilidad['mensaje']);
          setState(() {
            _procesando = false;
          });
          return;
        }

        // PASO 2: Crear bloqueo temporal
        final String? referencia = await _crearBloqueoTemporal();
        if (referencia == null) {
          _mostrarError(
              'No se pudo procesar la reserva. La cancha puede estar ocupada.');
          setState(() {
            _procesando = false;
          });
          return;
        }

        // PASO 3: Iniciar pago con Wompi
        await lanzarPagoWompi(
          valorEnPesos: _montoPagado.toInt(),
          referencia: referencia,
        );
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
    _pollingTimer?.cancel();
    _cancelacionListener?.cancel(); // AGREGAR ESTA LÍNEA
    super.dispose();
  }

  // FUNCIÓN 1: VALIDAR DISPONIBILIDAD - AGREGAR DESPUÉS DE dispose()
  Future<Map<String, dynamic>> _validarDisponibilidad() async {
    try {
      final String canchaNombre = widget.reserva.cancha.nombre;
      final String fecha =
          DateFormat('yyyy-MM-dd').format(widget.reserva.fecha);
      final String horario = widget.reserva.horario.horaFormateada;

      // Crear identificador único para la reserva
      final String reservaKey = '${canchaNombre}_${fecha}_${horario}';

      // Verificar reservas confirmadas primero
      final QuerySnapshot reservasExistentes = await FirebaseFirestore.instance
          .collection('reservas')
          .where('cancha.nombre', isEqualTo: canchaNombre)
          .where('fecha', isEqualTo: fecha)
          .where('horario.horaFormateada', isEqualTo: horario)
          .where('confirmada', isEqualTo: true)
          .get();

      if (reservasExistentes.docs.isNotEmpty) {
        return {
          'disponible': false,
          'mensaje': 'Esta cancha ya fue reservada por otro usuario'
        };
      }

      // Verificar bloqueos temporales - CONSULTA SIMPLIFICADA
      final DateTime hace5Minutos =
          DateTime.now().subtract(Duration(minutes: 4));

      // Usar el identificador único para consulta más eficiente
      final QuerySnapshot reservasTemporales = await FirebaseFirestore.instance
          .collection('reservas_temporales')
          .where('reserva_key', isEqualTo: reservaKey)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(hace5Minutos))
          .get();

      // Filtrar en el cliente por estados activos
      final reservasActivas = reservasTemporales.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final estado = data['estado'];
        return estado == 'bloqueado' || estado == 'pendiente';
      }).toList();

      if (reservasActivas.isNotEmpty) {
        return {
          'disponible': false,
          'mensaje':
              'Otro usuario está procesando el pago para esta cancha en este momento'
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

// FUNCIÓN 2: CREAR BLOQUEO TEMPORAL
  Future<String?> _crearBloqueoTemporal() async {
    try {
      final String referencia =
          'reserva-${DateTime.now().millisecondsSinceEpoch}';
      final String canchaNombre = widget.reserva.cancha.nombre;
      final String fecha =
          DateFormat('yyyy-MM-dd').format(widget.reserva.fecha);
      final String horario = widget.reserva.horario.horaFormateada;
      final String reservaKey = '${canchaNombre}_${fecha}_${horario}';

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Verificar una vez más dentro de la transacción
        final QuerySnapshot reservasExistentes = await FirebaseFirestore
            .instance
            .collection('reservas')
            .where('cancha.nombre', isEqualTo: canchaNombre)
            .where('fecha', isEqualTo: fecha)
            .where('horario.horaFormateada', isEqualTo: horario)
            .where('confirmada', isEqualTo: true)
            .get();

        if (reservasExistentes.docs.isNotEmpty) {
          throw Exception('Cancha ya reservada');
        }

        // Verificar bloqueos activos con el nuevo campo
        final QuerySnapshot bloqueosActivos = await FirebaseFirestore.instance
            .collection('reservas_temporales')
            .where('reserva_key', isEqualTo: reservaKey)
            .get();

        // Verificar si hay bloqueos activos
        final DateTime hace5Minutos =
            DateTime.now().subtract(Duration(minutes: 4));
        bool hayBloqueoActivo = false;

        for (var doc in bloqueosActivos.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = data['timestamp'] as Timestamp?;
          final estado = data['estado'];

          if (timestamp != null &&
              timestamp.toDate().isAfter(hace5Minutos) &&
              (estado == 'bloqueado' || estado == 'pendiente')) {
            hayBloqueoActivo = true;
            break;
          }
        }

        if (hayBloqueoActivo) {
          throw Exception('Otro usuario está procesando esta reserva');
        }

        final DocumentReference docRef = FirebaseFirestore.instance
            .collection('reservas_temporales')
            .doc(referencia);

        transaction.set(docRef, {
          'referencia': referencia,
          'cancha': canchaNombre,
          'fecha': fecha,
          'horario': horario,
          'reserva_key': reservaKey, // CAMPO CLAVE PARA CONSULTAS EFICIENTES
          'monto': _montoPagado,
          'estado': 'bloqueado',
          'timestamp': FieldValue.serverTimestamp(),
          'expira_en':
              DateTime.now().add(Duration(minutes: 4)).millisecondsSinceEpoch,
          'datos_cliente': {
            'nombre': _nombreController.text,
            'telefono': _telefonoController.text,
            'email': _emailController.text,
          }
        });
      });

      return referencia;
    } catch (e) {
      print('Error al crear bloqueo temporal: $e');
      return null;
    }
  }

// FUNCIÓN 3: LIBERAR BLOQUEO
  Future<void> _liberarBloqueo(String referencia) async {
    try {
      await FirebaseFirestore.instance
          .collection('reservas_temporales')
          .doc(referencia)
          .update({
        'estado': 'expirado',
        'liberado_en': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error al liberar bloqueo: $e');
    }
  }

// FUNCIÓN 4: DIÁLOGO DE CANCELACIÓN
  void _mostrarPagoCancelado() {
    if (!mounted) return;
    Navigator.of(context).pop(); // Cerrar diálogo de verificación

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.cancel_outlined, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              const Text('Reserva No Disponible'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '¡Oops! Otro usuario completó esta reserva antes que tú.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tu pago no se procesará y no se te cobrará nada.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Regresar a pantalla anterior
              },
              child: const Text('Buscar Otra Cancha'),
            ),
          ],
        );
      },
    );
  }


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


  // Método para calcular el precio total dinámico de la cancha
  double _calcularPrecioTotalCancha() {
    final String day =
        DateFormat('EEEE', 'es').format(widget.reserva.fecha).toLowerCase();
    final String horaStr = '${widget.reserva.horario.hora.hour}:00';
    final Map<String, double>? dayPrices =
        widget.reserva.cancha.preciosPorHorario[day];
    return dayPrices != null && dayPrices.containsKey(horaStr)
        ? dayPrices[horaStr] ?? widget.reserva.cancha.precio
        : widget.reserva.cancha.precio;
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
                          label: 'Teléfono',
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
                            validatorMsg: 'Por favor',
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
                        _buildMensajeValidacion(), // NUEVA LÍNEA
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
                                          color: Colors.grey.withOpacity(0.3),
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
                                  onPressed: _datosValidos ? _confirmarReserva : null, // Deshabilitar si los datos no son válidos
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _datosValidos ? Colors.grey[850] : Colors.grey[400],
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: _datosValidos ? 4 : 1,
                                    shadowColor: Colors.grey.withOpacity(0.5),
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
      // Llamar a la validación en tiempo real
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