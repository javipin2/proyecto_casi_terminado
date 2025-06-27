import 'dart:developer' as developer; // Importar para usar log
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/reserva.dart';
import '../../../models/cancha.dart';
import '../../../providers/cancha_provider.dart';
import '../../../providers/sede_provider.dart';

class GraficasScreen extends StatefulWidget {
  const GraficasScreen({super.key});

  @override
  GraficasScreenState createState() => GraficasScreenState();
}

class GraficasScreenState extends State<GraficasScreen> {
  DateTime? _selectedDate;
  String? _selectedSedeId;
  String? _selectedCanchaId;
  List<Reserva> _reservas = [];
  List<Reserva> _filteredReservas = [];
  bool _isLoading = false;
  String _filterType = 'Mes';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
      await Future.wait([
        canchaProvider.fetchAllCanchas(),
        canchaProvider.fetchHorasReservadas(),
        sedeProvider.fetchSedes(),
      ]);

      final querySnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .get()
          .timeout(const Duration(seconds: 10));

      final canchasMap = {
        for (var cancha in canchaProvider.canchas) cancha.id: cancha
      };

      _reservas = querySnapshot.docs
          .map((doc) => Reserva.fromFirestoreWithCanchas(doc, canchasMap))
          .toList();

      _applyFilters();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: const Color(0xFFD32F2F),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    List<Reserva> filtered = List.from(_reservas);

    // Aplicar filtro de sede
    if (_selectedSedeId != null && _selectedSedeId!.isNotEmpty) {
      filtered = filtered.where((reserva) {
        // Comparar con el sedeId de la cancha de la reserva
        return reserva.cancha.sedeId == _selectedSedeId;
      }).toList();
      
      developer.log('Filtro por sede aplicado. Sede: $_selectedSedeId, Reservas: ${filtered.length}', name: 'GraficasScreen');
    }

    // Aplicar filtro de cancha
    if (_selectedCanchaId != null && _selectedCanchaId!.isNotEmpty) {
      filtered = filtered.where((reserva) => reserva.cancha.id == _selectedCanchaId).toList();
      
      developer.log('Filtro por cancha aplicado. Cancha: $_selectedCanchaId, Reservas: ${filtered.length}', name: 'GraficasScreen');
    }

    // Aplicar filtro de fecha
    if (_selectedDate != null) {
      filtered = filtered.where((reserva) => _isSameDay(reserva.fecha, _selectedDate!)).toList();
      
      developer.log('Filtro por fecha aplicado. Fecha: $_selectedDate, Reservas: ${filtered.length}', name: 'GraficasScreen');
    }

    setState(() => _filteredReservas = filtered);
    
    developer.log('Filtros aplicados. Total reservas filtradas: ${_filteredReservas.length}', name: 'GraficasScreen');
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  bool _isSameMonth(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month;
  }

  bool _isInSameWeek(DateTime date1, DateTime date2) {
    final startOfWeek1 = date1.subtract(Duration(days: date1.weekday - 1));
    final startOfWeek2 = date2.subtract(Duration(days: date2.weekday - 1));
    return _isSameDay(startOfWeek1, startOfWeek2);
  }

