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
import '../../../providers/reserva_recurrente_provider.dart';
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
  
  // ✅ NUEVAS VARIABLES
  DateTime? _mesEspecifico; // Para el selector de mes específico
  bool _mostrandoMesEspecifico = false; // Para controlar qué datos mostrar

  // Datos unificados
  List<Reserva> _reservasActuales = [];
  List<Cancha> _canchas = [];
  bool _isLoading = false;
  
  // Control de streams
  StreamSubscription<QuerySnapshot>? _reservasSubscription;

  String _formatearMonto(double monto) {
    // Convertir a entero para evitar decimales innecesarios
    int montoEntero = monto.toInt();
  
    // Formatear con puntos de miles usando RegExp
    String montoStr = montoEntero.toString();
    return montoStr.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match match) => '${match[1]}.',
    );
  }
  
  // Estadísticas calculadas
  Map<String, dynamic> _estadisticas = {
    'totalCompleto': 0,
    'totalParcial': 0,
    'canchasMasPedidas': <String, int>{},
    'sedesMasPedidas': <String, int>{},
    'horasMasPedidas': <String, int>{},
    'datosGrafica': <Map<String, dynamic>>[],
    'dineroTotalSinDescuentos': 0.0, // ✅ NUEVO CAMPO
    'dineroRecaudado': 0.0, // ✅ NUEVO CAMPO
    'eficiencia': 100.0, // ✅ NUEVO CAMPO
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
      
      await Provider.of<ReservaRecurrenteProvider>(context, listen: false).fetchReservasRecurrentes();
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
  
    query = query.where('confirmada', isEqualTo: true);
  
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

  void _procesarReservas(QuerySnapshot snapshot) async {
  if (!mounted) return; // ✅ Primera verificación
  
  try {
    Map<String, Cancha> canchasMap = {for (var c in _canchas) c.id: c};
  
    List<Reserva> reservasNormales = [];
    for (var doc in snapshot.docs) {
      try {
        var reserva = Reserva.fromFirestoreWithCanchas(doc, canchasMap);
        if (reserva.confirmada == true) {
          reservasNormales.add(reserva);
        }
      } catch (e) {
        debugPrint('ERROR: Al procesar reserva ${doc.id}: $e');
      }
    }
  
    // ✅ Verificar mounted antes de acceder al Provider
    if (!mounted) return;
    
    final reservaRecurrenteProvider = Provider.of<ReservaRecurrenteProvider>(context, listen: false);
  
    DateTime fechaInicio;
    DateTime fechaFin;
  
    if (_periodoSeleccionado == 'Diario') {
      fechaInicio = _fechaSeleccionada!.subtract(const Duration(days: 6));
      fechaFin = _fechaSeleccionada!;
    } else if (_periodoSeleccionado == 'Semanal') {
      fechaInicio = _fechaSeleccionada!.subtract(const Duration(days: 27));
      fechaFin = _fechaSeleccionada!;
    } else {
      fechaInicio = DateTime(_fechaSeleccionada!.year, _fechaSeleccionada!.month - 2, 1);
      fechaFin = _fechaSeleccionada!;
    }
  
    List<Reserva> reservasRecurrentes = await reservaRecurrenteProvider.generarReservasDesdeRecurrentes(
      fechaInicio,
      fechaFin,
      canchasMap,
    );
  
    // ✅ Verificar mounted después de operaciones async
    if (!mounted) return;
  
    debugPrint('📊 Reservas normales: ${reservasNormales.length}');
    debugPrint('📊 Reservas recurrentes virtuales: ${reservasRecurrentes.length}');
  
    List<Reserva> todasLasReservas = [...reservasNormales, ...reservasRecurrentes];
  
    debugPrint('📊 Total reservas combinadas: ${todasLasReservas.length}');
  
    _reservasActuales = _aplicarFiltros(todasLasReservas);
    _calcularTodasLasEstadisticas();
  
  } catch (e) {
    debugPrint('ERROR: Al procesar reservas: $e');
    // ✅ Verificar mounted antes de mostrar error
    if (mounted) {
      _mostrarError('Error al procesar reservas');
    }
  }
}


  List<Reserva> _obtenerReservasParaTarjetas() {
    if (_fechaSeleccionada == null) return [];

    List<Reserva> reservasFiltradas = [];

    if (_periodoSeleccionado == 'Diario') {
      String fechaSeleccionadaStr = DateFormat('yyyy-MM-dd').format(_fechaSeleccionada!);
      reservasFiltradas = _reservasActuales.where((reserva) {
        String fechaReservaStr = DateFormat('yyyy-MM-dd').format(reserva.fecha);
        return fechaReservaStr == fechaSeleccionadaStr;
      }).toList();
      
    } else if (_periodoSeleccionado == 'Semanal') {
      DateTime inicioSemana = _fechaSeleccionada!.subtract(Duration(days: _fechaSeleccionada!.weekday - 1));
      DateTime finSemana = inicioSemana.add(const Duration(days: 6));

      reservasFiltradas = _reservasActuales.where((reserva) {
        return reserva.fecha.isAfter(inicioSemana.subtract(const Duration(days: 1))) &&
               reserva.fecha.isBefore(finSemana.add(const Duration(days: 1)));
      }).toList();
      
    } else if (_periodoSeleccionado == 'Mensual') {
      if (_mostrandoMesEspecifico && _mesEspecifico != null) {
        DateTime inicioMes = DateTime(_mesEspecifico!.year, _mesEspecifico!.month, 1);
        DateTime finMes = DateTime(_mesEspecifico!.year, _mesEspecifico!.month + 1, 0);

        reservasFiltradas = _reservasActuales.where((reserva) {
          return reserva.fecha.isAfter(inicioMes.subtract(const Duration(days: 1))) &&
                 reserva.fecha.isBefore(finMes.add(const Duration(days: 1)));
        }).toList();
      } else {
        final DateTime hoy = DateTime.now();
        DateTime inicioMes = DateTime(_fechaSeleccionada!.year, _fechaSeleccionada!.month, 1);
        DateTime finMes = DateTime(hoy.year, hoy.month, hoy.day);
        if (hoy.hour < 23) {
          finMes = hoy.subtract(const Duration(days: 1));
        }

        reservasFiltradas = _reservasActuales.where((reserva) {
          final fechaReserva = DateTime(reserva.fecha.year, reserva.fecha.month, reserva.fecha.day);
          final fechaInicio = DateTime(inicioMes.year, inicioMes.month, inicioMes.day);
          final fechaFin = DateTime(finMes.year, finMes.month, finMes.day);
          
          return fechaReserva.isAfter(fechaInicio.subtract(const Duration(days: 1))) &&
                 fechaReserva.isBefore(fechaFin.add(const Duration(days: 1)));
        }).toList();
      }
    }

    return reservasFiltradas;
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
    List<Reserva> reservasParaTarjetas = _obtenerReservasParaTarjetas();

    int totalCompleto = 0;
    int totalParcial = 0;
    double montoCompleto = 0.0;
    double montoParcial = 0.0;
    
    double dineroTotalSinDescuentos = 0.0;
    double dineroRecaudado = 0.0;

    for (var reserva in reservasParaTarjetas) {
      if (reserva.tipoAbono == TipoAbono.completo) {
        totalCompleto++;
        montoCompleto += reserva.montoPagado;
      } else {
        totalParcial++;
        montoParcial += reserva.montoPagado;
      }
      
      dineroRecaudado += reserva.montoPagado;
      
      if (reserva.precioPersonalizado && reserva.precioOriginal != null) {
        dineroTotalSinDescuentos += reserva.precioOriginal!;
      } else {
        dineroTotalSinDescuentos += reserva.montoTotal;
      }
    }

    double eficiencia = dineroTotalSinDescuentos > 0 
        ? (dineroRecaudado / dineroTotalSinDescuentos * 100) 
        : 100.0;

    Map<String, int> canchasMasPedidas = {};
    Map<String, int> sedesMasPedidas = {};
    Map<String, int> horasMasPedidas = {};

    for (var reserva in _reservasActuales) {
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
          'totalReservasPeriodo': reservasParaTarjetas.length,
          'montoCompleto': montoCompleto,
          'montoParcial': montoParcial,
          'montoTotal': montoCompleto + montoParcial,
          'dineroTotalSinDescuentos': dineroTotalSinDescuentos,
          'dineroRecaudado': dineroRecaudado,
          'eficiencia': eficiencia,
          'reservasCompletas': reservasParaTarjetas.where((r) => r.tipoAbono == TipoAbono.completo).toList(),
          'reservasParciales': reservasParaTarjetas.where((r) => r.tipoAbono == TipoAbono.parcial).toList(),
          'todasReservasPeriodo': reservasParaTarjetas,
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
    // ✅ CORRECCIÓN: Para la gráfica mensual
    for (var i = 2; i >= 0; i--) {
      DateTime mes = DateTime(_fechaSeleccionada!.year, _fechaSeleccionada!.month - i, 1);
      String mesStr = DateFormat('MMM').format(mes);
      reservasPorPeriodo[mesStr] = 0;
      periodosOrdenados.add(mesStr);
    }
    
    // ✅ Obtener la fecha límite (ayer - excluyendo hoy)
    final DateTime hoy = DateTime.now();
    final DateTime fechaLimite = DateTime(hoy.year, hoy.month, hoy.day).subtract(const Duration(days: 1));
    
    // ✅ Filtrar reservas: meses pasados completos + mes actual hasta ayer (sin incluir hoy)
    for (var reserva in _reservasActuales) {
      final DateTime fechaReserva = DateTime(reserva.fecha.year, reserva.fecha.month, reserva.fecha.day);
      
      // Solo incluir reservas que sean de ayer hacia atrás (excluyendo hoy)
      if (fechaReserva.isBefore(fechaLimite.add(const Duration(days: 1)))) {
        String mes = DateFormat('MMM').format(reserva.fecha);
        if (reservasPorPeriodo.containsKey(mes)) {
          reservasPorPeriodo[mes] = (reservasPorPeriodo[mes] ?? 0) + 1;
        }
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

  int get _totalCompleto => _estadisticas['totalCompleto'] ?? 0;
  int get _totalParcial => _estadisticas['totalParcial'] ?? 0;
  int get _totalReservasPeriodo => _estadisticas['totalReservasPeriodo'] ?? 0;
  double get _montoCompleto => _estadisticas['montoCompleto'] ?? 0.0;
  double get _montoParcial => _estadisticas['montoParcial'] ?? 0.0;
  double get _montoTotal => _estadisticas['montoTotal'] ?? 0.0;
  double get _dineroTotalSinDescuentos => _estadisticas['dineroTotalSinDescuentos'] ?? 0.0;
  double get _dineroRecaudado => _estadisticas['dineroRecaudado'] ?? 0.0;
  double get _eficiencia => _estadisticas['eficiencia'] ?? 100.0;
  List<Reserva> get _reservasCompletas => _estadisticas['reservasCompletas'] ?? [];
  List<Reserva> get _reservasParciales => _estadisticas['reservasParciales'] ?? [];
  List<Reserva> get _todasReservasPeriodo => _estadisticas['todasReservasPeriodo'] ?? [];
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
      automaticallyImplyLeading: false,
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
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade50, Colors.white],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.tune, color: Colors.blue.shade700, size: 24),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Filtros de Búsqueda',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        Text(
                          'Personaliza tu consulta de estadísticas',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              
              _buildSeccionFiltro(
                'Período de Análisis',
                Icons.calendar_view_week,
                Colors.green,
                Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _periodoSeleccionado,
                          icon: Icon(Icons.keyboard_arrow_down, color: Colors.blue.shade600),
                          style: TextStyle(color: Colors.blue.shade700, fontSize: 16),
                          items: [
                            DropdownMenuItem(
                              value: 'Diario',
                              child: Row(
                                children: [
                                  Icon(Icons.today, size: 18, color: Colors.orange.shade600),
                                  SizedBox(width: 8),
                                  Text('Diario - Análisis por días'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Semanal',
                              child: Row(
                                children: [
                                  Icon(Icons.view_week, size: 18, color: Colors.green.shade600),
                                  SizedBox(width: 8),
                                  Text('Semanal - Análisis por semanas'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Mensual',
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_month, size: 18, color: Colors.blue.shade600),
                                  SizedBox(width: 8),
                                  Text('Mensual - Solo reservas pasadas'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _periodoSeleccionado = value!;
                              _mostrandoMesEspecifico = false;
                            });
                            _actualizarFiltros();
                          },
                        ),
                      ),
                    ),
                    
                    if (_periodoSeleccionado == 'Mensual') ...[
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await showDialog(
                                  context: context,
                                  builder: (context) {
                                    DateTime tempDate = _mesEspecifico ?? DateTime.now();
                                    return StatefulBuilder(
                                      builder: (context, setState) {
                                        return AlertDialog(
                                          title: Text('Seleccionar Mes'),
                                          content: SizedBox(
                                            height: 300,
                                            width: 300,
                                            child: Column(
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    IconButton(
                                                      onPressed: () => setState(() {
                                                        tempDate = DateTime(tempDate.year - 1, tempDate.month);
                                                      }),
                                                      icon: Icon(Icons.keyboard_arrow_left),
                                                    ),
                                                    Text(
                                                      tempDate.year.toString(),
                                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                    ),
                                                    IconButton(
                                                      onPressed: () => setState(() {
                                                        tempDate = DateTime(tempDate.year + 1, tempDate.month);
                                                      }),
                                                      icon: Icon(Icons.keyboard_arrow_right),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 20),
                                                Expanded(
                                                  child: GridView.count(
                                                    crossAxisCount: 3,
                                                    children: List.generate(12, (index) {
                                                      final mes = index + 1;
                                                      final esMesSeleccionado = tempDate.month == mes;
                                                      return GestureDetector(
                                                        onTap: () => setState(() {
                                                          tempDate = DateTime(tempDate.year, mes);
                                                        }),
                                                        child: Container(
                                                          margin: EdgeInsets.all(4),
                                                          decoration: BoxDecoration(
                                                            color: esMesSeleccionado 
                                                                ? Colors.purple.shade600 
                                                                : Colors.grey.shade100,
                                                            borderRadius: BorderRadius.circular(8),
                                                          ),
                                                          child: Center(
                                                            child: Text(
                                                              DateFormat('MMM').format(DateTime(2024, mes)),
                                                              style: TextStyle(
                                                                color: esMesSeleccionado 
                                                                    ? Colors.white 
                                                                    : Colors.black,
                                                                fontWeight: esMesSeleccionado 
                                                                    ? FontWeight.bold 
                                                                    : FontWeight.normal,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: Text('Cancelar'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  _mesEspecifico = tempDate;
                                                  _mostrandoMesEspecifico = true;
                                                });
                                                Navigator.pop(context);
                                                _actualizarFiltros();
                                              },
                                              child: Text('Seleccionar'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                              icon: Icon(Icons.history, size: 18),
                              label: Text(_mostrandoMesEspecifico && _mesEspecifico != null
                                  ? 'Mes: ${DateFormat('MMM yyyy').format(_mesEspecifico!)}'
                                  : 'Ver mes específico'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _mostrandoMesEspecifico 
                                    ? Colors.purple.shade100 
                                    : Colors.grey.shade100,
                                foregroundColor: _mostrandoMesEspecifico 
                                    ? Colors.purple.shade700 
                                    : Colors.grey.shade700,
                                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          if (_mostrandoMesEspecifico) ...[
                            SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _mostrandoMesEspecifico = false;
                                  _mesEspecifico = null;
                                });
                                _actualizarFiltros();
                              },
                              icon: Icon(Icons.close, color: Colors.red.shade600),
                              tooltip: 'Volver a reservas del mes actual',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              SizedBox(height: 16),
              
              _buildSeccionFiltro(
                'Fecha de Referencia',
                Icons.event,
                Colors.blue,
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
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
                                primary: Colors.blue.shade600,
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
                    icon: Icon(Icons.calendar_today, size: 18),
                    label: Text(_fechaSeleccionada != null
                        ? DateFormat('dd/MM/yyyy').format(_fechaSeleccionada!)
                        : 'Seleccionar fecha'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: Colors.blue.shade700,
                      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              
              SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: _buildSeccionFiltro(
                      'Sede',
                      Icons.location_city,
                      Colors.orange,
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _sedeSeleccionada,
                            hint: Row(
                              children: [
                                Icon(Icons.all_inbox, size: 16, color: Colors.grey.shade600),
                                SizedBox(width: 8),
                                Text('Todas las sedes', style: TextStyle(color: Colors.grey.shade600)),
                              ],
                            ),
                            icon: Icon(Icons.keyboard_arrow_down, color: Colors.orange.shade600),
                            isExpanded: true,
                            items: [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Row(
                                  children: [
                                    Icon(Icons.all_inbox, size: 16, color: Colors.grey.shade600),
                                    SizedBox(width: 8),
                                    Text('Todas las sedes'),
                                  ],
                                ),
                              ),
                              ...sedeProvider.sedeNames.map((sede) => DropdownMenuItem(
                                    value: sede,
                                    child: Row(
                                      children: [
                                        Icon(Icons.location_city, size: 16, color: Colors.orange.shade600),
                                        SizedBox(width: 8),
                                        Expanded(child: Text(sede, overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _sedeSeleccionada = value;
                                _canchaSeleccionada = null;
                              });
                              _actualizarFiltros();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildSeccionFiltro(
                      'Cancha',
                      Icons.sports_soccer,
                      Colors.green,
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _canchaSeleccionada,
                            hint: Row(
                              children: [
                                Icon(Icons.all_inbox, size: 16, color: Colors.grey.shade600),
                                SizedBox(width: 8),
                                Expanded(child: Text('Todas', style: TextStyle(color: Colors.grey.shade600))),
                              ],
                            ),
                            icon: Icon(Icons.keyboard_arrow_down, color: Colors.green.shade600),
                            isExpanded: true,
                            items: [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Row(
                                  children: [
                                    Icon(Icons.all_inbox, size: 16, color: Colors.grey.shade600),
                                    SizedBox(width: 8),
                                    Text('Todas las canchas'),
                                  ],
                                ),
                              ),
                              ..._getCanchasFiltradas().map((cancha) => DropdownMenuItem(
                                    value: cancha.id,
                                    child: Row(
                                      children: [
                                        Icon(Icons.sports_soccer, size: 16, color: Colors.green.shade600),
                                        SizedBox(width: 8),
                                        Expanded(child: Text(cancha.nombre, overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _canchaSeleccionada = value;
                              });
                              _actualizarFiltros();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeccionFiltro(String titulo, IconData icono, Color color, Widget contenido) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, size: 18, color: color),
            SizedBox(width: 8),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        contenido,
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
    String periodoTexto = '';
    if (_periodoSeleccionado == 'Diario') {
      periodoTexto = 'del ${DateFormat('dd/MM/yyyy').format(_fechaSeleccionada!)}';
    } else if (_periodoSeleccionado == 'Semanal') {
      DateTime inicioSemana = _fechaSeleccionada!.subtract(Duration(days: _fechaSeleccionada!.weekday - 1));
      DateTime finSemana = inicioSemana.add(const Duration(days: 6));
      periodoTexto = 'del ${DateFormat('dd/MM').format(inicioSemana)} al ${DateFormat('dd/MM').format(finSemana)}';
    } else if (_periodoSeleccionado == 'Mensual') {
      if (_mostrandoMesEspecifico && _mesEspecifico != null) {
        periodoTexto = 'de ${DateFormat('MMMM yyyy').format(_mesEspecifico!)} (completo)';
      } else {
        periodoTexto = 'pasadas de ${DateFormat('MMMM yyyy').format(_fechaSeleccionada!)}';
      }
    }

    return Column(
      children: [
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade100, Colors.green.shade50],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Solo reservas confirmadas',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Período: $periodoTexto',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _buildTarjeta(
                title: 'Reservas Completas',
                value: '$_totalCompleto',
                subtitle: '\$${_montoCompleto.toStringAsFixed(0)}',
                color: Colors.green.shade400,
                icon: Icons.check_circle,
                delay: 100,
                onTap: () => _mostrarDetalleReservas('Completas', _reservasCompletas),
              ),
              SizedBox(width: 6),
              _buildTarjeta(
                title: 'Reservas Parciales',
                value: '$_totalParcial',
                subtitle: '\$${_montoParcial.toStringAsFixed(0)}',
                color: Colors.orange.shade400,
                icon: Icons.hourglass_empty,
                delay: 200,
                onTap: () => _mostrarDetalleReservas('Parciales', _reservasParciales),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),
        
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _buildTarjeta(
                title: 'Total Reservas',
                value: '$_totalReservasPeriodo',
                subtitle: '\$${_montoTotal.toStringAsFixed(0)}',
                color: Colors.blue.shade400,
                icon: Icons.sports_soccer,
                delay: 300,
                onTap: () => _mostrarDetalleReservas('Todas', _todasReservasPeriodo),
              ),
              SizedBox(width: 6),
              _buildTarjeta(
                title: 'Eficiencia de Cobro',
                value: '${_eficiencia.toStringAsFixed(1)}%',
                subtitle: '\$${_dineroTotalSinDescuentos.toStringAsFixed(0)}',
                color: Colors.purple.shade400,
                icon: Icons.trending_up,
                delay: 400,
                onTap: () => _mostrarDetalleEficiencia(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTarjeta({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    required int delay,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: FadeInUp(
        duration: Duration(milliseconds: 600 + delay),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.1), Colors.white],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '\$${_formatearMonto(double.tryParse(subtitle.replaceAll('\$', '').replaceAll(',', '')) ?? 0)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
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

  void _mostrarDetalleReservas(String tipo, List<Reserva> reservas) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reservas $tipo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      reservas.length.toString(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: reservas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                          SizedBox(height: 16),
                          Text(
                            'No hay reservas para mostrar',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: reservas.length,
                      itemBuilder: (context, index) {
                        final reserva = reservas[index];
                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: reserva.tipoAbono == TipoAbono.completo
                                          ? Colors.green.shade100
                                          : Colors.orange.shade100,
                                      child: Icon(
                                        reserva.esReservaRecurrente
                                            ? Icons.repeat_rounded
                                            : reserva.tipoAbono == TipoAbono.completo
                                                ? Icons.check_circle
                                                : Icons.hourglass_empty,
                                        color: reserva.esReservaRecurrente
                                            ? const Color(0xFF1A237E)
                                            : reserva.tipoAbono == TipoAbono.completo
                                                ? Colors.green.shade600
                                                : Colors.orange.shade600,
                                        size: 20,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            reserva.nombre ?? 'Sin nombre',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            reserva.cancha.nombre,
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '\$${_formatearMonto(reserva.montoPagado)}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                        if (reserva.tipoAbono == TipoAbono.parcial)
                                          Text(
                                            'de \$${_formatearMonto(reserva.montoTotal)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                Container(
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                                          SizedBox(width: 8),
                                          Text(DateFormat('dd/MM/yyyy').format(reserva.fecha)),
                                          SizedBox(width: 16),
                                          Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                                          SizedBox(width: 8),
                                          Text(reserva.horario.horaFormateada),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.phone, size: 16, color: Colors.grey.shade600),
                                          SizedBox(width: 8),
                                          Text(reserva.telefono ?? 'Sin teléfono'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    if (reserva.esReservaRecurrente)
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'RECURRENTE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF1A237E),
                                          ),
                                        ),
                                      ),
                                    if (reserva.precioPersonalizado)
                                      Container(
                                        margin: EdgeInsets.only(left: 8),
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'PRECIO ESPECIAL',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: ${reservas.length} reservas',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        '\$${_formatearMonto(reservas.fold(0.0, (total, r) => total + r.montoPagado))}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalleEficiencia() {
    final reservasConDescuento = _todasReservasPeriodo
        .where((r) => r.precioPersonalizado && r.precioOriginal != null)
        .toList();
    final reservasNormales = _todasReservasPeriodo
        .where((r) => !r.precioPersonalizado)
        .toList();
    
    double descuentoTotalOtorgado = reservasConDescuento.fold(0.0, 
        (total, r) => total + (r.precioOriginal! - r.montoTotal));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Text(
                    'Análisis de Eficiencia de Cobro',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade800,
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Text('Recaudado', 
                                  style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                              Text('\$${_formatearMonto(_dineroRecaudado)}', 
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Text('Sin Descuentos', 
                                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                              Text('\$${_formatearMonto(_dineroTotalSinDescuentos)}', 
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Text('Descuento', 
                                  style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                              Text('\$${_formatearMonto(descuentoTotalOtorgado)}', 
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.trending_up, color: Colors.purple.shade700),
                        SizedBox(width: 8),
                        Text(
                          'Eficiencia: ${_eficiencia.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  if (reservasConDescuento.isNotEmpty) ...[
                    Text(
                      'Reservas con Precio Personalizado (${reservasConDescuento.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade800,
                      ),
                    ),
                    SizedBox(height: 8),
                    ...reservasConDescuento.map((reserva) => Card(
                      margin: EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.shade100,
                          child: Icon(Icons.percent, color: Colors.purple.shade600),
                        ),
                        title: Text(reserva.nombre ?? 'Sin nombre'),
                        subtitle: Text('${reserva.cancha.nombre} - ${DateFormat('dd/MM').format(reserva.fecha)}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (reserva.precioOriginal != null)
                              Text(
                                '\$${_formatearMonto(reserva.precioOriginal!)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            Text(
                              '\$${_formatearMonto(reserva.montoTotal)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                    SizedBox(height: 16),
                  ],
                  if (reservasNormales.isNotEmpty) ...[
                    Text(
                      'Reservas con Precio Normal (${reservasNormales.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    SizedBox(height: 8),
                    ...reservasNormales.map((reserva) => Card(
                      margin: EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(Icons.attach_money, color: Colors.blue.shade600),
                        ),
                        title: Text(reserva.nombre ?? 'Sin nombre'),
                        subtitle: Text('${reserva.cancha.nombre} - ${DateFormat('dd/MM').format(reserva.fecha)}'),
                        trailing: Text(
                          '\$${_formatearMonto(reserva.montoTotal)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    )),
                  ],
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Eficiencia: ${_eficiencia.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}