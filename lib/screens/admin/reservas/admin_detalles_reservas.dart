import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/models/cancha.dart';
import 'package:reserva_canchas/providers/sede_provider.dart';
import 'package:reserva_canchas/utils/reserva_audit_utils.dart';

import '../../../models/reserva.dart';
import '../../../models/horario.dart';
import '../../../providers/peticion_provider.dart';
import 'editar_reserva_screen.dart'; // Importar la nueva pantalla de edición

class DetallesReservaScreen extends StatefulWidget {
  final Reserva reserva;

  const DetallesReservaScreen({super.key, required this.reserva});

  @override
  DetallesReservaScreenState createState() => DetallesReservaScreenState();
}

class DetallesReservaScreenState extends State<DetallesReservaScreen>
    with TickerProviderStateMixin {
  late Reserva _currentReserva;
  Map<String, dynamic>? _grupoInfo;
  bool _isGrupoReserva = false;
  bool _esSuperAdmin = false;
  bool _esAdmin = false;

  late AnimationController _fadeController;
  bool _isLoading = true;
  bool _dataLoaded = false;
  double? _montoTotalCalculado;

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,##0', 'es_CO');
    return 'COP ${formatter.format(amount)}';
  }

  @override
  void initState() {
  super.initState();
  _currentReserva = widget.reserva;
  
  _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  // Iniciar escucha del control total
  final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
  peticionProvider.iniciarEscuchaControlTotal();

  _initializeData();
}

  Future<void> _initializeData() async {
    try {
      await Future.wait([
        _verificarRolUsuario(),
        _cargarInformacionGrupo(),
      ]).timeout(const Duration(seconds: 15));
      
      _montoTotalCalculado = await _calcularMontoTotal(_currentReserva);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dataLoaded = true;
        });
        
        _fadeController.forward();
      }
    } catch (e) {
      debugPrint('Error inicializando datos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dataLoaded = true;
        });
        _fadeController.forward();
      }
    }
  }

  AppBar buildAppBar() {
  // Obtener el estado del control total del provider
  final peticionProvider = Provider.of<PeticionProvider>(context);
  final controlTotalActivado = peticionProvider.controlTotalActivado;
  
  return AppBar(
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isGrupoReserva ? 'Reserva Grupal - Detalles' : 'Detalles de la Reserva',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ],
    ),
    backgroundColor: _backgroundColor,
    elevation: 0,
    foregroundColor: _primaryColor,
    actions: [
      // Indicadores de rol
      if (_esSuperAdmin)
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple.withOpacity(0.3)),
          ),
          child: Text(
            'SUPER',
            style: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.purple[700],
            ),
          ),
        )
      else if (_esAdmin)
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Text(
            'ADMIN',
            style: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.orange[700],
            ),
          ),
        ),
      
      // Botón de editar
      IconButton(
        icon: const Icon(Icons.edit),
        color: _secondaryColor,
        onPressed: _navigateToEditScreen,
        tooltip: 'Editar reserva',
      ),
      
      // Botón de eliminar - Lógica de visibilidad:
      // - SuperAdmin: Siempre visible (sin restricciones)
      // - Admin: Solo visible cuando control total está activado
      if (_esSuperAdmin || (_esAdmin && controlTotalActivado))
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.redAccent),
          onPressed: _deleteReserva,
          tooltip: 'Eliminar',
        ),
    ],
  );
}


  // Navegar a la pantalla de edición
  Future<void> _navigateToEditScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarReservaScreen(
          reserva: _currentReserva,
          grupoInfo: _grupoInfo,
          isGrupoReserva: _isGrupoReserva,
          esSuperAdmin: _esSuperAdmin,
          esAdmin: _esAdmin,
        ),
      ),
    );
    
    // Si se realizaron cambios, actualizar la vista
    if (result == true) {
      // Recargar datos de la reserva
      final doc = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reserva.id)
          .get();
      
      if (doc.exists && mounted) {
        // Aquí podrías actualizar _currentReserva con los nuevos datos
        _initializeData(); // Recargar todos los datos
      }
    }
  }

  Future<void> _verificarRolUsuario() async {
    try {
      final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
      
      final results = await Future.wait([
        peticionProvider.esSuperAdmin(),
        peticionProvider.esAdmin(),
      ]).timeout(const Duration(seconds: 5));
      
      if (mounted) {
        setState(() {
          _esSuperAdmin = results[0];
          _esAdmin = results[1];
        });
      }
    } catch (e) {
      debugPrint('Error verificando rol: $e');
      if (mounted) {
        setState(() {
          _esSuperAdmin = false;
          _esAdmin = false;
        });
      }
    }
  }

  Future<double> _calcularMontoTotal(Reserva reserva) async {
    debugPrint('--- Calculando monto total ---');
    final day = DateFormat('EEEE', 'es').format(reserva.fecha).toLowerCase();
    
    Cancha cancha = reserva.cancha;
    if (cancha.preciosPorHorario.isEmpty || cancha.precio == 0) {
      try {
        final canchaDoc = await FirebaseFirestore.instance
            .collection('canchas')
            .doc(reserva.cancha.id)
            .get();
        if (canchaDoc.exists) {
          cancha = Cancha.fromFirestore(canchaDoc);
        }
      } catch (e) {
        debugPrint('Error al cargar cancha: $e');
      }
    }

    double montoTotal = 0.0;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(reserva.id)
          .get();

      List<String> horarios = [];
      if (doc.exists && doc.data() != null) {
        final data = doc.data();
        horarios = (data?['horarios'] as List<dynamic>?)?.cast<String>() ?? [reserva.horario.horaFormateada];
      } else {
        horarios = [reserva.horario.horaFormateada];
      }

      for (var horarioStr in horarios) {
        try {
          final time = DateFormat('h:mm a').parse(horarioStr);
          final horario = Horario(hora: TimeOfDay(hour: time.hour, minute: time.minute));
          final precio = Reserva.calcularMontoTotal(cancha, reserva.fecha, horario);
          montoTotal += precio;
        } catch (e) {
          debugPrint('Error al parsear hora: $horarioStr, error: $e');
          montoTotal += cancha.precio;
        }
      }
    } catch (e) {
      debugPrint('Error Firestore: $e');
      montoTotal = Reserva.calcularMontoTotal(cancha, reserva.fecha, reserva.horario);
    }

    return montoTotal;
  }

  Future<void> _cargarInformacionGrupo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reserva.id)
          .get()
          .timeout(const Duration(seconds: 5));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final grupoId = data['grupo_reserva_id'] as String?;
        
        if (grupoId != null && grupoId.isNotEmpty) {
          if (mounted) {
            setState(() {
              _isGrupoReserva = true;
            });
          }
          
          final grupoQuery = await FirebaseFirestore.instance
              .collection('reservas')
              .where('grupo_reserva_id', isEqualTo: grupoId)
              .get()
              .timeout(const Duration(seconds: 5));
          
          if (grupoQuery.docs.isNotEmpty && mounted) {
            List<Map<String, dynamic>> reservasGrupo = [];
            double totalGrupo = 0;
            double totalPagadoGrupo = 0;
            double totalDescuentoGrupo = 0;
            double totalOriginalGrupo = 0;
            
            for (var reservaDoc in grupoQuery.docs) {
              final reservaData = reservaDoc.data();
              reservasGrupo.add({
                'id': reservaDoc.id,
                'horario': reservaData['horario'] ?? '',
                'valor': (reservaData['valor'] as num?)?.toDouble() ?? 0.0,
                'montoPagado': (reservaData['montoPagado'] as num?)?.toDouble() ?? 0.0,
                'descuento_aplicado': (reservaData['descuento_aplicado'] as num?)?.toDouble() ?? 0.0,
                'precio_original': (reservaData['precio_original'] as num?)?.toDouble() ?? 0.0,
                'estado': reservaData['estado'] ?? '',
              });
              
              totalGrupo += (reservaData['valor'] as num?)?.toDouble() ?? 0.0;
              totalPagadoGrupo += (reservaData['montoPagado'] as num?)?.toDouble() ?? 0.0;
              totalDescuentoGrupo += (reservaData['descuento_aplicado'] as num?)?.toDouble() ?? 0.0;
              totalOriginalGrupo += (reservaData['precio_original'] as num?)?.toDouble() ?? 0.0;
            }
            
            reservasGrupo.sort((a, b) {
              try {
                final timeA = DateFormat('h:mm a').parse(a['horario']);
                final timeB = DateFormat('h:mm a').parse(b['horario']);
                return timeA.compareTo(timeB);
              } catch (e) {
                return a['horario'].compareTo(b['horario']);
              }
            });
            
            setState(() {
              _grupoInfo = {
                'grupo_id': grupoId,
                'reservas': reservasGrupo,
                'total_grupo': totalGrupo,
                'total_pagado_grupo': totalPagadoGrupo,
                'total_descuento_grupo': totalDescuentoGrupo,
                'total_original_grupo': totalOriginalGrupo,
                'cantidad_reservas': reservasGrupo.length,
              };
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error cargando información del grupo: $e');
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.montserrat(),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.montserrat(),
        ),
        backgroundColor: _secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteReserva() async {
  // Mostrar diálogo con campo opcional para motivo
  String? motivo;
  bool? confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      final TextEditingController motivoController = TextEditingController();
      
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Eliminar Reserva',
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _primaryColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Estás seguro que deseas eliminar esta reserva?',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                color: _primaryColor,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Esta acción no se puede deshacer y será registrada en el sistema de auditoría.',
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: motivoController,
              decoration: InputDecoration(
                labelText: 'Motivo (opcional)',
                hintText: 'Ej: Cancelación del cliente, error en reserva...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (value) => motivo = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              motivo = motivoController.text.trim();
              Navigator.of(context).pop(true);
            },
            child: Text(
              'Eliminar',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    },
  );

  if (confirm != true) return;

  try {
    // 🔍 OBTENER DATOS ACTUALES ANTES DE ELIMINAR PARA AUDITORÍA
    final datosReservaParaAuditoria = {
      'nombre': widget.reserva.nombre,
      'telefono': widget.reserva.telefono,
      'correo': widget.reserva.email,
      'fecha': DateFormat('yyyy-MM-dd').format(widget.reserva.fecha),
      'horario': widget.reserva.horario.horaFormateada,
      'montoTotal': widget.reserva.montoTotal,
      'montoPagado': widget.reserva.montoPagado,
      'cancha_nombre': widget.reserva.cancha.nombre,
      'cancha_id': widget.reserva.cancha.id,
      'sede': widget.reserva.sede,
      'estado': widget.reserva.tipoAbono.toString(),
      'confirmada': widget.reserva.confirmada,
      'precio_personalizado': widget.reserva.precioPersonalizado ?? false,
      'precio_original': widget.reserva.precioOriginal,
      'descuento_aplicado': widget.reserva.descuentoAplicado,
    };

    // Eliminar de Firestore
    await FirebaseFirestore.instance
        .collection('reservas')
        .doc(widget.reserva.id)
        .delete();

    // 🔍 AUDITORÍA AUTOMÁTICA - Registrar eliminación
    await ReservaAuditUtils.auditarEliminacionReserva(
      reservaId: widget.reserva.id,
      datosReserva: datosReservaParaAuditoria,
      motivo: motivo?.isNotEmpty == true ? motivo : 'Eliminación desde pantalla de edición',
    );

    if (!mounted) return;

    _mostrarExito('Reserva eliminada con éxito.');
    Navigator.of(context).pop(true);
  } catch (e) {
    debugPrint('Error al eliminar la reserva: $e');
    if (!mounted) return;
    _mostrarError('Error al eliminar la reserva: $e');
  }
}




  Widget _buildGrupoInfoCard() {
    if (!_isGrupoReserva || _grupoInfo == null) return const SizedBox.shrink();
    
    final grupoInfo = _grupoInfo!;
    final reservas = grupoInfo['reservas'] as List<Map<String, dynamic>>;
    final totalGrupo = grupoInfo['total_grupo'] as double;
    final totalPagadoGrupo = grupoInfo['total_pagado_grupo'] as double;
    final pendiente = totalGrupo - totalPagadoGrupo;
    
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.blue.withOpacity(0.2), width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.withOpacity(0.03),
              Colors.white,
              Colors.blue.withOpacity(0.01),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header mejorado
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.group,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reserva Grupal',
                            style: GoogleFonts.montserrat(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue[800],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${grupoInfo['cantidad_reservas']} horas consecutivas',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'ID: ${grupoInfo['grupo_id'].toString().substring(0, 8)}...',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Resumen financiero mejorado
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          color: _primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Resumen Financiero',
                          style: GoogleFonts.montserrat(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    if (grupoInfo['total_original_grupo'] > 0) ...[
                      _buildFinancialRow(
                        'Precio original:',
                        _formatCurrency(grupoInfo['total_original_grupo']),
                        Colors.grey[600]!,
                        isStrikethrough: grupoInfo['total_descuento_grupo'] > 0,
                      ),
                      if (grupoInfo['total_descuento_grupo'] > 0)
                        _buildFinancialRow(
                          'Descuento aplicado:',
                          '- ${_formatCurrency(grupoInfo['total_descuento_grupo'])}',
                          Colors.green[600]!,
                          icon: Icons.local_offer,
                        ),
                      const Divider(height: 20),
                    ],
                    
                    _buildFinancialRow(
                      'Total del grupo:',
                      _formatCurrency(totalGrupo),
                      _primaryColor,
                      isLarge: true,
                      icon: Icons.calculate,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: pendiente > 0 
                            ? Colors.orange.withOpacity(0.1)
                            : Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: pendiente > 0 
                              ? Colors.orange.withOpacity(0.3)
                              : Colors.green.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildFinancialRow(
                            'Total pagado:',
                            _formatCurrency(totalPagadoGrupo),
                            Colors.green[700]!,
                            icon: Icons.payments,
                          ),
                          const SizedBox(height: 8),
                          _buildFinancialRow(
                            'Pendiente por pagar:',
                            _formatCurrency(pendiente),
                            pendiente > 0 ? Colors.orange[700]! : Colors.green[700]!,
                            icon: pendiente > 0 ? Icons.pending : Icons.check_circle,
                            isLarge: pendiente > 0,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Lista de horas
              Text(
                'Detalles por hora:',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 12),
              
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: reservas.length,
                  itemBuilder: (context, index) {
                    final reserva = reservas[index];
                    final isCurrentReserva = reserva['id'] == widget.reserva.id;
                    final isPagadoCompleto = reserva['montoPagado'] >= reserva['valor'];
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isCurrentReserva 
                            ? Colors.blue.withOpacity(0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isCurrentReserva 
                              ? Colors.blue.withOpacity(0.4)
                              : Colors.grey.withOpacity(0.2),
                          width: isCurrentReserva ? 2 : 1,
                        ),
                        boxShadow: isCurrentReserva ? [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ] : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            if (isCurrentReserva)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            if (isCurrentReserva) const SizedBox(width: 12),
                            
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 18,
                                        color: isCurrentReserva ? Colors.blue : _primaryColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        reserva['horario'],
                                        style: GoogleFonts.montserrat(
                                          fontSize: 16,
                                          fontWeight: isCurrentReserva 
                                              ? FontWeight.w700 
                                              : FontWeight.w600,
                                          color: isCurrentReserva ? Colors.blue : _primaryColor,
                                        ),
                                      ),
                                      if (isCurrentReserva) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'ACTUAL',
                                            style: GoogleFonts.montserrat(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Valor: ${_formatCurrency(reserva['valor'])}',
                                          style: GoogleFonts.montserrat(
                                            fontSize: 13,
                                            color: _primaryColor.withOpacity(0.8),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Pagado: ${_formatCurrency(reserva['montoPagado'])}',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: isPagadoCompleto 
                                              ? Colors.green[600] 
                                              : Colors.orange[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isPagadoCompleto 
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isPagadoCompleto ? Icons.check_circle : Icons.pending,
                                    size: 14,
                                    color: isPagadoCompleto 
                                        ? Colors.green[700] 
                                        : Colors.orange[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isPagadoCompleto ? 'Completo' : 'Pendiente',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isPagadoCompleto 
                                          ? Colors.green[700] 
                                          : Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialRow(String label, String value, Color color, {
    IconData? icon,
    bool isLarge = false,
    bool isStrikethrough = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: isLarge ? 16 : 14,
                fontWeight: isLarge ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: isLarge ? 16 : 14,
              fontWeight: FontWeight.w700,
              color: color,
              decoration: isStrikethrough ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
void dispose() {
  _fadeController.dispose();
  // Detener escucha del control total
  final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
  peticionProvider.detenerEscuchaControlTotal();
  super.dispose();
}

  @override
Widget build(BuildContext context) {
  return Consumer<PeticionProvider>(
    builder: (context, peticionProvider, child) {
      return Localizations(
        locale: const Locale('es', 'ES'),
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        child: Scaffold(
          appBar: buildAppBar(),
          body: Container(
            color: _backgroundColor,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ListView(
                      children: [
                        if (_isGrupoReserva) ...[
                          _buildGrupoInfoCard()
                              .animate()
                              .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                              .slideY(
                                  begin: -0.2,
                                  end: 0,
                                  duration: 600.ms,
                                  curve: Curves.easeOutQuad),
                          const SizedBox(height: 16),
                        ],
                        _buildInfoCard()
                            .animate()
                            .fadeIn(duration: 600.ms, curve: Curves.easeOutQuad)
                            .slideY(
                                begin: -0.2,
                                end: 0,
                                duration: 600.ms,
                                curve: Curves.easeOutQuad),
                        const SizedBox(height: 16),
                        _buildClientInfoCard()
                            .animate()
                            .fadeIn(
                                duration: 600.ms,
                                delay: 200.ms,
                                curve: Curves.easeOutQuad)
                            .slideY(
                              begin: -0.2,
                              end: 0,
                              duration: 600.ms,
                              delay: 200.ms,
                              curve: Curves.easeOutQuad,
                            ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    },
  );
}

  Widget _buildInfoCard() {
    final reserva = _currentReserva;
    return FutureBuilder<double>(
      future: _calcularMontoTotal(reserva),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 2,
            color: _cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return Card(
            elevation: 2,
            color: _cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error: ${snapshot.error}',
                style: GoogleFonts.montserrat(color: Colors.redAccent),
              ),
            ),
          );
        }

        final montoTotal = snapshot.data ?? 0.0;
        
        return Card(
          elevation: 2,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _cardColor,
                  Colors.white,
                  _cardColor,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _secondaryColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.info_outline,
                          color: _secondaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Información de la Reserva',
                          style: GoogleFonts.montserrat(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  _buildInfoRow(
                    icon: Icons.sports_soccer,
                    label: 'Cancha',
                    value: reserva.cancha.nombre,
                  ),
                  const SizedBox(height: 12),
                  
                  _buildInfoRow(
                    icon: Icons.location_on,
                    label: 'Sede',
                    value: Provider.of<SedeProvider>(context, listen: false).sedes.firstWhere(
                      (sede) => sede['id'] == reserva.sede,
                      orElse: () => {'nombre': reserva.sede},
                    )['nombre'] as String,
                  ),
                  const SizedBox(height: 12),
                  
                  _buildInfoRow(
                    icon: Icons.calendar_today,
                    label: 'Fecha',
                    value: DateFormat('EEEE d MMMM, yyyy', 'es').format(reserva.fecha),
                  ),
                  const SizedBox(height: 12),
                  
                  _buildInfoRow(
                    icon: Icons.access_time,
                    label: 'Horario',
                    value: reserva.horario.horaFormateada,
                  ),
                  const SizedBox(height: 20),
                  
                  // Valor total con diseño especial
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _secondaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _secondaryColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _secondaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.monetization_on,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Valor Total',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _primaryColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatCurrency(montoTotal),
                                style: GoogleFonts.montserrat(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _secondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: _secondaryColor,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClientInfoCard() {
    final reserva = _currentReserva;
    
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.withOpacity(0.05),
              Colors.white,
              Colors.green.withOpacity(0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Información del Cliente',
                      style: GoogleFonts.montserrat(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              _buildClientInfoRow(
                icon: Icons.person_outline,
                label: 'Nombre',
                value: reserva.nombre ?? 'No especificado',
              ),
              const SizedBox(height: 12),
              
              _buildClientInfoRow(
                icon: Icons.phone_outlined,
                label: 'Teléfono',
                value: reserva.telefono ?? 'No especificado',
              ),
              const SizedBox(height: 12),
              
              _buildClientInfoRow(
                icon: Icons.email_outlined,
                label: 'Correo',
                value: reserva.email ?? 'No especificado',
              ),
              const SizedBox(height: 20),
              
              // Información de pago
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: reserva.tipoAbono == TipoAbono.completo
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: reserva.tipoAbono == TipoAbono.completo
                        ? Colors.green.withOpacity(0.3)
                        : Colors.orange.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: reserva.tipoAbono == TipoAbono.completo
                                ? Colors.green.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            reserva.tipoAbono == TipoAbono.completo
                                ? Icons.check_circle
                                : Icons.pending,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Estado de Pago',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _primaryColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                reserva.tipoAbono == TipoAbono.completo
                                    ? 'Completo'
                                    : 'Pendiente',
                                style: GoogleFonts.montserrat(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: reserva.tipoAbono == TipoAbono.completo
                                      ? Colors.green[700]
                                      : Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Abono',
                                style: GoogleFonts.montserrat(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _primaryColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatCurrency(reserva.montoPagado),
                                style: GoogleFonts.montserrat(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.green,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  }