import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:reserva_canchas/providers/cancha_provider.dart';
import 'package:reserva_canchas/services/plan_feature_service.dart';
import '../../../providers/sede_provider.dart';
import '../../../widgets/mapa_seleccion_ubicacion.dart';
import 'dart:async';

// Helper para ejecutar futures sin await (evita warnings)
void unawaited(Future<void> future) {
  // Intencionalmente no esperamos el future
}

class AdminSedesScreen extends StatefulWidget {
  const AdminSedesScreen({super.key});

  @override
  State<AdminSedesScreen> createState() => _AdminSedesScreenState();
}

class _AdminSedesScreenState extends State<AdminSedesScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _sedeController = TextEditingController();
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  bool _isLoading = false;
  bool _isFormVisible = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  double? _latitudSeleccionada;
  double? _longitudSeleccionada;

  static const _primaryColor = Color(0xFF2196F3);
  static const _backgroundColor = Color(0xFFF8F9FA);
  static const _cardColor = Colors.white;
  static const _textPrimary = Color(0xFF212121);
  static const _textSecondary = Color(0xFF757575);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SedeProvider>(context, listen: false).fetchSedes();
    });
  }

  @override
  void dispose() {
    _sedeController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleFormVisibility() {
    setState(() {
      _isFormVisible = !_isFormVisible;
      if (_isFormVisible) {
        _animationController.forward();
      } else {
        _animationController.reverse();
        _sedeController.clear();
        _clearSelectedImage();
        _latitudSeleccionada = null;
        _longitudSeleccionada = null;
      }
    });
  }

  Future<String?> _uploadImage(String sede) async {
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('sede/${sede}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      UploadTask uploadTask;

      if (kIsWeb) {
        if (_selectedImageBytes != null) {
          uploadTask = storageRef.putData(_selectedImageBytes!);
        } else {
          return null;
        }
      } else {
        if (_selectedImageFile != null) {
          uploadTask = storageRef.putFile(_selectedImageFile!);
        } else {
          return null;
        }
      }

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();
      debugPrint('Imagen subida exitosamente a: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('Error subiendo imagen: $e');
      _showSnackBar('Error al subir la imagen: $e', isError: true);
      return null;
    }
  }

  void _pickImage() async {
  final picker = ImagePicker();
  final pickedFile = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1920,
    maxHeight: 1080,
    imageQuality: 85,
  );

  if (pickedFile != null && mounted) {
    try {
      Uint8List? compressedBytes;
      if (kIsWeb) {
        compressedBytes = await pickedFile.readAsBytes();
        if (compressedBytes.length > 5 * 1024 * 1024) {
          _showSnackBar('La imagen excede el tamaño máximo de 5MB', isError: true);
          return;
        }
        // Intentar compresión solo si es compatible, de lo contrario usar los bytes originales
        try {
          compressedBytes = await FlutterImageCompress.compressWithList(
            compressedBytes,
            minWidth: 1920,
            minHeight: 1080,
            quality: 70,
          );
        } catch (e) {
          debugPrint('Error al comprimir imagen en web: $e');
          // Usar los bytes originales si la compresión falla
          compressedBytes = await pickedFile.readAsBytes();
        }
      } else {
        final file = File(pickedFile.path);
        final fileSize = await file.length();
        if (fileSize > 5 * 1024 * 1024) {
          _showSnackBar('La imagen excede el tamaño máximo de 5MB', isError: true);
          return;
        }
        compressedBytes = await FlutterImageCompress.compressWithFile(
          pickedFile.path,
          minWidth: 1920,
          minHeight: 1080,
          quality: 70,
        );
      }

      if (mounted) {
        setState(() {
          if (kIsWeb) {
            _selectedImageBytes = compressedBytes;
            _selectedImageFile = null;
          } else {
            _selectedImageFile = File(pickedFile.path); // Guardar el archivo original para _uploadImage
            _selectedImageBytes = null;
          }
        });
      }
    } catch (e) {
      _showSnackBar('Error al procesar la imagen: $e', isError: true);
    }
  }
}

  void _clearSelectedImage() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageBytes = null;
    });
  }

  bool get _hasSelectedImage =>
      (kIsWeb && _selectedImageBytes != null) || (!kIsWeb && _selectedImageFile != null);

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.montserrat(fontSize: 14, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _addSede() async {
    if (!_formKey.currentState!.validate()) return;

    // Verificar límite de sedes según el plan / configuración del lugar
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final maxSedes = await PlanFeatureService.getLugarMaxSedes();
    if (maxSedes != null && sedeProvider.sedes.length >= maxSedes) {
      _showSnackBar(
        'Has alcanzado el máximo de sedes permitido por tu plan ($maxSedes). '
        'Puedes ajustar el límite desde la gestión de lugares.',
        isError: true,
      );
      return;
    }

    if (!_hasSelectedImage) {
      _showSnackBar('Por favor, selecciona una imagen para la sede', isError: true);
      return;
    }
    setState(() {
      _isLoading = true;
    });
    
    // Ejecutar operaciones pesadas de forma asíncrona sin bloquear
    unawaited(_addSedeAsync());
  }

  Future<void> _addSedeAsync() async {
    try {
      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
      final sedeName = _sedeController.text.trim();

      String? imageUrl = await _uploadImage(sedeName);
      if (imageUrl == null) {
        if (!mounted) return;
        _showSnackBar('Error al subir la imagen. Intenta de nuevo.', isError: true);
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      await sedeProvider.crearSede(
        sedeName, 
        imageUrl: imageUrl,
        latitud: _latitudSeleccionada,
        longitud: _longitudSeleccionada,
      );

      if (!mounted) return;

      if (sedeProvider.errorMessage.isNotEmpty) {
        _showSnackBar(sedeProvider.errorMessage, isError: true);
      } else {
        _showSnackBar('Sede $sedeName añadida con éxito');
        _toggleFormVisibility();
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error al añadir sede: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _editSede(String sedeId) async {
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final sede = sedeProvider.sedes.firstWhere(
      (s) => s['id'] == sedeId,
      orElse: () => {'nombre': '', 'imagen': ''},
    );
    final currentName = sede['nombre'] as String;
    final currentImageUrl = sede['imagen'] as String?;
    final currentLatitud = sede['latitud'] as double?;
    final currentLongitud = sede['longitud'] as double?;

    _sedeController.text = currentName;
    _latitudSeleccionada = currentLatitud;
    _longitudSeleccionada = currentLongitud;

    File? tempImageFile;
    Uint8List? tempImageBytes;
    double? tempLatitud = currentLatitud;
    double? tempLongitud = currentLongitud;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool hasTempImage = (kIsWeb && tempImageBytes != null) || (!kIsWeb && tempImageFile != null);

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header mejorado
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _primaryColor.withOpacity(0.1),
                            _primaryColor.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.edit_location_alt, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Editar Sede',
                                  style: GoogleFonts.montserrat(
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                    fontSize: 20,
                                  ),
                                ),
                                Text(
                                  'Modifica la información de la sede',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12,
                                    color: _textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Información Básica',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _sedeController,
                              decoration: InputDecoration(
                                labelText: 'Nombre de la sede',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: _primaryColor, width: 2),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                prefixIcon: Icon(Icons.location_city, color: _primaryColor),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                              style: GoogleFonts.montserrat(fontSize: 16),
                              validator: (value) =>
                                  value!.isEmpty ? 'Ingrese un nombre' : null,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Imagen de la Sede',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () async {
                                final picker = ImagePicker();
                                final pickedFile = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  maxWidth: 1920,
                                  maxHeight: 1080,
                                  imageQuality: 85,
                                );

                                if (pickedFile != null) {
                                  try {
                                    Uint8List? compressedBytes;
                                    if (kIsWeb) {
                                      compressedBytes = await pickedFile.readAsBytes();
                                      if (compressedBytes.length > 5 * 1024 * 1024) {
                                        _showSnackBar('La imagen excede el tamaño máximo de 5MB', isError: true);
                                        return;
                                      }
                                      try {
                                        compressedBytes = await FlutterImageCompress.compressWithList(
                                          compressedBytes,
                                          minWidth: 1920,
                                          minHeight: 1080,
                                          quality: 70,
                                        );
                                      } catch (e) {
                                        debugPrint('Error al comprimir imagen en web: $e');
                                        compressedBytes = await pickedFile.readAsBytes();
                                      }
                                    } else {
                                      final file = File(pickedFile.path);
                                      final fileSize = await file.length();
                                      if (fileSize > 5 * 1024 * 1024) {
                                        _showSnackBar('La imagen excede el tamaño máximo de 5MB', isError: true);
                                        return;
                                      }
                                      compressedBytes = await FlutterImageCompress.compressWithFile(
                                        pickedFile.path,
                                        minWidth: 1920,
                                        minHeight: 1080,
                                        quality: 70,
                                      );
                                    }

                                    setDialogState(() {
                                      if (kIsWeb) {
                                        tempImageBytes = compressedBytes;
                                        tempImageFile = null;
                                      } else {
                                        tempImageFile = File(pickedFile.path);
                                        tempImageBytes = null;
                                      }
                                    });
                                  } catch (e) {
                                    _showSnackBar('Error al procesar la imagen: $e', isError: true);
                                  }
                                }
                              },
                              child: Container(
                                height: 140,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: hasTempImage || (currentImageUrl != null && currentImageUrl.isNotEmpty)
                                        ? _primaryColor.withOpacity(0.3)
                                        : Colors.red.withOpacity(0.5),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.grey.shade50,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: hasTempImage
                                      ? _buildImageWidget(
                                          imageFile: tempImageFile,
                                          imageBytes: tempImageBytes,
                                        )
                                      : currentImageUrl != null && currentImageUrl.isNotEmpty
                                          ? Image.network(
                                              currentImageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                debugPrint('Error mostrando imagen de sede: $error');
                                                return _buildPlaceholderImage();
                                              },
                                            )
                                          : _buildPlaceholderImage(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Ubicación',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            MapaSeleccionUbicacion(
                              latitudInicial: tempLatitud,
                              longitudInicial: tempLongitud,
                              onUbicacionSeleccionada: (latitud, longitud) {
                                setDialogState(() {
                                  tempLatitud = latitud;
                                  tempLongitud = longitud;
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    // Botones de acción
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            icon: const Icon(Icons.close, size: 18),
                            label: Text(
                              'Cancelar',
                              style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (_sedeController.text.isEmpty) {
                                if (!mounted) return;
                                _showSnackBar('Por favor, ingrese un nombre para la sede', isError: true);
                                return;
                              }
                              if (!hasTempImage && (currentImageUrl == null || currentImageUrl.isEmpty)) {
                                if (!mounted) return;
                                _showSnackBar('Por favor, selecciona una imagen para la sede', isError: true);
                                return;
                              }
                              Navigator.pop(context, {
                                'newSede': _sedeController.text.trim(),
                                'imageFile': tempImageFile,
                                'imageBytes': tempImageBytes,
                                'latitud': tempLatitud,
                                'longitud': tempLongitud,
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.save, size: 18),
                            label: Text(
                              'Guardar Cambios',
                              style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      // Cerrar el modal primero para evitar bloqueos
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      
      // Ejecutar operaciones pesadas de forma asíncrona sin bloquear
      unawaited(_editSedeAsync(
        sedeId: sedeId,
        currentName: currentName,
        currentImageUrl: currentImageUrl,
        currentLatitud: currentLatitud,
        currentLongitud: currentLongitud,
        result: result,
      ));
    }
  }

  Future<void> _editSedeAsync({
    required String sedeId,
    required String currentName,
    required String? currentImageUrl,
    required double? currentLatitud,
    required double? currentLongitud,
    required Map<String, dynamic> result,
  }) async {
    try {
      final newSede = result['newSede'] as String;
      final newImageFile = result['imageFile'] as File?;
      final newImageBytes = result['imageBytes'] as Uint8List?;
      final newLatitud = result['latitud'] as double?;
      final newLongitud = result['longitud'] as double?;

      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);

      // Ejecutar actualizaciones en paralelo cuando sea posible
      final futures = <Future>[];

      if (newSede != currentName) {
        futures.add(sedeProvider.renombrarSede(sedeId, newSede));
      }

      // Actualizar ubicación si cambió
      if ((newLatitud != currentLatitud) || (newLongitud != currentLongitud)) {
        futures.add(sedeProvider.actualizarUbicacionSede(sedeId, newLatitud, newLongitud));
      }

      // Esperar actualizaciones de nombre y ubicación
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }

      // Verificar errores
      if (sedeProvider.errorMessage.isNotEmpty) {
        if (!mounted) return;
        _showSnackBar(sedeProvider.errorMessage, isError: true);
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Manejar imagen por separado (requiere upload)
      String? newImageUrl = currentImageUrl;
      bool hasNewImage = (kIsWeb && newImageBytes != null) || (!kIsWeb && newImageFile != null);

      if (hasNewImage) {
        final oldImageFile = _selectedImageFile;
        final oldImageBytes = _selectedImageBytes;

        _selectedImageFile = newImageFile;
        _selectedImageBytes = newImageBytes;

        newImageUrl = await _uploadImage(newSede);

        _selectedImageFile = oldImageFile;
        _selectedImageBytes = oldImageBytes;

        if (newImageUrl != null && newImageUrl != currentImageUrl) {
          await sedeProvider.actualizarImagenSede(sedeId, newImageUrl);
          if (sedeProvider.errorMessage.isNotEmpty) {
            if (!mounted) return;
            _showSnackBar(sedeProvider.errorMessage, isError: true);
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            return;
          }
        }
      }

      // Refrescar sedes de forma asíncrona sin bloquear
      unawaited(sedeProvider.fetchSedes());

      if (mounted) {
        setState(() {
          _sedeController.clear();
          _isLoading = false;
        });
        _showSnackBar('Sede actualizada con éxito');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error al actualizar sede: $e', isError: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _deleteSede(String sedeId) async {
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final sede = sedeProvider.sedes.firstWhere(
      (s) => s['id'] == sedeId,
      orElse: () => {'nombre': 'Desconocida'},
    );
    final sedeName = sede['nombre'] as String;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[600], size: 24),
            SizedBox(width: 8),
            Text('Eliminar Sede', style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w600,
              color: _textPrimary,
              fontSize: 18,
            )),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
            minWidth: 280,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(10),
            ),
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¿Estás seguro de eliminar la sede "$sedeName"?',
                    style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w500)),
                SizedBox(height: 12),
                Text('Esta acción eliminará:',
                    style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: Colors.red[800])),
                _buildWarningItem('Todas las canchas de esta sede'),
                _buildWarningItem('Todas las reservas asociadas'),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Esta acción no se puede deshacer.',
                    style: GoogleFonts.montserrat(
                      color: Colors.red[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: _textSecondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text('Cancelar', style: GoogleFonts.montserrat(fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text('Eliminar', style: GoogleFonts.montserrat(fontSize: 14)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });
      try {
        final sedeProvider = Provider.of<SedeProvider>(context, listen: false);

        await sedeProvider.eliminarSede(sedeId);

        if (sedeProvider.errorMessage.isNotEmpty) {
          _showSnackBar(sedeProvider.errorMessage, isError: true);
        } else {
          try {
            final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
            canchaProvider.reset();
          } catch (e) {
            debugPrint('CanchaProvider no disponible: $e');
          }

          _showSnackBar('Sede "$sedeName" y todas sus canchas eliminadas con éxito');
        }
      } catch (e) {
        _showSnackBar('Error al eliminar sede: $e', isError: true);
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: Colors.red[600]),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.montserrat(fontSize: 14, color: _textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget({File? imageFile, Uint8List? imageBytes}) {
    if (kIsWeb && imageBytes != null) {
      return Image.memory(
        imageBytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error mostrando imagen en web: $error');
          return _buildPlaceholderImage();
        },
      );
    } else if (!kIsWeb && imageFile != null) {
      return Image.file(
        imageFile,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error mostrando imagen en móvil: $error');
          return _buildPlaceholderImage();
        },
      );
    }
    return _buildPlaceholderImage();
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[100],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate, size: 36, color: _primaryColor),
          SizedBox(height: 8),
          Text(
            'Seleccionar imagen (obligatorio)',
            style: GoogleFonts.montserrat(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (kIsWeb)
            Text(
              '(Compatible con web)',
              style: GoogleFonts.montserrat(color: Colors.grey[400], fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImageCard() {
    return Container(
      color: Colors.grey.shade200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            'Sin imagen',
            style: GoogleFonts.montserrat(
              color: Colors.grey.shade500,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContainer() {
    final screenWidth = MediaQuery.of(context).size.width;
    final imageHeight = screenWidth < 600 ? 100.0 : 120.0;

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: imageHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: _hasSelectedImage ? _primaryColor.withOpacity(0.3) : Colors.red.withOpacity(0.5),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _hasSelectedImage
                  ? _buildImageWidget(
                      imageFile: _selectedImageFile,
                      imageBytes: _selectedImageBytes,
                    )
                  : _buildPlaceholderImage(),
            ),
            if (_hasSelectedImage)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _clearSelectedImage,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red[600],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = screenWidth < 600 ? 16.0 : 24.0;
    final formWidth = screenWidth < 600 ? screenWidth * 0.9 : 500.0;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Container(
          width: formWidth,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.add_business, color: _primaryColor, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Nueva Sede',
                      style: GoogleFonts.montserrat(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _sedeController,
                  decoration: InputDecoration(
                    labelText: 'Nombre de la sede',
                    hintText: 'Ej: Sede Norte, Sede Centro...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _primaryColor, width: 2),
                    ),
                    prefixIcon: Icon(Icons.location_city, color: _primaryColor),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  style: GoogleFonts.montserrat(fontSize: 16),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Ingrese un nombre' : null,
                ),
                SizedBox(height: 16),
                _buildImageContainer(),
                SizedBox(height: 16),
                MapaSeleccionUbicacion(
                  latitudInicial: _latitudSeleccionada,
                  longitudInicial: _longitudSeleccionada,
                  onUbicacionSeleccionada: (latitud, longitud) {
                    setState(() {
                      _latitudSeleccionada = latitud;
                      _longitudSeleccionada = longitud;
                    });
                  },
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _addSede,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 12),
                          elevation: 4,
                        ),
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_circle_outline, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Añadir Sede',
                                    style: GoogleFonts.montserrat(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _toggleFormVisibility,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _textSecondary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get isSmallScreen {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth < 600;
  }

  @override
  Widget build(BuildContext context) {
    final sedeProvider = Provider.of<SedeProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          'Gestión de Sedes',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: isSmallScreen ? 18 : 20,
          ),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleFormVisibility,
        backgroundColor: _primaryColor,
        tooltip: _isFormVisible ? 'Ocultar formulario' : 'Agregar sede',
        elevation: 4,
        mini: isSmallScreen,
        child: Icon(_isFormVisible ? Icons.close : Icons.add, color: Colors.white, size: 24),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isFormVisible)
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(child: _buildForm()),
              ),
            Expanded(
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<int?>(
                      future: PlanFeatureService.getLugarMaxSedes(),
                      builder: (context, snapshot) {
                        final maxSedes = snapshot.data;
                        final current = sedeProvider.sedes.length;
                        String text;
                        if (maxSedes == null) {
                          text = 'Sedes registradas: $current (ilimitadas)';
                        } else {
                          text = 'Sedes registradas: $current / $maxSedes';
                        }
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(
                                left: 8, right: 8, top: 8, bottom: 4),
                            child: Chip(
                              backgroundColor: Colors.blue.shade50,
                              label: Text(
                                text,
                                style: GoogleFonts.montserrat(
                                  fontSize: 12,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: sedeProvider.sedes.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.business_outlined, size: isSmallScreen ? 60 : 80, color: Colors.grey[400]),
                            SizedBox(height: 12),
                            Text(
                              'No hay sedes registradas',
                              style: GoogleFonts.montserrat(
                                fontSize: isSmallScreen ? 16 : 18,
                                color: _textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Agrega tu primera sede para comenzar',
                              style: GoogleFonts.montserrat(
                                color: Colors.grey[500],
                                fontSize: isSmallScreen ? 12 : 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                          : GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isSmallScreen ? 1 : (screenWidth < 1200 ? 2 : 3),
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: isSmallScreen ? 1.2 : 1.1,
                        ),
                        padding: EdgeInsets.all(16),
                        itemCount: sedeProvider.sedes.length,
                        itemBuilder: (context, index) {
                          final sede = sedeProvider.sedes[index];
                          final imageUrl = sede['imagen'] as String?;
                          final tieneUbicacion = sede['latitud'] != null && sede['longitud'] != null;
                          
                          return Container(
                            decoration: BoxDecoration(
                              color: _cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Imagen de la sede
                                Expanded(
                                  flex: 3,
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    child: imageUrl != null && imageUrl.startsWith('http')
                                        ? Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return _buildPlaceholderImageCard();
                                                },
                                              ),
                                              // Overlay sutil
                                              Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.transparent,
                                                      Colors.black.withOpacity(0.3),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : _buildPlaceholderImageCard(),
                                  ),
                                ),
                                // Información de la sede
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    sede['nombre'] as String,
                                                    style: GoogleFonts.montserrat(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: isSmallScreen ? 14 : 16,
                                                      color: _textPrimary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  tieneUbicacion ? Icons.location_on : Icons.location_off,
                                                  size: 14,
                                                  color: tieneUbicacion ? Colors.green.shade600 : Colors.grey.shade400,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  tieneUbicacion ? 'Ubicación configurada' : 'Sin ubicación',
                                                  style: GoogleFonts.montserrat(
                                                    fontSize: 11,
                                                    color: tieneUbicacion ? Colors.green.shade600 : Colors.grey.shade500,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        // Botones de acción
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: IconButton(
                                                icon: Icon(
                                                  Icons.edit_rounded,
                                                  color: Colors.blue.shade700,
                                                  size: 20,
                                                ),
                                                onPressed: () => _editSede(sede['id'] as String),
                                                tooltip: 'Editar sede',
                                                padding: const EdgeInsets.all(8),
                                                constraints: const BoxConstraints(),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: IconButton(
                                                icon: Icon(
                                                  Icons.delete_rounded,
                                                  color: Colors.red.shade700,
                                                  size: 20,
                                                ),
                                                onPressed: () => _deleteSede(sede['id'] as String),
                                                tooltip: 'Eliminar sede',
                                                padding: const EdgeInsets.all(8),
                                                constraints: const BoxConstraints(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
}