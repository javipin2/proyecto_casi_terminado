// lib/models/peticion.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

enum EstadoPeticion { pendiente, aprobada, rechazada }

class Peticion {
  String id;
  String reservaId;
  String adminId; // ID del admin que hizo los cambios
  String adminName; // Nombre del admin que hizo los cambios
  EstadoPeticion estado;
  Map<String, dynamic> valoresAntiguos;
  Map<String, dynamic> valoresNuevos;
  String? motivoRechazo;
  DateTime fechaCreacion;
  DateTime? fechaRespuesta;
  String? superAdminId; // Quien aprobó/rechazó la petición
  String descripcionCambios; // Resumen de los cambios realizados

  Peticion({
    required this.id,
    required this.reservaId,
    required this.adminId,
    required this.adminName,
    this.estado = EstadoPeticion.pendiente,
    required this.valoresAntiguos,
    required this.valoresNuevos,
    this.motivoRechazo,
    required this.fechaCreacion,
    this.fechaRespuesta,
    this.superAdminId,
    required this.descripcionCambios,
  });

  // Crear desde Firestore
  factory Peticion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return Peticion(
      id: doc.id,
      reservaId: data['reserva_id'] ?? '',
      adminId: data['admin_id'] ?? '',
      adminName: data['admin_name'] ?? 'Admin desconocido',
      estado: EstadoPeticion.values.firstWhere(
        (e) => e.toString() == 'EstadoPeticion.${data['estado']}',
        orElse: () => EstadoPeticion.pendiente,
      ),
      valoresAntiguos: Map<String, dynamic>.from(data['valores_antiguos'] ?? {}),
      valoresNuevos: Map<String, dynamic>.from(data['valores_nuevos'] ?? {}),
      motivoRechazo: data['motivo_rechazo'],
      fechaCreacion: (data['fecha_creacion'] as Timestamp).toDate(),
      fechaRespuesta: data['fecha_respuesta'] != null 
          ? (data['fecha_respuesta'] as Timestamp).toDate()
          : null,
      superAdminId: data['super_admin_id'],
      descripcionCambios: data['descripcion_cambios'] ?? '',
    );
  }

  // Convertir a Firestore
  Map<String, dynamic> toFirestore() {
    final data = {
      'reserva_id': reservaId,
      'admin_id': adminId,
      'admin_name': adminName,
      'estado': estado.toString().split('.').last,
      'valores_antiguos': valoresAntiguos,
      'valores_nuevos': valoresNuevos,
      'fecha_creacion': Timestamp.fromDate(fechaCreacion),
      'descripcion_cambios': descripcionCambios,
    };

    if (motivoRechazo != null) {
      data['motivo_rechazo'] = motivoRechazo!;
    }

    if (fechaRespuesta != null) {
      data['fecha_respuesta'] = Timestamp.fromDate(fechaRespuesta!);
    }

    if (superAdminId != null) {
      data['super_admin_id'] = superAdminId!;
    }

    return data;
  }

  // Generar descripción automática de los cambios
  static String generarDescripcionCambios(
  Map<String, dynamic> valoresAntiguos, 
  Map<String, dynamic> valoresNuevos
) {
  List<String> cambios = [];

  // Verificar si es una reserva recurrente
  final esReservaRecurrente = valoresNuevos['tipo'] == 'reserva_recurrente_precio';
  
  if (esReservaRecurrente) {
    cambios.add('🔄 RESERVA RECURRENTE');
    
    // Cambios específicos para reservas recurrentes
    final oldTotal = valoresAntiguos['montoTotal'] as double? ?? 0;
    final newTotal = valoresNuevos['montoTotal'] as double? ?? 0;
    
    if (oldTotal != newTotal) {
      final formatter = NumberFormat('#,##0', 'es_CO');
      cambios.add('Precio total: COP ${formatter.format(oldTotal)} → COP ${formatter.format(newTotal)}');
    }

    final oldPagado = valoresAntiguos['montoPagado'] as double? ?? 0;
    final newPagado = valoresNuevos['montoPagado'] as double? ?? 0;
    
    if (oldPagado != newPagado) {
      final formatter = NumberFormat('#,##0', 'es_CO');
      cambios.add('Abono: COP ${formatter.format(oldPagado)} → COP ${formatter.format(newPagado)}');
    }

    final oldPersonalizado = valoresAntiguos['precioPersonalizado'] as bool? ?? false;
    final newPersonalizado = valoresNuevos['precioPersonalizado'] as bool? ?? false;
    
    if (oldPersonalizado != newPersonalizado) {
      cambios.add('Precio personalizado: ${oldPersonalizado ? "Sí" : "No"} → ${newPersonalizado ? "Sí" : "No"}');
    }

    // Agregar información sobre el ID de la reserva recurrente
    final reservaRecurrenteId = valoresNuevos['reservaRecurrenteId'] as String?;
    if (reservaRecurrenteId != null) {
      cambios.add('ID Recurrencia: ${reservaRecurrenteId.substring(0, 8)}...');
    }

    return cambios.isEmpty ? 'Sin cambios detectados en reserva recurrente' : cambios.join(', ');
  } else {
    // Lógica original para reservas normales
    valoresNuevos.forEach((key, newValue) {
      final oldValue = valoresAntiguos[key];
      if (oldValue != newValue) {
        switch (key) {
          case 'fecha':
            final oldDate = oldValue is String ? oldValue : '';
            final newDate = newValue is String ? newValue : '';
            if (oldDate.isNotEmpty && newDate.isNotEmpty) {
              try {
                final oldDateFormatted = DateFormat('dd/MM/yyyy')
                    .format(DateFormat('yyyy-MM-dd').parse(oldDate));
                final newDateFormatted = DateFormat('dd/MM/yyyy')
                    .format(DateFormat('yyyy-MM-dd').parse(newDate));
                cambios.add('Fecha: $oldDateFormatted → $newDateFormatted');
              } catch (e) {
                cambios.add('Fecha: $oldValue → $newValue');
              }
            }
            break;
          case 'horario':
            cambios.add('Horario: $oldValue → $newValue');
            break;
          case 'nombre':
            cambios.add('Nombre: $oldValue → $newValue');
            break;
          case 'telefono':
            cambios.add('Teléfono: $oldValue → $newValue');
            break;
          case 'correo':
            cambios.add('Correo: $oldValue → $newValue');
            break;
          case 'valor':
            final oldVal = (oldValue as num?)?.toDouble() ?? 0;
            final newVal = (newValue as num?)?.toDouble() ?? 0;
            final formatter = NumberFormat('#,##0', 'es_CO');
            cambios.add('Valor: COP ${formatter.format(oldVal)} → COP ${formatter.format(newVal)}');
            break;
          case 'montoPagado':
            final oldVal = (oldValue as num?)?.toDouble() ?? 0;
            final newVal = (newValue as num?)?.toDouble() ?? 0;
            final formatter = NumberFormat('#,##0', 'es_CO');
            cambios.add('Abono: COP ${formatter.format(oldVal)} → COP ${formatter.format(newVal)}');
            break;
          case 'estado':
            final oldEstado = oldValue == 'completo' ? 'Completo' : 'Pendiente';
            final newEstado = newValue == 'completo' ? 'Completo' : 'Pendiente';
            cambios.add('Estado: $oldEstado → $newEstado');
            break;
          case 'precio_personalizado':
            final oldPersonalizado = oldValue as bool? ?? false;
            final newPersonalizado = newValue as bool? ?? false;
            if (oldPersonalizado != newPersonalizado) {
              cambios.add('Precio personalizado: ${oldPersonalizado ? "Sí" : "No"} → ${newPersonalizado ? "Sí" : "No"}');
            }
            break;
          case 'cancha_id':
            // Este requeriría cargar el nombre de la cancha, por simplicidad usamos el ID
            cambios.add('Cancha modificada');
            break;
        }
      }
    });

    return cambios.isEmpty ? 'Sin cambios detectados' : cambios.join(', ');
  }
}


  /// Getter para saber si es una petición de reserva recurrente
  bool get esReservaRecurrente => valoresNuevos['tipo'] == 'reserva_recurrente_precio';

  /// Getter para obtener la prioridad de la petición
  String get prioridad => valoresNuevos['prioridad'] as String? ?? 'normal';

  /// Getter para saber si requiere validación especial
  bool get requiereValidacionEspecial => valoresNuevos['requiere_validacion_especial'] as bool? ?? false;

  /// Getter para obtener el tipo de petición
  String get tipoPeticion => valoresNuevos['tipo'] as String? ?? 'reserva_normal';

  /// Getter para el ID de reserva recurrente (si aplica)
  String? get reservaRecurrenteId => valoresNuevos['reservaRecurrenteId'] as String?;

  // Getter para saber si está pendiente
  bool get estaPendiente => estado == EstadoPeticion.pendiente;

  // Getter para saber si fue aprobada
  bool get fueAprobada => estado == EstadoPeticion.aprobada;

  // Getter para saber si fue rechazada
  bool get fueRechazada => estado == EstadoPeticion.rechazada;

  

  // Método para aprobar la petición
  Peticion aprobar(String superAdminId) {
    return Peticion(
      id: id,
      reservaId: reservaId,
      adminId: adminId,
      adminName: adminName,
      estado: EstadoPeticion.aprobada,
      valoresAntiguos: valoresAntiguos,
      valoresNuevos: valoresNuevos,
      motivoRechazo: null,
      fechaCreacion: fechaCreacion,
      fechaRespuesta: DateTime.now(),
      superAdminId: superAdminId,
      descripcionCambios: descripcionCambios,
    );
  }

  // Método para rechazar la petición
  Peticion rechazar(String superAdminId, String motivo) {
    return Peticion(
      id: id,
      reservaId: reservaId,
      adminId: adminId,
      adminName: adminName,
      estado: EstadoPeticion.rechazada,
      valoresAntiguos: valoresAntiguos,
      valoresNuevos: valoresNuevos,
      motivoRechazo: motivo,
      fechaCreacion: fechaCreacion,
      fechaRespuesta: DateTime.now(),
      superAdminId: superAdminId,
      descripcionCambios: descripcionCambios,
    );
  }

  @override
  String toString() {
    return 'Peticion{id: $id, reservaId: $reservaId, estado: $estado, '
           'adminName: $adminName, descripcion: $descripcionCambios}';
  }
}