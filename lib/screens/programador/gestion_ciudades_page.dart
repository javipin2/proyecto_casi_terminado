import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/ciudad_provider.dart';
import '../../models/ciudad.dart';

class GestionCiudadesPage extends StatefulWidget {
  const GestionCiudadesPage({super.key});

  @override
  State<GestionCiudadesPage> createState() => _GestionCiudadesPageState();
}

class _GestionCiudadesPageState extends State<GestionCiudadesPage> 
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 700;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: const Color(0xFFF3F4F6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                // Header con botón de agregar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2E7D60), Color(0xFF3FA98C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.location_city_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Gestión de Ciudades',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Administra las ciudades disponibles para los diferentes lugares.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFE5F4EF),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _mostrarDialogoCrearCiudad(),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Agregar Ciudad'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF2E7D60),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.location_city_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Gestión de Ciudades',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Administra las ciudades disponibles para tus lugares y sedes.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFFE5F4EF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: () => _mostrarDialogoCrearCiudad(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Agregar Ciudad'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF2E7D60),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                // Lista de ciudades
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Consumer<CiudadProvider>(
                          builder: (context, ciudadProvider, child) {
                            if (ciudadProvider.isLoading) {
                              return const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF2E7D60),
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Cargando ciudades...',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (ciudadProvider.errorMessage != null) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 64,
                                      color: Colors.red[300],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      ciudadProvider.errorMessage!,
                                      style: const TextStyle(fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () =>
                                          ciudadProvider.fetchTodasLasCiudades(),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF2E7D60),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (ciudadProvider.ciudades.isEmpty) {
                              return const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.location_city,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No hay ciudades registradas',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return RefreshIndicator(
                              onRefresh: () =>
                                  ciudadProvider.fetchTodasLasCiudades(),
                              color: const Color(0xFF2E7D60),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: ciudadProvider.ciudades.length,
                                itemBuilder: (context, index) {
                                  final ciudad = ciudadProvider.ciudades[index];
                                  return _buildCiudadCard(ciudad, index);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCiudadCard(Ciudad ciudad, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: ciudad.activa ? Colors.green[100] : Colors.red[100],
                child: Text(
                  ciudad.codigo,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ciudad.activa ? Colors.green[800] : Colors.red[800],
                  ),
                ),
              ),
              title: Text(
                ciudad.nombre,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text('Código: ${ciudad.codigo}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: ciudad.activa,
                    onChanged: (value) {
                      Provider.of<CiudadProvider>(context, listen: false).actualizarCiudad(
                        ciudad.id,
                        {'activa': value, 'updatedAt': Timestamp.now()},
                      );
                    },
                    activeColor: const Color(0xFF2E7D60),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _mostrarDialogoEditarCiudad(ciudad);
                      } else if (value == 'delete') {
                        _mostrarDialogoEliminarCiudad(ciudad);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Editar'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Eliminar'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoCrearCiudad() {
    final nombreController = TextEditingController();
    final codigoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Nueva Ciudad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la Ciudad',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_city),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codigoController,
              decoration: const InputDecoration(
                labelText: 'Código (ej: BOG)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.code),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nombreController.text.isNotEmpty && codigoController.text.isNotEmpty) {
                final ciudad = Ciudad(
                  id: '',
                  nombre: nombreController.text,
                  codigo: codigoController.text.toUpperCase(),
                  activa: true,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                
                Provider.of<CiudadProvider>(context, listen: false).crearCiudad(ciudad);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D60),
              foregroundColor: Colors.white,
            ),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoEditarCiudad(Ciudad ciudad) {
    final nombreController = TextEditingController(text: ciudad.nombre);
    final codigoController = TextEditingController(text: ciudad.codigo);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Ciudad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la Ciudad',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_city),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codigoController,
              decoration: const InputDecoration(
                labelText: 'Código',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.code),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nombreController.text.isNotEmpty && codigoController.text.isNotEmpty) {
                Provider.of<CiudadProvider>(context, listen: false).actualizarCiudad(
                  ciudad.id,
                  {
                    'nombre': nombreController.text,
                    'codigo': codigoController.text.toUpperCase(),
                    'updatedAt': Timestamp.now(),
                  },
                );
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D60),
              foregroundColor: Colors.white,
            ),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoEliminarCiudad(Ciudad ciudad) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Ciudad'),
        content: Text('¿Estás seguro de que quieres eliminar la ciudad "${ciudad.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<CiudadProvider>(context, listen: false).eliminarCiudad(ciudad.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
