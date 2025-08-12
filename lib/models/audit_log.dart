// lib/models/audit_log.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

enum CategoriaLog {
  reservas,
  canchas,
  precios,
  sistema,
  seguridad,
  clientes,
  configuracion,
  usuarios,
  reportes
}

enum SeveridadLog {
  info,     // Verde - Operaciones normales
  warning,  // Amarillo - Precaución
  error,    // Naranja - Error no crítico
  critical  // Rojo - Crítico/Sospechoso
}

enum TipoAccion {
  crear,
  editar,
  eliminar,
  login,
  logout,
  cambio_precio,
  descuento_aplicado,
  reserva_masiva,
  acceso_no_autorizado
}

class AuditLog {
  final String id;
  final CategoriaLog categoria;
  final SeveridadLog severidad;
  final TipoAccion accion;
  final String usuarioId;
  final String usuarioNombre;
  final String descripcion;
  final String? entidadId;
  final String? entidadTipo;
  final Map<String, dynamic> datosAnteriores;
  final Map<String, dynamic> datosNuevos;
  final Map<String, dynamic> metadatos;
  final DateTime timestamp;
  final String? ipAddress;
  final String? userAgent;

  AuditLog({
    required this.id,
    required this.categoria,
    required this.severidad,
    required this.accion,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.descripcion,
    this.entidadId,
    this.entidadTipo,
    this.datosAnteriores = const {},
    this.datosNuevos = const {},
    this.metadatos = const {},
    required this.timestamp,
    this.ipAddress,
    this.userAgent,
  });

  factory AuditLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return AuditLog(
      id: doc.id,
      categoria: CategoriaLog.values.firstWhere(
        (e) => e.name == data['categoria'],
        orElse: () => CategoriaLog.sistema,
      ),
      severidad: SeveridadLog.values.firstWhere(
        (e) => e.name == data['severidad'],
        orElse: () => SeveridadLog.info,
      ),
      accion: TipoAccion.values.firstWhere(
        (e) => e.name == data['accion'],
        orElse: () => TipoAccion.crear,
      ),
      usuarioId: data['usuarioId'] ?? '',
      usuarioNombre: data['usuarioNombre'] ?? 'Usuario desconocido',
      descripcion: data['descripcion'] ?? '',
      entidadId: data['entidadId'],
      entidadTipo: data['entidadTipo'],
      datosAnteriores: Map<String, dynamic>.from(data['datosAnteriores'] ?? {}),
      datosNuevos: Map<String, dynamic>.from(data['datosNuevos'] ?? {}),
      metadatos: Map<String, dynamic>.from(data['metadatos'] ?? {}),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      ipAddress: data['ipAddress'],
      userAgent: data['userAgent'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'categoria': categoria.name,
      'severidad': severidad.name,
      'accion': accion.name,
      'usuarioId': usuarioId,
      'usuarioNombre': usuarioNombre,
      'descripcion': descripcion,
      'entidadId': entidadId,
      'entidadTipo': entidadTipo,
      'datosAnteriores': datosAnteriores,
      'datosNuevos': datosNuevos,
      'metadatos': metadatos,
      'timestamp': Timestamp.fromDate(timestamp),
      'ipAddress': ipAddress,
      'userAgent': userAgent,
    };
  }

  String get accionTexto {
    switch (accion) {
      case TipoAccion.crear:
        return 'Creación';
      case TipoAccion.editar:
        return 'Modificación';
      case TipoAccion.eliminar:
        return 'Eliminación';
      case TipoAccion.login:
        return 'Inicio de sesión';
      case TipoAccion.logout:
        return 'Cierre de sesión';
      case TipoAccion.cambio_precio:
        return 'Cambio de precio';
      case TipoAccion.descuento_aplicado:
        return 'Descuento aplicado';
      case TipoAccion.reserva_masiva:
        return 'Reserva masiva';
      case TipoAccion.acceso_no_autorizado:
        return 'Acceso no autorizado';
    }
  }

  String get fechaFormateada {
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(timestamp);
  }
}