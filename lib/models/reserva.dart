import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'cancha.dart';
import 'horario.dart';
import 'package:flutter/material.dart';

enum TipoAbono { parcial, completo }

class Reserva {
  String id;
  Cancha cancha;
  DateTime fecha;
  Horario horario;
  String sede;
  TipoAbono tipoAbono;
  double montoTotal;
  double montoPagado;
  String? nombre;
  String? telefono;
  String? email;
  bool confirmada;
  
  // NUEVAS PROPIEDADES PARA RESERVAS GRUPALES Y PRECIOS PERSONALIZADOS
  String? grupoReservaId;          // ID del grupo de reservas
  int? totalHorasGrupo;            // Total de horas en el grupo
  bool precioPersonalizado;        // Si tiene precio personalizado
  double? precioOriginal;          // Precio original antes del descuento
  double? descuentoAplicado;       // Descuento aplicado
  List<String>? horarios;          // Lista de horarios (para compatibilidad)
  
  // ✅ NUEVA PROPIEDAD PARA RESERVAS RECURRENTES
  String? reservaRecurrenteId;     // ID de la reserva recurrente padre
  bool esReservaRecurrente;        // Si proviene de una reserva recurrente

  Reserva({
    required this.id,
    required this.cancha,
    required this.fecha,
    required this.horario,
    required this.sede,
    required this.tipoAbono,
    required this.montoTotal,
    required this.montoPagado,
    this.nombre,
    this.telefono,
    this.email,
    this.confirmada = false,
    // Propiedades existentes
    this.grupoReservaId,
    this.totalHorasGrupo,
    this.precioPersonalizado = false,
    this.precioOriginal,
    this.descuentoAplicado,
    this.horarios,
    // ✅ NUEVAS PROPIEDADES PARA RECURRENCIA
    this.reservaRecurrenteId,
    this.esReservaRecurrente = false,
  });

  // GETTER PARA SABER SI ES RESERVA GRUPAL
  bool get esReservaGrupal => grupoReservaId != null && (totalHorasGrupo ?? 0) > 1;

  // GETTER PARA SABER SI TIENE DESCUENTO
  bool get tieneDescuento => precioPersonalizado && (descuentoAplicado ?? 0) > 0;

  // GETTER PARA OBTENER EL PORCENTAJE DE DESCUENTO
  double get porcentajeDescuento {
    if (!tieneDescuento || precioOriginal == null || precioOriginal == 0) return 0.0;
    return ((descuentoAplicado ?? 0) / precioOriginal!) * 100;
  }

  // Calcular el monto total basado en el día y la hora
  static double calcularMontoTotal(Cancha cancha, DateTime fecha, Horario horario) {
    final String day = DateFormat('EEEE', 'es').format(fecha).toLowerCase();
    final String horaStr = horario.horaFormateada; // Usar directamente el formato 12h
    final preciosPorDia = cancha.preciosPorHorario[day] ?? {};
    final precioData = preciosPorDia[horaStr];
    final precio = precioData is Map<String, dynamic>
        ? (precioData['precio'] as num?)?.toDouble() ?? cancha.precio
        : (precioData as num?)?.toDouble() ?? cancha.precio;
    debugPrint('Calculando monto: Día=$day, Hora=$horaStr, Precio=$precio');
    return precio;
  }

