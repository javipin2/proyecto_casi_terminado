// lib/models/reserva_recurrente.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

enum TipoRecurrencia { diaria, semanal, mensual }
enum EstadoRecurrencia { activa, pausada, cancelada }

class ReservaRecurrente {
  final String id;
  final String clienteId;
  final String clienteNombre;
  final String clienteTelefono;
  final String? clienteEmail;
  final String canchaId;
  final String sede;
  final String horario; // Formato "8:00 PM"
  final List<String> diasSemana; // ["lunes", "martes", "miercoles", etc.]
  final TipoRecurrencia tipoRecurrencia;
  final EstadoRecurrencia estado;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final double montoTotal;
  final double montoPagado;
  final List<String> diasExcluidos; // Fechas específicas en formato "yyyy-MM-dd"
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;
  final String? notas;
  
  // ✅ NUEVAS PROPIEDADES PARA PRECIO PERSONALIZADO
  final bool precioPersonalizado;
  final double? precioOriginal;
  final double? descuentoAplicado;

  ReservaRecurrente({
    required this.id,
    required this.clienteId,
    required this.clienteNombre,
    required this.clienteTelefono,
    this.clienteEmail,
    required this.canchaId,
    required this.sede,
    required this.horario,
    required this.diasSemana,
    required this.tipoRecurrencia,
    required this.estado,
    required this.fechaInicio,
    this.fechaFin,
    required this.montoTotal,
    required this.montoPagado,
    required this.diasExcluidos,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    this.notas,
    // ✅ NUEVOS PARÁMETROS
    this.precioPersonalizado = false,
    this.precioOriginal,
    this.descuentoAplicado,
  });

  // Verificar si una fecha específica está activa para esta reserva recurrente
  bool estaActivaEnFecha(DateTime fecha) {
  // Normalizar fechas para comparación (sin hora)
  final fechaNormalizada = DateTime(fecha.year, fecha.month, fecha.day);
  final inicioNormalizado = DateTime(fechaInicio.year, fechaInicio.month, fechaInicio.day);
  
  // ✅ Verificar que la fecha esté dentro del rango de inicio
  if (fechaNormalizada.isBefore(inicioNormalizado)) return false;
  
  // ✅ Verificar fecha fin si existe
  if (fechaFin != null) {
    final finNormalizado = DateTime(fechaFin!.year, fechaFin!.month, fechaFin!.day);
    if (fechaNormalizada.isAfter(finNormalizado)) return false;
  }
  
  // ✅ Verificar si el día está excluido
  final fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
  if (diasExcluidos.contains(fechaStr)) return false;
  
  // ✅ Verificar si el día de la semana coincide
  final diaSemana = DateFormat('EEEE', 'es').format(fecha).toLowerCase();
  if (!diasSemana.contains(diaSemana)) return false;
  
  // ✅ SI LLEGAMOS AQUÍ, LA FECHA ES VÁLIDA SEGÚN LA CONFIGURACIÓN
  // El estado se verifica en el provider, no aquí
  return true;
}



  // Excluir un día específico
  ReservaRecurrente excluirDia(DateTime fecha) {
    final fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
    final nuevasExclusiones = List<String>.from(diasExcluidos);
    if (!nuevasExclusiones.contains(fechaStr)) {
      nuevasExclusiones.add(fechaStr);
    }
    
    return copyWith(
      diasExcluidos: nuevasExclusiones,
      fechaActualizacion: DateTime.now(),
    );
  }

  // Incluir un día previamente excluido
  ReservaRecurrente incluirDia(DateTime fecha) {
    final fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
    final nuevasExclusiones = List<String>.from(diasExcluidos);
    nuevasExclusiones.remove(fechaStr);
    
    return copyWith(
      diasExcluidos: nuevasExclusiones,
      fechaActualizacion: DateTime.now(),
    );
  }

