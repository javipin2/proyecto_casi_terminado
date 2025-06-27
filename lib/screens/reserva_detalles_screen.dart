import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/providers/sede_provider.dart';
import '../models/cancha.dart';
import '../models/horario.dart';
import '../models/reserva.dart';

class ReservaDetallesScreen extends StatelessWidget {
  final Cancha cancha;
  final DateTime fecha;
  final Horario horario;
  final String sede;
  

  const ReservaDetallesScreen({
    super.key,
    required this.cancha,
    required this.fecha,
    required this.horario,
    required this.sede,
  });

  Future<Reserva?> _fetchReserva() async {
    final String fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
    final String horaNormalizada = Horario.normalizarHora(horario.horaFormateada);
    final String reservaId =
        '${fechaStr}_${cancha.id}_${horaNormalizada}_${sede}';

    print('🔍 Buscando reserva con ID: $reservaId');

    try {
      // Intento 1: Buscar por ID determinista
      final docSnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(reservaId)
          .get();

      if (docSnapshot.exists) {
        print('✅ Reserva encontrada con ID: $reservaId');
        return Reserva.fromFirestoreWithCanchas(docSnapshot, {cancha.id: cancha});
      }

      // Intento 2: Buscar por campos
      print('⚠️ No se encontró reserva con ID, buscando por campos...');
      final querySnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .where('fecha', isEqualTo: fechaStr)
          .where('cancha_id', isEqualTo: cancha.id)
          .where('sede', isEqualTo: sede)
          .where('horario', isEqualTo: horaNormalizada)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        print('✅ Reserva encontrada por campos');
        return Reserva.fromFirestoreWithCanchas(
            querySnapshot.docs.first, {cancha.id: cancha});
      }

      print('❌ No se encontró ninguna reserva');
      return null;
    } catch (e) {
      print('🔥 Error al cargar reserva: $e');
      throw Exception('Error al cargar reserva: $e');
    }
  }

  String _maskPhoneNumber(String? telefono) {
    if (telefono == null || telefono.length < 4) return '****';
    final lastFour = telefono.substring(telefono.length - 4);
    return '*****$lastFour';
  }

  String _maskEmail(String? email) {
    if (email == null || !email.contains('@')) return '****@****';
    final parts = email.split('@');
    final prefix = parts[0];
    final domain = parts[1];
    final visiblePrefix =
        prefix.length <= 4 ? prefix : prefix.substring(0, 4);
    return '$visiblePrefix****@$domain';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF424242)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'Detalles de la Reserva',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF424242),
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<Reserva?>(
        future: _fetchReserva(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.green.shade300),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cargando detalles...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 70, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Error al cargar la reserva',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Forzar recarga
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReservaDetallesScreen(
                            cancha: cancha,
                            fecha: fecha,
                            horario: horario,
                            sede: sede,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Volver'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 70, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'No se encontró la reserva',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReservaDetallesScreen(
                            cancha: cancha,
                            fecha: fecha,
                            horario: horario,
                            sede: sede,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Volver'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final reserva = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(13),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Información de la Reserva',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        icon: Icons.sports_soccer,
                        label: 'Cancha',
                        value: reserva.cancha.nombre,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        icon: Icons.calendar_today,
                        label: 'Fecha',
                        value: DateFormat('EEEE, d MMMM yyyy', 'es')
                            .format(reserva.fecha),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        icon: Icons.access_time,
                        label: 'Hora',
                        value: reserva.horario.horaFormateada,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        icon: Icons.location_on,
                        label: 'Sede',
                        value: Provider.of<SedeProvider>(context, listen: false)
                            .sedes
                            .firstWhere(
                              (sede) => sede['id'] == reserva.sede,
                              orElse: () => {'nombre': reserva.sede}, // Fallback al ID si no se encuentra
                            )['nombre'] as String,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(13),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Datos del Cliente',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        icon: Icons.person,
                        label: 'Nombre',
                        value: reserva.nombre ?? 'No registrado',
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        icon: Icons.phone,
                        label: 'Teléfono',
                        value: _maskPhoneNumber(reserva.telefono),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        icon: Icons.email,
                        label: 'Correo',
                        value: _maskEmail(reserva.email),
                      ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Volver'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(
      {required IconData icon, required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}