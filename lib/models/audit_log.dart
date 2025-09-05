// lib/models/audit_entry.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AuditEntry {
  final String id;
  final String accion;
  final String entidad;
  final String entidadId;
  final String usuarioId;
  final String usuarioNombre;
  final String usuarioRol;
  final Timestamp timestamp;
  final Map<String, dynamic> datosAntiguos;
  final Map<String, dynamic> datosNuevos;
  final Map<String, dynamic> metadatos;
  final String descripcion;
  final String nivelRiesgo;
  final List<String> alertas;
  final List<String> cambiosDetectados;
  final String ipAddress;
  final String userAgent;

  AuditEntry({
    required this.id,
    required this.accion,
    required this.entidad,
    required this.entidadId,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.usuarioRol,
    required this.timestamp,
    required this.datosAntiguos,
    required this.datosNuevos,
    required this.metadatos,
    required this.descripcion,
    required this.nivelRiesgo,
    required this.alertas,
    required this.cambiosDetectados,
    required this.ipAddress,
    required this.userAgent,
  });

  factory AuditEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AuditEntry(
      id: doc.id,
      accion: data['accion'] ?? '',
      entidad: data['entidad'] ?? '',
      entidadId: data['entidad_id'] ?? '',
      usuarioId: data['usuario_id'] ?? '',
      usuarioNombre: data['usuario_nombre'] ?? '',
      usuarioRol: data['usuario_rol'] ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      datosAntiguos: Map<String, dynamic>.from(data['datos_antiguos'] ?? {}),
      datosNuevos: Map<String, dynamic>.from(data['datos_nuevos'] ?? {}),
      metadatos: Map<String, dynamic>.from(data['metadatos'] ?? {}),
      descripcion: data['descripcion'] ?? '',
      nivelRiesgo: data['nivel_riesgo'] ?? 'bajo',
      alertas: List<String>.from(data['alertas'] ?? []),
      cambiosDetectados: List<String>.from(data['cambios_detectados'] ?? []),
      ipAddress: data['ip_address'] ?? '',
      userAgent: data['user_agent'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'accion': accion,
      'entidad': entidad,
      'entidad_id': entidadId,
      'usuario_id': usuarioId,
      'usuario_nombre': usuarioNombre,
      'usuario_rol': usuarioRol,
      'timestamp': timestamp,
      'datos_antiguos': datosAntiguos,
      'datos_nuevos': datosNuevos,
      'metadatos': metadatos,
      'descripcion': descripcion,
      'nivel_riesgo': nivelRiesgo,
      'alertas': alertas,
      'cambios_detectados': cambiosDetectados,
      'ip_address': ipAddress,
      'user_agent': userAgent,
    };
  }

  // Getters útiles
  DateTime get fechaLocal => timestamp.toDate();
  String get fechaFormateada => DateFormat('dd/MM/yyyy HH:mm:ss').format(fechaLocal);
  
  Color get colorNivelRiesgo {
    switch (nivelRiesgo) {
      case 'critico':
        return Colors.red.shade700;
      case 'alto':
        return Colors.orange.shade700;
      case 'medio':
        return Colors.yellow.shade700;
      case 'bajo':
        return Colors.green.shade700;
      default:
        return Colors.grey;
    }
  }

  IconData get iconoNivelRiesgo {
    switch (nivelRiesgo) {
      case 'critico':
        return Icons.error;
      case 'alto':
        return Icons.warning;
      case 'medio':
        return Icons.info;
      case 'bajo':
        return Icons.check_circle;
      default:
        return Icons.help;
    }
  }

  String get nombreNivelRiesgo {
    switch (nivelRiesgo) {
      case 'critico':
        return 'Crítico';
      case 'alto':
        return 'Alto';
      case 'medio':
        return 'Medio';
      case 'bajo':
        return 'Bajo';
      default:
        return 'Desconocido';
    }
  }

  bool get tieneAlertas => alertas.isNotEmpty;
  bool get tieneCambios => cambiosDetectados.isNotEmpty;
}