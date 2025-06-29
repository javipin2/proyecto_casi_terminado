import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as developer;

import 'package:reserva_canchas/models/cancha.dart';

enum EstadoHorario { disponible, reservado, vencido }

class Horario {
  final TimeOfDay hora;
  final EstadoHorario estado;

  Horario({
    required this.hora,
    this.estado = EstadoHorario.disponible,
  });

  // Retorna la hora formateada, p. ej.: "8:00 PM"
  String get horaFormateada {
    final int hour12 = (hora.hourOfPeriod == 0 ? 12 : hora.hourOfPeriod);
    final String minuteStr = hora.minute.toString().padLeft(2, '0');
    final String period = hora.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour12:$minuteStr $period';
  }

  // Normaliza el formato de la hora para comparaciones
  static String normalizarHora(String horaStr) {
    return horaStr.trim().toUpperCase().replaceFirst(RegExp(r'\s+'), ' ');
  }

  // Convierte una cadena en formato "h:mm a" o "h:mm" a un objeto Horario
  static Horario fromHoraFormateada(String horaStr) {
    try {
      horaStr = horaStr.trim();
      // Intentar con formato AM/PM
      if (horaStr.toUpperCase().contains(RegExp(r'AM|PM'))) {
        final dateFormat = DateFormat('h:mm a');
        final dateTime = dateFormat.parse(horaStr.toUpperCase());
        return Horario(hora: TimeOfDay(hour: dateTime.hour, minute: dateTime.minute));
      }
      // Formato de 24 horas
      final parts = horaStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      return Horario(hora: TimeOfDay(hour: hour, minute: minute));
    } catch (e) {
      developer.log('Error parseando hora: $horaStr - $e');
      return Horario(hora: const TimeOfDay(hour: 0, minute: 0));
    }
  }

  // Convierte TimeOfDay a minutos del día para comparaciones
  int get minutosDelDia => hora.hour * 60 + hora.minute;

  // Convierte TimeOfDay a minutos del día para ordenamiento visual
  // Trata 12:00 AM (medianoche) como la última hora del día
  int get minutosDelDiaParaOrdenamiento {
    if (hora.hour == 0) {
      return 1440 + hora.minute;
    }
    return hora.hour * 60 + hora.minute;
  }

  // Verifica si la hora está vencida comparando con la hora actual
  bool estaVencida(DateTime fecha) {
    final now = DateTime.now();
    if (fecha.year != now.year || fecha.month != now.month || fecha.day != now.day) {
      return false;
    }
    
    final horaActual = TimeOfDay.now();
    final minutosActuales = horaActual.hour * 60 + horaActual.minute;
    return minutosDelDiaParaOrdenamiento <= minutosActuales;
  }

  // Registra un horario ocupado en Firestore con un ID determinista
  static Future<bool> marcarHorarioOcupado({
    required DateTime fecha,
    required String canchaId,
    required String sede,
    required TimeOfDay hora,
  }) async {
    final horaFormateada = normalizarHora(Horario(hora: hora).horaFormateada);
    final fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
    final reservaId = '${fechaStr}_${canchaId}_${horaFormateada}_$sede';

    try {
      final docRef = FirebaseFirestore.instance.collection('reservas').doc(reservaId);
      final docSnapshot = await docRef.get();
      
      if (docSnapshot.exists) {
        developer.log('⚠️ Reserva ya existe para $fechaStr a las $horaFormateada en $sede, cancha: $canchaId');
        return false;
      }

      await docRef.set({
        'fecha': fechaStr,
        'cancha_id': canchaId,
        'sede': sede,
        'horario': horaFormateada,
        'estado': 'Pendiente',
        'created_at': Timestamp.now(),
      });
      developer.log('✅ Reserva guardada para $fechaStr a las $horaFormateada en $sede, cancha: $canchaId');
      return true;
    } catch (e) {
      developer.log('🔥 Error al marcar horario como ocupado: $e');
      throw Exception('Error al marcar horario como ocupado: $e');
    }
  }

  // Genera los horarios disponibles para una fecha, cancha y sede determinada
  static Future<List<Horario>> generarHorarios({
    required DateTime fecha,
    required String canchaId,
    required String sede,
    QuerySnapshot? reservasSnapshot,
    required Cancha cancha,
  }) async {
    final List<Horario> horarios = [];
    final fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
    final day = DateFormat('EEEE', 'es').format(fecha).toLowerCase();

    try {
      // Obtener reservas si no se proporcionaron
      final snapshot = reservasSnapshot ?? await FirebaseFirestore.instance
          .collection('reservas')
          .where('fecha', isEqualTo: fechaStr)
          .where('cancha_id', isEqualTo: canchaId)
          .where('sede', isEqualTo: sede)
          .get();

      // Crear un Set de horarios ocupados normalizados
      final horariosOcupados = snapshot.docs
    .map((doc) => normalizarHora((doc.data() as Map<String, dynamic>?)?['horario'] ?? ''))
    .where((horario) => horario.isNotEmpty)
    .toSet();

      // Procesar horarios definidos en preciosPorHorario
      final dayPrices = cancha.preciosPorHorario[day] ?? {};
      for (final horaStr in dayPrices.keys) {
        final horaConfig = dayPrices[horaStr];
        if (horaConfig?['habilitada'] != true) continue;

        final horarioObj = Horario.fromHoraFormateada(horaStr);
        final horaFormateadaNormalizada = normalizarHora(horarioObj.horaFormateada);
        final estado = horarioObj.estaVencida(fecha)
            ? EstadoHorario.vencido
            : horariosOcupados.contains(horaFormateadaNormalizada)
                ? EstadoHorario.reservado
                : EstadoHorario.disponible;

        horarios.add(Horario(hora: horarioObj.hora, estado: estado));
      }

      // Ordenar horarios cronológicamente
      horarios.sort((a, b) => a.minutosDelDiaParaOrdenamiento.compareTo(b.minutosDelDiaParaOrdenamiento));

      developer.log('📊 ${horariosOcupados.length} horarios ocupados para $fechaStr');
      developer.log('📋 Generados ${horarios.length} horarios');
      return horarios;
    } catch (e) {
      developer.log('🔥 Error al obtener horarios ocupados: $e');
      throw Exception('Error al obtener horarios ocupados: $e');
    }
  }
}