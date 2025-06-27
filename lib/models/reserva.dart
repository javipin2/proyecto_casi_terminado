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
  });

  // Calcular el monto total basado en el día y la hora
  static double calcularMontoTotal(Cancha cancha, DateTime fecha, Horario horario) {
    final String day = DateFormat('EEEE', 'es').format(fecha).toLowerCase();
    String horaStr = horario.horaFormateada; // Ej. "10:00 PM"
    try {
      final time = DateFormat('h:mm a').parse(horaStr);
      horaStr = '${time.hour.toString().padLeft(2, '0')}:00'; // Ej. "22:00"
    } catch (e) {
      debugPrint('Error al parsear hora: $horaStr, error: $e');
      horaStr = '${horario.hora.hour.toString().padLeft(2, '0')}:00';
    }
    final preciosPorDia = cancha.preciosPorHorario[day] ?? {};
    final precio = preciosPorDia[horaStr] ?? cancha.precio;
    debugPrint('Calculando monto: Día=$day, Hora=$horaStr, Precio=$precio');
    return precio;
  }

  // Constructor original para compatibilidad con documentos existentes
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

    final montoTotal = calcularMontoTotal(cancha, fecha, horario);
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
    );
  }

  // Constructor con canchasMap para uso en AdminRegistroReservasScreen
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

    final montoTotal = calcularMontoTotal(cancha, fecha, horario);
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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
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
  }
}