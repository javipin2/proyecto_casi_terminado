// lib/utils/audit_interceptor.dart
import 'package:reserva_canchas/models/audit_log.dart';
import 'package:reserva_canchas/services/audit_service.dart';
import 'package:reserva_canchas/models/reserva.dart';
import 'package:reserva_canchas/models/cancha.dart';
import 'package:reserva_canchas/models/cliente.dart';

class AuditInterceptor {
  static final AuditService _auditService = AuditService();

  // 🎫 INTERCEPTAR CAMBIOS EN RESERVAS
  static Future<void> interceptarCambioReserva({
    required String usuarioId,
    required String usuarioNombre,
    required TipoAccion accion,
    required String reservaId,
    Map<String, dynamic> datosAnteriores = const {},
    Map<String, dynamic> datosNuevos = const {},
  }) async {
    
    // Determinar severidad basada en el tipo de cambio
    SeveridadLog severidad = SeveridadLog.info;
    String descripcion = '';

    switch (accion) {
      case TipoAccion.crear:
        descripcion = 'Nueva reserva creada: $reservaId';
        severidad = SeveridadLog.info;
        break;
      
      case TipoAccion.editar:
        final cambios = _analizarCambiosReserva(datosAnteriores, datosNuevos);
        descripcion = 'Reserva modificada: $reservaId - ${cambios.descripcion}';
        severidad = cambios.esCritico ? SeveridadLog.critical : 
                   cambios.esSospechoso ? SeveridadLog.warning : SeveridadLog.info;
        break;
      
      case TipoAccion.eliminar:
        descripcion = 'Reserva eliminada: $reservaId';
        severidad = SeveridadLog.warning;
        break;
      
      default:
        descripcion = 'Acción en reserva: ${accion.name} - $reservaId';
    }

    await _auditService.registrarLog(
      categoria: CategoriaLog.reservas,
      severidad: severidad,
      accion: accion,
      usuarioId: usuarioId,
      usuarioNombre: usuarioNombre,
      descripcion: descripcion,
      entidadId: reservaId,
      entidadTipo: 'reserva',
      datosAnteriores: datosAnteriores,
      datosNuevos: datosNuevos,
      metadatos: {
        'timestamp_cambio': DateTime.now().toIso8601String(),
        'app_version': '1.0.0', // Obtener de package_info
      },
    );
  }

  // 🏟️ INTERCEPTAR CAMBIOS EN CANCHAS
  static Future<void> interceptarCambioCancha({
    required String usuarioId,
    required String usuarioNombre,
    required TipoAccion accion,
    required String canchaId,
    Map<String, dynamic> datosAnteriores = const {},
    Map<String, dynamic> datosNuevos = const {},
  }) async {
    
    SeveridadLog severidad = SeveridadLog.info;
    String descripcion = '';

    switch (accion) {
      case TipoAccion.editar:
        if (_esCambioPrecio(datosAnteriores, datosNuevos)) {
          descripcion = 'Precios de cancha modificados: $canchaId';
          severidad = SeveridadLog.warning;
        } else {
          descripcion = 'Configuración de cancha modificada: $canchaId';
          severidad = SeveridadLog.info;
        }
        break;
      
      case TipoAccion.crear:
        descripcion = 'Nueva cancha creada: $canchaId';
        break;
      
      case TipoAccion.eliminar:
        descripcion = 'Cancha eliminada: $canchaId';
        severidad = SeveridadLog.critical;
        break;
      
      default:
        descripcion = 'Acción en cancha: ${accion.name} - $canchaId';
    }

    await _auditService.registrarLog(
      categoria: CategoriaLog.canchas,
      severidad: severidad,
      accion: accion,
      usuarioId: usuarioId,
      usuarioNombre: usuarioNombre,
      descripcion: descripcion,
      entidadId: canchaId,
      entidadTipo: 'cancha',
      datosAnteriores: datosAnteriores,
      datosNuevos: datosNuevos,
    );
  }

  // 👤 INTERCEPTAR CAMBIOS EN CLIENTES
  static Future<void> interceptarCambioCliente({
    required String usuarioId,
    required String usuarioNombre,
    required TipoAccion accion,
    required String clienteId,
    Map<String, dynamic> datosAnteriores = const {},
    Map<String, dynamic> datosNuevos = const {},
  }) async {
    
    await _auditService.registrarLog(
      categoria: CategoriaLog.clientes,
      severidad: accion == TipoAccion.eliminar ? SeveridadLog.warning : SeveridadLog.info,
      accion: accion,
      usuarioId: usuarioId,
      usuarioNombre: usuarioNombre,
      descripcion: 'Cliente ${accion.name}: $clienteId',
      entidadId: clienteId,
      entidadTipo: 'cliente',
      datosAnteriores: datosAnteriores,
      datosNuevos: datosNuevos,
    );
  }

  // 🔍 ANALIZAR CAMBIOS EN RESERVA
  static _CambioReserva _analizarCambiosReserva(
    Map<String, dynamic> datosAnteriores,
    Map<String, dynamic> datosNuevos,
  ) {
    List<String> cambios = [];
    bool esCritico = false;
    bool esSospechoso = false;

    // Analizar cambio de precio
    final precioAnterior = (datosAnteriores['valor'] as num?)?.toDouble() ?? 0;
    final precioNuevo = (datosNuevos['valor'] as num?)?.toDouble() ?? 0;
    
    if (precioAnterior != precioNuevo) {
      final diferenciaPorcentaje = precioAnterior > 0 
          ? ((precioAnterior - precioNuevo).abs() / precioAnterior) * 100 
          : 0;
      
      cambios.add('Precio: \${precioAnterior.toStringAsFixed(0)} → \${precioNuevo.toStringAsFixed(0)}');
      
      if (diferenciaPorcentaje > 50) {
        esCritico = true;
      } else if (diferenciaPorcentaje > 25) {
        esSospechoso = true;
      }
    }

    // Analizar cambio de fecha/hora
    if (datosAnteriores['fecha'] != datosNuevos['fecha']) {
      cambios.add('Fecha: ${datosAnteriores['fecha']} → ${datosNuevos['fecha']}');
      esSospechoso = true;
    }

    if (datosAnteriores['horario'] != datosNuevos['horario']) {
      cambios.add('Horario: ${datosAnteriores['horario']} → ${datosNuevos['horario']}');
      esSospechoso = true;
    }

    // Analizar cambio de datos del cliente
    if (datosAnteriores['nombre'] != datosNuevos['nombre']) {
      cambios.add('Cliente: ${datosAnteriores['nombre']} → ${datosNuevos['nombre']}');
    }

    return _CambioReserva(
      descripcion: cambios.isNotEmpty ? cambios.join(', ') : 'Cambios menores',
      esCritico: esCritico,
      esSospechoso: esSospechoso,
    );
  }

  // 💰 VERIFICAR SI ES CAMBIO DE PRECIO
  static bool _esCambioPrecio(
    Map<String, dynamic> datosAnteriores,
    Map<String, dynamic> datosNuevos,
  ) {
    final precioAnterior = datosAnteriores['precio'] ?? datosAnteriores['valor'] ?? 0;
    final precioNuevo = datosNuevos['precio'] ?? datosNuevos['valor'] ?? 0;
    return precioAnterior != precioNuevo;
  }
}

class _CambioReserva {
  final String descripcion;
  final bool esCritico;
  final bool esSospechoso;

  _CambioReserva({
    required this.descripcion,
    required this.esCritico,
    required this.esSospechoso,
  });
}