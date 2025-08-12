// lib/screens/widgets/alert_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:reserva_canchas/models/alerta_critica.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';
import 'package:intl/intl.dart';

class AlertPanel extends StatefulWidget {
  final bool showOnlyUnread;

  const AlertPanel({Key? key, this.showOnlyUnread = true}) : super(key: key);

  @override
  State<AlertPanel> createState() => _AlertPanelState();
}

class _AlertPanelState extends State<AlertPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuditProvider>(context, listen: false)
          .cargarAlertas(soloNoLeidas: widget.showOnlyUnread);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuditProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Cargando alertas...'),
              ],
            ),
          );
        }

        if (provider.alertas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.green.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No hay alertas críticas',
                  style: GoogleFonts.montserrat(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'El sistema está funcionando normalmente',
                  style: GoogleFonts.montserrat(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: provider.alertas.length,
          itemBuilder: (context, index) {
            final alerta = provider.alertas[index];
            return _buildAlertCard(alerta, provider);
          },
        );
      },
    );
  }

  Widget _buildAlertCard(AlertaCritica alerta, AuditProvider provider) {
    final color = _getColorForRiskLevel(alerta.nivelRiesgo);
    final icon = _getIconForAlertType(alerta.tipo);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 2),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          alerta.titulo,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alerta.descripcion,
              style: GoogleFonts.montserrat(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  alerta.usuarioNombre,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM HH:mm').format(alerta.timestamp),
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (alerta.detalles.isNotEmpty) ...[
                  Text(
                    'Detalles:',
                    style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...alerta.detalles.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            '${entry.key}:',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.value.toString(),
                            style: GoogleFonts.montserrat(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 12),
                ],
                if (alerta.accionRecomendada != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.blue.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            alerta.accionRecomendada!,
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => provider.marcarAlertaLeida(alerta.id),
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(
                        'Marcar como leída',
                        style: GoogleFonts.montserrat(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0, duration: 300.ms);
  }

  Color _getColorForRiskLevel(NivelRiesgo nivel) {
    switch (nivel) {
      case NivelRiesgo.bajo:
        return Colors.green.shade600;
      case NivelRiesgo.medio:
        return Colors.yellow.shade700;
      case NivelRiesgo.alto:
        return Colors.orange.shade600;
      case NivelRiesgo.critico:
        return Colors.red.shade600;
    }
  }

  IconData _getIconForAlertType(TipoAlerta tipo) {
    switch (tipo) {
      case TipoAlerta.precio_anomalo:
        return Icons.attach_money;
      case TipoAlerta.reserva_sospechosa:
        return Icons.event_busy;
      case TipoAlerta.eliminacion_masiva:
        return Icons.delete_sweep;
      case TipoAlerta.acceso_no_autorizado:
        return Icons.security;
      case TipoAlerta.cambio_critico:
        return Icons.warning;
      case TipoAlerta.actividad_inusual:
        return Icons.timeline;
    }
  }
}