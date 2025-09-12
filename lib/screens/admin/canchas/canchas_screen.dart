import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/models/cancha.dart';
import 'package:reserva_canchas/providers/sede_provider.dart';
import 'editar_cancha_screen.dart';
import 'registrar_cancha_screen.dart';

class CanchasScreen extends StatefulWidget {
  const CanchasScreen({super.key});

  @override
  CanchasScreenState createState() => CanchasScreenState();
}

class CanchasScreenState extends State<CanchasScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  void _initializeScreen() {
    Future.microtask(() {
      if (mounted) {
        final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
        if (sedeProvider.sedes.isEmpty) {
          sedeProvider.fetchSedes();
        }
      }
    });
  }

  Future<void> _eliminarCancha(String canchaId, BuildContext context) async {
    if (!mounted) return;

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
              'Confirmar',
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

    if (confirm == true && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('canchas')
            .doc(canchaId)
            .delete();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cancha eliminada correctamente',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
            backgroundColor: _secondaryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al eliminar: $error',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    }
  }

  Future<void> _navigateToAddCancha() async {
    if (!mounted) return;

    await Navigator.push(
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

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _navigateToEditCancha(String canchaId, Cancha cancha) async {
    if (!mounted) return;

    await Navigator.push(
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

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    final isTablet = screenWidth >= 500 && screenWidth <= 900;
    final textScale = screenWidth < 500 ? 0.9 : (isTablet ? 1.0 : 1.1);
    final paddingScale = screenWidth < 500 ? 8.0 : 16.0;

    final sedeProvider = Provider.of<SedeProvider>(context);

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
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(paddingScale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                      icon: Icon(Icons.add_circle_outline, color: Colors.white, size: 20 * textScale),
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
                        padding: EdgeInsets.symmetric(horizontal: 20 * textScale, vertical: 12 * textScale),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: paddingScale),
                Card(
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
                        _buildSedeFilter(textScale, paddingScale, sedeProvider),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: paddingScale),
                Expanded(
                  child: _buildMainContent(isDesktop, isTablet, textScale, sedeProvider),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSedeFilter(double textScale, double paddingScale, SedeProvider sedeProvider) {
    return SizedBox(
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
          contentPadding: EdgeInsets.symmetric(horizontal: 16 * textScale, vertical: 16 * textScale),
        ),
        value: sedeProvider.selectedSede.isNotEmpty ? sedeProvider.sedeNames.firstWhere((name) => name == sedeProvider.selectedSede) : null,
        hint: Text(
          'Selecciona una sede',
          style: GoogleFonts.montserrat(color: _primaryColor),
        ),
        items: [
          const DropdownMenuItem(
            value: '',
            child: Text('Todas las sedes', style: TextStyle(color: Color(0xFF3C4043))),
          ),
          ...sedeProvider.sedes.map((sede) => DropdownMenuItem(
                value: sede['nombre'] as String,
                child: Text(sede['nombre'] as String, style: GoogleFonts.montserrat(color: _primaryColor)),
              )),
        ],
        onChanged: (value) {
          if (value != null && mounted) {
            sedeProvider.setSede(value);
            setState(() {});
          }
        },
        icon: Icon(Icons.arrow_drop_down, color: _primaryColor),
        isExpanded: true,
        dropdownColor: _backgroundColor,
      ),
    );
  }

  Widget _buildMainContent(bool isDesktop, bool isTablet, double textScale, SedeProvider sedeProvider) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('canchas')
          .where('sedeId', isEqualTo: sedeProvider.sedes.isNotEmpty && sedeProvider.selectedSede.isNotEmpty
              ? sedeProvider.sedes.firstWhere((s) => s['nombre'] == sedeProvider.selectedSede)['id']
              : null, // Si no hay filtro, no aplica where
          )
          .snapshots(),
      builder: (context, snapshot) {
        if (!mounted) return const SizedBox.shrink();

        if (snapshot.hasError) {
          return SizedBox(
            width: double.infinity,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.redAccent, size: 60 * textScale),
                  SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: GoogleFonts.montserrat(color: Colors.redAccent, fontSize: 16 * textScale),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        bool hasData = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        bool isLoading = snapshot.connectionState == ConnectionState.waiting;

        if (isLoading && !hasData) {
          return SizedBox(
            width: double.infinity,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor)),
                  SizedBox(height: 16),
                  Text(
                    'Cargando canchas...',
                    style: GoogleFonts.montserrat(color: _primaryColor, fontSize: 16 * textScale),
                  ),
                ],
              ),
            ),
          );
        }

        final canchaDocs = snapshot.data?.docs ?? [];

        if (canchaDocs.isEmpty) {
          return SizedBox(
            width: double.infinity,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sports_soccer, color: Color.fromRGBO(60, 64, 67, 0.5), size: 70 * textScale),
                  SizedBox(height: 16),
                  Text(
                    'No se encontraron canchas',
                    style: GoogleFonts.montserrat(fontSize: 18 * textScale, color: _primaryColor, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Intenta con otro filtro o registra una nueva cancha',
                    style: GoogleFonts.montserrat(fontSize: 14 * textScale, color: Color.fromRGBO(60, 64, 67, 0.8)),
                  ),
                ],
              ),
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            return (isDesktop || isTablet)
                ? _buildDataTable(canchaDocs, constraints.maxWidth, textScale, sedeProvider)
                : _buildListView(canchaDocs, textScale, sedeProvider);
          },
        );
      },
    );
  }

  Widget _buildDataTable(List<QueryDocumentSnapshot> canchaDocs, double maxWidth, double textScale, SedeProvider sedeProvider) {
    final columnWidth = maxWidth / 5.0;
    final minColumnWidth = 100.0;
    final maxColumnWidth = columnWidth.clamp(minColumnWidth, 200.0);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _cardColor),
      ),
      color: _cardColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          width: double.infinity,
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
              DataColumn(label: SizedBox(width: maxColumnWidth, child: Text('Nombre', overflow: TextOverflow.ellipsis))),
              DataColumn(label: SizedBox(width: maxColumnWidth, child: Text('Sede', overflow: TextOverflow.ellipsis))),
              DataColumn(label: SizedBox(width: maxColumnWidth, child: Text('Descripción', overflow: TextOverflow.ellipsis))),
              DataColumn(label: SizedBox(width: maxColumnWidth * 0.8, child: Text('Precio', overflow: TextOverflow.ellipsis))),
              DataColumn(label: SizedBox(width: maxColumnWidth * 0.8, child: Text('Acciones', overflow: TextOverflow.ellipsis))),
            ],
            rows: canchaDocs.asMap().entries.map((entry) {
              final index = entry.key;
              final doc = entry.value;
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final sedeId = data['sedeId']?.toString() ?? 'N/A';
              final sede = sedeProvider.sedes.firstWhere(
                (s) => s['id'] == sedeId,
                orElse: () => {'nombre': 'Sede desconocida'},
              );

              return DataRow(
                color: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) => index % 2 == 0 ? _cardColor : _backgroundColor,
                ),
                cells: [
                  DataCell(SizedBox(width: maxColumnWidth, child: Text(data['nombre']?.toString() ?? 'N/A', overflow: TextOverflow.ellipsis))),
                  DataCell(SizedBox(
                    width: maxColumnWidth,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8 * textScale, vertical: 4 * textScale),
                      decoration: BoxDecoration(
                        color: Color.fromRGBO(66, 133, 244, 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Color.fromRGBO(66, 133, 244, 0.2)),
                      ),
                      child: Text(sede['nombre'] as String, overflow: TextOverflow.ellipsis, style: GoogleFonts.montserrat(color: _secondaryColor, fontWeight: FontWeight.w500)),
                    ),
                  )),
                  DataCell(SizedBox(width: maxColumnWidth, child: Text(data['descripcion']?.toString() ?? 'N/A', overflow: TextOverflow.ellipsis))),
                  DataCell(SizedBox(
                    width: maxColumnWidth * 0.8,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8 * textScale, vertical: 4 * textScale),
                      decoration: BoxDecoration(
                        color: Color.fromRGBO(0, 128, 0, 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Color.fromRGBO(0, 128, 0, 0.2)),
                      ),
                      child: Text('\$${data['precio']?.toString() ?? 'N/A'}', overflow: TextOverflow.ellipsis, style: GoogleFonts.montserrat(color: Colors.green[700], fontWeight: FontWeight.w600)),
                    ),
                  )),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(message: 'Editar cancha', child: IconButton(
                        icon: Icon(Icons.edit, color: _secondaryColor, size: 20 * textScale),
                        onPressed: () => _navigateToEditCancha(doc.id, Cancha.fromFirestore(doc)),
                      )),
                      Tooltip(message: 'Eliminar cancha', child: IconButton(
                        icon: Icon(Icons.delete, color: Colors.redAccent, size: 20 * textScale),
                        onPressed: () => _eliminarCancha(doc.id, context),
                      )),
                    ],
                  )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildListView(List<QueryDocumentSnapshot> canchaDocs, double textScale, SedeProvider sedeProvider) {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      itemCount: canchaDocs.length,
      itemBuilder: (context, index) {
        final doc = canchaDocs[index];
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final sedeId = data['sedeId']?.toString() ?? 'N/A';
        final sede = sedeProvider.sedes.firstWhere(
          (s) => s['id'] == sedeId,
          orElse: () => {'nombre': 'Sede desconocida'},
        );

        return Container(
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
                style: GoogleFonts.montserrat(fontSize: 16 * textScale, fontWeight: FontWeight.w600, color: _primaryColor),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 4 * textScale),
                  Text('Sede: ${sede['nombre']}', style: GoogleFonts.montserrat(fontSize: 14 * textScale, color: Color.fromRGBO(60, 64, 67, 0.8)), overflow: TextOverflow.ellipsis),
                  Text('Descripción: ${data['descripcion']?.toString() ?? 'N/A'}', style: GoogleFonts.montserrat(fontSize: 14 * textScale, color: Color.fromRGBO(60, 64, 67, 0.8)), overflow: TextOverflow.ellipsis),
                  Text('Precio: \$${data['precio']?.toString() ?? 'N/A'}', style: GoogleFonts.montserrat(fontSize: 14 * textScale, color: Colors.green[700], fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit, color: _secondaryColor, size: 20 * textScale),
                    onPressed: () => _navigateToEditCancha(doc.id, Cancha.fromFirestore(doc)),
                    tooltip: 'Editar cancha',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.redAccent, size: 20 * textScale),
                    onPressed: () => _eliminarCancha(doc.id, context),
                    tooltip: 'Eliminar cancha',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}