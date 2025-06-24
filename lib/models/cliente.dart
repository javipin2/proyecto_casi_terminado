// lib/models/cliente.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Cliente {
  final String id;
  final String nombre;
  final String telefono;
  final String? correo; // Campo opcional

  Cliente({
    required this.id,
    required this.nombre,
    required this.telefono,
    this.correo,
  });

  // Método para crear un Cliente desde un documento de Firestore
  factory Cliente.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return Cliente(
      id: doc.id,
      nombre: data['nombre'] ?? '',
      telefono: data['telefono'] ?? '',
      correo: data['correo'], // Puede ser nulo
    );
  }

  // Convertir a Map para guardar en Firestore (no necesario aquí, pero útil para consistencia)
  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'telefono': telefono,
      'correo': correo,
    };
  }
}
