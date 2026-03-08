import 'package:shared_preferences/shared_preferences.dart';
import '../models/ciudad.dart';

class CiudadPreferenceService {
  static const String _ciudadKey = 'selected_ciudad_id';
  static const String _ciudadNombreKey = 'selected_ciudad_nombre';
  static const String _ciudadCodigoKey = 'selected_ciudad_codigo';
  static const String _isFirstTimeKey = 'is_first_time';

  /// Guarda la ciudad seleccionada en SharedPreferences
  static Future<void> saveSelectedCiudad(Ciudad ciudad) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ciudadKey, ciudad.id);
    await prefs.setString(_ciudadNombreKey, ciudad.nombre);
    await prefs.setString(_ciudadCodigoKey, ciudad.codigo);
    await prefs.setBool(_isFirstTimeKey, false);
  }

  /// Obtiene la ciudad guardada desde SharedPreferences
  static Future<Ciudad?> getSelectedCiudad() async {
    final prefs = await SharedPreferences.getInstance();
    final ciudadId = prefs.getString(_ciudadKey);
    final ciudadNombre = prefs.getString(_ciudadNombreKey);
    final ciudadCodigo = prefs.getString(_ciudadCodigoKey);

    if (ciudadId != null && ciudadNombre != null && ciudadCodigo != null) {
      return Ciudad(
        id: ciudadId,
        nombre: ciudadNombre,
        codigo: ciudadCodigo,
        activa: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
    return null;
  }

  /// Verifica si es la primera vez que el usuario abre la app
  static Future<bool> isFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isFirstTimeKey) ?? true;
  }

  /// Limpia la ciudad guardada
  static Future<void> clearSelectedCiudad() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ciudadKey);
    await prefs.remove(_ciudadNombreKey);
    await prefs.remove(_ciudadCodigoKey);
  }

  /// Verifica si hay una ciudad guardada
  static Future<bool> hasSelectedCiudad() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ciudadKey) != null;
  }
}
