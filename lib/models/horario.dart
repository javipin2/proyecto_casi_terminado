import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    return horaStr.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Registra un horario ocupado en Firestore con un ID determinista.
  /// Verifica si la reserva ya existe para evitar duplicados.
  static Future<bool> marcarHorarioOcupado({
    required DateTime fecha,
    required String canchaId,
    required String sede,
    required TimeOfDay hora,
  }) async {
    final String horaFormateada = normalizarHora(Horario(hora: hora).horaFormateada);
    final String fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
    // Crear un ID determinista para la reserva
    final String reservaId =
        '${fechaStr}_${canchaId}_${horaFormateada}_${sede}';

    print('📝 Creando reserva con ID: $reservaId');

    try {
      final docRef =
          FirebaseFirestore.instance.collection('reservas').doc(reservaId);

      // Verificar si la reserva ya existe
      final docSnapshot = await docRef.get();
      if (docSnapshot.exists) {
        print(
            '⚠️ Reserva ya existe para $fechaStr a las $horaFormateada en $sede, cancha: $canchaId');
        return false; // No crear duplicado
      }

      // Crear la reserva
      await docRef.set({
        'fecha': fechaStr,
        'cancha_id': canchaId,
        'sede': sede,
        'horario': horaFormateada,
        'estado': 'Pendiente',
        'created_at': Timestamp.now(),
      });
      print(
          '✅ Reserva guardada para $fechaStr a las $horaFormateada en $sede, cancha: $canchaId');
      return true;
    } catch (e) {
      print('🔥 Error al marcar horario como ocupado: $e');
      throw Exception('🔥 Error al marcar horario como ocupado: $e');
    }
  }

  /// Genera los horarios disponibles para una fecha, cancha y sede determinada.
  static Future<List<Horario>> generarHorarios({
    required DateTime fecha,
    required String canchaId,
    required String sede,
    QuerySnapshot? reservasSnapshot,
  }) async {
    final List<Horario> horarios = [];
    const List<int> horasDisponibles = [
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23
    ];
    final String fechaStr = DateFormat('yyyy-MM-dd').format(fecha);

    try {
      // Obtener reservas si no se proporcionó un snapshot
      reservasSnapshot ??= await FirebaseFirestore.instance
          .collection('reservas')
          .where('fecha', isEqualTo: fechaStr)
          .where('cancha_id', isEqualTo: canchaId)
          .where('sede', isEqualTo: sede)
          .get();

      // Usar un Set para comparaciones más rápidas
      final horariosOcupados = <String>{
        for (var doc in reservasSnapshot.docs)
          normalizarHora((doc.data() as Map<String, dynamic>)['horario'] ?? '')
      };

      final now = DateTime.now();
      final bool esHoy = fechaStr == DateFormat('yyyy-MM-dd').format(now);

      for (var h in horasDisponibles) {
        final timeOfDay = TimeOfDay(hour: h, minute: 0);
        final String horaFormateada = normalizarHora(Horario(hora: timeOfDay).horaFormateada);
        final bool ocupado = horariosOcupados.contains(horaFormateada);
        final bool vencido = esHoy && h <= now.hour;

        EstadoHorario estado;
        if (vencido) {
          estado = EstadoHorario.vencido;
        } else if (ocupado) {
          estado = EstadoHorario.reservado;
        } else {
          estado = EstadoHorario.disponible;
        }

        horarios.add(Horario(hora: timeOfDay, estado: estado));
      }

      print('📊 ${horariosOcupados.length} horarios ocupados para $fechaStr');
      return horarios;
    } catch (e) {
      print('🔥 Error al obtener horarios ocupados: $e');
      throw Exception('🔥 Error al obtener horarios ocupados: $e');
    }
  }
}