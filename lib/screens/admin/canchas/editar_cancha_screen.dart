import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/providers/sede_provider.dart';
import '../../../models/cancha.dart';

class EditarCanchaScreen extends StatefulWidget {
  final String canchaId;
  final Cancha cancha;

  const EditarCanchaScreen({
    super.key,
    required this.canchaId,
    required this.cancha,
  });

  @override
  State<EditarCanchaScreen> createState() => _EditarCanchaScreenState();
}

class _EditarCanchaScreenState extends State<EditarCanchaScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Controllers
  late TextEditingController _nombreController;
  late TextEditingController _descripcionController;
  late TextEditingController _ubicacionController;
  late TextEditingController _precioController;
  late TextEditingController _motivoNoDisponibleController;
  Map<String, Map<String, TextEditingController>> _precioControllers = {};

  // State variables
  bool _techada = false;
  String _sede = "";
  String? _selectedDay;
  String _imagenUrl = "";
  bool _disponible = true;
  XFile? _imagenSeleccionada;
  Uint8List? _imagenBytes;
  late Map<String, Map<String, double>> _preciosPorHorario;
  bool _isLoading = false;
  bool _isUploadingImage = false;

  final ImagePicker _picker = ImagePicker();
  final List<String> _daysOfWeek = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo'
  ];
  final List<String> _horarios =
      List.generate(19, (index) => '${5 + index}:00').where((h) => int.parse(h.split(':')[0]) <= 23).toList();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();

    _initializeControllers();
    _initializePreciosPorHorario();
  }

  void _initializeControllers() {
    _nombreController = TextEditingController(text: widget.cancha.nombre);
    _descripcionController = TextEditingController(text: widget.cancha.descripcion);
    _ubicacionController = TextEditingController(text: widget.cancha.ubicacion);
    _precioController = TextEditingController(text: widget.cancha.precio.toString());
    _motivoNoDisponibleController = TextEditingController(text: widget.cancha.motivoNoDisponible ?? '');
    _techada = widget.cancha.techada;
    _sede = widget.cancha.sedeId;
    _imagenUrl = widget.cancha.imagen;
    _disponible = widget.cancha.disponible;

    // Inicializar controladores para precios por horario
    for (var day in _daysOfWeek) {
      _precioControllers[day] = {};
      for (var hora in _horarios) {
        _precioControllers[day]![hora] = TextEditingController(
          text: widget.cancha.preciosPorHorario[day]?[hora]?.toString() ?? widget.cancha.precio.toString(),
        );
      }
    }
  }

  void _initializePreciosPorHorario() {
    _preciosPorHorario = Map.from(widget.cancha.preciosPorHorario);
    for (var day in _daysOfWeek) {
      if (!_preciosPorHorario.containsKey(day)) {
        _preciosPorHorario[day] = {};
        for (var hora in _horarios) {
          _preciosPorHorario[day]![hora] = widget.cancha.precio;
        }
      }
    }
  }

  void _updatePrecioControllers(String day) {
    for (var hora in _horarios) {
      _precioControllers[day]![hora]?.text =
          _preciosPorHorario[day]![hora]?.toString() ?? widget.cancha.precio.toString();
    }
  }

  Future<void> _seleccionarImagen() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Seleccionar Imagen',
                  style: GoogleFonts.montserrat(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildImageSourceButton(
                        icon: Icons.photo_library,
                        label: 'Galería',
                        onTap: () {
                          _getImage(ImageSource.gallery);
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildImageSourceButton(
                        icon: Icons.photo_camera,
                        label: 'Cámara',
                        onTap: () {
                          _getImage(ImageSource.camera);
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSourceButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Color.fromRGBO(79, 70, 229, 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color.fromRGBO(79, 70, 229, 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF4F46E5), size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.montserrat(
                color: const Color(0xFF4F46E5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
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

      if (image != null && mounted) {
        setState(() {
          _imagenSeleccionada = image;
        });

        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          if (mounted) {
            setState(() {
              _imagenBytes = bytes;
            });
          }
        }
      }
    } catch (e) {
      _mostrarError("Error al seleccionar imagen: $e");
    }
  }

  Future<String?> _subirImagen() async {
    if (_imagenSeleccionada == null) return null;

    setState(() {
      _isUploadingImage = true;
    });

    try {
      String fileName = 'canchas/${widget.canchaId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      if (kIsWeb && _imagenBytes != null) {
        await storageRef.putData(_imagenBytes!);
      } else {
        await storageRef.putFile(File(_imagenSeleccionada!.path));
      }

      final downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      _mostrarError("Error al subir imagen: $e");
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Widget _buildImageSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(79, 70, 229, 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.image,
                      color: Color(0xFF4F46E5),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "Imagen de la Cancha",
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
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
                  child: _imagenSeleccionada != null
                      ? Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _buildImageWidget(),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: DecoratedBox(
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
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : _buildImagePlaceholder(),
                ),
              ),
            ),
            if (_isUploadingImage) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(79, 70, 229, 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Subiendo imagen...",
                          style: GoogleFonts.montserrat(
                            color: const Color(0xFF4F46E5),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget() {
    if (kIsWeb) {
      if (_imagenBytes != null) {
        return Image.memory(
          _imagenBytes!,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
        );
      } else if (_imagenSeleccionada != null) {
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
          ),
        );
      }
    } else if (_imagenSeleccionada != null) {
      return Image.file(
        File(_imagenSeleccionada!.path),
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
      );
    }

    if (_imagenUrl.isNotEmpty) {
      return Image.network(
        _imagenUrl,
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(),
      );
    }

    return _buildImagePlaceholder();
  }

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate,
          size: 48,
          color: Color.fromRGBO(79, 70, 229, 0.7),
        ),
        const SizedBox(height: 12),
        Text(
          "Seleccionar Imagen",
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Toca para elegir desde galería o cámara",
          style: GoogleFonts.montserrat(
            fontSize: 14,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_imagenSeleccionada != null) {
        String? nuevaImagenUrl = await _subirImagen();
        if (nuevaImagenUrl != null) {
          _imagenUrl = nuevaImagenUrl;
        }
      }

      // Actualizar precios desde los controladores
      for (var day in _daysOfWeek) {
        for (var hora in _horarios) {
          final value = _precioControllers[day]![hora]!.text;
          _preciosPorHorario[day]![hora] = double.tryParse(value) ?? 0.0;
        }
      }

      await FirebaseFirestore.instance.collection('canchas').doc(widget.canchaId).update({
        'nombre': _nombreController.text.trim(),
        'descripcion': _descripcionController.text.trim(),
        'imagen': _imagenUrl,
        'ubicacion': _ubicacionController.text.trim(),
        'precio': double.tryParse(_precioController.text.trim()) ?? 0,
        'techada': _techada,
        'sedeId': _sede,
        'preciosPorHorario': _preciosPorHorario,
        'disionalble': _disponible,
        'motivoNoDisponible': _disponible ? null : _motivoNoDisponibleController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text("Cancha actualizada correctamente"),
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
      _mostrarError("Error al actualizar cancha: $error");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _mostrarError(String mensaje) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(mensaje)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    _nombreController.dispose();
    _descripcionController.dispose();
    _ubicacionController.dispose();
    _precioController.dispose();
    _motivoNoDisponibleController.dispose();
    for (var day in _daysOfWeek) {
      for (var hora in _horarios) {
        _precioControllers[day]![hora]!.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildImageSection(),
                const SizedBox(height: 24),
                _buildBasicInfoSection(),
                const SizedBox(height: 24),
                _buildDetailsSection(),
                const SizedBox(height: 24),
                _buildAvailabilitySection(),
                const SizedBox(height: 24),
                _buildPricingSection(),
                const SizedBox(height: 32),
                _buildActionButtons(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      title: Text(
        "Editar Cancha",
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: Colors.black87,
        ),
      ),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Información Básica",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            _buildStyledTextField(
              controller: _nombreController,
              label: "Nombre de la Cancha",
              icon: Icons.sports_soccer,
              validator: (value) => value == null || value.isEmpty ? "Ingrese el nombre" : null,
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _descripcionController,
              label: "Descripción",
              icon: Icons.description,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _ubicacionController,
              label: "Ubicación",
              icon: Icons.location_on,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Detalles de la Cancha",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: SwitchListTile(
                title: Text(
                  "¿Es techada?",
                  style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  _techada ? "Cancha techada" : "Cancha al aire libre",
                  style: GoogleFonts.montserrat(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                value: _techada,
                onChanged: (value) => setState(() => _techada = value),
                activeColor: const Color(0xFF4F46E5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _precioController,
              label: "Precio por defecto",
              icon: Icons.attach_money,
              keyboardType: TextInputType.number,
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                return parsed == null || parsed < 0 ? "Ingrese un precio válido" : null;
              },
            ),
            const SizedBox(height: 16),
            _buildSedeDropdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilitySection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Disponibilidad",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: SwitchListTile(
                title: Text(
                  "¿Cancha disponible?",
                  style: GoogleFonts.montserrat(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  _disponible ? "Cancha disponible" : "Cancha no disponible",
                  style: GoogleFonts.montserrat(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                value: _disponible,
                onChanged: (value) => setState(() {
                  _disponible = value;
                  if (value) {
                    _motivoNoDisponibleController.clear();
                  }
                }),
                activeColor: const Color(0xFF4F46E5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (!_disponible) ...[
              const SizedBox(height: 16),
              _buildStyledTextField(
                controller: _motivoNoDisponibleController,
                label: "Motivo de no disponibilidad",
                icon: Icons.warning,
                maxLines: 2,
                validator: (value) => value == null || value.isEmpty ? "Ingrese el motivo de no disponibilidad" : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.montserrat(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF4F46E5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildSedeDropdown() {
    final sedeProvider = Provider.of<SedeProvider>(context);

    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: "Sede",
        prefixIcon: const Icon(Icons.business, color: Color(0xFF4F46E5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      value: _sede.isNotEmpty ? _sede : null,
      hint: Text(
        "Selecciona una sede",
        style: GoogleFonts.montserrat(color: Colors.grey[600]),
      ),
      items: sedeProvider.sedes.map((sede) {
        return DropdownMenuItem<String>(
          value: sede['id'] as String,
          child: Text(sede['nombre'] as String, style: GoogleFonts.montserrat()),
        );
      }).toList(),
      validator: (value) => value == null || value.isEmpty ? "Seleccione la sede" : null,
      onChanged: (value) => setState(() => _sede = value ?? ""),
      style: GoogleFonts.montserrat(color: Colors.black87),
      dropdownColor: Colors.white,
      iconEnabledColor: const Color(0xFF4F46E5),
    );
  }

  Widget _buildPricingSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Configuración de Precios",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: "Día para editar precios",
                prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF4F46E5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              value: _selectedDay,
              hint: Text(
                "Selecciona un día",
                style: GoogleFonts.montserrat(color: Colors.grey[600]),
              ),
              items: _daysOfWeek.map((day) {
                return DropdownMenuItem<String>(
                  value: day,
                  child: Text(day[0].toUpperCase() + day.substring(1), style: GoogleFonts.montserrat()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDay = value;
                  if (value != null) {
                    _updatePrecioControllers(value);
                  }
                });
              },
              style: GoogleFonts.montserrat(color: Colors.black87),
              dropdownColor: Colors.white,
              iconEnabledColor: const Color(0xFF4F46E5),
            ),
            if (_selectedDay != null) ...[
              const SizedBox(height: 20),
              _buildPricingCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPricingCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[50]!, Colors.indigo[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  "Precios para ${_selectedDay!}",
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._horarios.map((hora) => _buildHorarioPrecio(hora)),
          ],
        ),
      ),
    );
  }

  Widget _buildHorarioPrecio(String hora) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Text(
                  hora,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _precioControllers[_selectedDay]![hora],
              decoration: InputDecoration(
                prefixText: "\$ ",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              style: GoogleFonts.montserrat(fontSize: 14),
              onChanged: (value) {
                _preciosPorHorario[_selectedDay]![hora] = double.tryParse(value) ?? 0.0;
              },
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                return parsed == null || parsed < 0 ? "Precio inválido" : null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _guardarCambios,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text("Guardando..."),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.save),
                      const SizedBox(width: 8),
                      Text(
                        "Guardar Cambios",
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF6B7280)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              "Cancelar",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ],
    );
  }
}