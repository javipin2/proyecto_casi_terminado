import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reserva_canchas/models/cancha.dart';
import 'editar_cancha_screen.dart';
import 'registrar_cancha_screen.dart';
import '../admin_dashboard_screen.dart';

class CanchasScreen extends StatefulWidget {
  const CanchasScreen({super.key});

  @override
  CanchasScreenState createState() => CanchasScreenState();
}

class CanchasScreenState extends State<CanchasScreen> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;
  
  String _selectedSede = "";
  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);
  
  // Control de estado
  bool _isInitialized = false;
  bool _isDisposed = false;
  List<QueryDocumentSnapshot>? _lastCanchasData;
  Set<String>? _lastSedesData;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _initializeScreen() {
    // Usar Future.delayed en lugar de addPostFrameCallback para mayor estabilidad
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_isDisposed && mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    });
  }

  Query _buildQuery() {
    Query query = FirebaseFirestore.instance.collection('canchas');
    if (_selectedSede.isNotEmpty) {
      query = query.where('sede', isEqualTo: _selectedSede);
    }
    return query;
  }

  Future<void> _eliminarCancha(String canchaId, BuildContext context) async {
    if (_isDisposed || !mounted) return;
    
    bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(
              'Confirmar eliminación',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
          ],
        ),
        content: Text(
          '¿Deseas eliminar esta cancha?',
          style: GoogleFonts.montserrat(color: _primaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.montserrat(color: _secondaryColor),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Eliminar',
              style: GoogleFonts.montserrat(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && !_isDisposed && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('canchas')
            .doc(canchaId)
            .delete();
        if (!_isDisposed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cancha eliminada correctamente',
                style: GoogleFonts.montserrat(color: Colors.white),
              ),
              backgroundColor: _secondaryColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
            ),
          );
        }
      } catch (error) {
        if (!_isDisposed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error al eliminar: $error',
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
      }
    }
  }

  Future<void> _navigateToAddCancha() async {
    if (_isDisposed || !mounted) return;
    
    // ignore: unused_local_variable
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => 
            const RegistrarCanchaScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    
    // Refresh con delay para evitar problemas de renderizado
    if (!_isDisposed && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!_isDisposed && mounted) {
        setState(() {
          // Forzar actualización
        });
      }
    }
  }

  Future<void> _navigateToEditCancha(String canchaId, Cancha cancha) async {
    if (_isDisposed || !mounted) return;
    
    // ignore: unused_local_variable
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => 
            EditarCanchaScreen(canchaId: canchaId, cancha: cancha),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    
    // Refresh con delay para evitar problemas de renderizado
    if (!_isDisposed && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!_isDisposed && mounted) {
        setState(() {
          // Forzar actualización
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Necesario para AutomaticKeepAliveClientMixin
    
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    final isTablet = screenWidth >= 500 && screenWidth <= 900;
    final textScale = screenWidth < 500 ? 0.9 : (isTablet ? 1.0 : 1.1);
    final paddingScale = screenWidth < 500 ? 8.0 : 16.0;

    // Pantalla de carga inicial más estable
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Gestión de Canchas',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w600,
              color: _primaryColor,
              fontSize: 20 * textScale,
            ),
          ),
          backgroundColor: _backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back,
                color: _secondaryColor, size: 24 * textScale),
            onPressed: () {
              if (!_isDisposed && mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminDashboardScreen()),
                );
              }
            },
            tooltip: 'Volver al Dashboard',
          ),
        ),
        body: Container(
          color: _backgroundColor,
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                ),
                const SizedBox(height: 16),
                Text(
                  'Cargando...',
                  style: GoogleFonts.montserrat(
                    color: _primaryColor,
                    fontSize: 16 * textScale,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gestión de Canchas',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: _primaryColor,
            fontSize: 20 * textScale,
          ),
        ),
        backgroundColor: _backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: _secondaryColor, size: 24 * textScale),
          onPressed: () {
            if (!_isDisposed && mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const AdminDashboardScreen()),
              );
            }
          },
          tooltip: 'Volver al Dashboard',
        ),
      ),
      body: Container(
        color: _backgroundColor,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(paddingScale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header con botón
                Container(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Lista de Canchas',
                          style: GoogleFonts.montserrat(
                            fontSize: 24 * textScale,
                            fontWeight: FontWeight.w600,
                            color: _primaryColor,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _navigateToAddCancha,
                        icon: Icon(Icons.add_circle_outline,
                            color: Colors.white, size: 20 * textScale),
                        label: Text(
                          'Nueva Cancha',
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 16 * textScale,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryColor,
                          padding: EdgeInsets.symmetric(
                              horizontal: 20 * textScale, vertical: 12 * textScale),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 3,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: paddingScale),

                // Filtros
                Container(
                  width: double.infinity,
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: _cardColor),
                    ),
                    color: _cardColor,
                    child: Padding(
                      padding: EdgeInsets.all(paddingScale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filtros',
                            style: GoogleFonts.montserrat(
                              fontSize: 18 * textScale,
                              fontWeight: FontWeight.w600,
                              color: _primaryColor,
                            ),
                          ),
                          SizedBox(height: paddingScale),
                          _buildSedeFilter(textScale, paddingScale),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: paddingScale),

                // Lista principal
                Expanded(
                  child: Container(
                    width: double.infinity,
                    child: _buildMainContent(isDesktop, isTablet, textScale),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSedeFilter(double textScale, double paddingScale) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('canchas').snapshots(),
      builder: (context, snapshot) {
        if (_isDisposed) return const SizedBox.shrink();

        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: EdgeInsets.all(paddingScale),
            child: Text(
              'Error al cargar filtros: ${snapshot.error}',
              style: GoogleFonts.montserrat(
                color: Colors.redAccent,
                fontSize: 14 * textScale,
              ),
            ),
          );
        }

        // Mostrar filtro con datos en cache si están disponibles
        bool hasData = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        bool isLoading = snapshot.connectionState == ConnectionState.waiting;

        if (hasData) {
          final canchaDocs = snapshot.data!.docs;
          final sedesSet = <String>{};
          for (var doc in canchaDocs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final sede = data['sede']?.toString();
            if (sede != null && sede.isNotEmpty) {
              sedesSet.add(sede);
            }
          }
          _lastSedesData = sedesSet;
        }

        final sedesSet = _lastSedesData ?? <String>{};

        if (isLoading && sedesSet.isEmpty) {
          return Container(
            width: double.infinity,
            padding: EdgeInsets.all(paddingScale),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
              ),
            ),
          );
        }

        if (sedesSet.isEmpty) {
          return Container(
            width: double.infinity,
            padding: EdgeInsets.all(paddingScale),
            child: Text(
              'No hay sedes disponibles',
              style: GoogleFonts.montserrat(
                color: _primaryColor.withOpacity(0.7),
                fontSize: 14 * textScale,
              ),
            ),
          );
        }

        final sedes = ['Todas las sedes', ...sedesSet.toList()..sort()];

        return Container(
          width: double.infinity,
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Filtrar por Sede',
              labelStyle: GoogleFonts.montserrat(color: _primaryColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _cardColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _cardColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _secondaryColor),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 16 * textScale, vertical: 16 * textScale),
            ),
            value: _selectedSede.isNotEmpty ? _selectedSede : null,
            hint: Text(
              'Selecciona una sede',
              style: GoogleFonts.montserrat(color: _primaryColor),
            ),
            items: sedes
                .map((sede) => DropdownMenuItem(
                      value: sede == 'Todas las sedes' ? '' : sede,
                      child: Text(
                        sede,
                        style: GoogleFonts.montserrat(color: _primaryColor),
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              if (!_isDisposed && mounted) {
                setState(() {
                  _selectedSede = value ?? '';
                });
              }
            },
            icon: Icon(Icons.arrow_drop_down, color: _primaryColor),
            isExpanded: true,
            dropdownColor: _backgroundColor,
          ),
        );
      },
    );
  }

  Widget _buildMainContent(bool isDesktop, bool isTablet, double textScale) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildQuery().snapshots(),
      builder: (context, snapshot) {
        if (_isDisposed) return const SizedBox.shrink();

        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 60 * textScale),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: GoogleFonts.montserrat(
                        color: Colors.redAccent, fontSize: 16 * textScale),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        bool hasData = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        bool isLoading = snapshot.connectionState == ConnectionState.waiting;

        if (hasData) {
          _lastCanchasData = snapshot.data!.docs;
        }

        final canchaDocs = _lastCanchasData ?? [];

        if (isLoading && canchaDocs.isEmpty) {
          return Container(
            width: double.infinity,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cargando canchas...',
                    style: GoogleFonts.montserrat(
                      color: _primaryColor,
                      fontSize: 16 * textScale,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (canchaDocs.isEmpty) {
          return Container(
            width: double.infinity,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sports_soccer,
                      color: _primaryColor.withOpacity(0.5),
                      size: 70 * textScale),
                  const SizedBox(height: 16),
                  Text(
                    'No se encontraron canchas',
                    style: GoogleFonts.montserrat(
                      fontSize: 18 * textScale,
                      color: _primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Intenta con otro filtro o registra una nueva cancha',
                    style: GoogleFonts.montserrat(
                      fontSize: 14 * textScale,
                      color: _primaryColor.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            return (isDesktop || isTablet)
                ? _buildDataTable(canchaDocs, constraints.maxWidth, textScale)
                : _buildListView(canchaDocs, textScale);
          },
        );
      },
    );
  }

  Widget _buildDataTable(List<QueryDocumentSnapshot> canchaDocs,
      double maxWidth, double textScale) {
    
    final columnWidth = maxWidth / 5.0;
    final minColumnWidth = 100.0;
    final maxColumnWidth = columnWidth.clamp(minColumnWidth, 200.0);

    return Container(
      width: double.infinity,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _cardColor),
        ),
        color: _cardColor,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          physics: const ClampingScrollPhysics(),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(minWidth: maxWidth),
            child: DataTable(
              columnSpacing: 8,
              headingRowHeight: 56 * textScale,
              dataRowMinHeight: 60 * textScale,
              dataRowMaxHeight: 60 * textScale,
              headingTextStyle: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                color: _primaryColor,
                fontSize: 14 * textScale,
              ),
              dataTextStyle: GoogleFonts.montserrat(
                fontWeight: FontWeight.w500,
                color: _primaryColor,
                fontSize: 13 * textScale,
              ),
              columns: [
                DataColumn(
                  label: Container(
                    width: maxColumnWidth,
                    child: Text('Nombre', overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataColumn(
                  label: Container(
                    width: maxColumnWidth,
                    child: Text('Sede', overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataColumn(
                  label: Container(
                    width: maxColumnWidth,
                    child: Text('Descripción', overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataColumn(
                  label: Container(
                    width: maxColumnWidth * 0.8,
                    child: Text('Precio', overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataColumn(
                  label: Container(
                    width: maxColumnWidth * 0.8,
                    child: Text('Acciones', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              rows: canchaDocs.asMap().entries.map((entry) {
                final index = entry.key;
                final doc = entry.value;
                final data = doc.data() as Map<String, dynamic>? ?? {};
                return DataRow(
                  color: MaterialStateProperty.resolveWith<Color>(
                    (Set<MaterialState> states) {
                      return index % 2 == 0 ? _cardColor : _backgroundColor;
                    },
                  ),
                  cells: [
                    DataCell(
                      Container(
                        width: maxColumnWidth,
                        child: Text(
                          data['nombre']?.toString() ?? 'N/A',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        width: maxColumnWidth,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8 * textScale, vertical: 4 * textScale),
                          decoration: BoxDecoration(
                            color: _secondaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: _secondaryColor.withOpacity(0.2)),
                          ),
                          child: Text(
                            data['sede']?.toString() ?? 'N/A',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.montserrat(
                              color: _secondaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        width: maxColumnWidth,
                        child: Text(
                          data['descripcion']?.toString() ?? 'N/A',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        width: maxColumnWidth * 0.8,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8 * textScale, vertical: 4 * textScale),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border:
                                Border.all(color: Colors.green.withOpacity(0.2)),
                          ),
                          child: Text(
                            '\$${data['precio']?.toString() ?? 'N/A'}',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.montserrat(
                              color: Colors.green[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Editar cancha',
                            child: IconButton(
                              icon: Icon(
                                Icons.edit,
                                color: _secondaryColor,
                                size: 20 * textScale,
                              ),
                              onPressed: () {
                                _navigateToEditCancha(doc.id, Cancha.fromFirestore(doc));
                              },
                            ),
                          ),
                          Tooltip(
                            message: 'Eliminar cancha',
                            child: IconButton(
                              icon: Icon(
                                Icons.delete,
                                color: Colors.redAccent,
                                size: 20 * textScale,
                              ),
                              onPressed: () => _eliminarCancha(doc.id, context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListView(
      List<QueryDocumentSnapshot> canchaDocs, double textScale) {
    return Container(
      width: double.infinity,
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        itemCount: canchaDocs.length,
        itemBuilder: (context, index) {
          final doc = canchaDocs[index];
          final data = doc.data() as Map<String, dynamic>? ?? {};
          return Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: 12 * textScale),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _cardColor),
              ),
              color: _cardColor,
              child: ListTile(
                contentPadding: EdgeInsets.all(12 * textScale),
                title: Text(
                  data['nombre']?.toString() ?? 'N/A',
                  style: GoogleFonts.montserrat(
                    fontSize: 16 * textScale,
                    fontWeight: FontWeight.w600,
                    color: _primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 4 * textScale),
                    Text(
                      'Sede: ${data['sede']?.toString() ?? 'N/A'}',
                      style: GoogleFonts.montserrat(
                        fontSize: 14 * textScale,
                        color: _primaryColor.withOpacity(0.8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Descripción: ${data['descripcion']?.toString() ?? 'N/A'}',
                      style: GoogleFonts.montserrat(
                        fontSize: 14 * textScale,
                        color: _primaryColor.withOpacity(0.8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Precio: \$${data['precio']?.toString() ?? 'N/A'}',
                      style: GoogleFonts.montserrat(
                        fontSize: 14 * textScale,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.edit,
                        color: _secondaryColor,
                        size: 20 * textScale,
                      ),
                      onPressed: () {
                        _navigateToEditCancha(doc.id, Cancha.fromFirestore(doc));
                      },
                      tooltip: 'Editar cancha',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete,
                        color: Colors.redAccent,
                        size: 20 * textScale,
                      ),
                      onPressed: () => _eliminarCancha(doc.id, context),
                      tooltip: 'Eliminar cancha',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}