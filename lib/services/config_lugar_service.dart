import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/config_lugar.dart';

/// Servicio para leer/guardar la configuración del lugar (horarios, WhatsApp, cuentas).
/// Firestore: colección `config`, documento `lugar_{lugarId}`.
class ConfigLugarService {
  static const String _collection = 'config';

  static String _docId(String lugarId) => 'lugar_$lugarId';

  /// Obtiene la configuración del lugar. Si no existe, devuelve una config por defecto.
  static Future<ConfigLugar> getConfig(String lugarId) async {
    if (lugarId.isEmpty) return ConfigLugar();
    final doc = await FirebaseFirestore.instance
        .collection(_collection)
        .doc(_docId(lugarId))
        .get();
    if (doc.exists && doc.data() != null) {
      return ConfigLugar.fromFirestore(doc.data()!);
    }
    return ConfigLugar();
  }

  /// Guarda la configuración del lugar.
  static Future<void> setConfig(String lugarId, ConfigLugar config) async {
    if (lugarId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(_collection)
        .doc(_docId(lugarId))
        .set(config.toFirestore());
  }
}
