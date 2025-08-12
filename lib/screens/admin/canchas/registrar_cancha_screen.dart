import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/providers/cancha_provider.dart';
import 'package:reserva_canchas/providers/sede_provider.dart';
import '../../../models/horario.dart';

class RegistrarCanchaScreen extends StatefulWidget {
  const RegistrarCanchaScreen({super.key});

  @override
  State<RegistrarCanchaScreen> createState() => _RegistrarCanchaScreenState();
}

class _RegistrarCanchaScreenState extends State<RegistrarCanchaScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Controllers
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _precioController = TextEditingController();
  final _motivoNoDisponibleController = TextEditingController();
  final Map<String, Map<String, TextEditingController>> _precioControllers = {};
  final Map<String, Map<String, bool>> _habilitadaHorario = {};
  final Map<String, Map<String, bool>> _completoHorario = {};

  // State variables
  bool _techada = false;
  String _sede = "";
  String? _selectedDay;
  XFile? _imagenSeleccionada;
  Uint8List? _imagenBytes;
  bool _disponible = true;
  bool _isLoading = false;
  bool _isUploadingImage = false;
  final Map<String, Map<String, Map<String, dynamic>>> _preciosPorHorario = {};

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
  final List<String> _horarios = List.generate(24, (index) {
    final timeOfDay = TimeOfDay(hour: (index + 1) % 24, minute: 0);
    return Horario(hora: timeOfDay).horaFormateada;
  }).toList();

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

    _initializePreciosPorHorario();

    // Añadir listener a _precioController para actualizar precios por horario
    _precioController.addListener(_updatePreciosPorHorarioFromDefault);
  }

  void _initializePreciosPorHorario() {
    for (var day in _daysOfWeek) {
      _precioControllers[day] = {};
      _habilitadaHorario[day] = {};
      _completoHorario[day] = {};
      _preciosPorHorario[day] = {};
      for (var hora in _horarios) {
        final horaNormalizada = Horario.normalizarHora(hora);
        // Inicializar con el precio por defecto si está disponible, sino 0.0
        final defaultPrice = double.tryParse(_precioController.text.trim()) ?? 0.0;
        _precioControllers[day]![horaNormalizada] = TextEditingController(text: defaultPrice.toString());
        _habilitadaHorario[day]![horaNormalizada] = true;
        _completoHorario[day]![horaNormalizada] = false;
        _preciosPorHorario[day]![horaNormalizada] = {
          'precio': defaultPrice,
          'habilitada': true,
          'completo': false,
        };
      }
    }
  }

  void _updatePrecioControllers(String day) {
    for (var hora in _horarios) {
      final horaNormalizada = Horario.normalizarHora(hora);
      // Usar el precio almacenado en _preciosPorHorario o el precio por defecto
      final precio = _preciosPorHorario[day]![horaNormalizada]?['precio']?.toString() ??
          (double.tryParse(_precioController.text.trim()) ?? 0.0).toString();
      final habilitada = _preciosPorHorario[day]![horaNormalizada]?['habilitada'] ?? true;
      final completo = _preciosPorHorario[day]![horaNormalizada]?['completo'] ?? false;
      _precioControllers[day]![horaNormalizada]?.text = precio;
      _habilitadaHorario[day]![horaNormalizada] = habilitada;
      _completoHorario[day]![horaNormalizada] = completo;
    }
  }

  // Nuevo método para actualizar precios por horario cuando cambia el precio por defecto
  void _updatePreciosPorHorarioFromDefault() {
    final defaultPrice = double.tryParse(_precioController.text.trim()) ?? 0.0;
    for (var day in _daysOfWeek) {
      for (var hora in _horarios) {
        final horaNormalizada = Horario.normalizarHora(hora);
        // Solo actualizar si el precio no ha sido modificado manualmente
        if (_precioControllers[day]![horaNormalizada]!.text.isEmpty ||
            double.tryParse(_precioControllers[day]![horaNormalizada]!.text) == _preciosPorHorario[day]![horaNormalizada]!['precio']) {
          _precioControllers[day]![horaNormalizada]!.text = defaultPrice.toString();
          _preciosPorHorario[day]![horaNormalizada]!['precio'] = defaultPrice;
        }
      }
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
        imageQuality: 70, // Calidad reducida para ambas plataformas
      );

      if (image != null && mounted) {
        Uint8List imageBytes = await image.readAsBytes();
        
        // Verificar tamaño del archivo (límite más estricto)
        if (imageBytes.length > 3 * 1024 * 1024) { // 3MB en lugar de 5MB
          _mostrarError('La imagen excede el tamaño máximo de 3MB');
          return;
        }

        if (mounted) {
          setState(() {
            _imagenSeleccionada = image;
            _imagenBytes = imageBytes;
          });
        }
      }
    } catch (e) {
      _mostrarError("Error al seleccionar imagen: $e");
    }
  }

  Future<String> _subirImagen() async {
    setState(() {
      _isUploadingImage = true;
    });

    try {
      String fileName = 'canchas/${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      // Metadata común para ambas plataformas
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedFrom': kIsWeb ? 'web' : 'mobile',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (kIsWeb) {
        // En web: usar bytes directamente
        Uint8List? bytesToUpload = _imagenBytes;
        
        if (bytesToUpload == null && _imagenSeleccionada != null) {
          bytesToUpload = await _imagenSeleccionada!.readAsBytes();
        }
        
        if (bytesToUpload == null) {
          throw Exception('No se pudo obtener los bytes de la imagen');
        }
        
        await storageRef.putData(bytesToUpload, metadata);
      } else {
        // En móvil: usar File
        if (_imagenSeleccionada == null) {
          throw Exception('No se seleccionó ninguna imagen');
        }
        
        await storageRef.putFile(File(_imagenSeleccionada!.path), metadata);
      }

      final downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Error detallado al subir imagen: $e');
      _mostrarError("Error al subir imagen: $e");
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Widget _buildImageWidget() {
    if (_imagenSeleccionada == null) {
      return _buildImagePlaceholder();
    }

    if (kIsWeb) {
      // En web: usar Memory si tenemos bytes, sino leer del XFile
      if (_imagenBytes != null) {
        return Image.memory(
          _imagenBytes!,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildImageErrorWidget();
          },
        );
      } else {
        // Fallback para web sin bytes
        return FutureBuilder<Uint8List>(
          future: _imagenSeleccionada!.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Image.memory(
                snapshot.data!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildImageErrorWidget();
                },
              );
            } else if (snapshot.hasError) {
              return _buildImageErrorWidget();
            } else {
              return _buildImageLoadingWidget();
            }
          },
        );
      }
    } else {
      // En móvil: usar File
      return Image.file(
        File(_imagenSeleccionada!.path),
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageErrorWidget();
        },
      );
    }
  }

  Widget _buildImageErrorWidget() {
    return Container(
      width: double.infinity,
      height: 200,
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red[400],
          ),
          const SizedBox(height: 8),
          Text(
            "Error al cargar imagen",
            style: GoogleFonts.montserrat(
              fontSize: 14,
              color: Colors.red[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _seleccionarImagen,
            child: Text(
              "Seleccionar otra imagen",
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: const Color(0xFF4F46E5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageLoadingWidget() {
    return Container(
      width: double.infinity,
      height: 200,
      color: Colors.grey[100],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Cargando imagen...",
            style: GoogleFonts.montserrat(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
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

  Future<void> _registrarCancha() async {
    if (!_formKey.currentState!.validate()) return;

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmar Registro', style: GoogleFonts.montserrat()),
        content: Text('¿Está seguro de registrar esta cancha?', style: GoogleFonts.montserrat()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirmar', style: GoogleFonts.montserrat()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String imagenUrl = 'assets/cancha_demo.png';
      if (_imagenSeleccionada != null) {
        imagenUrl = await _subirImagen();
      }

      // Actualizar precios, habilitada y completo desde los controladores
      for (var day in _daysOfWeek) {
        for (var hora in _horarios) {
          final horaNormalizada = Horario.normalizarHora(hora);
          final value = _precioControllers[day]![horaNormalizada]!.text;
          _preciosPorHorario[day]![horaNormalizada] = {
            'precio': double.tryParse(value) ?? 0.0,
            'habilitada': _habilitadaHorario[day]![horaNormalizada]!,
            'completo': _completoHorario[day]![horaNormalizada]!,
          };
        }
      }

      await FirebaseFirestore.instance.collection('canchas').add({
        'nombre': _nombreController.text.trim(),
        'descripcion': _descripcionController.text.trim(),
        'imagen': imagenUrl,
        'ubicacion': _ubicacionController.text.trim(),
        'precio': double.tryParse(_precioController.text.trim()) ?? 0,
        'techada': _techada,
        'sedeId': _sede,
        'preciosPorHorario': _preciosPorHorario,
        'disponible': _disponible,
        'motivoNoDisponible': _disponible ? null : _motivoNoDisponibleController.text.trim(),
      });

      if (mounted) {
        // Mover la notificación a CanchaProvider dentro del bloque mounted
        await Provider.of<CanchaProvider>(context, listen: false).fetchCanchas(_sede);
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
        _mostrarError("Error al registrar cancha: $error");
      }
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
    _precioController.removeListener(_updatePreciosPorHorarioFromDefault);
    _animationController.dispose();
    _scrollController.dispose();
    _nombreController.dispose();
    _descripcionController.dispose();
    _ubicacionController.dispose();
    _precioController.dispose();
    _motivoNoDisponibleController.dispose();
    for (var day in _daysOfWeek) {
      for (var hora in _horarios) {
        _precioControllers[day]![Horario.normalizarHora(hora)]!.dispose();
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
        "Registrar Nueva Cancha",
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
              "Configuración de Precios y Disponibilidad",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: "Día para editar precios y disponibilidad",
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
                  "Ajustes para ${_selectedDay!}",
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 400,
              child: SingleChildScrollView(
                child: Column(
                  children: _horarios.map((hora) => _buildHorarioPrecio(hora)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorarioPrecio(String hora) {
  final horaNormalizada = Horario.normalizarHora(hora);
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Habilitada",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
            Text(
              "Pago Comp.",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
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
                controller: _precioControllers[_selectedDay]![horaNormalizada],
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
                  _preciosPorHorario[_selectedDay]![horaNormalizada]!['precio'] = double.tryParse(value) ?? 0.0;
                },
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  return parsed == null || parsed < 0 ? "Precio inválido" : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Switch(
                value: _habilitadaHorario[_selectedDay]![horaNormalizada]!,
                onChanged: (value) {
                  setState(() {
                    _habilitadaHorario[_selectedDay]![horaNormalizada] = value;
                    _preciosPorHorario[_selectedDay]![horaNormalizada]!['habilitada'] = value;
                  });
                },
                activeColor: const Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Switch(
                value: _completoHorario[_selectedDay]![horaNormalizada]!,
                onChanged: (value) {
                  setState(() {
                    _completoHorario[_selectedDay]![horaNormalizada] = value;
                    _preciosPorHorario[_selectedDay]![horaNormalizada]!['completo'] = value;
                  });
                },
                activeColor: const Color(0xFF4F46E5),
              ),
            ),
          ],
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
            onPressed: _isLoading ? null : _registrarCancha,
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
                        "Registrar Cancha",
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