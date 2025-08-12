// lib/services/anomaly_detector.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:reserva_canchas/models/alerta_critica.dart';
import 'dart:developer' as developer;

class ResultadoAnalisisPrecio {
  final bool esAnomalo;
  final NivelRiesgo nivelRiesgo;
  final String razon;
  final double porcentajeDescuento;

  ResultadoAnalisisPrecio({
    required this.esAnomalo,
    required this.nivelRiesgo,
    required this.razon,
    required this.porcentajeDescuento,
  });
}

class AnomalyDetector {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 💰 DETECTAR PRECIOS ANÓMALOS
  Future<ResultadoAnalisisPrecio> esPrecioAnomalo(
    Map<String, dynamic> datosNuevos,
    Map<String, dynamic> datosAnteriores,
    String entidadId,
  ) async {
    try {
      final precioNuevo = (datosNuevos['valor'] as num?)?.toDouble() ?? 0;
      final precioAnterior = (datosAnteriores['valor'] as num?)?.toDouble() ?? 0;
      final descuentoAplicado = (datosNuevos['descuento_aplicado'] as num?)?.toDouble() ?? 0;
      final precioOriginal = (datosNuevos['precio_original'] as num?)?.toDouble() ?? precioNuevo;

      // Si no hay cambio de precio, no es anómalo
      if (precioNuevo == precioAnterior && descuentoAplicado == 0) {
        return ResultadoAnalisisPrecio(
          esAnomalo: false,
          nivelRiesgo: NivelRiesgo.bajo,
          razon: 'Sin cambios de precio',
          porcentajeDescuento: 0,
        );
      }

      // Calcular porcentaje de descuento
      double porcentajeDescuento = 0;
      if (precioOriginal > 0 && descuentoAplicado > 0) {
        porcentajeDescuento = (descuentoAplicado / precioOriginal) * 100;
      } else if (precioAnterior > 0 && precioNuevo < precioAnterior) {
        porcentajeDescuento = ((precioAnterior - precioNuevo) / precioAnterior) * 100;
      }

      // 🚨 DESCUENTO MAYOR AL 50% - CRÍTICO
      if (porcentajeDescuento >= 50) {
        return ResultadoAnalisisPrecio(
          esAnomalo: true,
          nivelRiesgo: NivelRiesgo.critico,
          razon: 'Descuento crítico del ${porcentajeDescuento.toStringAsFixed(1)}% aplicado. Precio: \${precioAnterior.toStringAsFixed(0)} → \${precioNuevo.toStringAsFixed(0)}',
          porcentajeDescuento: porcentajeDescuento,
        );
      }

      // ⚠️ DESCUENTO ENTRE 30-50% - ALTO
      if (porcentajeDescuento >= 30) {
        return ResultadoAnalisisPrecio(
          esAnomalo: true,
          nivelRiesgo: NivelRiesgo.alto,
          razon: 'Descuento significativo del ${porcentajeDescuento.toStringAsFixed(1)}% aplicado. Precio: \${precioAnterior.toStringAsFixed(0)} → \${precioNuevo.toStringAsFixed(0)}',
          porcentajeDescuento: porcentajeDescuento,
        );
      }

      // 📊 COMPARAR CON PROMEDIO HISTÓRICO
      final promedioHistorico = await _obtenerPromedioPrecios(entidadId);
      if (promedioHistorico > 0) {
        final desviacionPorcentaje = ((promedioHistorico - precioNuevo).abs() / promedioHistorico) * 100;
        
        if (desviacionPorcentaje >= 40) {
          return ResultadoAnalisisPrecio(
            esAnomalo: true,
            nivelRiesgo: NivelRiesgo.alto,
            razon: 'Precio se desvía ${desviacionPorcentaje.toStringAsFixed(1)}% del promedio histórico (\${promedioHistorico.toStringAsFixed(0)})',
            porcentajeDescuento: desviacionPorcentaje,
          );
        }
      }

      // 💰 PRECIO EXCESIVAMENTE BAJO (menos de $10,000)
      if (precioNuevo > 0 && precioNuevo < 10000) {
        return ResultadoAnalisisPrecio(
          esAnomalo: true,
          nivelRiesgo: NivelRiesgo.medio,
          razon: 'Precio excesivamente bajo: \${precioNuevo.toStringAsFixed(0)} (menos de \$10,000)',
          porcentajeDescuento: porcentajeDescuento,
        );
      }

      return ResultadoAnalisisPrecio(
        esAnomalo: false,
        nivelRiesgo: NivelRiesgo.bajo,
        razon: 'Precio dentro de rangos normales',
        porcentajeDescuento: porcentajeDescuento,
      );
    } catch (e) {
      developer.log('🔥 Error al analizar precio: $e');
      return ResultadoAnalisisPrecio(
        esAnomalo: false,
        nivelRiesgo: NivelRiesgo.bajo,
        razon: 'Error en análisis',
        porcentajeDescuento: 0,
      );
    }
  }

