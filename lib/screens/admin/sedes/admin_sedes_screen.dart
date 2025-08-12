import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:reserva_canchas/providers/cancha_provider.dart';
import '../../../providers/sede_provider.dart';

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

  void _addSede() async {
    if (_formKey.currentState!.validate()) {
      if (!_hasSelectedImage) {
        _showSnackBar('Por favor, selecciona una imagen para la sede', isError: true);
        return;
      }
      setState(() {
        _isLoading = true;
      });
      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
      final sedeName = _sedeController.text.trim();

      String? imageUrl = await _uploadImage(sedeName);
      if (imageUrl == null) {
        _showSnackBar('Error al subir la imagen. Intenta de nuevo.', isError: true);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      try {
        await sedeProvider.crearSede(sedeName, imageUrl: imageUrl);

        if (sedeProvider.errorMessage.isNotEmpty) {
          _showSnackBar(sedeProvider.errorMessage, isError: true);
        } else {
          _showSnackBar('Sede $sedeName añadida con éxito');
          _toggleFormVisibility();
        }
      } catch (e) {
        _showSnackBar('Error al añadir sede: $e', isError: true);
      } finally {
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

    _sedeController.text = currentName;

    File? tempImageFile;
    Uint8List? tempImageBytes;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool hasTempImage = (kIsWeb && tempImageBytes != null) || (!kIsWeb && tempImageFile != null);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.edit_location_alt, color: _primaryColor, size: 24),
                  SizedBox(width: 8),
                  Text('Editar Sede', style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                    fontSize: 18,
                  )),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                    minWidth: 280,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _sedeController,
                        decoration: InputDecoration(
                          labelText: 'Nombre de la sede',
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
                            value!.isEmpty ? 'Ingrese un nombre' : null,
                      ),
                      SizedBox(height: 16),
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

        setDialogState(() {
          if (kIsWeb) {
            tempImageBytes = compressedBytes;
            tempImageFile = null;
          } else {
            tempImageFile = File(pickedFile.path); // Guardar el archivo original para _uploadImage
            tempImageBytes = null;
          }
        });
      } catch (e) {
        _showSnackBar('Error al procesar la imagen: $e', isError: true);
      }
    }
  },
  child: Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: hasTempImage || (currentImageUrl != null && currentImageUrl.isNotEmpty)
                                  ? _primaryColor.withOpacity(0.3)
                                  : Colors.red.withOpacity(0.5),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[50],
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
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: _textSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text('Cancelar', style: GoogleFonts.montserrat(fontSize: 14)),
                ),
                ElevatedButton(
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
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text('Guardar', style: GoogleFonts.montserrat(fontSize: 14)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _isLoading = true;
      });
      final newSede = result['newSede'] as String;
      final newImageFile = result['imageFile'] as File?;
      final newImageBytes = result['imageBytes'] as Uint8List?;

      try {
        final sedeProvider = Provider.of<SedeProvider>(context, listen: false);

        if (newSede != currentName) {
          await sedeProvider.renombrarSede(sedeId, newSede);
          if (sedeProvider.errorMessage.isNotEmpty) {
            if (!mounted) return;
            _showSnackBar(sedeProvider.errorMessage, isError: true);
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }

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
              setState(() {
                _isLoading = false;
              });
              return;
            }
          }
        }

        await sedeProvider.fetchSedes();

        setState(() {
          _sedeController.clear();
        });

        if (!mounted) return;
        _showSnackBar('Sede actualizada con éxito');
      } catch (e) {
        if (!mounted) return;
        _showSnackBar('Error al actualizar sede: $e', isError: true);
      } finally {
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
        child: Icon(_isFormVisible ? Icons.close : Icons.add, color: Colors.white, size: 24),
        tooltip: _isFormVisible ? 'Ocultar formulario' : 'Agregar sede',
        elevation: 4,
        mini: isSmallScreen,
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
                    : ListView.builder(
                        itemCount: sedeProvider.sedes.length,
                        padding: EdgeInsets.only(top: 8, bottom: isSmallScreen ? 80 : 16),
                        itemBuilder: (context, index) {
                          final sede = sedeProvider.sedes[index];
                          final imageUrl = sede['imagen'] as String?;
                          return Container(
                            margin: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            decoration: BoxDecoration(
                              color: _cardColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.08),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 12 : 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: isSmallScreen ? 48 : 56,
                                height: isSmallScreen ? 48 : 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Color.fromRGBO(33, 150, 243, 0.2)),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: imageUrl != null && imageUrl.startsWith('http')
                                      ? Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            debugPrint('Error cargando imagen de sede: $error');
                                            return Container(
                                              color: Colors.grey[100],
                                              child: Icon(
                                                Icons.business,
                                                color: _primaryColor,
                                                size: isSmallScreen ? 24 : 28,
                                              ),
                                            );
                                          },
                                        )
                                      : Container(
                                          color: Colors.grey[100],
                                          child: Icon(
                                            Icons.business,
                                            color: _primaryColor,
                                            size: isSmallScreen ? 24 : 28,
                                          ),
                                        ),
                                ),
                              ),
                              title: Text(
                                sede['nombre'] as String,
                                style: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isSmallScreen ? 14 : 16,
                                  color: _textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Toca para gestionar canchas',
                                style: GoogleFonts.montserrat(
                                  color: _textSecondary,
                                  fontSize: isSmallScreen ? 12 : 13,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        color: Colors.blue[600],
                                        size: isSmallScreen ? 20 : 24,
                                      ),
                                      onPressed: () => _editSede(sede['id'] as String),
                                      tooltip: 'Editar sede',
                                      padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Colors.red[600],
                                        size: isSmallScreen ? 20 : 24,
                                      ),
                                      onPressed: () => _deleteSede(sede['id'] as String),
                                      tooltip: 'Eliminar sede',
                                      padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}