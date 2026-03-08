import 'package:cloud_firestore/cloud_firestore.dart';

class Ciudad {
  final String id;
  final String nombre;
  final String codigo;
  final bool activa;
  final DateTime createdAt;
  final DateTime updatedAt;

  Ciudad({
    required this.id,
    required this.nombre,
    required this.codigo,
    required this.activa,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Ciudad.fromFirestore(Map<String, dynamic> data, String id) {
    return Ciudad(
      id: id,
      nombre: data['nombre'] ?? '',
      codigo: data['codigo'] ?? '',
      activa: data['activa'] ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'codigo': codigo,
      'activa': activa,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Ciudad copyWith({
    String? id,
    String? nombre,
    String? codigo,
    bool? activa,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Ciudad(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      codigo: codigo ?? this.codigo,
      activa: activa ?? this.activa,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
