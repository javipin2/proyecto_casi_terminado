import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../providers/lugar_provider.dart';
import '../../providers/ciudad_provider.dart';
import '../../models/lugar.dart';

class GestionUsuariosPage extends StatefulWidget {
  const GestionUsuariosPage({super.key});

  @override
  State<GestionUsuariosPage> createState() => _GestionUsuariosPageState();
}

class _GestionUsuariosPageState extends State<GestionUsuariosPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String? _ciudadFiltro;
  String? _lugarSeleccionado; // al tocar un lugar, mostramos sus usuarios

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarDatosIniciales();
    });
  }

  void _cargarDatosIniciales() {
    final ciudadProvider = Provider.of<CiudadProvider>(context, listen: false);
    final lugarProvider = Provider.of<LugarProvider>(context, listen: false);
    if (ciudadProvider.ciudades.isEmpty) ciudadProvider.fetchCiudades();
    lugarProvider.fetchTodosLosLugares();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  List<Lugar> _lugaresFiltrados(LugarProvider lugarProvider) {
    var list = lugarProvider.lugares;
    if (_ciudadFiltro != null && _ciudadFiltro!.isNotEmpty) {
      list = list.where((l) => l.ciudadId == _ciudadFiltro).toList();
    }
    return list;
  }

  void _irALugares() {
    setState(() {
      _lugarSeleccionado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: const Color(0xFFF3F4F6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                _buildHeader(isWide: isWide),
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
                        child: _lugarSeleccionado == null
                            ? _buildLugaresContent()
                            : _buildUsuariosContent(),
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

  Widget _buildHeader({required bool isWide}) {
    return Padding(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gestión de Usuarios',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lugarSeleccionado == null
                            ? 'Selecciona un lugar para ver y administrar sus usuarios.'
                            : 'Usuarios asociados al lugar seleccionado.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFE5F4EF),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_lugarSeleccionado != null && isWide) ...[
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: _irALugares,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    tooltip: 'Volver a lugares',
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    onPressed: () => _mostrarDialogoCrearUsuario(),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Agregar Usuario'),
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
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Consumer<CiudadProvider>(
                    builder: (context, ciudadProvider, _) {
                      return DropdownButtonFormField<String>(
                        value: _ciudadFiltro,
                        decoration: InputDecoration(
                          labelText: 'Filtrar por Ciudad',
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.location_city),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todas las ciudades'),
                          ),
                          ...ciudadProvider.ciudades
                              .map((c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.nombre),
                                  )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _ciudadFiltro = value;
                            if (value != null) {
                              Provider.of<LugarProvider>(context, listen: false)
                                  .fetchLugaresPorCiudad(value);
                            } else {
                              Provider.of<LugarProvider>(context, listen: false)
                                  .fetchTodosLosLugares();
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if (_lugarSeleccionado != null)
                  Expanded(
                    child: Consumer<LugarProvider>(
                      builder: (context, lugarProvider, _) {
                        final list = lugarProvider.lugares
                            .where((l) => l.id == _lugarSeleccionado);
                        final lugar = list.isEmpty ? null : list.first;
                        return InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Lugar actual',
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.place),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          child: Text(
                            lugar?.nombre ?? 'Lugar',
                            style: const TextStyle(fontSize: 16),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
            if (_lugarSeleccionado != null && !isWide) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: _irALugares,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    tooltip: 'Volver a lugares',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _mostrarDialogoCrearUsuario(),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Agregar Usuario'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF2E7D60),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLugaresContent() {
    return Consumer<LugarProvider>(
      builder: (context, lugarProvider, _) {
        final lugares = _lugaresFiltrados(lugarProvider);
        if (lugarProvider.isLoading && lugares.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D60)),
                ),
                SizedBox(height: 16),
                Text('Cargando lugares...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        if (lugares.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No hay lugares para mostrar. Ajusta el filtro de ciudad.',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: lugares.length,
          itemBuilder: (context, index) {
            final lugar = lugares[index];
            return _buildLugarCard(lugar);
          },
        );
      },
    );
  }

  Widget _buildLugarCard(Lugar lugar) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF2E7D60).withOpacity(0.2),
          child: const Icon(Icons.place, color: Color(0xFF2E7D60)),
        ),
        title: Text(
          lugar.nombre,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Consumer<CiudadProvider>(
          builder: (context, ciudadProvider, _) {
            final list = ciudadProvider.ciudades
                .where((c) => c.id == lugar.ciudadId);
            final ciudad = list.isEmpty ? null : list.first;
            return Text(ciudad?.nombre ?? lugar.ciudadId);
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          setState(() {
            _lugarSeleccionado = lugar.id;
          });
        },
      ),
    );
  }

  Stream<QuerySnapshot> _getUsuariosStream() {
    if (_lugarSeleccionado != null && _lugarSeleccionado!.isNotEmpty) {
      return FirebaseFirestore.instance
          .collection('usuarios')
          .where('lugarId', isEqualTo: _lugarSeleccionado)
          .snapshots();
    }
    return const Stream.empty();
  }

  Widget _buildUsuariosContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getUsuariosStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D60)),
                ),
                SizedBox(height: 16),
                Text('Cargando usuarios...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }
        final usuarios = snapshot.data?.docs ?? [];
        if (usuarios.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No hay usuarios en este lugar',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Usa "Agregar Usuario" para crear uno',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: usuarios.length,
          itemBuilder: (context, index) {
            return _buildUsuarioCard(usuarios[index], index);
          },
        );
      },
    );
  }

  Widget _buildUsuarioCard(QueryDocumentSnapshot usuario, int index) {
    final data = usuario.data() as Map<String, dynamic>;
    final nombre = data['nombre'] ?? 'Sin nombre';
    final email = data['email'] ?? 'Sin email';
    final rol = data['rol'] ?? 'Sin rol';
    final activo = data['activo'] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: _getRolColor(rol).withOpacity(0.2),
          child: Text(
            nombre.isNotEmpty ? nombre[0].toUpperCase() : 'U',
            style: TextStyle(
              color: _getRolColor(rol),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          nombre,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildChip(rol, _getRolColor(rol)),
                const SizedBox(width: 8),
                _buildChip(
                  activo ? 'Activo' : 'Inactivo',
                  activo ? Colors.green : Colors.red,
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _manejarAccionUsuario(value, usuario),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'editar',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Editar'),
                ],
              ),
            ),
            PopupMenuItem(
              value: activo ? 'desactivar' : 'activar',
              child: Row(
                children: [
                  Icon(activo ? Icons.block : Icons.check_circle, size: 20),
                  const SizedBox(width: 8),
                  Text(activo ? 'Desactivar' : 'Activar'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'eliminar',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Eliminar', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getRolColor(String rol) {
    switch (rol.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'superadmin':
        return Colors.red;
      case 'encargado':
        return Colors.blue;
      case 'programador':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _manejarAccionUsuario(String accion, QueryDocumentSnapshot usuario) {
    switch (accion) {
      case 'editar':
        _mostrarDialogoEditarUsuario(usuario);
        break;
      case 'activar':
      case 'desactivar':
        _cambiarEstadoUsuario(usuario);
        break;
      case 'eliminar':
        _mostrarDialogoEliminarUsuario(usuario);
        break;
    }
  }

  void _mostrarDialogoCrearUsuario() {
    if (_lugarSeleccionado == null) return;
    showDialog(
      context: context,
      builder: (context) => _CrearUsuarioDialog(
        lugarId: _lugarSeleccionado!,
        onUsuarioCreado: () => setState(() {}),
      ),
    );
  }

  void _mostrarDialogoEditarUsuario(QueryDocumentSnapshot usuario) {
    showDialog(
      context: context,
      builder: (context) => _EditarUsuarioDialog(
        usuario: usuario,
        onUsuarioActualizado: () => setState(() {}),
      ),
    );
  }

  void _cambiarEstadoUsuario(QueryDocumentSnapshot usuario) {
    final data = usuario.data() as Map<String, dynamic>;
    final activo = data['activo'] ?? true;
    usuario.reference.update({
      'activo': !activo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Usuario ${!activo ? 'activado' : 'desactivado'}'),
        backgroundColor: const Color(0xFF2E7D60),
      ),
    );
  }

  void _mostrarDialogoEliminarUsuario(QueryDocumentSnapshot usuario) {
    final data = usuario.data() as Map<String, dynamic>;
    final nombre = data['nombre'] ?? 'Usuario';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Eliminar al usuario "$nombre"? Se eliminará también su cuenta de acceso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final uid = usuario.id;
              Navigator.pop(context);
              try {
                await FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uid)
                    .delete();
                // Opcional: eliminar de Auth con Cloud Function
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Usuario eliminado'),
                    backgroundColor: Colors.red,
                  ),
                );
                setState(() {});
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
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

// --- Crear usuario ---

class _CrearUsuarioDialog extends StatefulWidget {
  final String lugarId;
  final VoidCallback onUsuarioCreado;

  const _CrearUsuarioDialog({
    required this.lugarId,
    required this.onUsuarioCreado,
  });

  @override
  State<_CrearUsuarioDialog> createState() => _CrearUsuarioDialogState();
}

class _CrearUsuarioDialogState extends State<_CrearUsuarioDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _rolSeleccionado = 'encargado';
  bool _isLoading = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear Usuario'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (!v.contains('@')) return 'Email válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerida';
                  if (v.length < 6) return 'Mínimo 6 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _rolSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'encargado', child: Text('Encargado')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                ],
                onChanged: (value) => setState(() => _rolSeleccionado = value!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _crearUsuario,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D60),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }

  Future<void> _crearUsuario() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final uid = cred.user?.uid;
      if (uid == null) throw Exception('No se obtuvo UID');
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'email': _emailController.text.trim(),
        'nombre': _nombreController.text.trim(),
        'rol': _rolSeleccionado,
        'lugarId': widget.lugarId,
        'activo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      widget.onUsuarioCreado();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Usuario ${_nombreController.text} creado'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// --- Editar usuario (nombre, email, contraseña) ---

class _EditarUsuarioDialog extends StatefulWidget {
  final QueryDocumentSnapshot usuario;
  final VoidCallback onUsuarioActualizado;

  const _EditarUsuarioDialog({
    required this.usuario,
    required this.onUsuarioActualizado,
  });

  @override
  State<_EditarUsuarioDialog> createState() => _EditarUsuarioDialogState();
}

class _EditarUsuarioDialogState extends State<_EditarUsuarioDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreController;
  late TextEditingController _emailController;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _rolSeleccionado = 'encargado';
  String? _lugarSeleccionado;
  bool _isLoading = false;
  bool _cambiarContrasena = false;

  @override
  void initState() {
    super.initState();
    final d = widget.usuario.data() as Map<String, dynamic>;
    _nombreController = TextEditingController(text: d['nombre']?.toString() ?? '');
    _emailController = TextEditingController(text: d['email']?.toString() ?? '');
    _rolSeleccionado = d['rol']?.toString() ?? 'encargado';
    _lugarSeleccionado = d['lugarId']?.toString();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Usuario'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (!v.contains('@')) return 'Email válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _cambiarContrasena,
                onChanged: (value) => setState(() {
                  _cambiarContrasena = value ?? false;
                  if (!_cambiarContrasena) {
                    _passwordController.clear();
                    _confirmPasswordController.clear();
                  }
                }),
                title: const Text('Cambiar contraseña'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF2E7D60),
              ),
              if (_cambiarContrasena) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (!_cambiarContrasena) return null;
                    if (v == null || v.isEmpty) return 'Ingresa la nueva contraseña';
                    if (v.length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (!_cambiarContrasena) return null;
                    if (v == null || v.isEmpty) return 'Confirma la contraseña';
                    if (v != _passwordController.text) return 'No coinciden';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _rolSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'encargado', child: Text('Encargado')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                ],
                onChanged: (value) => setState(() => _rolSeleccionado = value!),
              ),
              const SizedBox(height: 16),
              Consumer<LugarProvider>(
                builder: (context, lugarProvider, _) {
                  return DropdownButtonFormField<String>(
                    value: _lugarSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Lugar',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Sin lugar'),
                      ),
                      ...lugarProvider.lugares
                          .map((l) => DropdownMenuItem(
                                value: l.id,
                                child: Text(l.nombre),
                              )),
                    ],
                    onChanged: (value) => setState(() => _lugarSeleccionado = value),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D60),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final uid = widget.usuario.id;
    final newEmail = _emailController.text.trim();
    final newPassword = _cambiarContrasena &&
            _passwordController.text.trim().isNotEmpty &&
            _passwordController.text == _confirmPasswordController.text
        ? _passwordController.text
        : null;
    final dataOriginal = widget.usuario.data() as Map<String, dynamic>;
    final oldEmail = dataOriginal['email']?.toString();

    try {
      // 1) Actualizar Firestore
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'nombre': _nombreController.text.trim(),
        'email': newEmail,
        'rol': _rolSeleccionado,
        'lugarId': _lugarSeleccionado,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2) Si cambió email o contraseña, llamar Cloud Function (Auth)
      if (newEmail != oldEmail || newPassword != null) {
        try {
          final callable = FirebaseFunctions.instance
              .httpsCallable('updateUserAuth');
          await callable.call<void>({
            'uid': uid,
            if (newEmail != oldEmail) 'newEmail': newEmail,
            if (newPassword != null) 'newPassword': newPassword,
          });
        } on FirebaseFunctionsException catch (e) {
          if (e.code == 'unavailable' || e.code == 'not-found') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Datos guardados. Para actualizar email/contraseña en el acceso, despliega la función updateUserAuth en Firebase.',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } else {
            rethrow;
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onUsuarioActualizado();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuario actualizado'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