  // CONSTRUCTOR MEJORADO DESDE FIRESTORE CON SOPORTE COMPLETO
  static Future<Reserva> fromFirestore(DocumentSnapshot doc) async {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    final fecha = DateFormat('yyyy-MM-dd').parse(data['fecha']);
    final horaStrFull = data['horario'] as String; // Ej. "10:00 PM"
    final is12HourFormat = horaStrFull.contains(RegExp(r'(AM|PM)', caseSensitive: false));
    final horaStr = horaStrFull.split(' ')[0]; // Ej. "10:00"
    int hour = int.parse(horaStr.split(':')[0]);
    final minute = int.parse(horaStr.split(':')[1]);

    if (is12HourFormat) {
      final period = horaStrFull.toUpperCase().contains('PM') ? 'PM' : 'AM';
      if (period == 'PM' && hour != 12) {
        hour += 12; // Convertir a formato 24h
      } else if (period == 'AM' && hour == 12) {
        hour = 0; // 12 AM es 00:00
      }
    }

    final hora = TimeOfDay(hour: hour, minute: minute);
    final horario = Horario(hora: hora);

    // Cargar cancha desde Firestore
    final canchaId = data['cancha_id'] as String? ?? '';
    Cancha cancha;
    if (canchaId.isNotEmpty) {
      final canchaDoc = await FirebaseFirestore.instance
          .collection('canchas')
          .doc(canchaId)
          .get();
      cancha = canchaDoc.exists
          ? Cancha.fromFirestore(canchaDoc)
          : Cancha(
              id: canchaId,
              nombre: 'Cancha desconocida',
              descripcion: '',
              imagen: 'assets/cancha_demo.png',
              techada: false,
              ubicacion: '',
              precio: 0.0,
              sedeId: data['sede'] ?? '',
              preciosPorHorario: {},
            );
    } else {
      cancha = Cancha(
        id: '',
        nombre: 'Cancha desconocida',
        descripcion: '',
        imagen: 'assets/cancha_demo.png',
        techada: false,
        ubicacion: '',
        precio: 0.0,
        sedeId: data['sede'] ?? '',
        preciosPorHorario: {},
      );
    }

    // LEER DATOS NUEVOS CON VALORES POR DEFECTO PARA COMPATIBILIDAD
    final grupoReservaId = data['grupo_reserva_id'] as String?;
    final totalHorasGrupo = data['total_horas_grupo'] as int?;
    final precioPersonalizado = data['precioPersonalizado'] as bool? ?? false;
    final precioOriginal = (data['precio_original'] as num?)?.toDouble();
    final descuentoAplicado = (data['descuento_aplicado'] as num?)?.toDouble();
    final reservaRecurrenteId = data['reservaRecurrenteId'] as String?;
    final esReservaRecurrente = data['esReservaRecurrente'] as bool? ?? false;


    
    // LEER LISTA DE HORARIOS SI EXISTE (para compatibilidad futura)
    List<String>? horarios;
    if (data['horarios'] is List) {
      horarios = List<String>.from(data['horarios']);
    }

    // USAR EL VALOR GUARDADO EN LA BD O CALCULAR SI NO EXISTE
    final montoTotal = (data['valor'] as num?)?.toDouble() ?? 
                      calcularMontoTotal(cancha, fecha, horario);
    final montoPagado = (data['montoPagado'] ?? 0).toDouble();
    final tipoAbono = montoPagado < montoTotal ? TipoAbono.parcial : TipoAbono.completo;

    return Reserva(
      id: doc.id,
      cancha: cancha,
      fecha: fecha,
      horario: horario,
      sede: data['sede'] ?? '',
      tipoAbono: tipoAbono,
      montoTotal: montoTotal,
      montoPagado: montoPagado,
      nombre: data['nombre'],
      telefono: data['telefono'],
      email: data['correo'],
      confirmada: data['confirmada'] ?? false,
      grupoReservaId: grupoReservaId,
      totalHorasGrupo: totalHorasGrupo,
      precioPersonalizado: precioPersonalizado,
      precioOriginal: precioOriginal,
      descuentoAplicado: descuentoAplicado,
      horarios: horarios,
      // ✅ NUEVOS CAMPOS PARA RECURRENCIA
      reservaRecurrenteId: reservaRecurrenteId,
      esReservaRecurrente: esReservaRecurrente,
    );
  }