  void _clearFilters() {
    setState(() {
      _selectedDate = null;
      _selectedSedeId = null;
      _selectedCanchaId = null;
      _filterType = 'Mes';
    });
    _applyFilters();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1976D2),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF424242),
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _applyFilters();
    }
  }

  Map<String, dynamic> _getStats() {
    final currentDate = DateTime.now();
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final totalCanchas = canchaProvider.canchas.length;
    final totalSedes = sedeProvider.sedes.length;

    final periodFilteredReservas = _filteredReservas.where((reserva) {
      switch (_filterType) {
        case 'Día':
          return _isSameDay(reserva.fecha, currentDate);
        case 'Semana':
          return _isInSameWeek(reserva.fecha, currentDate);
        case 'Mes':
          return _isSameMonth(reserva.fecha, currentDate);
        default:
          return true;
      }
    }).toList();

    final totalReservas = periodFilteredReservas.length;

    String canchaMasPedida = 'Sin datos';
    String sedeMasPedida = 'Sin datos';
    String horaMasPedida = 'Sin datos';

    if (periodFilteredReservas.isNotEmpty) {
      final canchaCount = <String, int>{};
      final sedeCount = <String, int>{};
      final horaCount = <String, int>{};

      for (var reserva in periodFilteredReservas) {
        canchaCount[reserva.cancha.nombre] = (canchaCount[reserva.cancha.nombre] ?? 0) + 1;
        final sede = sedeProvider.sedes.firstWhere(
          (s) => s['id'] == reserva.sede,
          orElse: () => {'nombre': 'Desconocida'},
        );
        sedeCount[sede['nombre'] as String] = (sedeCount[sede['nombre'] as String] ?? 0) + 1;
        horaCount[reserva.horario.horaFormateada] = (horaCount[reserva.horario.horaFormateada] ?? 0) + 1;
      }

      canchaMasPedida = canchaCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      sedeMasPedida = sedeCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      horaMasPedida = horaCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }

    return {
      'totalReservas': totalReservas,
      'totalCanchas': totalCanchas,
      'totalSedes': totalSedes,
      'canchaMasPedida': canchaMasPedida,
      'sedeMasPedida': sedeMasPedida,
      'horaMasPedida': horaMasPedida,
    };
  }

  List<BarChartGroupData> _getSedeReservasData() {
    if (_filteredReservas.isEmpty) return [];

    final currentDate = DateTime.now();
    final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
    final periodFilteredReservas = _filteredReservas.where((reserva) {
      switch (_filterType) {
        case 'Día':
          return _isSameDay(reserva.fecha, currentDate);
        case 'Semana':
          return _isInSameWeek(reserva.fecha, currentDate);
        case 'Mes':
          return _isSameMonth(reserva.fecha, currentDate);
        default:
          return true;
      }
    }).toList();

    final sedeCount = <String, int>{};
    for (var reserva in periodFilteredReservas) {
      final sede = sedeProvider.sedes.firstWhere(
        (s) => s['id'] == reserva.sede,
        orElse: () => {'nombre': 'Desconocida'},
      );
      final nombreSede = sede['nombre'] as String;
      sedeCount[nombreSede] = (sedeCount[nombreSede] ?? 0) + 1;
    }

    final sedes = sedeCount.keys.toList();
    return List.generate(sedes.length, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: sedeCount[sedes[index]]!.toDouble(),
            gradient: const LinearGradient(
              colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 24,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 0,
              color: const Color(0xFFEEEEEE),
            ),
          ),
        ],
      );
    });
  }

  List<BarChartGroupData> _getCanchaReservasData() {
    if (_filteredReservas.isEmpty) return [];

    final currentDate = DateTime.now();
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final periodFilteredReservas = _filteredReservas.where((reserva) {
      switch (_filterType) {
        case 'Día':
          return _isSameDay(reserva.fecha, currentDate);
        case 'Semana':
          return _isInSameWeek(reserva.fecha, currentDate);
        case 'Mes':
          return _isSameMonth(reserva.fecha, currentDate);
        default:
          return true;
      }
    }).toList();

    final canchaCount = <String, int>{};
    for (var reserva in periodFilteredReservas) {
      canchaCount[reserva.cancha.id] = (canchaCount[reserva.cancha.id] ?? 0) + 1;
    }

    final canchas = canchaCount.keys.map((id) => canchaProvider.canchas.firstWhere((c) => c.id == id).nombre).toList();
    return List.generate(canchas.length, (index) {
      final canchaId = canchaCount.keys.elementAt(index);
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: canchaCount[canchaId]!.toDouble(),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFA726), Color(0xFFF57C00)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 24,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 0,
              color: const Color(0xFFEEEEEE),
            ),
          ),
        ],
      );
    });
  }

  List<BarChartGroupData> _getHorarioReservasData() {
    if (_filteredReservas.isEmpty) return [];

    final currentDate = DateTime.now();
    final periodFilteredReservas = _filteredReservas.where((reserva) {
      switch (_filterType) {
        case 'Día':
          return _isSameDay(reserva.fecha, currentDate);
        case 'Semana':
          return _isInSameWeek(reserva.fecha, currentDate);
        case 'Mes':
          return _isSameMonth(reserva.fecha, currentDate);
        default:
          return true;
      }
    }).toList();

    final horaCount = <String, int>{};
    for (var reserva in periodFilteredReservas) {
      horaCount[reserva.horario.horaFormateada] = (horaCount[reserva.horario.horaFormateada] ?? 0) + 1;
    }

    final horas = horaCount.keys.toList();
    return List.generate(horas.length, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: horaCount[horas[index]]!.toDouble(),
            gradient: const LinearGradient(
              colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 24,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 0,
              color: const Color(0xFFEEEEEE),
            ),
          ),
        ],
      );
    });
  }

  Map<String, dynamic> _getReservasTemporalesData() {
    if (_filteredReservas.isEmpty) {
      return {'spots': <FlSpot>[], 'labels': <String>[]};
    }

    final currentDate = DateTime.now();
    final reservasData = <String, int>{};

    int historicalRange;
    switch (_filterType) {
      case 'Día':
        historicalRange = 10;
        break;
      case 'Semana':
        historicalRange = 4;
        break;
      case 'Mes':
        historicalRange = 6;
        break;
      default:
        historicalRange = 6;
    }

    for (var reserva in _filteredReservas) {
      String key;
      DateTime startDate;
      switch (_filterType) {
        case 'Día':
          startDate = currentDate.subtract(Duration(days: historicalRange - 1));
          if (reserva.fecha.isBefore(startDate) || reserva.fecha.isAfter(currentDate)) continue;
          key = DateFormat('dd/MM/yyyy').format(reserva.fecha);
          break;
        case 'Semana':
          startDate = currentDate.subtract(Duration(days: (historicalRange - 1) * 7));
          final startOfWeek = reserva.fecha.subtract(Duration(days: reserva.fecha.weekday - 1));
          if (startOfWeek.isBefore(startDate) || startOfWeek.isAfter(currentDate)) continue;
          final endOfWeek = startOfWeek.add(const Duration(days: 6));
          key = '${DateFormat('dd/MM').format(startOfWeek)}-${DateFormat('dd/MM').format(endOfWeek)}';
          break;
        case 'Mes':
        default:
          startDate = DateTime(currentDate.year, currentDate.month - historicalRange + 1, 1);
          if (reserva.fecha.isBefore(startDate) || reserva.fecha.isAfter(currentDate)) continue;
          key = DateFormat('MMM yyyy', 'es').format(reserva.fecha);
          break;
      }
      reservasData[key] = (reservasData[key] ?? 0) + 1;
    }

    final sortedEntries = reservasData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = sortedEntries.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value.toDouble());
    }).toList();

    final labels = sortedEntries.map((entry) => entry.key).toList();

    return {
      'spots': spots,
      'labels': labels,
    };
  }

  @override
  Widget build(BuildContext context) {
    final canchaProvider = Provider.of<CanchaProvider>(context);
    final sedeProvider = Provider.of<SedeProvider>(context);
  
    final stats = _getStats();
    final isWide = MediaQuery.of(context).size.width > 800;
    

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Análisis de Reservas",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF212121),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF1976D2)),
            onPressed: _loadData,
            tooltip: 'Actualizar datos',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1976D2)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cargando datos...',
                    style: TextStyle(
                      fontSize: 16,
                      color: const Color(0xFF616161),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filtros',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF212121),
                            ),
                          ),
                          const SizedBox(height: 20),
                          isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildFilterDropdown()),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildDateSelector()),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildSedeDropdown(sedeProvider)),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildCanchaDropdown(canchaProvider)),
                                ],
                              )
                            : Column(
                                children: [
                                  _buildFilterDropdown(),
                                  const SizedBox(height: 16),
                                  _buildDateSelector(),
                                  const SizedBox(height: 16),
                                  _buildSedeDropdown(sedeProvider),
                                  const SizedBox(height: 16),
                                  _buildCanchaDropdown(canchaProvider),
                                ],
                              ),
                          const SizedBox(height: 20),
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.clear, size: 18),
                              label: const Text('Limpiar Filtros'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD32F2F),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estadísticas - Período: $_filterType',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF212121),
                            ),
                          ),
                          const SizedBox(height: 20),
                          isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildStatsColumn(stats, 0)),
                                    const SizedBox(width: 16),
                                    Expanded(child: _buildStatsColumn(stats, 1)),
                                  ],
                                )
                              : _buildStatsColumn(stats, -1),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_filteredReservas.isNotEmpty) ...[
                    isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: _buildChart('Reservas por Sede', _buildSedeChart())),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: _buildChart('Reservas por Cancha', _buildCanchaChart())),
                            ],
                          )
                        : Column(
                            children: [
                              _buildChart('Reservas por Sede', _buildSedeChart()),
                              const SizedBox(height: 24),
                              _buildChart('Reservas por Cancha', _buildCanchaChart()),
                            ],
                          ),
                    const SizedBox(height: 24),
                    _buildChart('Horarios Más Pedidos', _buildHorarioChart()),
                    const SizedBox(height: 24),
                    _buildChart('Reservas en el Tiempo ($_filterType)', _buildTemporalChart()),
                  ] else
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 64,
                              color: const Color(0xFFB0BEC5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No hay datos para mostrar',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF616161),
                              ),
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

  Widget _buildFilterDropdown() {
    return DropdownButtonFormField<String>(
      value: _filterType,
      decoration: InputDecoration(
        labelText: 'Período',
        labelStyle: const TextStyle(color: Color(0xFF1976D2)),
        filled: true,
        fillColor: const Color(0xFFE3F2FD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBBDEFB), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
        ),
        prefixIcon: const Icon(Icons.filter_list, color: Color(0xFF1976D2)),
      ),
      items: ['Día', 'Semana', 'Mes']
          .map((type) => DropdownMenuItem(value: type, child: Text(type)))
          .toList(),
      onChanged: (value) {
        if (value != null && value != _filterType) {
          setState(() {
            _filterType = value;
            _selectedDate = null;
          });
          _applyFilters();
        }
      },
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Color(0xFF212121),
      ),
      dropdownColor: Colors.white,
    );
  }

  Widget _buildDateSelector() {
    return InkWell(
      onTap: () => _selectDate(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Fecha',
          labelStyle: const TextStyle(color: Color(0xFF1976D2)),
          filled: true,
          fillColor: const Color(0xFFE3F2FD),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFBBDEFB), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
          ),
          prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF1976D2)),
        ),
        child: Text(
          _selectedDate == null
              ? 'Todas las fechas'
              : DateFormat('dd/MM/yyyy').format(_selectedDate!),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFF212121),
          ),
        ),
      ),
    );
  }

  Widget _buildSedeDropdown(SedeProvider sedeProvider) {
    return DropdownButtonFormField<String>(
      value: _selectedSedeId,
      decoration: InputDecoration(
        labelText: 'Sede',
        labelStyle: const TextStyle(color: Color(0xFF1976D2)),
        filled: true,
        fillColor: const Color(0xFFE3F2FD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBBDEFB), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
        ),
        prefixIcon: const Icon(Icons.location_on, color: Color(0xFF1976D2)),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todas las sedes')),
        ...sedeProvider.sedes.map((sede) => DropdownMenuItem(
              value: sede['id'] as String,
              child: Text(sede['nombre'] as String),
            )),
      ],
      onChanged: (value) {
        if (value != _selectedSedeId) {
          setState(() {
            _selectedSedeId = value;
            _selectedCanchaId = null; // Resetear cancha al cambiar sede
          });
          _applyFilters();
        }
      },
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Color(0xFF212121),
      ),
      dropdownColor: Colors.white,
    );
  }

  Widget _buildCanchaDropdown(CanchaProvider canchaProvider) {
    // Filtrar canchas según la sede seleccionada
    final canchas = _selectedSedeId != null && _selectedSedeId!.isNotEmpty
        ? canchaProvider.canchas.where((cancha) => cancha.sedeId == _selectedSedeId).toList()
        : canchaProvider.canchas;

    // Depuración mejorada
    developer.log('Sede seleccionada: $_selectedSedeId', name: 'GraficasScreen');
    developer.log('Total canchas: ${canchaProvider.canchas.length}', name: 'GraficasScreen');
    developer.log('Canchas filtradas: ${canchas.length}', name: 'GraficasScreen');
    developer.log('Detalle canchas disponibles: ${canchas.map((c) => "ID: ${c.id}, Nombre: ${c.nombre}, SedeId: ${c.sedeId}").toList()}', name: 'GraficasScreen');

    // Si no hay canchas disponibles para la sede seleccionada, resetear la cancha seleccionada
    if (_selectedCanchaId != null && !canchas.any((cancha) => cancha.id == _selectedCanchaId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedCanchaId = null;
        });
      });
    }

    // Mostrar mensaje si no hay canchas disponibles y hay una sede seleccionada
    if (canchas.isEmpty && _selectedSedeId != null && _selectedSedeId!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cancha',
            style: TextStyle(color: Color(0xFF1976D2), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBDEFB), width: 1.5),
            ),
            child: const Text(
              'No hay canchas disponibles para esta sede',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF616161),
              ),
            ),
          ),
        ],
      );
    }

    // Si no hay sede seleccionada y no hay canchas, mostrar mensaje general
    if (canchas.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cancha',
            style: TextStyle(color: Color(0xFF1976D2), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBDEFB), width: 1.5),
            ),
            child: const Text(
              'No hay canchas disponibles',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF616161),
              ),
            ),
          ),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedCanchaId,
      decoration: InputDecoration(
        labelText: 'Cancha',
        labelStyle: const TextStyle(color: Color(0xFF1976D2)),
        filled: true,
        fillColor: const Color(0xFFE3F2FD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBBDEFB), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
        ),
        prefixIcon: const Icon(Icons.sports_soccer, color: Color(0xFF1976D2)),
      ),
      items: [
        // Solo mostrar "Todas las canchas" si no hay sede seleccionada
        if (_selectedSedeId == null || _selectedSedeId!.isEmpty)
          const DropdownMenuItem(value: null, child: Text('Todas las canchas'))
        else
          const DropdownMenuItem(value: null, child: Text('Todas las canchas de esta sede')),
        ...canchas.map((cancha) => DropdownMenuItem(
              value: cancha.id,
              child: Text(cancha.nombre),
            )),
      ],
      onChanged: (value) {
        if (value != _selectedCanchaId) {
          setState(() => _selectedCanchaId = value);
          _applyFilters();
        }
      },
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Color(0xFF212121),
      ),
      dropdownColor: Colors.white,
    );
  }

  Widget _buildStatsColumn(Map<String, dynamic> stats, int column) {
    final items = [
      ['Total Reservas', '${stats['totalReservas']}', Icons.book_online, const Color(0xFF1976D2)],
      ['Total Canchas', '${stats['totalCanchas']}', Icons.sports_soccer, const Color(0xFF2E7D32)],
      ['Total Sedes', '${stats['totalSedes']}', Icons.location_on, const Color(0xFFD32F2F)],
      ['Cancha Popular', stats['canchaMasPedida'], Icons.star, const Color(0xFFF57C00)],
      ['Sede Popular', stats['sedeMasPedida'], Icons.place, const Color(0xFF7B1FA2)],
      ['Hora Popular', stats['horaMasPedida'], Icons.access_time, const Color(0xFF00897B)],
    ];

    if (column == -1) {
      return Column(
        children: items.map((item) => _buildStatItem(item[0], item[1], item[2], item[3])).toList(),
      );
    } else {
      final start = column * 3;
      final end = (start + 3).clamp(0, items.length);
      return Column(
        children: items
            .sublist(start, end)
            .map((item) => _buildStatItem(item[0], item[1], item[2], item[3]))
            .toList(),
      );
    }
  }

  Widget _buildStatItem(String title, String value, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.1),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF616161),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF212121),
                      ),
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildChart(String title, Widget chart) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF212121),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 280,
              child: chart,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSedeChart() {
    final sedeProvider = Provider.of<SedeProvider>(context);
    final sedes = sedeProvider.sedes.map((s) => s['id'] as String).toSet().toList();
    final sedeMap = {for (var s in sedeProvider.sedes) s['id']: s['nombre']};

    return BarChart(
      BarChartData(
        barGroups: _getSedeReservasData(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < sedes.length) {
                  final sedeId = sedes[value.toInt()];
                  final nombreSede = sedeMap[sedeId] ?? 'Desconocida';
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      nombreSede,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF424242),
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF424242),
                ),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _filteredReservas.isNotEmpty
              ? (_filteredReservas.length / 5).ceilToDouble()
              : 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: const Color(0xFFEEEEEE),
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: const Color(0xFFEEEEEE),
            width: 1,
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color.fromRGBO(25, 118, 210, 0.9),
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (group.x.toInt() >= 0 && group.x.toInt() < sedes.length) {
                final nombreSede = sedeMap[sedes[group.x.toInt()]] ?? 'Desconocida';
                return BarTooltipItem(
                  '$nombreSede: ${rod.toY.toInt()} reservas',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }
              return null;
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCanchaChart() {
    final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
    final canchaIds = canchaProvider.canchas.map((c) => c.id).toSet().toList();

    return BarChart(
      BarChartData(
        barGroups: _getCanchaReservasData(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < canchaIds.length) {
                  final canchaId = canchaIds[value.toInt()];
                  final nombreCancha = canchaProvider.canchas.firstWhere(
                    (c) => c.id == canchaId,
                    orElse: () => Cancha(
                      id: '',
                      nombre: 'Desconocida',
                      descripcion: '',
                      imagen: '',
                      techada: false,
                      ubicacion: '',
                      precio: 0,
                      sedeId: '',
                      preciosPorHorario: {},
                    ),
                  ).nombre;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      nombreCancha,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF424242),
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF424242),
                ),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _filteredReservas.isNotEmpty
              ? (_filteredReservas.length / 5).ceilToDouble()
              : 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: const Color(0xFFEEEEEE),
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: const Color(0xFFEEEEEE),
            width: 1,
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color.fromRGBO(245, 124, 0, 0.9),
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (group.x.toInt() >= 0 && group.x.toInt() < canchaIds.length) {
                final canchaId = canchaIds[group.x.toInt()];
                final nombreCancha = canchaProvider.canchas.firstWhere(
                  (c) => c.id == canchaId,
                  orElse: () => Cancha(
                    id: '',
                    nombre: 'Desconocida',
                    descripcion: '',
                    imagen: '',
                    techada: false,
                    ubicacion: '',
                    precio: 0,
                    sedeId: '',
                    preciosPorHorario: {},
                  ),
                ).nombre;
                return BarTooltipItem(
                  '$nombreCancha: ${rod.toY.toInt()} reservas',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }
              return null;
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHorarioChart() {
    return BarChart(
      BarChartData(
        barGroups: _getHorarioReservasData(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final horas = _filteredReservas.map((r) => r.horario.horaFormateada).toSet().toList();
                return value.toInt() >= 0 && value.toInt() < horas.length
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          horas[value.toInt()],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF424242),
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF424242),
                ),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _filteredReservas.isNotEmpty
              ? (_filteredReservas.length / 5).ceilToDouble()
              : 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: const Color(0xFFEEEEEE),
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: const Color(0xFFEEEEEE),
            width: 1,
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color.fromRGBO(46, 125, 50, 0.9),
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final horas = _filteredReservas.map((r) => r.horario.horaFormateada).toSet().toList();
              return BarTooltipItem(
                '${horas[group.x.toInt()]}: ${rod.toY.toInt()} reservas',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTemporalChart() {
    final temporalData = _getReservasTemporalesData();
    final spots = temporalData['spots'] as List<FlSpot>;
    final labels = temporalData['labels'] as List<String>;

    if (spots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 48,
              color: const Color(0xFFB0BEC5),
            ),
            const SizedBox(height: 8),
            Text(
              'No hay datos suficientes para mostrar la gráfica temporal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF616161),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: const LinearGradient(
              colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            barWidth: 5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                    radius: 6,
                    color: const Color(0xFF1976D2),
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: const LinearGradient(
                colors: [
                  Color.fromRGBO(66, 165, 245, 0.5),
                  Color.fromRGBO(25, 118, 210, 0.5),
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: spots.length > 10 ? (spots.length / 5).ceil().toDouble() : 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF424242),
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF424242),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: spots.isNotEmpty
              ? (spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) / 5)
                  .ceilToDouble()
              : 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: const Color(0xFFEEEEEE),
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: const Color(0xFFEEEEEE),
            width: 1,
          ),
        ),
        minX: 0,
        maxX: spots.isNotEmpty ? (spots.length - 1).toDouble() : 0,
        minY: 0,
        maxY: spots.isNotEmpty
            ? (spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2)
            : 10,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color.fromRGBO(25, 118, 210, 0.9),
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                if (index >= 0 && index < labels.length) {
                  return LineTooltipItem(
                    '${labels[index]}: ${spot.y.toInt()} reservas',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                }
                return null;
              }).whereType<LineTooltipItem>().toList();
            },
          ),
        ),
      ),
    );
  }
}