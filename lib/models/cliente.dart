import 'package:cloud_firestore/cloud_firestore.dart';

class Cliente {
  final String id;
  final String nombre;
  final String telefono;

  Cliente({
    required this.id,
    required this.nombre,
    required this.telefono,
  });

  // Método para crear un Cliente desde un documento de Firestore
  factory Cliente.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return Cliente(
      id: doc.id,
      nombre: data['nombre'] ?? '',
      telefono: data['telefono'] ?? '',
    );
  }

  // Convertir a Map para guardar en Firestore (no necesario aquí, pero útil para consistencia)
  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'telefono': telefono,
    };
  }
}