  // 📈 OBTENER PROMEDIO HISTÓRICO DE PRECIOS
  Future<double> _obtenerPromedioPrecios(String canchaId) async {
    try {
      final hace30Dias = DateTime.now().subtract(const Duration(days: 30));
      
      final reservas = await _firestore
          .collection('reservas')
          .where('cancha_id', isEqualTo: canchaId)
          .where('created_at', isGreaterThan: Timestamp.fromDate(hace30Dias))
          .get();

      if (reservas.docs.isEmpty) return 0;

      double suma = 0;
      int contador = 0;

      for (final doc in reservas.docs) {
        final data = doc.data();
        final valor = (data['valor'] as num?)?.toDouble();
        if (valor != null && valor > 0) {
          suma += valor;
          contador++;
        }
      }

      return contador > 0 ? suma / contador : 0;
    } catch (e) {
      developer.log('🔥 Error al obtener promedio de precios: $e');
      return 0;
    }
  }

  // 🔍 DETECTAR PATRONES SOSPECHOSOS EN RESERVAS
  Future<bool> esPatronReservaSospechoso(Map<String, dynamic> reservaData) async {
    try {
      final clienteTelefono = reservaData['telefono'] as String? ?? '';
      final fecha = reservaData['fecha'] as String? ?? '';
      
      if (clienteTelefono.isEmpty) return false;

      // Buscar reservas del mismo teléfono en el mismo día
      final reservasMismoDia = await _firestore
          .collection('reservas')
          .where('telefono', isEqualTo: clienteTelefono)
          .where('fecha', isEqualTo: fecha)
          .get();

      // 🚨 MÁS DE 3 RESERVAS DEL MISMO TELÉFONO EN UN DÍA
      if (reservasMismoDia.docs.length > 3) {
        return true;
      }

      // 🚨 RESERVAS EN HORARIOS CONSECUTIVOS (posible acaparamiento)
      if (reservasMismoDia.docs.length >= 2) {
        final horarios = reservasMismoDia.docs
            .map((doc) => (doc.data() as Map<String, dynamic>)['horario'] as String? ?? '')
            .where((h) => h.isNotEmpty)
            .toList();
        
        // Verificar si hay horarios consecutivos
        return _tieneHorariosConsecutivos(horarios);
      }

      return false;
    } catch (e) {
      developer.log('🔥 Error al detectar patrón sospechoso: $e');
      return false;
    }
  }

  // ⏰ VERIFICAR HORARIOS CONSECUTIVOS
  bool _tieneHorariosConsecutivos(List<String> horarios) {
    if (horarios.length < 2) return false;

    // Convertir horarios a minutos del día para comparar
    final minutosDelDia = horarios.map((h) => _convertirHoraAMinutos(h)).toList();
    minutosDelDia.sort();

    for (int i = 0; i < minutosDelDia.length - 1; i++) {
      final diferencia = minutosDelDia[i + 1] - minutosDelDia[i];
      if (diferencia == 60) { // 1 hora de diferencia = horarios consecutivos
        return true;
      }
    }

    return false;
  }

  // 🕐 CONVERTIR HORA STRING A MINUTOS
  int _convertirHoraAMinutos(String horaStr) {
    try {
      final partes = horaStr.split(' ');
      final hora = partes[0].split(':');
      int horas = int.parse(hora[0]);
      final minutos = int.parse(hora[1]);
      
      if (partes.length > 1 && partes[1].toUpperCase() == 'PM' && horas != 12) {
        horas += 12;
      } else if (partes.length > 1 && partes[1].toUpperCase() == 'AM' && horas == 12) {
        horas = 0;
      }
      
      return horas * 60 + minutos;
    } catch (e) {
      developer.log('🔥 Error al convertir hora: $horaStr - $e');
      return 0;
    }
  }
}