  // CONSTRUCTOR CON CANCHAS MAP ACTUALIZADO
  factory Reserva.fromFirestoreWithCanchas(
      DocumentSnapshot doc, Map<String, Cancha> canchasMap) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    final fecha = DateFormat('yyyy-MM-dd').parse(data['fecha']);
    final horaStrFull = data['horario'] as String; // Ej. "8:00 PM" o "20:00"
    final horaStr = horaStrFull.split(' ')[0]; // Ej. "8:00"
    final is12HourFormat =
        horaStrFull.contains(RegExp(r'(AM|PM)', caseSensitive: false));
    int hour = int.parse(horaStr.split(':')[0]);
    final minute = int.parse(horaStr.split(':')[1]);

    if (is12HourFormat) {
      final period = horaStrFull.toUpperCase().contains('PM') ? 'PM' : 'AM';
      if (period == 'PM' && hour != 12) {
        hour += 12; // Convertir a formato 24h
      } else if (period == 'AM' && hour == 12) {
        hour = 0; // 12 AM es 00:00
      }
    }

    final hora = TimeOfDay(hour: hour, minute: minute);
    final horario = Horario(hora: hora);
    final canchaId = data['cancha_id'] ?? '';
    final cancha = canchasMap[canchaId] ??
        Cancha(
          id: canchaId,
          nombre: 'Cancha desconocida',
          descripcion: '',
          imagen: 'assets/cancha_demo.png',
          techada: false,
          ubicacion: '',
          precio: 0.0,
          sedeId: data['sede'] ?? '',
          preciosPorHorario: {},
        );

    // LEER DATOS NUEVOS CON VALORES POR DEFECTO
    final grupoReservaId = data['grupo_reserva_id'] as String?;
    final totalHorasGrupo = data['total_horas_grupo'] as int?;
    final precioPersonalizado = data['precio_personalizado'] as bool? ?? false;
    final precioOriginal = (data['precio_original'] as num?)?.toDouble();
    final descuentoAplicado = (data['descuento_aplicado'] as num?)?.toDouble();
    // ✅ LEER NUEVAS PROPIEDADES PARA RECURRENCIA
    final reservaRecurrenteId = data['reserva_recurrente_id'] as String?;
    final esReservaRecurrente = data['es_reserva_recurrente'] as bool? ?? false;
    
    List<String>? horarios;
    if (data['horarios'] is List) {
      horarios = List<String>.from(data['horarios']);
    }

    final montoTotal = (data['valor'] as num?)?.toDouble() ?? 
                      calcularMontoTotal(cancha, fecha, horario);
    final montoPagado = (data['montoPagado'] ?? 0).toDouble();
    final tipoAbono =
        montoPagado < montoTotal ? TipoAbono.parcial : TipoAbono.completo;

