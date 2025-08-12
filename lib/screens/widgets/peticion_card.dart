// lib/widgets/peticion_card.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/peticion.dart';


class PeticionCard extends StatelessWidget {
  final Peticion peticion;
  final VoidCallback? onAprobar;
  final VoidCallback? onRechazar;

  const PeticionCard({
    Key? key,
    required this.peticion,
    this.onAprobar,
    this.onRechazar,
  }) : super(key: key);

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _getEstadoColor().withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _getEstadoColor().withOpacity(0.03),
              Colors.white,
              _getEstadoColor().withOpacity(0.01),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con estado y fecha
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge de estado
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getEstadoColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _getEstadoColor().withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getEstadoIcon(),
                          size: 14,
                          color: _getEstadoColor(),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getEstadoTexto(),
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _getEstadoColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Fecha
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(peticion.fechaCreacion),
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: _primaryColor.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Información del admin y reserva
              Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 20,
                    color: _secondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Admin: ${peticion.adminName}',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              Row(
                children: [
                  Icon(
                    Icons.bookmark,
                    size: 20,
                    color: _secondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reserva ID: ${peticion.reservaId.substring(0, 12)}...',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: _primaryColor.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Descripción de cambios
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.edit_note,
                          size: 20,
                          color: _primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cambios realizados:',
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      peticion.descripcionCambios,
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: _primaryColor.withOpacity(0.8),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Detalles de cambios (expandible)
              const SizedBox(height: 16),
              _buildCambiosDetallados(),
              
              // Información de respuesta si existe
              if (peticion.fechaRespuesta != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getEstadoColor().withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getEstadoColor().withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            peticion.fueAprobada ? Icons.check_circle : Icons.cancel,
                            size: 20,
                            color: _getEstadoColor(),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            peticion.fueAprobada ? 'Aprobada' : 'Rechazada',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _getEstadoColor(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(peticion.fechaRespuesta!)}',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: _primaryColor.withOpacity(0.6),
                        ),
                      ),
                      if (peticion.motivoRechazo != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Motivo: ${peticion.motivoRechazo}',
                          style: GoogleFonts.montserrat(
                            fontSize: 14,
                            color: _primaryColor.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              
              // Botones de acción para peticiones pendientes
              if (peticion.estaPendiente && (onAprobar != null || onRechazar != null)) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (onRechazar != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onRechazar,
                          icon: const Icon(Icons.close, size: 18),
                          label: Text(
                            'Rechazar',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    if (onRechazar != null && onAprobar != null)
                      const SizedBox(width: 12),
                    if (onAprobar != null)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onAprobar,
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(
                            'Aprobar',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCambiosDetallados() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      title: Text(
        'Ver cambios detallados',
        style: GoogleFonts.montserrat(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _secondaryColor,
        ),
      ),
      leading: Icon(
        Icons.info_outline,
        size: 20,
        color: _secondaryColor,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Valores antiguos
              Text(
                'Valores anteriores:',
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.red[700],
                ),
              ),
              const SizedBox(height: 8),
              ...peticion.valoresAntiguos.entries.map((entry) => 
                _buildCambioItem(entry.key, entry.value, Colors.red[100]!, Colors.red[700]!),
              ),
              
              const SizedBox(height: 16),
              
              // Valores nuevos
              Text(
                'Valores nuevos:',
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
              ),
              const SizedBox(height: 8),
              ...peticion.valoresNuevos.entries.map((entry) => 
                _buildCambioItem(entry.key, entry.value, Colors.green[100]!, Colors.green[700]!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCambioItem(String key, dynamic value, Color backgroundColor, Color textColor) {
    String displayKey = _getDisplayKey(key);
    String displayValue = _getDisplayValue(key, value);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$displayKey: ',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: textColor.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDisplayKey(String key) {
    switch (key) {
      case 'nombre':
        return 'Nombre';
      case 'telefono':
        return 'Teléfono';
      case 'correo':
        return 'Correo';
      case 'fecha':
        return 'Fecha';
      case 'horario':
        return 'Horario';
      case 'valor':
        return 'Valor';
      case 'montoPagado':
        return 'Abono';
      case 'estado':
        return 'Estado';
      case 'cancha_id':
        return 'Cancha ID';
      case 'sede':
        return 'Sede';
      case 'confirmada':
        return 'Confirmada';
      default:
        return key;
    }
  }

  String _getDisplayValue(String key, dynamic value) {
    if (value == null) return 'Sin valor';
    
    switch (key) {
      case 'fecha':
        try {
          final date = DateTime.parse(value.toString());
          return DateFormat('dd/MM/yyyy').format(date);
        } catch (e) {
          return value.toString();
        }
      case 'valor':
      case 'montoPagado':
        final formatter = NumberFormat('#,##0', 'es_CO');
        return 'COP ${formatter.format((value as num).toDouble())}';
      case 'estado':
        return value == 'completo' ? 'Completo' : 'Pendiente';
      case 'confirmada':
        return (value as bool) ? 'Sí' : 'No';
      default:
        return value.toString();
    }
  }

  Color _getEstadoColor() {
    switch (peticion.estado) {
      case EstadoPeticion.pendiente:
        return Colors.orange;
      case EstadoPeticion.aprobada:
        return Colors.green;
      case EstadoPeticion.rechazada:
        return Colors.red;
    }
  }

  IconData _getEstadoIcon() {
    switch (peticion.estado) {
      case EstadoPeticion.pendiente:
        return Icons.pending_actions;
      case EstadoPeticion.aprobada:
        return Icons.check_circle;
      case EstadoPeticion.rechazada:
        return Icons.cancel;
    }
  }

  String _getEstadoTexto() {
    switch (peticion.estado) {
      case EstadoPeticion.pendiente:
        return 'Pendiente';
      case EstadoPeticion.aprobada:
        return 'Aprobada';
      case EstadoPeticion.rechazada:
        return 'Rechazada';
    }
  }
}