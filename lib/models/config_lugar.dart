/// Configuración por lugar: horarios de actividad, WhatsApp y cuentas para reservas.
/// Se guarda en Firestore en: config/lugar_{lugarId}
class ConfigLugar {
  /// Lunes=1 .. Domingo=7. Cada entrada: cerrado, o inicio/fin en "HH:mm" (24h).
  final Map<int, HorarioDia> horariosActividad;
  /// Número de WhatsApp para el mensaje de reserva (ej: +573013435434).
  final String whatsappReservas;
  /// Texto de cuentas bancarias que se incluye en el mensaje de WhatsApp.
  final String textoCuentasReservas;

  ConfigLugar({
    Map<int, HorarioDia>? horariosActividad,
    this.whatsappReservas = '',
    this.textoCuentasReservas = '',
  }) : horariosActividad = horariosActividad ?? _defaultHorarios();

  static Map<int, HorarioDia> _defaultHorarios() {
    return {
      1: HorarioDia(inicio: '06:00', fin: '22:00'), // Lunes
      2: HorarioDia(inicio: '06:00', fin: '22:00'),
      3: HorarioDia(inicio: '06:00', fin: '22:00'),
      4: HorarioDia(inicio: '06:00', fin: '22:00'),
      5: HorarioDia(inicio: '06:00', fin: '22:00'),
      6: HorarioDia(inicio: '06:00', fin: '22:00'),
      7: HorarioDia(inicio: '06:00', fin: '22:00'), // Domingo
    };
  }

  /// Devuelve el horario del día (1=lunes .. 7=domingo).
  HorarioDia horarioDia(int weekday) {
    return horariosActividad[weekday] ?? HorarioDia(inicio: '06:00', fin: '22:00');
  }

  /// Indica si el lugar está cerrado ese día.
  bool estaCerradoDia(int weekday) {
    return horarioDia(weekday).cerrado;
  }

  /// Indica si en el día y hora dados el lugar está dentro del horario de actividad.
  /// [weekday] 1=lunes .. 7=domingo; [hora] y [minuto] en formato 24h.
  bool estaDentroDeHorario(int weekday, int hora, int minuto) {
    final h = horarioDia(weekday);
    if (h.cerrado) return false;
    final totalMinutos = hora * 60 + minuto;
    final inicioMin = _parseHHmm(h.inicio);
    final finMin = _parseHHmm(h.fin);
    return totalMinutos >= inicioMin && totalMinutos < finMin;
  }

  static int _parseHHmm(String s) {
    final parts = s.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  factory ConfigLugar.fromFirestore(Map<String, dynamic> data) {
    Map<int, HorarioDia> horarios = {};
    final raw = data['horariosActividad'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final k = int.tryParse(e.key.toString()) ?? 0;
        if (k >= 1 && k <= 7 && e.value is Map) {
          horarios[k] = HorarioDia.fromMap(Map<String, dynamic>.from(e.value as Map));
        }
      }
    }
    if (horarios.length < 7) {
      final def = _defaultHorarios();
      for (int i = 1; i <= 7; i++) {
        horarios.putIfAbsent(i, () => def[i]!);
      }
    }
    return ConfigLugar(
      horariosActividad: horarios,
      whatsappReservas: data['whatsappReservas'] as String? ?? '',
      textoCuentasReservas: data['textoCuentasReservas'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    final horariosMap = <String, dynamic>{};
    for (final e in horariosActividad.entries) {
      horariosMap['${e.key}'] = e.value.toMap();
    }
    return {
      'horariosActividad': horariosMap,
      'whatsappReservas': whatsappReservas,
      'textoCuentasReservas': textoCuentasReservas,
    };
  }

  ConfigLugar copyWith({
    Map<int, HorarioDia>? horariosActividad,
    String? whatsappReservas,
    String? textoCuentasReservas,
  }) {
    return ConfigLugar(
      horariosActividad: horariosActividad ?? Map.from(this.horariosActividad),
      whatsappReservas: whatsappReservas ?? this.whatsappReservas,
      textoCuentasReservas: textoCuentasReservas ?? this.textoCuentasReservas,
    );
  }
}

class HorarioDia {
  final bool cerrado;
  final String inicio; // "HH:mm" 24h
  final String fin;

  HorarioDia({this.cerrado = false, this.inicio = '06:00', this.fin = '22:00'});

  Map<String, dynamic> toMap() => {
        'cerrado': cerrado,
        'inicio': inicio,
        'fin': fin,
      };

  factory HorarioDia.fromMap(Map<String, dynamic> m) {
    return HorarioDia(
      cerrado: m['cerrado'] as bool? ?? false,
      inicio: m['inicio'] as String? ?? '06:00',
      fin: m['fin'] as String? ?? '22:00',
    );
  }

  HorarioDia copyWith({bool? cerrado, String? inicio, String? fin}) {
    return HorarioDia(
      cerrado: cerrado ?? this.cerrado,
      inicio: inicio ?? this.inicio,
      fin: fin ?? this.fin,
    );
  }
}
