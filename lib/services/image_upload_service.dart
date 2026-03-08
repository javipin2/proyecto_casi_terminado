import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ImageUploadService {
  static final ImagePicker _picker = ImagePicker();
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Abre el selector de imágenes (galería). En web muestra el file picker.
  static Future<XFile?> pickImage() async {
    return await _picker.pickImage(source: ImageSource.gallery);
  }

  /// Sube la imagen de un lugar y retorna la URL pública
  static Future<String> uploadLugarImage({
    required String lugarId,
    required XFile imageFile,
  }) async {
    // Detectar extensión
    final String fileExtension = _detectExtension(imageFile.path);
    final String path = 'lugares/$lugarId/portada$fileExtension';

    final Reference ref = _storage.ref().child(path);

    // Para compatibilidad (Web/Android/iOS), subimos como bytes
    final Uint8List data = await imageFile.readAsBytes();
    final metadata = SettableMetadata(contentType: _mimeFromExtension(fileExtension));
    await ref.putData(data, metadata);

    final String url = await ref.getDownloadURL();
    return url;
  }

  static String _detectExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.jpg')) return '.jpg';
    if (lower.endsWith('.jpeg')) return '.jpeg';
    if (lower.endsWith('.webp')) return '.webp';
    // Valor por defecto
    return '.jpg';
  }

  static String _mimeFromExtension(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}


