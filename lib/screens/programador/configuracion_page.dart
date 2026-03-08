import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/index_error_service.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> 
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final TextEditingController _cuentasController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  bool _loadingCuentas = true;
  bool _savingCuentas = false;

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

    _cargarCuentasPago();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cuentasController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 900;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: const Color(0xFFF3F4F6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2E7D60),
                          Color(0xFF3FA98C),
                        ],
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
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Icon(
                            Icons.settings,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Configuración del Sistema',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Panel de control y herramientas avanzadas para programador.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFE5F4EF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Información del usuario actual
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Información del Usuario',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D60),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildInfoRow(
                                  'Nombre',
                                  authProvider.userName ??
                                      'No disponible'),
                              _buildInfoRow(
                                  'Email',
                                  authProvider.userEmail ??
                                      'No disponible'),
                              _buildInfoRow(
                                  'Rol',
                                  _getRolTexto(
                                      authProvider.userRole ?? 'No disponible')),
                              _buildInfoRow(
                                  'Estado',
                                  authProvider.isAuthenticated
                                      ? 'Activo'
                                      : 'Inactivo'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Estadísticas + acciones en layout responsivo
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Estadísticas del Sistema',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E7D60),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          'Ciudades',
                                          '0',
                                          Icons.location_city,
                                          Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          'Lugares',
                                          '0',
                                          Icons.location_on,
                                          Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          'Usuarios',
                                          '0',
                                          Icons.people,
                                          Colors.green,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          'Reservas',
                                          '0',
                                          Icons.calendar_today,
                                          Colors.purple,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Acciones del Sistema',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E7D60),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildActionTile(
                                    'Exportar Datos',
                                    'Exportar información del sistema',
                                    Icons.download,
                                    Colors.blue,
                                    () => _mostrarMensaje(
                                        'Función de exportación en desarrollo'),
                                  ),
                                  _buildActionTile(
                                    'Respaldar Sistema',
                                    'Crear respaldo de la base de datos',
                                    Icons.backup,
                                    Colors.green,
                                    () => _mostrarMensaje(
                                        'Función de respaldo en desarrollo'),
                                  ),
                                  _buildActionTile(
                                    'Limpiar Cache',
                                    'Limpiar datos temporales',
                                    Icons.cleaning_services,
                                    Colors.orange,
                                    () => _mostrarMensaje(
                                        'Cache limpiado exitosamente'),
                                  ),
                                  _buildActionTile(
                                    'Logs del Sistema',
                                    'Ver registros del sistema',
                                    Icons.assignment,
                                    Colors.purple,
                                    () => _mostrarMensaje(
                                        'Logs del sistema en desarrollo'),
                                  ),
                                  _buildActionTile(
                                    'Reporte de Índices',
                                    'Ver índices necesarios para Firestore',
                                    Icons.storage,
                                    Colors.indigo,
                                    () => _mostrarReporteIndices(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Estadísticas del Sistema',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E7D60),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildStatCard(
                                        'Ciudades',
                                        '0',
                                        Icons.location_city,
                                        Colors.blue,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildStatCard(
                                        'Lugares',
                                        '0',
                                        Icons.location_on,
                                        Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildStatCard(
                                        'Usuarios',
                                        '0',
                                        Icons.people,
                                        Colors.green,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildStatCard(
                                        'Reservas',
                                        '0',
                                        Icons.calendar_today,
                                        Colors.purple,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Acciones del Sistema',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E7D60),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildActionTile(
                                  'Exportar Datos',
                                  'Exportar información del sistema',
                                  Icons.download,
                                  Colors.blue,
                                  () => _mostrarMensaje(
                                      'Función de exportación en desarrollo'),
                                ),
                                _buildActionTile(
                                  'Respaldar Sistema',
                                  'Crear respaldo de la base de datos',
                                  Icons.backup,
                                  Colors.green,
                                  () => _mostrarMensaje(
                                      'Función de respaldo en desarrollo'),
                                ),
                                _buildActionTile(
                                  'Limpiar Cache',
                                  'Limpiar datos temporales',
                                  Icons.cleaning_services,
                                  Colors.orange,
                                  () => _mostrarMensaje(
                                      'Cache limpiado exitosamente'),
                                ),
                                _buildActionTile(
                                  'Logs del Sistema',
                                  'Ver registros del sistema',
                                  Icons.assignment,
                                  Colors.purple,
                                  () => _mostrarMensaje(
                                      'Logs del sistema en desarrollo'),
                                ),
                                _buildActionTile(
                                  'Reporte de Índices',
                                  'Ver índices necesarios para Firestore',
                                  Icons.storage,
                                  Colors.indigo,
                                  () => _mostrarReporteIndices(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 24),

                  // Cuentas de pago del programador
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _buildCuentasPagoSection(),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Información de la aplicación
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Información de la Aplicación',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D60),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow('Versión', '1.0.0'),
                          _buildInfoRow('Plataforma', 'Flutter'),
                          _buildInfoRow('Base de Datos', 'Firebase Firestore'),
                          _buildInfoRow('Autenticación', 'Firebase Auth'),
                          _buildInfoRow('Última Actualización', 'Hoy'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E7D60),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  String _getRolTexto(String rol) {
    switch (rol) {
      case 'admin':
        return 'Administrador';
      case 'encargado':
        return 'Encargado';
      case 'superadmin':
        return 'Super Administrador';
      case 'programador':
        return 'Programador';
      default:
        return 'Usuario';
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: const Color(0xFF2E7D60),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _mostrarReporteIndices() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storage, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Reporte de Índices Firestore'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Índices necesarios para el funcionamiento óptimo:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              _buildIndexItem('Ciudades', [
                'activa (ascending) + nombre (ascending)',
                'nombre (ascending)',
              ]),
              
              _buildIndexItem('Lugares', [
                'ciudadId (ascending) + activo (ascending) + nombre (ascending)',
                'nombre (ascending)',
              ]),
              
              _buildIndexItem('Sedes', [
                'lugarId (ascending) + activa (ascending) + nombre (ascending)',
                'nombre (ascending)',
              ]),
              
              _buildIndexItem('Usuarios', [
                'lugarId (ascending) + activo (ascending)',
                'rol (ascending) + activo (ascending)',
              ]),
              
              _buildIndexItem('Reservas', [
                'cancha_id (ascending) + fecha (ascending)',
                'estado (ascending) + fecha (ascending)',
              ]),
              
              _buildIndexItem('Audit Logs', [
                'timestamp (descending) + usuario_id (ascending)',
                'accion (ascending) + timestamp (descending)',
              ]),
              
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Comandos útiles:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• firebase firestore:indexes'),
                    Text('• firebase firestore:indexes --create'),
                    Text('• Ver en Firebase Console > Firestore > Indexes'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          ElevatedButton(
            onPressed: () {
              IndexErrorService.generateIndexReport();
              Navigator.pop(context);
              _mostrarMensaje('Reporte generado en consola');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text('Generar en Consola'),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexItem(String collection, List<String> indexes) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📁 $collection:',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E7D60),
            ),
          ),
          const SizedBox(height: 4),
          ...indexes.map((index) => Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 2),
            child: Text(
              '• $index',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontFamily: 'monospace',
              ),
            ),
          )),
        ],
      ),
    );
  }

  Future<void> _cargarCuentasPago() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('pagos_programador')
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final texto = data['textoCuentas'] as String?;
        final whatsapp = data['whatsappCobro'] as String?;
        _cuentasController.text = texto ?? '';
        _whatsappController.text = whatsapp ?? '';
      }
    } catch (_) {
      // ignorar errores de carga
    } finally {
      if (mounted) {
        setState(() {
          _loadingCuentas = false;
        });
      }
    }
  }

  Widget _buildCuentasPagoSection() {
    if (_loadingCuentas) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cuentas de pago del programador',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E7D60),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Este texto se mostrará en la ventana de bloqueo para que los clientes sepan a dónde transferir el dinero.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF4B5563),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cuentasController,
          maxLines: 6,
          minLines: 4,
          decoration: InputDecoration(
            hintText:
                'Ejemplo:\nBanco X - Cuenta de ahorros 123456789 a nombre de Juan Pérez\nNequi: 300 000 0000\nDaviplata: 300 000 0001',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'WhatsApp para comprobantes',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2E7D60),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _whatsappController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'Ejemplo: +57 300 000 0000',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.phone_in_talk_rounded),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _savingCuentas ? null : _guardarCuentasPago,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D60),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _savingCuentas
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(
              _savingCuentas ? 'Guardando...' : 'Guardar cuentas',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _guardarCuentasPago() async {
    setState(() {
      _savingCuentas = true;
    });
    try {
      await FirebaseFirestore.instance
          .collection('config')
          .doc('pagos_programador')
          .set(
        {
          'textoCuentas': _cuentasController.text.trim(),
          'whatsappCobro': _whatsappController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _mostrarMensaje('Cuentas de pago actualizadas');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar cuentas de pago: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingCuentas = false;
        });
      }
    }
  }
}
