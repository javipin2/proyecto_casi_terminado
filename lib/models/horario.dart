import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as developer;

import 'package:reserva_canchas/models/cancha.dart';

enum EstadoHorario { disponible, reservado, vencido, procesandoPago }

class Horario {
  final TimeOfDay hora;
  final EstadoHorario estado;
  final bool esReservaRecurrente;
  final String? clienteNombre;
  final Map<String, dynamic>? reservaRecurrenteData;

  Horario({
    required this.hora,
    this.estado = EstadoHorario.disponible,
    this.esReservaRecurrente = false,
    this.clienteNombre,
    this.reservaRecurrenteData,
  });

  Horario copyWith({
    TimeOfDay? hora,
    EstadoHorario? estado,
    bool? esReservaRecurrente,
    String? clienteNombre,
    Map<String, dynamic>? reservaRecurrenteData,
  }) {
    return Horario(
      hora: hora ?? this.hora,
      estado: estado ?? this.estado,
      esReservaRecurrente: esReservaRecurrente ?? this.esReservaRecurrente,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      reservaRecurrenteData: reservaRecurrenteData ?? this.reservaRecurrenteData,
    );
  }

  String get horaFormateada {
    final int hour12 = (hora.hourOfPeriod == 0 ? 12 : hora.hourOfPeriod);
    final String minuteStr = hora.minute.toString().padLeft(2, '0');
    final String period = hora.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour12:$minuteStr $period';
  }