  // Crear desde Firestore
  factory ReservaRecurrente.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return ReservaRecurrente(
      id: doc.id,
      clienteId: data['clienteId'] ?? '',
      clienteNombre: data['clienteNombre'] ?? '',
      clienteTelefono: data['clienteTelefono'] ?? '',
      clienteEmail: data['clienteEmail'],
      canchaId: data['canchaId'] ?? '',
      sede: data['sede'] ?? '',
      horario: data['horario'] ?? '',
      diasSemana: List<String>.from(data['diasSemana'] ?? []),
      tipoRecurrencia: TipoRecurrencia.values.firstWhere(
        (e) => e.name == (data['tipoRecurrencia'] ?? 'semanal'),
        orElse: () => TipoRecurrencia.semanal,
      ),
      estado: EstadoRecurrencia.values.firstWhere(
        (e) => e.name == (data['estado'] ?? 'activa'),
        orElse: () => EstadoRecurrencia.activa,
      ),
      fechaInicio: (data['fechaInicio'] as Timestamp).toDate(),
      fechaFin: data['fechaFin'] != null ? (data['fechaFin'] as Timestamp).toDate() : null,
      montoTotal: (data['montoTotal'] ?? 0).toDouble(),
      montoPagado: (data['montoPagado'] ?? 0).toDouble(),
      diasExcluidos: List<String>.from(data['diasExcluidos'] ?? []),
      fechaCreacion: (data['fechaCreacion'] as Timestamp).toDate(),
      fechaActualizacion: (data['fechaActualizacion'] as Timestamp).toDate(),
      notas: data['notas'],
      // ✅ NUEVOS CAMPOS
      precioPersonalizado: data['precioPersonalizado'] as bool? ?? false,
      precioOriginal: (data['precioOriginal'] as num?)?.toDouble(),
      descuentoAplicado: (data['descuentoAplicado'] as num?)?.toDouble(),
    );
  }

  // Convertir a Firestore
  Map<String, dynamic> toFirestore() {
    final data = {
      'clienteId': clienteId,
      'clienteNombre': clienteNombre,
      'clienteTelefono': clienteTelefono,
      'clienteEmail': clienteEmail,
      'canchaId': canchaId,
      'sede': sede,
      'horario': horario,
      'diasSemana': diasSemana,
      'tipoRecurrencia': tipoRecurrencia.name,
      'estado': estado.name,
      'fechaInicio': Timestamp.fromDate(fechaInicio),
      'fechaFin': fechaFin != null ? Timestamp.fromDate(fechaFin!) : null,
      'montoTotal': montoTotal,
      'montoPagado': montoPagado,
      'diasExcluidos': diasExcluidos,
      'fechaCreacion': Timestamp.fromDate(fechaCreacion),
      'fechaActualizacion': Timestamp.fromDate(fechaActualizacion),
      'notas': notas,
      // ✅ NUEVOS CAMPOS
      'precioPersonalizado': precioPersonalizado,
    };
    
    if (precioOriginal != null) {
      data['precioOriginal'] = precioOriginal!;
    }
    
    if (descuentoAplicado != null) {
      data['descuentoAplicado'] = descuentoAplicado!;
    }
    
    return data;
  }
  

  // CopyWith
  ReservaRecurrente copyWith({
    String? id,
    String? clienteId,
    String? clienteNombre,
    String? clienteTelefono,
    String? clienteEmail,
    String? canchaId,
    String? sede,
    String? horario,
    List<String>? diasSemana,
    TipoRecurrencia? tipoRecurrencia,
    EstadoRecurrencia? estado,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    double? montoTotal,
    double? montoPagado,
    List<String>? diasExcluidos,
    DateTime? fechaCreacion,
    DateTime? fechaActualizacion,
    String? notas,
    // ✅ NUEVOS PARÁMETROS
    bool? precioPersonalizado,
    double? precioOriginal,
    double? descuentoAplicado,
  }) {
    return ReservaRecurrente(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      clienteTelefono: clienteTelefono ?? this.clienteTelefono,
      clienteEmail: clienteEmail ?? this.clienteEmail,
      canchaId: canchaId ?? this.canchaId,
      sede: sede ?? this.sede,
      horario: horario ?? this.horario,
      diasSemana: diasSemana ?? this.diasSemana,
      tipoRecurrencia: tipoRecurrencia ?? this.tipoRecurrencia,
      estado: estado ?? this.estado,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      montoTotal: montoTotal ?? this.montoTotal,
      montoPagado: montoPagado ?? this.montoPagado,
      diasExcluidos: diasExcluidos ?? this.diasExcluidos,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
      notas: notas ?? this.notas,
      // ✅ NUEVOS CAMPOS
      precioPersonalizado: precioPersonalizado ?? this.precioPersonalizado,
      precioOriginal: precioOriginal ?? this.precioOriginal,
      descuentoAplicado: descuentoAplicado ?? this.descuentoAplicado,
    );
  }
}
