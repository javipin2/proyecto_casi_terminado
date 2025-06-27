import 'dart:io' show File;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/providers/sede_provider.dart';

class RegistrarCanchaScreen extends StatefulWidget {
  const RegistrarCanchaScreen({super.key});

  @override
  State<RegistrarCanchaScreen> createState() => _RegistrarCanchaScreenState();
}

class _RegistrarCanchaScreenState extends State<RegistrarCanchaScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _descripcionController = TextEditingController();
  final TextEditingController _ubicacionController = TextEditingController();
  final TextEditingController _precioController = TextEditingController();

  XFile? _imagenSeleccionada;
  Uint8List? _imagenBytes;
  final ImagePicker _picker = ImagePicker();
  bool _cargandoImagen = false;
  bool _techada = false;
  String _sede = "";
  bool _isLoading = false;

  Future<void> _seleccionarImagen() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galería'),
                onTap: () {
                  _getImage(ImageSource.gallery);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Cámara'),
                onTap: () {
                  _getImage(ImageSource.camera);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _imagenSeleccionada = image;
          _cargandoImagen = kIsWeb;
          if (!kIsWeb) {
            _imagenBytes = null;
          }
        });

        if (kIsWeb) {
          try {
            final bytes = await image.readAsBytes();
            setState(() {
              _imagenBytes = bytes;
              _cargandoImagen = false;
            });
          } catch (e) {
            setState(() {
              _cargandoImagen = false;
              _imagenSeleccionada = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al cargar imagen: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        _cargandoImagen = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al seleccionar imagen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildImageSelector() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: _seleccionarImagen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: (_imagenSeleccionada != null && !_cargandoImagen)
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildImageWidget(),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color.fromRGBO(0, 0, 0, 0.54),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _imagenSeleccionada = null;
                              _imagenBytes = null;
                              _cargandoImagen = false;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                )
              : _cargandoImagen
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            "Cargando imagen...",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate,
                          size: 48,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Seleccionar Imagen",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Toca para elegir desde galería o cámara",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildImageWidget() {
    if (kIsWeb && _imagenBytes != null) {
      return Image.memory(
        _imagenBytes!,
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
      );
    } else if (!kIsWeb && _imagenSeleccionada != null) {
      return Image.file(
        File(_imagenSeleccionada!.path),
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
      );
    } else {
      return const Center(child: CircularProgressIndicator());
    }
  }

  Future<void> _registrarCancha() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        String imagenUrl = "";

        if (_imagenSeleccionada != null) {
          String fileName = 'canchas/${DateTime.now().toIso8601String()}.jpg';
          Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

          if (kIsWeb && _imagenBytes != null) {
            await storageRef.putData(_imagenBytes!);
          } else {
            await storageRef.putFile(File(_imagenSeleccionada!.path));
          }

          imagenUrl = await storageRef.getDownloadURL();
        } else {
          imagenUrl = 'assets/cancha_demo.png';
        }

        await FirebaseFirestore.instance.collection('canchas').add({
          'nombre': _nombreController.text.trim(),
          'descripcion': _descripcionController.text.trim(),
          'imagen': imagenUrl,
          'ubicacion': _ubicacionController.text.trim(),
          'precio': double.tryParse(_precioController.text.trim()) ?? 0,
          'techada': _techada,
          'sedeId': _sede,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text("Cancha registrada correctamente"),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          Navigator.pop(context);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text("Error al registrar cancha: $error")),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _ubicacionController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.green.shade600),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.green.shade600, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red),
          ),
          labelStyle: TextStyle(color: Colors.grey.shade700),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.green.shade600, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownSede() {
    final sedeProvider = Provider.of<SedeProvider>(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: "Sede",
          prefixIcon: Icon(Icons.business, color: Colors.green.shade600),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.green.shade600, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        value: _sede.isNotEmpty ? _sede : null,
        items: sedeProvider.sedes.map((sede) => DropdownMenuItem(
              value: sede['id'] as String,
              child: Text(sede['nombre'] as String),
            )).toList(),
        validator: (value) => value == null || value.isEmpty ? "Seleccione la sede" : null,
        onChanged: (value) {
          setState(() {
            _sede = value ?? "";
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "Registrar Nueva Cancha",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: const Center(
                child: Text(
                  "Complete la información de la cancha",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle("Información Básica", Icons.info_outline),
                    _buildTextField(
                      controller: _nombreController,
                      label: "Nombre de la Cancha",
                      icon: Icons.sports_soccer,
                      hint: "Ej: Cancha Principal",
                      validator: (value) => value == null || value.isEmpty
                          ? "Ingrese el nombre"
                          : null,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _descripcionController,
                      label: "Descripción",
                      icon: Icons.description,
                      maxLines: 3,
                      hint: "Describe las características de la cancha",
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Imagen de la Cancha",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildImageSelector(),
                    const SizedBox(height: 30),
                    _buildSectionTitle("Características", Icons.settings),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CheckboxListTile(
                        title: const Text(
                          "Cancha Techada",
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: const Text("¿La cancha cuenta con techo?"),
                        value: _techada,
                        activeColor: Colors.green.shade600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _techada = value ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                    _buildSectionTitle("Ubicación y Precio", Icons.location_on),
                    _buildTextField(
                      controller: _ubicacionController,
                      label: "Ubicación",
                      icon: Icons.place,
                      hint: "Dirección de la cancha",
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _precioController,
                      label: "Precio por Hora",
                      icon: Icons.attach_money,
                      keyboardType: TextInputType.number,
                      hint: "Ej: 50000",
                    ),
                    const SizedBox(height: 20),
                    _buildDropdownSede(),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: _isLoading
                          ? Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                ),
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _registrarCancha,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                elevation: 3,
                                shadowColor: Colors.green.shade200,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_circle_outline, size: 24),
                                  SizedBox(width: 8),
                                  Text(
                                    "Registrar Cancha",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
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