  static String normalizarHora(String horaStr) {
    try {
      // Limpiar espacios y convertir a mayúsculas
      String normalizada = horaStr.trim().toUpperCase();
      
      // Reemplazar múltiples espacios con uno solo
      normalizada = normalizada.replaceAll(RegExp(r'\s+'), ' ');
      
      // Asegurar formato consistente
      if (normalizada.contains('AM') || normalizada.contains('PM')) {
        return normalizada;
      }
      
      // Si no tiene AM/PM, intentar convertir desde formato 24 horas
      final parts = normalizada.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
        
        if (hour == 0) {
          return '12:${minute.toString().padLeft(2, '0')} AM';
        } else if (hour < 12) {
          return '$hour:${minute.toString().padLeft(2, '0')} AM';
        } else if (hour == 12) {
          return '12:${minute.toString().padLeft(2, '0')} PM';
        } else {
          return '${hour - 12}:${minute.toString().padLeft(2, '0')} PM';
        }
      }
      
      return normalizada;
    } catch (e) {
      developer.log('Error normalizando hora: $horaStr - $e');
      return horaStr.trim().toUpperCase();
    }
  }

  static Horario fromHoraFormateada(String horaStr) {
    try {
      horaStr = horaStr.trim();
      if (horaStr.toUpperCase().contains(RegExp(r'AM|PM'))) {
        final dateFormat = DateFormat('h:mm a');
        final dateTime = dateFormat.parse(horaStr.toUpperCase());
        return Horario(
          hora: TimeOfDay(hour: dateTime.hour, minute: dateTime.minute),
          esReservaRecurrente: false,
          clienteNombre: null,
        );
      }
      final parts = horaStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      return Horario(
        hora: TimeOfDay(hour: hour, minute: minute),
        esReservaRecurrente: false,
        clienteNombre: null,
      );
    } catch (e) {
      developer.log('Error parseando hora: $horaStr - $e');
      return Horario(
        hora: const TimeOfDay(hour: 0, minute: 0),
        esReservaRecurrente: false,
        clienteNombre: null,
      );
    }
  }

  int get minutosDelDia => hora.hour * 60 + hora.minute;

  int get minutosDelDiaParaOrdenamiento {
    if (hora.hour == 0) {
      return 1440 + hora.minute;
    }
    return hora.hour * 60 + hora.minute;
  }

  bool estaVencida(DateTime fecha) {
    final now = DateTime.now();
    if (fecha.year != now.year || fecha.month != now.month || fecha.day != now.day) {
      return false;
    }
    
    final horaActual = TimeOfDay.now();
    final minutosActuales = horaActual.hour * 60 + horaActual.minute;
    return minutosDelDiaParaOrdenamiento <= minutosActuales;
  }

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

  /// **Convertir día de la semana de string a int**
  static int _convertirDiaSemana(String dia) {
    switch (dia.toLowerCase()) {
      case 'lunes':
      case 'monday':
        return 1;
      case 'martes':
      case 'tuesday':
        return 2;
      case 'miércoles':
      case 'miercoles':
      case 'wednesday':
        return 3;
      case 'jueves':
      case 'thursday':
        return 4;
      case 'viernes':
      case 'friday':
        return 5;
      case 'sábado':
      case 'sabado':
      case 'saturday':
        return 6;
      case 'domingo':
      case 'sunday':
        return 7;
      default:
        return 0;
    }
  }

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
      final snapshot = reservasSnapshot ?? await FirebaseFirestore.instance
          .collection('reservas')
          .where('fecha', isEqualTo: fechaStr)
          .where('cancha_id', isEqualTo: canchaId)
          .where('sede', isEqualTo: sede)
          .get();

      final horariosOcupados = <String, Map<String, dynamic>>{};
      final horariosProcesandoPago = <String, Map<String, dynamic>>{};
      
      // ✅ NUEVO: Consultar reservas temporales (en proceso de pago)
      try {
        final ahora = DateTime.now().millisecondsSinceEpoch;
        final reservasTemporalesSnapshot = await FirebaseFirestore.instance
            .collection('reservas_temporales')
            .where('cancha_id', isEqualTo: canchaId)
            .where('fecha', isEqualTo: fechaStr)
            .where('sede', isEqualTo: sede)
            .where('expira_en', isGreaterThan: ahora)
            .get();
        
        developer.log('⏳ Reservas temporales encontradas: ${reservasTemporalesSnapshot.docs.length}');
        
        for (var doc in reservasTemporalesSnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            final estado = data['estado'] as String?;
            final horarioStr = normalizarHora(data['horario'] ?? '');
            
            if (horarioStr.isNotEmpty && (estado == 'bloqueado' || estado == 'pendiente')) {
              horariosProcesandoPago[horarioStr] = {
                'estado': estado,
                'clienteNombre': data['nombre'] as String? ?? 'Cliente',
                'referencia': doc.id,
              };
              developer.log('⏳ Horario $horarioStr marcado como PROCESANDO PAGO (estado: $estado)');
            }
          }
        }
      } catch (e) {
        developer.log('⚠️ Error consultando reservas temporales: $e');
      }
      
      // Procesar reservas existentes
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          // ✅ FILTRAR RESERVAS CON ESTADO "devolucion"
          final estado = data['estado'] as String?;
          if (estado == 'devolucion') {
            developer.log('🚫 Reserva ${doc.id} excluida por tener estado "devolucion"');
            continue; // Saltar esta reserva
          }
          
          final horarioStr = normalizarHora(data['horario'] ?? '');
          if (horarioStr.isNotEmpty) {
            horariosOcupados[horarioStr] = {
              'confirmada': data['confirmada'] as bool? ?? false,
              'clienteNombre': data['nombre'] as String? ?? 'Cliente',
            };
          }
        }
      }

      final dayPrices = cancha.preciosPorHorario[day] ?? {};
      for (final horaStr in dayPrices.keys) {
        final horaConfig = dayPrices[horaStr];
        if (horaConfig?['habilitada'] != true) continue;

        final horarioObj = Horario.fromHoraFormateada(horaStr);
        final horaFormateadaNormalizada = normalizarHora(horarioObj.horaFormateada);
        
        EstadoHorario estado;
        String? clienteNombre;
        
        if (horarioObj.estaVencida(fecha)) {
          estado = EstadoHorario.vencido;
        } else if (horariosProcesandoPago.containsKey(horaFormateadaNormalizada)) {
          // ✅ PRIORIDAD MÁXIMA: Si hay una reserva temporal (en proceso de pago), mostrar como "Procesando"
          final tempInfo = horariosProcesandoPago[horaFormateadaNormalizada]!;
          estado = EstadoHorario.procesandoPago;
          clienteNombre = tempInfo['clienteNombre'] as String? ?? 'Procesando pago';
          developer.log('⏳ Horario $horaFormateadaNormalizada marcado como PROCESANDO PAGO (reserva temporal)');
        } else if (horariosOcupados.containsKey(horaFormateadaNormalizada)) {
          final reservaInfo = horariosOcupados[horaFormateadaNormalizada]!;
          final confirmada = reservaInfo['confirmada'] as bool;
          clienteNombre = reservaInfo['clienteNombre'] as String?;
          
          estado = confirmada ? EstadoHorario.reservado : EstadoHorario.procesandoPago;
        } else {
          estado = EstadoHorario.disponible;
        }

        horarios.add(Horario(
          hora: horarioObj.hora, 
          estado: estado,
          esReservaRecurrente: false,
          clienteNombre: clienteNombre,
        ));
      }

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