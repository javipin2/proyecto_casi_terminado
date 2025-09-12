import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/cancha.dart';
import '../models/horario.dart';
import '../models/reserva.dart';
import 'reserva_screen.dart';

class DetallesScreen extends StatefulWidget {
  final Cancha cancha;
  final DateTime fecha;
  final Horario horario;
  final String sede;

  const DetallesScreen({
    super.key,
    required this.cancha,
    required this.fecha,
    required this.horario,
    required this.sede,
  });

  @override
  State<DetallesScreen> createState() => _DetallesScreenState();
}

class _DetallesScreenState extends State<DetallesScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Map<String, dynamic>? _obtenerConfiguracionHorario(String day, String horaStr) {
    final dayPrices = widget.cancha.preciosPorHorario[day];

    if (dayPrices == null) {
      debugPrint('🔍 No hay precios para el día: $day');
      return null;
    }

    // Normalizar la hora de entrada
    final horaNormalizada = _normalizarHoraFormato(horaStr);
    debugPrint('🔍 Hora normalizada de entrada: "$horaNormalizada"');

    // Buscar coincidencia exacta
    if (dayPrices.containsKey(horaStr)) {
      final config = dayPrices[horaStr];
      debugPrint('🔍 Coincidencia exacta encontrada para "$horaStr": $config');
      debugPrint('🔍 Campo completo específico: ${config?['completo']}');
      return config;
    }

    // Buscar con normalización
    for (final entry in dayPrices.entries) {
      final llave = entry.key;
      final llaveNormalizada = _normalizarHoraFormato(llave);
      debugPrint('🔍 Comparando "$llaveNormalizada" con "$horaNormalizada"');

      if (llaveNormalizada == horaNormalizada) {
        debugPrint('🔍 Coincidencia encontrada: $llave -> ${entry.value}');
        debugPrint('🔍 Campo completo específico: ${entry.value['completo']}');
        return entry.value;
      }
    }

    debugPrint('🔍 No se encontró configuración para "$horaStr"');
    debugPrint('🔍 Llaves disponibles: ${dayPrices.keys.toList()}');
    return null;
  }

  String _normalizarHoraFormato(String horaStr) {
    try {
      final dateFormat = DateFormat('h:mm a');
      final dateTime = dateFormat.parse(horaStr.toUpperCase());
      return dateFormat.format(dateTime).toUpperCase();
    } catch (e) {
      debugPrint('🔍 Error normalizando hora "$horaStr": $e');
      return Horario.normalizarHora(horaStr);
    }
  }

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
        curve: Curves.easeInOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutQuart,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String day = DateFormat('EEEE', 'es').format(widget.fecha).toLowerCase();
    final String horaStr = widget.horario.horaFormateada;

    final Map<String, dynamic>? configuracionHorario = _obtenerConfiguracionHorario(day, horaStr);

    final double precioCompleto = configuracionHorario != null ? configuracionHorario['precio']?.toDouble() ?? widget.cancha.precio : widget.cancha.precio;
    final bool esCompleto = configuracionHorario != null ? configuracionHorario['completo'] == true : false;

    debugPrint('🔍 DEBUG - Día: $day');
    debugPrint('🔍 DEBUG - Hora: "$horaStr"');
    debugPrint('🔍 DEBUG - Configuración encontrada: $configuracionHorario');
    debugPrint('🔍 DEBUG - Precio: $precioCompleto');
    debugPrint('🔍 DEBUG - Es completo: $esCompleto');

    final double abono = 20000;
    final currencyFormat = NumberFormat.currency(symbol: "\$", decimalDigits: 0);
    final theme = Theme.of(context);

    void hapticFeedback() {
      HapticFeedback.lightImpact();
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        title: const Text(
          'Detalles de la Reserva',
          style: TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(15),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.sports_soccer_rounded,
                                        color: theme.primaryColor,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          widget.cancha.nombre,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInfoRow(
                                    Icons.calendar_today_rounded,
                                    'Fecha',
                                    DateFormat('EEEE, d MMMM y', 'es').format(widget.fecha),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Divider(height: 1),
                                  ),
                                  _buildInfoRow(
                                    Icons.access_time_rounded,
                                    'Hora',
                                    widget.horario.horaFormateada,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Divider(height: 1),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(15),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Información de Pago',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    esCompleto
                                        ? 'Este horario requiere pago completo.'
                                        : 'El precio puede variar según el día y horario.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: esCompleto ? Colors.orange.shade600 : Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildPriceRow(
                                    'Precio completo',
                                    currencyFormat.format(precioCompleto),
                                  ),
                                  if (!esCompleto)
                                    Column(
                                      children: [
                                        const SizedBox(height: 8),
                                        _buildPriceRow(
                                          'Abono mínimo',
                                          currencyFormat.format(abono),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: constraints.maxHeight > 600
                                  ? constraints.maxHeight * 0.15
                                  : 16,
                            ),
                            if (!esCompleto)
                              Column(
                                children: [
                                  _buildActionButton(
                                    label: 'Abonar y Reservar',
                                    price: currencyFormat.format(abono),
                                    color: Colors.grey[800]!,
                                    onPressed: () {
                                      hapticFeedback();
                                      _animateButtonPress(() {
                                        _hacerReserva(TipoAbono.parcial, abono);
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            _buildActionButton(
                              label: esCompleto ? 'Pagar' : 'Pagar Completo',
                              price: currencyFormat.format(precioCompleto),
                              color: theme.primaryColor,
                              onPressed: () {
                                hapticFeedback();
                                _animateButtonPress(() {
                                  _hacerReserva(TipoAbono.completo, precioCompleto);
                                });
                              },
                              isPrimary: true,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(String label, String price) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey[700],
          ),
        ),
        Text(
          price,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required String price,
    required Color color,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * _animationController.value),
          child: Opacity(
            opacity: _animationController.value,
            child: child,
          ),
        );
      },
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: color.withAlpha(76),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(51),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    price,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _animateButtonPress(VoidCallback action) {
    HapticFeedback.mediumImpact();
    action();
  }

  Future<void> _hacerReserva(TipoAbono tipoAbono, double montoPagado) async {
    Reserva reserva = Reserva(
      id: '',
      cancha: widget.cancha,
      fecha: widget.fecha,
      horario: widget.horario,
      sede: widget.sede,
      tipoAbono: tipoAbono,
      montoTotal: montoPagado == (precioPorHorario() * 0.3).roundToDouble()
          ? precioPorHorario()
          : montoPagado,
      montoPagado: montoPagado,
      confirmada: true,
    );

    try {
      final bool? reservaExitosa = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => ReservaScreen(reserva: reserva),
        ),
      );

      if (reservaExitosa == true && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al continuar con la reserva: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  double precioPorHorario() {
    final String day = DateFormat('EEEE', 'es').format(widget.fecha).toLowerCase();
    final String horaStr = widget.horario.horaFormateada;

    final configuracion = _obtenerConfiguracionHorario(day, horaStr);
    return configuracion != null ? configuracion['precio']?.toDouble() ?? widget.cancha.precio : widget.cancha.precio;
  }
}