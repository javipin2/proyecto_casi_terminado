import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/providers/cancha_provider.dart';
import '../../../providers/sede_provider.dart';

class AdminSedesScreen extends StatefulWidget {
  const AdminSedesScreen({super.key});

  @override
  State<AdminSedesScreen> createState() => _AdminSedesScreenState();
}

class _AdminSedesScreenState extends State<AdminSedesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sedeController = TextEditingController();
  
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  bool _isLoading = false;

  // Tema de colores
  static const _primaryColor = Color(0xFF2196F3);
  static const _secondaryColor = Color(0xFF1976D2);
  static const _backgroundColor = Color(0xFFF8F9FA);
  static const _cardColor = Colors.white;
  static const _textPrimary = Color(0xFF212121);
  static const _textSecondary = Color(0xFF757575);

  @override
  void dispose() {
    _sedeController.dispose();
    super.dispose();
  }

  Future<String?> _uploadImage(String sede) async {
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('sedes/${sede}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      
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
      maxWidth: 800,
      maxHeight: 600,
      imageQuality: 80,
    );
    
    if (pickedFile != null) {
      setState(() {
        if (kIsWeb) {
          pickedFile.readAsBytes().then((bytes) {
            setState(() {
              _selectedImageBytes = bytes;
              _selectedImageFile = null;
            });
          });
        } else {
          final file = File(pickedFile.path);
          setState(() {
            _selectedImageFile = file;
            _selectedImageBytes = null;
          });
        }
      });
    }
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageBytes = null;
    });
  }

  bool get _hasSelectedImage => 
      (kIsWeb && _selectedImageBytes != null) || 
      (!kIsWeb && _selectedImageFile != null);

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _addSede() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
      final sedeName = _sedeController.text.trim();

      String? imageUrl;
      if (_hasSelectedImage) {
        imageUrl = await _uploadImage(sedeName);
      }

      try {
        await sedeProvider.crearSede(sedeName, imageUrl: imageUrl);
        
        if (sedeProvider.errorMessage.isNotEmpty) {
          _showSnackBar(sedeProvider.errorMessage, isError: true);
        } else {
          _sedeController.clear();
          _clearSelectedImage();
          _showSnackBar('Sede $sedeName añadida con éxito');
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

  void _editSede(String oldSede) async {
    _sedeController.text = oldSede;
    String? currentImageUrl = Provider.of<SedeProvider>(context, listen: false)
        .sedeImages[oldSede];
    
    File? tempImageFile;
    Uint8List? tempImageBytes;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool hasTempImage = (kIsWeb && tempImageBytes != null) || 
                               (!kIsWeb && tempImageFile != null);
            
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.edit_location_alt, color: _primaryColor),
                  SizedBox(width: 8),
                  Text('Editar Sede', style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  )),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                        prefixIcon: Icon(Icons.location_city, color: _primaryColor),
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Ingrese un nombre' : null,
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final pickedFile = await picker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 800,
                          maxHeight: 600,
                          imageQuality: 80,
                        );
                        
                        if (pickedFile != null) {
                          setDialogState(() {
                            if (kIsWeb) {
                              pickedFile.readAsBytes().then((bytes) {
                                setDialogState(() {
                                  tempImageBytes = bytes;
                                  tempImageFile = null;
                                });
                              });
                            } else {
                              final file = File(pickedFile.path);
                              setDialogState(() {
                                tempImageFile = file;
                                tempImageBytes = null;
                              });
                            }
                          });
                        }
                      },
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!, width: 2),
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.grey[50],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: _textSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_sedeController.text.isNotEmpty) {
                      Navigator.pop(context, {
                        'newSede': _sedeController.text.trim(),
                        'imageFile': tempImageFile,
                        'imageBytes': tempImageBytes,
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Guardar'),
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
        String? newImageUrl = currentImageUrl;
        
        bool hasNewImage = (kIsWeb && newImageBytes != null) || 
                          (!kIsWeb && newImageFile != null);
        
        if (hasNewImage) {
          final oldImageFile = _selectedImageFile;
          final oldImageBytes = _selectedImageBytes;
          
          _selectedImageFile = newImageFile;
          _selectedImageBytes = newImageBytes;
          
          newImageUrl = await _uploadImage(newSede);
          
          _selectedImageFile = oldImageFile;
          _selectedImageBytes = oldImageBytes;
        }

        await sedeProvider.renombrarSede(oldSede, newSede);
        
        if (newImageUrl != null && newImageUrl != currentImageUrl) {
          await sedeProvider.actualizarImagenSede(newSede, newImageUrl);
        }

        await sedeProvider.fetchSedes();
        
        setState(() {
          _sedeController.clear();
        });
        
        _showSnackBar('Sede actualizada con éxito');
      } catch (e) {
        _showSnackBar('Error al actualizar sede: $e', isError: true);
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _deleteSede(String sede) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[600], size: 28),
            SizedBox(width: 8),
            Text('Eliminar Sede', style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            )),
          ],
        ),
        content: Container(
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Estás seguro de eliminar la sede "$sede"?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 12),
              Text('Esta acción eliminará:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
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
                  style: TextStyle(
                    color: Colors.red[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: _textSecondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Eliminar'),
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
        
        await sedeProvider.eliminarSede(sede);
        
        if (sedeProvider.errorMessage.isNotEmpty) {
          _showSnackBar(sedeProvider.errorMessage, isError: true);
        } else {
          try {
            final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
            canchaProvider.reset();
          } catch (e) {
            debugPrint('CanchaProvider no disponible: $e');
          }
          
          _showSnackBar('Sede "$sede" y todas sus canchas eliminadas con éxito');
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
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: Colors.red[600]),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14))),
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
          Icon(Icons.add_photo_alternate, size: 40, color: _primaryColor),
          SizedBox(height: 8),
          Text('Seleccionar imagen', 
            style: TextStyle(color: _textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
          if (kIsWeb)
            Text('(Compatible con web)', 
              style: TextStyle(color: Colors.grey[400], fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildImageContainer() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: _primaryColor.withOpacity(0.3), width: 2),
          borderRadius: BorderRadius.circular(16),
          color: _hasSelectedImage ? null : Colors.grey[50],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: _hasSelectedImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _buildImageWidget(
                      imageFile: _selectedImageFile,
                      imageBytes: _selectedImageBytes,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _clearSelectedImage,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red[600],
                          borderRadius: BorderRadius.circular(20),
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
              )
            : _buildPlaceholderImage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sedeProvider = Provider.of<SedeProvider>(context);

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text('Gestión de Sedes', style: GoogleFonts.montserrat(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        )),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Header con degradado
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_primaryColor, _secondaryColor],
              ),
            ),
            child: Container(
              margin: EdgeInsets.all(16),
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.add_business, color: _primaryColor, size: 28),
                        SizedBox(width: 12),
                        Text('Nueva Sede', style: GoogleFonts.montserrat(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        )),
                      ],
                    ),
                    SizedBox(height: 20),
                    TextFormField(
                      controller: _sedeController,
                      decoration: InputDecoration(
                        labelText: 'Nombre de la sede',
                        hintText: 'Ej: Sede Norte, Sede Centro...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _primaryColor, width: 2),
                        ),
                        prefixIcon: Icon(Icons.location_city, color: _primaryColor),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'Ingrese un nombre' : null,
                    ),
                    SizedBox(height: 20),
                    _buildImageContainer(),
                    SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _addSede,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                                  Icon(Icons.add_circle_outline),
                                  SizedBox(width: 8),
                                  Text('Añadir Sede', style: GoogleFonts.montserrat(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  )),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Lista de sedes
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 16),
              child: sedeProvider.sedes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.business_outlined, size: 80, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text('No hay sedes registradas',
                            style: GoogleFonts.montserrat(
                              fontSize: 18,
                              color: _textSecondary,
                              fontWeight: FontWeight.w500,
                            )),
                          SizedBox(height: 8),
                          Text('Agrega tu primera sede para comenzar',
                            style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(top: 8, bottom: 16),
                      itemCount: sedeProvider.sedes.length,
                      itemBuilder: (context, index) {
                        final sede = sedeProvider.sedes[index];
                        final imageUrl = sedeProvider.sedeImages[sede];
                        
                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _cardColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 15,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.all(16),
                            leading: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _primaryColor.withOpacity(0.2)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: imageUrl != null && imageUrl.startsWith('http')
                                    ? Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          debugPrint('Error cargando imagen de sede: $error');
                                          return Container(
                                            color: Colors.grey[100],
                                            child: Icon(Icons.business, 
                                              color: _primaryColor, size: 28),
                                          );
                                        },
                                      )
                                    : Container(
                                        color: Colors.grey[100],
                                        child: Icon(Icons.business, 
                                          color: _primaryColor, size: 28),
                                      ),
                              ),
                            ),
                            title: Text(sede, style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: _textPrimary,
                            )),
                            subtitle: Text('Toca para gestionar canchas',
                              style: TextStyle(color: _textSecondary, fontSize: 13)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.edit_outlined, color: Colors.blue[600]),
                                    onPressed: () => _editSede(sede),
                                    tooltip: 'Editar sede',
                                  ),
                                ),
                                SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.delete_outline, color: Colors.red[600]),
                                    onPressed: () => _deleteSede(sede),
                                    tooltip: 'Eliminar sede',
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
    );
  }
}