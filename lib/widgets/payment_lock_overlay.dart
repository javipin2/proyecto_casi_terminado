import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/lugar_helper.dart';

enum PagoEstado {
  ok,
  avisoPre,
  avisoVencido,
  avisoUltimoDia,
  bloqueado,
}

class PaymentLockOverlay extends StatefulWidget {
  final Widget child;

  const PaymentLockOverlay({super.key, required this.child});

  @override
  State<PaymentLockOverlay> createState() => _PaymentLockOverlayState();
}

class _PaymentLockOverlayState extends State<PaymentLockOverlay> {
  bool _loading = true;
  bool _show = false;
  bool _forceBlock = false;
  String _titulo = '';
  String _mensajePrincipal = '';
  String _cuentasPago = '';
  String _whatsappCobro = '';
  String _planNombre = '';
  String _valorMensual = '';
  String _proximoVencimiento = '';

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  Future<void> _cargarEstado() async {
    try {
      final lugarId = await LugarHelper.getLugarId();
      if (!mounted) return;
      if (lugarId == null) {
        setState(() {
          _loading = false;
          _show = false;
        });
        return;
      }

      final lugarDoc = await FirebaseFirestore.instance
          .collection('lugares')
          .doc(lugarId)
          .get();
      if (!mounted) return;
      if (!lugarDoc.exists) {
        setState(() {
          _loading = false;
          _show = false;
        });
        return;
      }

      final data = lugarDoc.data() as Map<String, dynamic>;
      final plan = data['plan'] as String?;
      final planInicioTs = data['planInicio'];
      final planValor = data['planValorMensual'];
      final ultimoPagoTs = data['planUltimoPago'];

      if (plan == null ||
          planInicioTs == null ||
          planValor == null ||
          planInicioTs is! Timestamp) {
        setState(() {
          _loading = false;
          _show = false;
        });
        return;
      }

      final inicio = planInicioTs.toDate();
      final ultimoPago = (ultimoPagoTs is Timestamp)
          ? ultimoPagoTs.toDate()
          : null;
      final monto = (planValor is num) ? planValor.toDouble() : null;
      if (monto == null) {
        setState(() {
          _loading = false;
          _show = false;
        });
        return;
      }

      final ahora = DateTime.now();
      final info = _calcularEstadoPago(inicio, ultimoPago, ahora);
      if (info.estado == PagoEstado.ok) {
        setState(() {
          _loading = false;
          _show = false;
        });
        return;
      }

      String cuentas = '';
      String whatsapp = '';
      try {
        final confDoc = await FirebaseFirestore.instance
            .collection('config')
            .doc('pagos_programador')
            .get();
        if (confDoc.exists) {
          final confData = confDoc.data() as Map<String, dynamic>;
          cuentas = (confData['textoCuentas'] as String?) ?? '';
          whatsapp = (confData['whatsappCobro'] as String?) ?? '';
        }
      } catch (_) {
        // ignorar errores de lectura de cuentas
      }

      String titulo;
      String mensaje;
      switch (info.estado) {
        case PagoEstado.avisoPre:
          titulo = 'Tu pago mensual vence pronto';
          mensaje =
              'Mañana se cumple la fecha de pago de tu plan. Si realizas el pago a tiempo el sistema seguirá funcionando normalmente.';
          break;
        case PagoEstado.avisoVencido:
          titulo = 'Pago mensual vencido (periodo de gracia)';
          mensaje =
              'La fecha de pago de tu plan ya se cumplió. Si en los próximos 2 días no se registra el pago, el sistema será bloqueado y no podrás gestionar reservas.';
          break;
        case PagoEstado.avisoUltimoDia:
          titulo = 'Último día antes del bloqueo';
          mensaje =
              'Tu mensualidad está vencida. Si no se registra el pago hoy, mañana el sistema quedará bloqueado y no podrás usar el panel.';
          break;
        case PagoEstado.bloqueado:
          titulo = 'Sistema bloqueado por falta de pago';
          mensaje =
              'No se ha registrado el pago de tu plan. El sistema permanecerá bloqueado hasta que se reciba y confirme el pago correspondiente.';
          break;
        case PagoEstado.ok:
          titulo = '';
          mensaje = '';
          break;
      }

      setState(() {
        _loading = false;
        _show = true;
        _forceBlock = info.estado == PagoEstado.bloqueado;
        _titulo = titulo;
        _mensajePrincipal = mensaje;
        _cuentasPago = cuentas;
        _whatsappCobro = whatsapp;
        _planNombre = plan.toUpperCase();
        _valorMensual = '\$${monto.toStringAsFixed(0)}';
        _proximoVencimiento = _formatearFecha(info.proximoVencimiento);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _show = false;
      });
    }
  }

