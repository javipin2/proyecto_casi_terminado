import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'clientes_screen.dart';

class EditarClienteScreen extends StatefulWidget {
  final String clienteId;
  final Map<String, dynamic> clienteData;

  const EditarClienteScreen({
    super.key,
    required this.clienteId,
    required this.clienteData,
  });

  @override
  EditarClienteScreenState createState() => EditarClienteScreenState();
}

class EditarClienteScreenState extends State<EditarClienteScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreController;
  late TextEditingController _telefonoController;
  late TextEditingController _correoController;
  bool _isLoading = false;
  late AnimationController _fadeController;

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    // Inicializar controladores con datos existentes
    _nombreController =
        TextEditingController(text: widget.clienteData['nombre'] ?? '');
    _telefonoController =
        TextEditingController(text: widget.clienteData['telefono'] ?? '');
    _correoController =
        TextEditingController(text: widget.clienteData['correo'] ?? '');

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _actualizarCliente() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        await FirebaseFirestore.instance
            .collection('clientes')
            .doc(widget.clienteId)
            .update({
          'nombre': _nombreController.text.trim(),
          'telefono': _telefonoController.text.trim(),
          'correo': _correoController.text.trim(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cliente actualizado correctamente',
                style: GoogleFonts.montserrat(color: Colors.white),
              ),
              backgroundColor: _secondaryColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ClientesScreen()),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error al actualizar cliente: $error',
                style: GoogleFonts.montserrat(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
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
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Editar Cliente',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: _primaryColor,
          ),
        ),
        backgroundColor: _backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _secondaryColor),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ClientesScreen()),
            );
          },
          tooltip: 'Volver a Clientes',
        ),
      ),
      body: Container(
        color: _backgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Animate(
              effects: [
                FadeEffect(duration: const Duration(milliseconds: 600)),
                SlideEffect(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                  duration: const Duration(milliseconds: 600),
                ),
              ],
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: _cardColor),
                ),
                color: _cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nombreController,
                          decoration: InputDecoration(
                            labelText: 'Nombre',
                            prefixIcon:
                                Icon(Icons.person, color: _secondaryColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          style: GoogleFonts.montserrat(color: _primaryColor),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Ingrese el nombre'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _telefonoController,
                          decoration: InputDecoration(
                            labelText: 'Teléfono',
                            prefixIcon:
                                Icon(Icons.phone, color: _secondaryColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          style: GoogleFonts.montserrat(color: _primaryColor),
                          keyboardType: TextInputType.phone,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Ingrese el teléfono'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _correoController,
                          decoration: InputDecoration(
                            labelText: 'Correo Electrónico',
                            prefixIcon:
                                Icon(Icons.email, color: _secondaryColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          style: GoogleFonts.montserrat(color: _primaryColor),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null; // Correo es opcional
                            }
                            final emailRegex =
                                RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                            if (!emailRegex.hasMatch(value)) {
                              return 'Ingrese un correo válido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _isLoading
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          _secondaryColor),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Actualizando...',
                                      style: GoogleFonts.montserrat(
                                        color: _primaryColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: _actualizarCliente,
                                icon: Icon(Icons.save, color: Colors.white),
                                label: Text(
                                  'Actualizar Cliente',
                                  style: GoogleFonts.montserrat(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _secondaryColor,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 3,
                                  minimumSize: Size(
                                      isDesktop ? 300 : double.infinity, 50),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
