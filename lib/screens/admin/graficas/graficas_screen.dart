import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:animate_do/animate_do.dart';
import '../../../providers/sede_provider.dart';
import '../../../providers/cancha_provider.dart';
import '../../../models/cancha.dart';
import '../../../models/reserva.dart';
import 'dart:async';

class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  @override
  EstadisticasScreenState createState() => EstadisticasScreenState();
}

class EstadisticasScreenState extends State<EstadisticasScreen> {
  // Filtros
  String _periodoSeleccionado = 'Diario';
  String? _sedeSeleccionada;
  String? _canchaSeleccionada;
  DateTime? _fechaSeleccionada;
  
  // Datos unificados
  List<Reserva> _reservasActuales = [];
  List<Cancha> _canchas = [];
  bool _isLoading = false;
  
  // Control de streams
  StreamSubscription<QuerySnapshot>? _reservasSubscription;
  
  // Estadísticas calculadas
  Map<String, dynamic> _estadisticas = {
    'totalCompleto': 0,
    'totalParcial': 0,
    'canchasMasPedidas': <String, int>{},
    'sedesMasPedidas': <String, int>{},
    'horasMasPedidas': <String, int>{},
    'datosGrafica': <Map<String, dynamic>>[],
  };

  // Para la última actualización
  DateTime _lastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fechaSeleccionada = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inicializarDatos();
    });
  }

  @override
  void dispose() {
    _reservasSubscription?.cancel();
    super.dispose();
  }

  Future<void> _inicializarDatos() async {
    setState(() => _isLoading = true);

    try {
      if (!mounted) return;
      
      await Provider.of<SedeProvider>(context, listen: false).fetchSedes();
      if (!mounted) return;
      
      await Provider.of<CanchaProvider>(context, listen: false).fetchAllCanchas();
      if (!mounted) return;
      
      _canchas = Provider.of<CanchaProvider>(context, listen: false).canchas;
      
      _configurarStreamReservas();
      
    } catch (e) {
      _mostrarError('Error al inicializar datos: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _configurarStreamReservas() {
    _reservasSubscription?.cancel();
    
    Query query = _construirQuery();
    
    _reservasSubscription = query.snapshots().listen(
      (snapshot) {
        _procesarReservas(snapshot);
        if (mounted) setState(() => _lastUpdate = DateTime.now());
      },
      onError: (error) => _mostrarError('Error en stream: $error'),
    );
  }

  Query _construirQuery() {
    Query query = FirebaseFirestore.instance.collection('reservas');
    
    if (_periodoSeleccionado == 'Diario' && _fechaSeleccionada != null) {
      DateTime fechaInicio = _fechaSeleccionada!.subtract(const Duration(days: 6));
      String fechaInicioStr = DateFormat('yyyy-MM-dd').format(fechaInicio);
      String fechaFinStr = DateFormat('yyyy-MM-dd').format(_fechaSeleccionada!);
      
      query = query
          .where('fecha', isGreaterThanOrEqualTo: fechaInicioStr)
          .where('fecha', isLessThanOrEqualTo: fechaFinStr);
          
    } else if (_periodoSeleccionado == 'Semanal') {
      DateTime fechaInicio = _fechaSeleccionada!.subtract(const Duration(days: 27));
      String fechaInicioStr = DateFormat('yyyy-MM-dd').format(fechaInicio);
      String fechaFinStr = DateFormat('yyyy-MM-dd').format(_fechaSeleccionada!);
      
      query = query
          .where('fecha', isGreaterThanOrEqualTo: fechaInicioStr)
          .where('fecha', isLessThanOrEqualTo: fechaFinStr);
          
    } else if (_periodoSeleccionado == 'Mensual') {
      DateTime fechaInicio = DateTime(_fechaSeleccionada!.year, _fechaSeleccionada!.month - 2, 1);
      String fechaInicioStr = DateFormat('yyyy-MM-dd').format(fechaInicio);
      String fechaFinStr = DateFormat('yyyy-MM-dd').format(_fechaSeleccionada!);
      
      query = query
          .where('fecha', isGreaterThanOrEqualTo: fechaInicioStr)
          .where('fecha', isLessThanOrEqualTo: fechaFinStr);
    }
    
    return query.orderBy('fecha', descending: false);
  }

  void _procesarReservas(QuerySnapshot snapshot) {
    if (!mounted) return;
    
    try {
      Map<String, Cancha> canchasMap = {for (var c in _canchas) c.id: c};
      
      List<Reserva> todasLasReservas = [];
      for (var doc in snapshot.docs) {
        try {
          var reserva = Reserva.fromFirestoreWithCanchas(doc, canchasMap);
          todasLasReservas.add(reserva);
        } catch (e) {
          debugPrint('ERROR: Al procesar reserva ${doc.id}: $e');
        }
      }
      
      _reservasActuales = _aplicarFiltros(todasLasReservas);
      _calcularTodasLasEstadisticas();
      
    } catch (e) {
      debugPrint('ERROR: Al procesar reservas: $e');
      _mostrarError('Error al procesar reservas');
    }
  }

  List<Reserva> _aplicarFiltros(List<Reserva> reservas) {
    return reservas.where((reserva) {
      if (_sedeSeleccionada != null && _sedeSeleccionada!.isNotEmpty) {
        final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
        final sedeId = sedeProvider.sedes
            .firstWhere((s) => s['nombre'] == _sedeSeleccionada,
                orElse: () => {'id': ''})['id'];
        if (reserva.cancha.sedeId != sedeId) return false;
      }
      
      if (_canchaSeleccionada != null && _canchaSeleccionada!.isNotEmpty) {
        if (reserva.cancha.id != _canchaSeleccionada) return false;
      }
      
      return true;
    }).toList();
  }

  void _calcularTodasLasEstadisticas() {
    int totalCompleto = 0;
    int totalParcial = 0;
    Map<String, int> canchasMasPedidas = {};
    Map<String, int> sedesMasPedidas = {};
    Map<String, int> horasMasPedidas = {};

    for (var reserva in _reservasActuales) {
      if (reserva.tipoAbono == TipoAbono.completo) {
        totalCompleto++;
      } else {
        totalParcial++;
      }

      canchasMasPedidas[reserva.cancha.nombre] = 
          (canchasMasPedidas[reserva.cancha.nombre] ?? 0) + 1;

      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
      final sedeNombre = sedeProvider.sedes
          .firstWhere((s) => s['id'] == reserva.cancha.sedeId, 
                    orElse: () => {'nombre': 'Desconocida'})['nombre'];
      sedesMasPedidas[sedeNombre] = (sedesMasPedidas[sedeNombre] ?? 0) + 1;

      horasMasPedidas[reserva.horario.horaFormateada] = 
          (horasMasPedidas[reserva.horario.horaFormateada] ?? 0) + 1;
    }

    List<Map<String, dynamic>> datosGrafica = _calcularDatosGrafica();

    if (mounted) {
      setState(() {
        _estadisticas = {
          'totalCompleto': totalCompleto,
          'totalParcial': totalParcial,
          'canchasMasPedidas': canchasMasPedidas,
          'sedesMasPedidas': sedesMasPedidas,
          'horasMasPedidas': horasMasPedidas,
          'datosGrafica': datosGrafica,
        };
      });
    }
  }

  List<Map<String, dynamic>> _calcularDatosGrafica() {
    Map<String, int> reservasPorPeriodo = {};
    List<String> periodosOrdenados = [];

    if (_periodoSeleccionado == 'Diario') {
      for (var i = 6; i >= 0; i--) {
        DateTime fecha = _fechaSeleccionada!.subtract(Duration(days: i));
        String fechaStr = DateFormat('dd/MM').format(fecha);
        reservasPorPeriodo[fechaStr] = 0;
        periodosOrdenados.add(fechaStr);
      }
      
      for (var reserva in _reservasActuales) {
        String fecha = DateFormat('dd/MM').format(reserva.fecha);
        if (reservasPorPeriodo.containsKey(fecha)) {
          reservasPorPeriodo[fecha] = (reservasPorPeriodo[fecha] ?? 0) + 1;
        }
      }
      
    } else if (_periodoSeleccionado == 'Semanal') {
      for (var i = 3; i >= 0; i--) {
        DateTime fechaReferencia = _fechaSeleccionada!.subtract(Duration(days: 7 * i));
        DateTime inicioSemana = fechaReferencia.subtract(Duration(days: fechaReferencia.weekday - 1));
        String semanaStr = DateFormat('dd/MM').format(inicioSemana);
        reservasPorPeriodo[semanaStr] = 0;
        periodosOrdenados.add(semanaStr);
      }
      
      for (var reserva in _reservasActuales) {
        DateTime inicioSemana = reserva.fecha.subtract(Duration(days: reserva.fecha.weekday - 1));
        String semana = DateFormat('dd/MM').format(inicioSemana);
        if (reservasPorPeriodo.containsKey(semana)) {
          reservasPorPeriodo[semana] = (reservasPorPeriodo[semana] ?? 0) + 1;
        }
      }
      
    } else {
      for (var i = 2; i >= 0; i--) {
        DateTime mes = DateTime(_fechaSeleccionada!.year, _fechaSeleccionada!.month - i, 1);
        String mesStr = DateFormat('MMM').format(mes);
        reservasPorPeriodo[mesStr] = 0;
        periodosOrdenados.add(mesStr);
      }
      
      for (var reserva in _reservasActuales) {
        String mes = DateFormat('MMM').format(reserva.fecha);
        if (reservasPorPeriodo.containsKey(mes)) {
          reservasPorPeriodo[mes] = (reservasPorPeriodo[mes] ?? 0) + 1;
        }
      }
    }

    return periodosOrdenados
        .map((periodo) => {
              'periodo': periodo, 
              'reservas': (reservasPorPeriodo[periodo] ?? 0).toDouble()
            })
        .toList();
  }

  void _mostrarError(String mensaje) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _actualizarFiltros() {
    _configurarStreamReservas();
  }

  // Getters para acceder a las estadísticas
  int get _totalCompleto => _estadisticas['totalCompleto'] ?? 0;
  int get _totalParcial => _estadisticas['totalParcial'] ?? 0;
  Map<String, int> get _canchasMasPedidas => _estadisticas['canchasMasPedidas'] ?? {};
  Map<String, int> get _sedesMasPedidas => _estadisticas['sedesMasPedidas'] ?? {};
  Map<String, int> get _horasMasPedidas => _estadisticas['horasMasPedidas'] ?? {};
  List<Map<String, dynamic>> get _datosGrafica => _estadisticas['datosGrafica'] ?? [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: _isLoading
            ? _buildLoadingIndicator()
            : CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeInUp(
                            duration: const Duration(milliseconds: 800),
                            child: _buildFiltros(),
                          ),
                          const SizedBox(height: 20),
                          FadeInUp(
                            duration: const Duration(milliseconds: 900),
                            child: _buildTarjetasResumen(),
                          ),
                          const SizedBox(height: 20),
                          FadeInUp(
                            duration: const Duration(milliseconds: 1000),
                            child: _buildGraficaLineal(),
                          ),
                          const SizedBox(height: 20),
                          FadeInUp(
                            duration: const Duration(milliseconds: 1100),
                            child: _buildEstadisticasDetalladas(),
                          ),
                          const SizedBox(height: 10),
                          FadeInUp(
                            duration: const Duration(milliseconds: 1200),
                            child: _buildLastUpdate(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: FadeIn(
        duration: const Duration(milliseconds: 500),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            const SizedBox(height: 16),
            Text(
              'Cargando estadísticas...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120.0,
      floating: true,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'Estadísticas',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                blurRadius: 4.0,
                color: Colors.black26,
                offset: Offset(2.0, 2.0),
              ),
            ],
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade600, Colors.blue.shade900],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Actualizar datos',
          onPressed: _actualizarFiltros,
        ),
      ],
    );
  }

  Widget _buildFiltros() {
    final sedeProvider = Provider.of<SedeProvider>(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Filtros',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Column(
                key: ValueKey(_periodoSeleccionado + (_sedeSeleccionada ?? '') + (_canchaSeleccionada ?? '')),
                children: [
                  _buildFiltroRow(
                    label: 'Período',
                    tooltip: 'Selecciona el rango temporal para las estadísticas',
                    child: DropdownButton<String>(
                      value: _periodoSeleccionado,
                      items: ['Diario', 'Semanal', 'Mensual']
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _periodoSeleccionado = value!;
                        });
                        _actualizarFiltros();
                      },
                      style: TextStyle(color: Colors.blue.shade700),
                      underline: Container(
                        height: 2,
                        color: Colors.blue.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFiltroRow(
                    label: 'Fecha',
                    tooltip: 'Selecciona la fecha de referencia',
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue.shade700,
                        backgroundColor: Colors.blue.shade50,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        final fecha = await showDatePicker(
                          context: context,
                          initialDate: _fechaSeleccionada ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: Colors.blue.shade700,
                                  onPrimary: Colors.white,
                                  surface: Colors.white,
                                  onSurface: Colors.black87,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (fecha != null) {
                          setState(() {
                            _fechaSeleccionada = fecha;
                          });
                          _actualizarFiltros();
                        }
                      },
                      child: Text(
                        _fechaSeleccionada != null
                            ? DateFormat('dd/MM/yyyy').format(_fechaSeleccionada!)
                            : 'Seleccionar',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFiltroRow(
                    label: 'Sede',
                    tooltip: 'Filtra por sede específica',
                    child: DropdownButton<String>(
                      value: _sedeSeleccionada,
                      hint: const Text('Todas'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todas'),
                        ),
                        ...sedeProvider.sedeNames.map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(e),
                            )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _sedeSeleccionada = value;
                          _canchaSeleccionada = null;
                        });
                        _actualizarFiltros();
                      },
                      style: TextStyle(color: Colors.blue.shade700),
                      underline: Container(
                        height: 2,
                        color: Colors.blue.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFiltroRow(
                    label: 'Cancha',
                    tooltip: 'Filtra por cancha específica',
                    child: DropdownButton<String>(
                      value: _canchaSeleccionada,
                      hint: const Text('Todas'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todas'),
                        ),
                        ..._getCanchasFiltradas().map((e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.nombre),
                            )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _canchaSeleccionada = value;
                        });
                        _actualizarFiltros();
                      },
                      style: TextStyle(color: Colors.blue.shade700),
                      underline: Container(
                        height: 2,
                        color: Colors.blue.shade200,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroRow({required String label, required String tooltip, required Widget child}) {
    return Row(
      children: [
        Tooltip(
          message: tooltip,
          child: Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  List<Cancha> _getCanchasFiltradas() {
    if (_sedeSeleccionada == null) return _canchas;
    
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final sedeId = sedeProvider.sedes
        .firstWhere((s) => s['nombre'] == _sedeSeleccionada, orElse: () => {'id': ''})['id'];
    
    return _canchas.where((c) => c.sedeId == sedeId).toList();
  }

  Widget _buildTarjetasResumen() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildTarjeta(
          title: 'Reservas Completas',
          value: '$_totalCompleto',
          color: Colors.green.shade400,
          icon: Icons.check_circle,
          delay: 100,
        ),
        _buildTarjeta(
          title: 'Reservas Parciales',
          value: '$_totalParcial',
          color: Colors.orange.shade400,
          icon: Icons.hourglass_empty,
          delay: 200,
        ),
        _buildTarjeta(
          title: 'Total Reservas',
          value: '${_reservasActuales.length}',
          color: Colors.blue.shade400,
          icon: Icons.sports_soccer,
          delay: 300,
        ),
      ],
    );
  }

  Widget _buildTarjeta({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required int delay,
  }) {
    return Expanded(
      child: FadeInUp(
        duration: Duration(milliseconds: 600 + delay),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.1), Colors.white],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  textAlign: TextAlign.center,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGraficaLineal() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reservas por $_periodoSeleccionado',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      Text(
                        _periodoSeleccionado == 'Diario'
                            ? 'Reservas en los últimos 7 días'
                            : _periodoSeleccionado == 'Semanal'
                                ? 'Reservas en las últimas 4 semanas'
                                : 'Reservas en los últimos 3 meses',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: _datosGrafica.isEmpty
                  ? Center(
                      child: Text(
                        'No hay datos para mostrar',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          horizontalInterval: 1,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                          ),
                          getDrawingVerticalLine: (value) => FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) => Text(
                                value.toInt().toString(),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index >= 0 && index < _datosGrafica.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      _datosGrafica[index]['periodo'],
                                      style: TextStyle(
                                        color: Colors.grey.shade800,
                                        fontSize: 10,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _datosGrafica.asMap().entries.map((entry) {
                              return FlSpot(entry.key.toDouble(), entry.value['reservas']);
                            }).toList(),
                            isCurved: true,
                            color: Colors.blue.shade600,
                            barWidth: 4,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                radius: 4,
                                color: Colors.blue.shade800,
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.blue.shade100.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => Colors.blue.shade800.withValues(alpha: 0.8),
                            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                              return LineTooltipItem(
                                '${_datosGrafica[spot.x.toInt()]['periodo']}\n${spot.y.toInt()} reservas',
                                const TextStyle(color: Colors.white, fontSize: 12),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticasDetalladas() {
    return Column(
      children: [
        _buildGraficaBarras(
          'Canchas Más Pedidas',
          _canchasMasPedidas,
          'Top 5 canchas con más reservas',
          Colors.blue.shade400,
          100,
        ),
        const SizedBox(height: 16),
        _buildGraficaBarras(
          'Sedes Más Pedidas',
          _sedesMasPedidas,
          'Top 5 sedes con más reservas',
          Colors.green.shade400,
          200,
        ),
        const SizedBox(height: 16),
        _buildGraficaBarras(
          'Horas Más Pedidas',
          _horasMasPedidas,
          'Top 5 horarios con más reservas',
          Colors.orange.shade400,
          300,
        ),
      ],
    );
  }

  Widget _buildGraficaBarras(String title, Map<String, int> datos, String subtitle, Color color, int delay) {
    var sortedEntries = datos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return FadeInUp(
      duration: Duration(milliseconds: 600 + delay),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    title.contains('Canchas')
                        ? Icons.sports_soccer
                        : title.contains('Sedes')
                            ? Icons.location_on
                            : Icons.access_time,
                    color: color,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: sortedEntries.isEmpty
                    ? Center(
                        child: Text(
                          'No hay datos disponibles',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          barGroups: sortedEntries.take(5).toList().asMap().entries.map((entry) {
                            return BarChartGroupData(
                              x: entry.key,
                              barRods: [
                                BarChartRodData(
                                  toY: entry.value.value.toDouble(),
                                  color: color,
                                  width: 16,
                                  borderRadius: BorderRadius.circular(4),
                                  backDrawRodData: BackgroundBarChartRodData(
                                    show: true,
                                    toY: sortedEntries.map((e) => e.value.toDouble()).reduce((a, b) => a > b ? a : b) * 1.2,
                                    color: Colors.grey.shade100,
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) => Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 && index < sortedEntries.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        sortedEntries[index].key,
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontSize: 10,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(
                            show: true,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => color.withValues(alpha: 0.8),
                              getTooltipItem: (group, groupIdx, rod, rodIdx) {
                                return BarTooltipItem(
                                  '${sortedEntries[groupIdx].key}\n${rod.toY.toInt()} reservas',
                                  const TextStyle(color: Colors.white, fontSize: 12),
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
    );
  }

  Widget _buildLastUpdate() {
    return Center(
      child: Text(
        'Última actualización: ${DateFormat('dd/MM/yyyy HH:mm').format(_lastUpdate)}',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}