  PagoEstadoInfo _calcularEstadoPago(
    DateTime inicio,
    DateTime? ultimoPago,
    DateTime ahora,
  ) {
    final today = DateTime(ahora.year, ahora.month, ahora.day);

    // Día base de cobro (no cambia aunque se pague tarde)
    final baseDay = inicio.day;

    // Referencia: fecha de inicio o último pago (lo que sea más reciente)
    DateTime ref = inicio;
    if (ultimoPago != null && ultimoPago.isAfter(ref)) {
      ref = ultimoPago;
    }

    // Próximo vencimiento: un mes después de la referencia, manteniendo el día base
    int year = ref.year;
    int month = ref.month + 1;
    if (month > 12) {
      month = 1;
      year++;
    }
    final maxDay = DateUtils.getDaysInMonth(year, month);
    final day = baseDay <= maxDay ? baseDay : maxDay;
    final DateTime due = DateTime(year, month, day);

    final diffDays = today.difference(due).inDays; // hoy - vencimiento

    if (diffDays == -1) {
      return PagoEstadoInfo(PagoEstado.avisoPre, diffDays, due);
    } else if (diffDays == 0) {
      return PagoEstadoInfo(PagoEstado.avisoVencido, diffDays, due);
    } else if (diffDays == 1) {
      return PagoEstadoInfo(PagoEstado.avisoUltimoDia, diffDays, due);
    } else if (diffDays >= 2) {
      return PagoEstadoInfo(PagoEstado.bloqueado, diffDays, due);
    } else {
      return PagoEstadoInfo(PagoEstado.ok, diffDays, due);
    }
  }

  String _formatearFecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  Future<void> _abrirWhatsAppCobro() async {
    final raw = _whatsappCobro.trim();
    if (raw.isEmpty) return;

    // Quitar espacios, guiones y otros caracteres no numéricos salvo '+'
    final numeroLimpio =
        raw.replaceAll(RegExp(r'[^0-9\+]'), '');
    if (numeroLimpio.isEmpty) return;

    final uri = Uri.parse('https://wa.me/$numeroLimpio');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      // Si falla, no rompemos la app; podríamos mostrar un SnackBar en el futuro
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show || _loading) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.35),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _forceBlock
                      ? const Color(0xFFFFF1F2) // fondo rosado cuando está bloqueado
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _forceBlock
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFE5E7EB),
                    width: _forceBlock ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _forceBlock
                                ? Colors.red.withOpacity(0.08)
                                : const Color(0xFF2E7D60).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _forceBlock
                                ? Icons.lock_rounded
                                : Icons.warning_amber_rounded,
                            color: _forceBlock
                                ? Colors.red.shade600
                                : const Color(0xFF2E7D60),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _titulo,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: _forceBlock
                                      ? const Color(0xFFB91C1C)
                                      : const Color(0xFF1F2933),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _forceBlock
                                    ? 'Acceso restringido por falta de pago'
                                    : 'Aviso de facturación de TuCanchaFácil',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _mensajePrincipal,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            _forceBlock ? FontWeight.w600 : FontWeight.w500,
                        color: _forceBlock
                            ? const Color(0xFF7F1D1D)
                            : const Color(0xFF4B5563),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resumen de tu plan',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _forceBlock
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Plan: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                TextSpan(
                                  text: _planNombre,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const TextSpan(text: '   •   '),
                                const TextSpan(
                                  text: 'Valor mensual: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                TextSpan(
                                  text: _valorMensual,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Próximo vencimiento: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                TextSpan(
                                  text: _proximoVencimiento,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_cuentasPago.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Cómo realizar el pago',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  'Realiza la transferencia a alguna de las siguientes cuentas y guarda el comprobante. ',
                            ),
                            TextSpan(
                              text:
                                  'Una vez confirmado el pago, tu sistema se desbloqueará automáticamente y se enviará la cuenta de cobro',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: ' al correo electrónico registrado.',
                            ),
                          ],
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4B5563),
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Text(
                          _cuentasPago,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ],
                    if (_whatsappCobro.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Enviar el comprobante por WhatsApp',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirWhatsAppCobro(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            side: const BorderSide(
                              color: Color(0xFF16A34A),
                            ),
                            foregroundColor: const Color(0xFF16A34A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.phone_in_talk_rounded, size: 20),
                          label: Text(
                            _whatsappCobro,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (!_forceBlock)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _show = false;
                            });
                          },
                          child: const Text('Entendido'),
                        ),
                      )
                    else
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Para cualquier duda sobre tu facturación comunícate con el programador de TuCanchaFácil.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB91C1C),
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PagoEstadoInfo {
  final PagoEstado estado;
  final int diasDiferencia;
  final DateTime proximoVencimiento;

  PagoEstadoInfo(this.estado, this.diasDiferencia, this.proximoVencimiento);
}