    return Reserva(
      id: doc.id,
      cancha: cancha,
      fecha: fecha,
      horario: horario,
      sede: data['sede'] ?? '',
      tipoAbono: tipoAbono,
      montoTotal: montoTotal,
      montoPagado: montoPagado,
      nombre: data['nombre'],
      telefono: data['telefono'],
      email: data['correo'],
      confirmada: data['confirmada'] ?? false,
      grupoReservaId: grupoReservaId,
      totalHorasGrupo: totalHorasGrupo,
      precioPersonalizado: precioPersonalizado,
      precioOriginal: precioOriginal,
      descuentoAplicado: descuentoAplicado,
      horarios: horarios,
      // ✅ NUEVOS CAMPOS PARA RECURRENCIA
      reservaRecurrenteId: reservaRecurrenteId,
      esReservaRecurrente: esReservaRecurrente,
    );
  }

  // TO FIRESTORE ACTUALIZADO PARA INCLUIR NUEVOS CAMPOS
  Map<String, dynamic> toFirestore() {
    final data = {
      'nombre': nombre,
      'telefono': telefono,
      'correo': email,
      'fecha': DateFormat('yyyy-MM-dd').format(fecha),
      'cancha_id': cancha.id,
      'horario': horario.horaFormateada,
      'estado': tipoAbono == TipoAbono.completo ? 'completo' : 'parcial',
      'valor': montoTotal,
      'montoPagado': montoPagado,
      'sede': sede,
      'confirmada': confirmada,
      'created_at': Timestamp.now(),
    };

    // AGREGAR CAMPOS OPCIONALES SOLO SI EXISTEN
    if (grupoReservaId != null) {
      data['grupo_reserva_id'] = grupoReservaId!;
    }
    
    if (totalHorasGrupo != null) {
      data['total_horas_grupo'] = totalHorasGrupo!;
    }
    
    if (precioPersonalizado) {
      data['precio_personalizado'] = true;
      if (precioOriginal != null) {
        data['precio_original'] = precioOriginal!;
      }
      if (descuentoAplicado != null) {
        data['descuento_aplicado'] = descuentoAplicado!;
      }
    }
    
    if (horarios != null && horarios!.isNotEmpty) {
      data['horarios'] = horarios!;
    }
    
    // ✅ AGREGAR NUEVAS PROPIEDADES PARA RECURRENCIA
    if (reservaRecurrenteId != null) {
      data['reserva_recurrente_id'] = reservaRecurrenteId!;
    }
    
    if (esReservaRecurrente) {
      data['es_reserva_recurrente'] = true;
    }

    return data;
  }

  // MÉTODO PARA COPIAR UNA RESERVA CON CAMBIOS
  Reserva copyWith({
    String? id,
    Cancha? cancha,
    DateTime? fecha,
    Horario? horario,
    String? sede,
    TipoAbono? tipoAbono,
    double? montoTotal,
    double? montoPagado,
    String? nombre,
    String? telefono,
    String? email,
    bool? confirmada,
    String? grupoReservaId,
    int? totalHorasGrupo,
    bool? precioPersonalizado,
    double? precioOriginal,
    double? descuentoAplicado,
    List<String>? horarios,
    // ✅ NUEVOS PARÁMETROS PARA RECURRENCIA
    String? reservaRecurrenteId,
    bool? esReservaRecurrente,
  }) {
    return Reserva(
      id: id ?? this.id,
      cancha: cancha ?? this.cancha,
      fecha: fecha ?? this.fecha,
      horario: horario ?? this.horario,
      sede: sede ?? this.sede,
      tipoAbono: tipoAbono ?? this.tipoAbono,
      montoTotal: montoTotal ?? this.montoTotal,
      montoPagado: montoPagado ?? this.montoPagado,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      email: email ?? this.email,
      confirmada: confirmada ?? this.confirmada,
      grupoReservaId: grupoReservaId ?? this.grupoReservaId,
      totalHorasGrupo: totalHorasGrupo ?? this.totalHorasGrupo,
      precioPersonalizado: precioPersonalizado ?? this.precioPersonalizado,
      precioOriginal: precioOriginal ?? this.precioOriginal,
      descuentoAplicado: descuentoAplicado ?? this.descuentoAplicado,
      horarios: horarios ?? this.horarios,
      // ✅ NUEVOS CAMPOS PARA RECURRENCIA
      reservaRecurrenteId: reservaRecurrenteId ?? this.reservaRecurrenteId,
      esReservaRecurrente: esReservaRecurrente ?? this.esReservaRecurrente,
    );
  }

  // MÉTODO PARA DEBUGGING Y LOGS
  @override
  String toString() {
    return 'Reserva{id: $id, cancha: ${cancha.nombre}, fecha: $fecha, horario: ${horario.horaFormateada}, '
           'montoTotal: $montoTotal, montoPagado: $montoPagado, esGrupal: $esReservaGrupal, '
           'tieneDescuento: $tieneDescuento, grupoId: $grupoReservaId, '
           'esRecurrente: $esReservaRecurrente, reservaRecurrenteId: $reservaRecurrenteId}';
  }
}