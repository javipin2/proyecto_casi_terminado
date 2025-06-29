import 'package:cloud_firestore/cloud_firestore.dart';

class Cancha {
  final String id;
  final String nombre;
  final String descripcion;
  final String imagen;
  final bool techada;
  final String ubicacion;
  final double precio;
  final String sedeId;
  final Map<String, Map<String, Map<String, dynamic>>> preciosPorHorario;
  final bool disponible;
  final String? motivoNoDisponible;

  Cancha({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.imagen,
    required this.techada,
    required this.ubicacion,
    required this.precio,
    required this.sedeId,
    this.preciosPorHorario = const {},
    this.disponible = true,
    this.motivoNoDisponible,
  });

  // Crear Cancha desde un documento de Firestore
  factory Cancha.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Procesar preciosPorHorario de forma más directa
    final preciosPorHorario = <String, Map<String, Map<String, dynamic>>>{};
    if (data['preciosPorHorario'] is Map) {
      final preciosRaw = data['preciosPorHorario'] as Map<String, dynamic>;
      for (final day in preciosRaw.keys) {
        final horariosRaw = preciosRaw[day];
        if (horariosRaw is Map) {
          final horarios = <String, Map<String, dynamic>>{};
          for (final hora in horariosRaw.keys) {
            final datos = horariosRaw[hora];
            horarios[hora] = {
              'precio': datos is Map
                  ? (datos['precio'] is num ? datos['precio'].toDouble() : 0.0)
                  : (datos is num ? datos.toDouble() : 0.0),
              'habilitada': datos is Map ? (datos['habilitada'] as bool? ?? true) : true,
            };
          }
          preciosPorHorario[day] = horarios;
        }
      }
    }

    return Cancha(
      id: doc.id,
      nombre: data['nombre'] as String? ?? '',
      descripcion: data['descripcion'] as String? ?? '',
      imagen: data['imagen'] as String? ?? 'assets/cancha_demo.png',
      techada: data['techada'] as bool? ?? false,
      ubicacion: data['ubicacion'] as String? ?? '',
      precio: (data['precio'] is num) ? data['precio'].toDouble() : 0.0,
      sedeId: data['sedeId'] as String? ?? '',
      preciosPorHorario: preciosPorHorario,
      disponible: data['disponible'] as bool? ?? true,
      motivoNoDisponible: data['motivoNoDisponible'] as String?,
    );
  }

  // Convertir a Map para guardar en Firestore, solo con campos modificados
  Future<Map<String, dynamic>> toFirestore() async {
    final docRef = FirebaseFirestore.instance.collection('canchas').doc(id);
    final currentDoc = await docRef.get();

    if (!currentDoc.exists) {
      // Si el documento no existe, devolver todos los campos
      return {
        'nombre': nombre,
        'descripcion': descripcion,
        'imagen': imagen,
        'techada': techada,
        'ubicacion': ubicacion,
        'precio': precio,
        'sedeId': sedeId,
        'preciosPorHorario': preciosPorHorario,
        'disponible': disponible,
        'motivoNoDisponible': motivoNoDisponible,
      };
    }

    final currentCancha = Cancha.fromFirestore(currentDoc);
    if (!hasChanges(currentCancha)) {
      return {}; // No hay cambios, no escribir nada
    }

    // Incluir solo los campos que han cambiado
    final updates = <String, dynamic>{};
    if (nombre != currentCancha.nombre) updates['nombre'] = nombre;
    if (descripcion != currentCancha.descripcion) updates['descripcion'] = descripcion;
    if (imagen != currentCancha.imagen) updates['imagen'] = imagen;
    if (techada != currentCancha.techada) updates['techada'] = techada;
    if (ubicacion != currentCancha.ubicacion) updates['ubicacion'] = ubicacion;
    if (precio != currentCancha.precio) updates['precio'] = precio;
    if (sedeId != currentCancha.sedeId) updates['sedeId'] = sedeId;
    if (disponible != currentCancha.disponible) updates['disponible'] = disponible;
    if (motivoNoDisponible != currentCancha.motivoNoDisponible) {
      updates['motivoNoDisponible'] = motivoNoDisponible;
    }
    if (preciosPorHorario.toString() != currentCancha.preciosPorHorario.toString()) {
      updates['preciosPorHorario'] = preciosPorHorario;
    }

    return updates;
  }

  // Método para comparar con datos existentes
  bool hasChanges(Cancha other) {
    if (nombre != other.nombre ||
        descripcion != other.descripcion ||
        imagen != other.imagen ||
        techada != other.techada ||
        ubicacion != other.ubicacion ||
        precio != other.precio ||
        sedeId != other.sedeId ||
        disponible != other.disponible ||
        motivoNoDisponible != other.motivoNoDisponible) {
      return true;
    }

    // Comparar preciosPorHorario de forma más eficiente
    if (preciosPorHorario.length != other.preciosPorHorario.length) return true;
    for (final day in preciosPorHorario.keys) {
      if (!other.preciosPorHorario.containsKey(day)) return true;
      final horarios = preciosPorHorario[day]!;
      final otherHorarios = other.preciosPorHorario[day]!;
      if (horarios.length != otherHorarios.length) return true;
      for (final hora in horarios.keys) {
        if (!otherHorarios.containsKey(hora)) return true;
        final current = horarios[hora]!;
        final otherData = otherHorarios[hora]!;
        if (current['precio'] != otherData['precio'] ||
            current['habilitada'] != otherData['habilitada']) {
          return true;
        }
      }
    }
    return false;
  }

  // Método auxiliar para obtener información de la sede
  static Future<Map<String, dynamic>?> getSedeInfo(String sedeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sedes')
          .doc(sedeId)
          .get();
      return doc.data();
    } catch (e) {
      print('Error obteniendo sede: $e');
      return null;
    }
  }
}