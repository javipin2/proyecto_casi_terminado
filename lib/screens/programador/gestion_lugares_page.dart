import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../providers/lugar_provider.dart';
import '../../providers/ciudad_provider.dart';
import '../../models/lugar.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/image_upload_service.dart';
import 'dart:typed_data';

class GestionLugaresPage extends StatefulWidget {
  const GestionLugaresPage({super.key});

  @override
  State<GestionLugaresPage> createState() => _GestionLugaresPageState();
}

enum PagoEstadoLugar {
  ok,
  avisoPre,
  avisoVencido,
  avisoUltimoDia,
  bloqueado,
}

class _GestionLugaresPageState extends State<GestionLugaresPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String? _ciudadFiltro;
  String? _planFiltro;

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
                // Header con filtros y botón de agregar
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
                                Icons.storefront_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Gestión de Lugares',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Administra los lugares por ciudad y plan contratado.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFE5F4EF),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isMobile) ...[
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: () => _mostrarDialogoCrearLugar(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Agregar Lugar'),
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
                        Consumer<CiudadProvider>(
                          builder: (context, ciudadProvider, child) {
                            final filtros = Column(
                              children: [
                                DropdownButtonFormField<String>(
                                  value: _ciudadFiltro,
                                  decoration: InputDecoration(
                                    labelText: 'Filtrar por Ciudad',
                                    floatingLabelBehavior:
                                        FloatingLabelBehavior.never,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    prefixIcon:
                                        const Icon(Icons.location_city),
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
                                        .map((ciudad) => DropdownMenuItem(
                                              value: ciudad.id,
                                              child: Text(ciudad.nombre),
                                            )),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _ciudadFiltro = value;
                                    });
                                    if (value != null) {
                                      Provider.of<LugarProvider>(context, listen: false)
                                          .fetchLugaresPorCiudad(value);
                                    } else {
                                      Provider.of<LugarProvider>(context, listen: false)
                                          .fetchTodosLosLugares();
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: _planFiltro,
                                  decoration: InputDecoration(
                                    labelText: 'Filtrar por Plan',
                                    floatingLabelBehavior:
                                        FloatingLabelBehavior.never,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    prefixIcon:
                                        const Icon(Icons.workspace_premium),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: null,
                                      child: Text('Todos los planes'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'basico',
                                      child: Text('Plan Básico'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'premium',
                                      child: Text('Plan Premium'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'pro',
                                      child: Text('Plan Pro'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'prueba',
                                      child: Text('Plan Prueba'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _planFiltro = value;
                                    });
                                  },
                                ),
                              ],
                            );

                            if (isMobile) {
                              return filtros;
                            }

                            final children = List<Widget>.from(filtros.children);
                            return Row(
                              children: [
                                Expanded(child: children[0]),
                                const SizedBox(width: 12),
                                Expanded(child: children[2]),
                              ],
                            );
                          },
                        ),
                        if (isMobile) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _mostrarDialogoCrearLugar(),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Agregar Lugar'),
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
                      ],
                    ),
                  ),
                ),

                // Lista de lugares
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
                        child: Consumer<LugarProvider>(
                          builder: (context, lugarProvider, child) {
                            if (lugarProvider.isLoading) {
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
                                      'Cargando lugares...',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (lugarProvider.errorMessage != null) {
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
                                      lugarProvider.errorMessage!,
                                      style: const TextStyle(fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () {
                                        if (_ciudadFiltro != null) {
                                          lugarProvider.fetchLugaresPorCiudad(
                                              _ciudadFiltro!);
                                        } else {
                                          lugarProvider.fetchTodosLosLugares();
                                        }
                                      },
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

                            if (lugarProvider.lugares.isEmpty) {
                              return const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No hay lugares registrados',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final lugaresFiltrados =
                                _aplicarFiltroPlan(lugarProvider.lugares);

                            if (lugaresFiltrados.isEmpty) {
                              return const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.place_outlined,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No hay lugares para el plan seleccionado',
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
                              onRefresh: () {
                                if (_ciudadFiltro != null) {
                                  return lugarProvider
                                      .fetchLugaresPorCiudad(_ciudadFiltro!);
                                } else {
                                  return lugarProvider.fetchTodosLosLugares();
                                }
                              },
                              color: const Color(0xFF2E7D60),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: lugaresFiltrados.length,
                                itemBuilder: (context, index) {
                                  final lugar = lugaresFiltrados[index];
                                  return _buildLugarCard(lugar, index);
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

  List<Lugar> _aplicarFiltroPlan(List<Lugar> lugares) {
    if (_planFiltro == null || _planFiltro!.isEmpty) {
      return lugares;
    }
    final filtro = _planFiltro!.toLowerCase();
    return lugares
        .where((lugar) => (lugar.plan ?? '').toLowerCase() == filtro)
        .toList();
  }

  Color _getColorPlan(String? plan) {
    switch ((plan ?? '').toLowerCase()) {
      case 'basico':
        return const Color(0xFF4CAF50); // verde
      case 'premium':
        return const Color(0xFF1976D2); // azul
      case 'pro':
        return const Color(0xFF9C27B0); // morado
      case 'prueba':
        return const Color(0xFFFFA000); // naranja
      default:
        return Colors.grey.shade400;
    }
  }

  String _getNombrePlan(String? plan) {
    switch ((plan ?? '').toLowerCase()) {
      case 'basico':
        return 'Plan Básico';
      case 'premium':
        return 'Plan Premium';
      case 'pro':
        return 'Plan Pro';
      case 'prueba':
        return 'Plan Prueba';
      default:
        return 'Plan sin definir';
    }
  }

  String _formatearFecha(DateTime fecha) {
    return DateFormat('dd/MM/yyyy').format(fecha);
  }

  PagoEstadoLugar? _getPagoEstadoLugar(Lugar lugar) {
    if (lugar.plan == null ||
        lugar.planInicio == null ||
        lugar.planValorMensual == null) {
      return null;
    }

    final inicio = lugar.planInicio!;
    final ultimoPago = lugar.planUltimoPago;
    final ahora = DateTime.now();
    final today = DateTime(ahora.year, ahora.month, ahora.day);

    final baseDay = inicio.day;

    DateTime ref = inicio;
    if (ultimoPago != null && ultimoPago.isAfter(ref)) {
      ref = ultimoPago;
    }

    int year = ref.year;
    int month = ref.month + 1;
    if (month > 12) {
      month = 1;
      year++;
    }
    final maxDay = DateUtils.getDaysInMonth(year, month);
    final day = baseDay <= maxDay ? baseDay : maxDay;
    final DateTime due = DateTime(year, month, day);

    final diffDays = today.difference(due).inDays;

    if (diffDays == -1) {
      return PagoEstadoLugar.avisoPre;
    } else if (diffDays == 0) {
      return PagoEstadoLugar.avisoVencido;
    } else if (diffDays == 1) {
      return PagoEstadoLugar.avisoUltimoDia;
    } else if (diffDays >= 2) {
      return PagoEstadoLugar.bloqueado;
    } else {
      return PagoEstadoLugar.ok;
    }
  }

  Widget _buildLugarCard(Lugar lugar, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        final planColor = _getColorPlan(lugar.plan);
        final pagoEstado = _getPagoEstadoLugar(lugar);

        Color cardColor = planColor.withOpacity(0.05);
        Color avatarBg = planColor.withOpacity(lugar.activo ? 0.25 : 0.12);
        BorderSide? borderSide;

        if (pagoEstado == PagoEstadoLugar.bloqueado) {
          cardColor = Colors.red.shade50;
          avatarBg = Colors.red.shade100;
          borderSide = BorderSide(color: Colors.red.shade300, width: 1.2);
        } else if (pagoEstado == PagoEstadoLugar.avisoPre ||
            pagoEstado == PagoEstadoLugar.avisoVencido ||
            pagoEstado == PagoEstadoLugar.avisoUltimoDia) {
          cardColor = const Color(0xFFFFF7E6); // tono amarillento de advertencia
          avatarBg = Colors.orange.shade100;
          borderSide = BorderSide(color: Colors.orange.shade300, width: 1);
        }

        return Transform.scale(
          scale: scale,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: borderSide ?? BorderSide.none,
            ),
            color: cardColor,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: avatarBg,
                child: Icon(
                  Icons.location_on,
                  color: planColor,
                ),
              ),
              title: Text(
                lugar.nombre,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lugar.direccion),
                  Text('Tel: ${lugar.telefono}'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(_getNombrePlan(lugar.plan)),
                        backgroundColor: planColor.withOpacity(0.15),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      if (lugar.planInicio != null)
                        Chip(
                          avatar: const Icon(
                            Icons.calendar_today,
                            size: 16,
                          ),
                          label: Text(
                            'Inicio: ${_formatearFecha(lugar.planInicio!)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: Colors.blue.shade50,
                        ),
                      if (lugar.planValorMensual != null)
                        Chip(
                          avatar: const Icon(
                            Icons.attach_money,
                            size: 16,
                          ),
                          label: Text(
                            'Mensual: \$${lugar.planValorMensual!.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: Colors.green.shade50,
                        ),
                      if (pagoEstado != null &&
                          pagoEstado != PagoEstadoLugar.ok)
                        Chip(
                          avatar: Icon(
                            pagoEstado == PagoEstadoLugar.bloqueado
                                ? Icons.block
                                : Icons.warning_amber_rounded,
                            size: 16,
                            color: pagoEstado == PagoEstadoLugar.bloqueado
                                ? Colors.red.shade700
                                : Colors.orange.shade700,
                          ),
                          label: Text(
                            () {
                              switch (pagoEstado) {
                                case PagoEstadoLugar.avisoPre:
                                  return 'Próximo vencimiento';
                                case PagoEstadoLugar.avisoVencido:
                                  return 'Pago vencido';
                                case PagoEstadoLugar.avisoUltimoDia:
                                  return 'En mora (último día)';
                                case PagoEstadoLugar.bloqueado:
                                  return 'Bloqueado por falta de pago';
                                case PagoEstadoLugar.ok:
                                default:
                                  return '';
                              }
                            }(),
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor:
                              pagoEstado == PagoEstadoLugar.bloqueado
                                  ? Colors.red.shade50
                                  : Colors.orange.shade50,
                        ),
                    ],
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: lugar.activo,
                    onChanged: (value) {
                      Provider.of<LugarProvider>(context, listen: false)
                          .activarDesactivarLugar(lugar.id, value);
                    },
                    activeColor: const Color(0xFF2E7D60),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _mostrarDialogoEditarLugar(lugar);
                      } else if (value == 'delete') {
                        _mostrarDialogoEliminarLugar(lugar);
                      } else if (value == 'pago') {
                        _registrarPagoLugar(lugar);
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
                        value: 'pago',
                        child: Row(
                          children: [
                            Icon(Icons.attach_money, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Registrar pago mensual'),
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

  Future<void> _registrarPagoLugar(Lugar lugar) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar pago mensual'),
        content: Text(
          '¿Confirmas que el lugar "${lugar.nombre}" ha pagado su mensualidad?\n\n'
          'Se reiniciará el ciclo de cobro usando la fecha de hoy como nueva fecha de inicio del plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D60),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar pago'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await Provider.of<LugarProvider>(context, listen: false).actualizarLugar(
        lugar.id,
        {
          // No cambiamos la fecha base del plan (planInicio),
          // solo registramos cuándo se pagó para mover el próximo ciclo.
          'planUltimoPago': Timestamp.now(),
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pago registrado para "${lugar.nombre}".'),
          backgroundColor: const Color(0xFF2E7D60),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar pago: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _mostrarDialogoCrearLugar() {
    final rootContext = context; // usar contexto de la página, no el del diálogo
    final nombreController = TextEditingController();
    final direccionController = TextEditingController();
    final telefonoController = TextEditingController();
    String? ciudadSeleccionada;
    String? planSeleccionado;
    DateTime? fechaInicioPlan;
    final valorPlanController = TextEditingController();
    final maxSedesController = TextEditingController();
    final maxCanchasController = TextEditingController();
    XFile? imagenSeleccionada;
    Uint8List? imagenPreviewBytes;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Crear Nuevo Lugar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Consumer<CiudadProvider>(
                      builder: (context, ciudadProvider, child) {
                        final ciudades = ciudadProvider.ciudades;
                        final items = ciudades.map((ciudad) => DropdownMenuItem(
                              value: ciudad.id,
                              child: Text(ciudad.nombre),
                            )).toList();
                        final selected = items.any((i) => i.value == ciudadSeleccionada) ? ciudadSeleccionada : null;
                        return DropdownButtonFormField<String>(
                          value: selected,
                          decoration: const InputDecoration(
                            labelText: 'Ciudad',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_city),
                          ),
                          items: items,
                          onChanged: (value) => setState(() => ciudadSeleccionada = value),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        Icon(Icons.image, color: Color(0xFF2E7D60)),
                        SizedBox(width: 8),
                        Text('Imagen de portada (opcional)'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 140,
                        color: Colors.grey[200],
                        child: imagenPreviewBytes != null
                            ? Image.memory(imagenPreviewBytes!, fit: BoxFit.cover, width: double.infinity)
                            : const Center(child: Icon(Icons.image, color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await ImageUploadService.pickImage();
                          if (picked != null) {
                            final bytes = await picked.readAsBytes();
                            setState(() {
                              imagenSeleccionada = picked;
                              imagenPreviewBytes = bytes;
                            });
                          }
                        },
                        icon: const Icon(Icons.upload),
                        label: Text(imagenPreviewBytes == null ? 'Seleccionar imagen' : 'Cambiar imagen'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nombreController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del Lugar',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: direccionController,
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: telefonoController,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: planSeleccionado,
                      decoration: const InputDecoration(
                        labelText: 'Plan del lugar',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.workspace_premium),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'basico',
                          child: Text('Plan Básico'),
                        ),
                        DropdownMenuItem(
                          value: 'premium',
                          child: Text('Plan Premium'),
                        ),
                        DropdownMenuItem(
                          value: 'pro',
                          child: Text('Plan Pro'),
                        ),
                        DropdownMenuItem(
                          value: 'prueba',
                          child: Text('Plan Prueba'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          planSeleccionado = value;
                          // Establecer valores por defecto según el plan
                          int? defSedes;
                          int? defCanchas;
                          switch ((value ?? '').toLowerCase()) {
                            case 'basico':
                              defSedes = 1;
                              defCanchas = 2;
                              break;
                            case 'premium':
                              defSedes = 3;
                              defCanchas = 6;
                              break;
                            case 'pro':
                              defSedes = null; // ilimitadas
                              defCanchas = null;
                              break;
                            case 'prueba':
                              defSedes = 1;
                              defCanchas = 2;
                              break;
                            default:
                              defSedes = null;
                              defCanchas = null;
                          }
                          maxSedesController.text =
                              defSedes != null ? defSedes.toString() : '';
                          maxCanchasController.text =
                              defCanchas != null ? defCanchas.toString() : '';
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: maxSedesController,
                            decoration: const InputDecoration(
                              labelText: 'Máximo de sedes',
                              helperText: 'Vacío = ilimitadas',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.location_city),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxCanchasController,
                            decoration: const InputDecoration(
                              labelText: 'Máximo de canchas',
                              helperText: 'Vacío = ilimitadas',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.sports_soccer),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: fechaInicioPlan ?? now,
                                firstDate: DateTime(now.year - 2),
                                lastDate: DateTime(now.year + 5),
                              );
                              if (pickedDate != null) {
                                setState(() {
                                  fechaInicioPlan = pickedDate;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Inicio del plan',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                fechaInicioPlan != null
                                    ? _formatearFecha(fechaInicioPlan!)
                                    : 'Sin definir',
                                style: TextStyle(
                                  color: fechaInicioPlan != null
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: valorPlanController,
                            decoration: const InputDecoration(
                              labelText: 'Valor mensual del plan',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (nombreController.text.isEmpty ||
                                  direccionController.text.isEmpty ||
                                  telefonoController.text.isEmpty ||
                                  ciudadSeleccionada == null ||
                                  planSeleccionado == null) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  const SnackBar(
                                    content: Text('Completa todos los campos obligatorios, incluido el plan.'),
                                  ),
                                );
                                return;
                              }
                              final ahora = DateTime.now();
                              final valorPlan = double.tryParse(
                                valorPlanController.text.replaceAll(',', '.'),
                              );
                              final maxSedes =
                                  int.tryParse(maxSedesController.text.trim());
                              final maxCanchas =
                                  int.tryParse(maxCanchasController.text.trim());
                              final docRef = await FirebaseFirestore.instance.collection('lugares').add({
                                'nombre': nombreController.text,
                                'ciudadId': ciudadSeleccionada!,
                                'direccion': direccionController.text,
                                'telefono': telefonoController.text,
                                'activo': true,
                                'createdAt': Timestamp.fromDate(ahora),
                                'updatedAt': Timestamp.fromDate(ahora),
                                'plan': planSeleccionado,
                                if (maxSedes != null) 'maxSedes': maxSedes,
                                if (maxCanchas != null) 'maxCanchas': maxCanchas,
                                if (fechaInicioPlan != null)
                                  'planInicio': Timestamp.fromDate(fechaInicioPlan!),
                                if (valorPlan != null)
                                  'planValorMensual': valorPlan,
                              });
                              if (imagenSeleccionada != null) {
                                try {
                                  final url = await ImageUploadService.uploadLugarImage(
                                    lugarId: docRef.id,
                                    imageFile: imagenSeleccionada!,
                                  );
                                  await docRef.update({'fotoUrl': url});
                                } catch (_) {}
                              }
                              Navigator.of(dialogContext).pop();
                              final prov = Provider.of<LugarProvider>(rootContext, listen: false);
                              if (_ciudadFiltro != null) {
                                await prov.fetchLugaresPorCiudad(_ciudadFiltro!);
                              } else {
                                await prov.fetchTodosLosLugares();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D60),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Crear'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarDialogoEditarLugar(Lugar lugar) {
    final rootContext = context; // usar contexto estable de la página
    final nombreController = TextEditingController(text: lugar.nombre);
    final direccionController = TextEditingController(text: lugar.direccion);
    final telefonoController = TextEditingController(text: lugar.telefono);
    String? ciudadSeleccionada = lugar.ciudadId;
    String? planSeleccionado = lugar.plan;
    DateTime? fechaInicioPlan = lugar.planInicio;
    final valorPlanController = TextEditingController(
      text: lugar.planValorMensual != null
          ? lugar.planValorMensual!.toStringAsFixed(0)
          : '',
    );
    final maxSedesController = TextEditingController(
      text: lugar.maxSedes != null ? lugar.maxSedes.toString() : '',
    );
    final maxCanchasController = TextEditingController(
      text: lugar.maxCanchas != null ? lugar.maxCanchas.toString() : '',
    );
    XFile? imagenNueva;
    Uint8List? imagenNuevaBytes;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Editar Lugar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Consumer<CiudadProvider>(
                      builder: (context, ciudadProvider, child) {
                        final ciudades = ciudadProvider.ciudades;
                        final items = ciudades.map((ciudad) => DropdownMenuItem(
                              value: ciudad.id,
                              child: Text(ciudad.nombre),
                            )).toList();
                        final selected = items.any((i) => i.value == ciudadSeleccionada) ? ciudadSeleccionada : null;
                        return DropdownButtonFormField<String>(
                          value: selected,
                          decoration: const InputDecoration(
                            labelText: 'Ciudad',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_city),
                          ),
                          items: items,
                          onChanged: (value) => setState(() => ciudadSeleccionada = value),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        Icon(Icons.image, color: Color(0xFF2E7D60)),
                        SizedBox(width: 8),
                        Text('Imagen de portada'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 140,
                        color: Colors.grey[200],
                        child: imagenNuevaBytes != null
                            ? Image.memory(imagenNuevaBytes!, fit: BoxFit.cover, width: double.infinity)
                            : (lugar.fotoUrl != null && lugar.fotoUrl!.isNotEmpty)
                                ? Image.network(lugar.fotoUrl!, fit: BoxFit.cover, width: double.infinity)
                                : const Center(child: Icon(Icons.image, color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await ImageUploadService.pickImage();
                          if (picked != null) {
                            final bytes = await picked.readAsBytes();
                            setState(() {
                              imagenNueva = picked;
                              imagenNuevaBytes = bytes;
                            });
                          }
                        },
                        icon: const Icon(Icons.upload),
                        label: Text(imagenNuevaBytes == null ? 'Seleccionar imagen' : 'Cambiar imagen'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nombreController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del Lugar',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: direccionController,
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: telefonoController,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: planSeleccionado,
                      decoration: const InputDecoration(
                        labelText: 'Plan del lugar',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.workspace_premium),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'basico',
                          child: Text('Plan Básico'),
                        ),
                        DropdownMenuItem(
                          value: 'premium',
                          child: Text('Plan Premium'),
                        ),
                        DropdownMenuItem(
                          value: 'pro',
                          child: Text('Plan Pro'),
                        ),
                        DropdownMenuItem(
                          value: 'prueba',
                          child: Text('Plan Prueba'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          planSeleccionado = value;
                          // Opcionalmente actualizar valores por defecto al cambiar de plan
                          int? defSedes;
                          int? defCanchas;
                          switch ((value ?? '').toLowerCase()) {
                            case 'basico':
                              defSedes = 1;
                              defCanchas = 2;
                              break;
                            case 'premium':
                              defSedes = 3;
                              defCanchas = 6;
                              break;
                            case 'pro':
                              defSedes = null;
                              defCanchas = null;
                              break;
                            case 'prueba':
                              defSedes = 1;
                              defCanchas = 2;
                              break;
                            default:
                              defSedes = null;
                              defCanchas = null;
                          }
                          if (lugar.maxSedes == null) {
                            maxSedesController.text =
                                defSedes != null ? defSedes.toString() : '';
                          }
                          if (lugar.maxCanchas == null) {
                            maxCanchasController.text =
                                defCanchas != null ? defCanchas.toString() : '';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: maxSedesController,
                            decoration: const InputDecoration(
                              labelText: 'Máximo de sedes',
                              helperText: 'Vacío = ilimitadas',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.location_city),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxCanchasController,
                            decoration: const InputDecoration(
                              labelText: 'Máximo de canchas',
                              helperText: 'Vacío = ilimitadas',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.sports_soccer),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: fechaInicioPlan ?? now,
                                firstDate: DateTime(now.year - 2),
                                lastDate: DateTime(now.year + 5),
                              );
                              if (pickedDate != null) {
                                setState(() {
                                  fechaInicioPlan = pickedDate;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Inicio del plan',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                fechaInicioPlan != null
                                    ? _formatearFecha(fechaInicioPlan!)
                                    : 'Sin definir',
                                style: TextStyle(
                                  color: fechaInicioPlan != null
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: valorPlanController,
                            decoration: const InputDecoration(
                              labelText: 'Valor mensual del plan',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (nombreController.text.isEmpty ||
                                  direccionController.text.isEmpty ||
                                  telefonoController.text.isEmpty ||
                                  ciudadSeleccionada == null ||
                                  planSeleccionado == null) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  const SnackBar(
                                    content: Text('Completa todos los campos obligatorios, incluido el plan.'),
                                  ),
                                );
                                return;
                              }
                              final valorPlan = double.tryParse(
                                valorPlanController.text.replaceAll(',', '.'),
                              );
                              final maxSedes =
                                  int.tryParse(maxSedesController.text.trim());
                              final maxCanchas =
                                  int.tryParse(maxCanchasController.text.trim());
                              final update = {
                                'nombre': nombreController.text,
                                'ciudadId': ciudadSeleccionada!,
                                'direccion': direccionController.text,
                                'telefono': telefonoController.text,
                                'updatedAt': Timestamp.now(),
                                'plan': planSeleccionado,
                              };
                              if (maxSedes != null) {
                                update['maxSedes'] = maxSedes;
                              } else {
                                update.remove('maxSedes');
                              }
                              if (maxCanchas != null) {
                                update['maxCanchas'] = maxCanchas;
                              } else {
                                update.remove('maxCanchas');
                              }
                              if (fechaInicioPlan != null) {
                                update['planInicio'] = Timestamp.fromDate(fechaInicioPlan!);
                              }
                              if (valorPlan != null) {
                                update['planValorMensual'] = valorPlan;
                              }
                              if (imagenNueva != null) {
                                try {
                                  final url = await ImageUploadService.uploadLugarImage(
                                    lugarId: lugar.id,
                                    imageFile: imagenNueva!,
                                  );
                                  update['fotoUrl'] = url;
                                } catch (_) {}
                              }
                              Navigator.of(dialogContext).pop();
                              await Provider.of<LugarProvider>(rootContext, listen: false).actualizarLugar(
                                lugar.id,
                                update,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D60),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Actualizar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarDialogoEliminarLugar(Lugar lugar) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Lugar'),
        content: Text('¿Estás seguro de que quieres eliminar el lugar "${lugar.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<LugarProvider>(context, listen: false).eliminarLugar(lugar.id);
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
