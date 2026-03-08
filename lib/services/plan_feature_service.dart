import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'lugar_helper.dart';

/// Planes disponibles para un lugar.
enum LugarPlan {
  basico,
  premium,
  pro,
  prueba,
  desconocido,
}

/// Funcionalidades que se controlan por plan.
enum PlanFeature {
  gestionClientes,
  reservasRecurrentes,
  promocionesHoras,
  auditoriaAvanzada,
}

class PlanFeatureService {
  static LugarPlan _cachedPlan = LugarPlan.desconocido;
  static String? _cachedLugarId;

  /// Obtener el plan actual del lugar del usuario autenticado (con caché).
  static Future<LugarPlan> getCurrentPlan() async {
    final lugarId = await LugarHelper.getLugarId();
    if (lugarId == null) return LugarPlan.desconocido;

    if (_cachedLugarId == lugarId && _cachedPlan != LugarPlan.desconocido) {
      return _cachedPlan;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('lugares')
          .doc(lugarId)
          .get();

      if (!doc.exists) {
        _cachedLugarId = lugarId;
        _cachedPlan = LugarPlan.desconocido;
        return _cachedPlan;
      }

      final data = doc.data() as Map<String, dynamic>;
      final String? planStr = data['plan'] as String?;
      _cachedPlan = _mapStringToPlan(planStr);
      _cachedLugarId = lugarId;
      return _cachedPlan;
    } catch (e) {
      debugPrint('PlanFeatureService: error obteniendo plan del lugar: $e');
      _cachedPlan = LugarPlan.desconocido;
      return _cachedPlan;
    }
  }

  static LugarPlan _mapStringToPlan(String? plan) {
    switch ((plan ?? '').toLowerCase()) {
      case 'basico':
        return LugarPlan.basico;
      case 'premium':
        return LugarPlan.premium;
      case 'pro':
        return LugarPlan.pro;
      case 'prueba':
        return LugarPlan.prueba;
      default:
        return LugarPlan.desconocido;
    }
  }

  /// Valores por defecto de capacidad según el plan.
  static int? defaultMaxSedesForPlan(LugarPlan plan) {
    switch (plan) {
      case LugarPlan.basico:
        return 1;
      case LugarPlan.premium:
        return 3;
      case LugarPlan.pro:
        return null; // ilimitadas
      case LugarPlan.prueba:
        return 1;
      case LugarPlan.desconocido:
        return null;
    }
  }

  static int? defaultMaxCanchasForPlan(LugarPlan plan) {
    switch (plan) {
      case LugarPlan.basico:
        return 2;
      case LugarPlan.premium:
        return 6;
      case LugarPlan.pro:
        return null; // ilimitadas
      case LugarPlan.prueba:
        return 2;
      case LugarPlan.desconocido:
        return null;
    }
  }

  static String planDisplayName(LugarPlan plan) {
    switch (plan) {
      case LugarPlan.basico:
        return 'Básico';
      case LugarPlan.premium:
        return 'Premium';
      case LugarPlan.pro:
        return 'Pro';
      case LugarPlan.prueba:
        return 'Prueba';
      case LugarPlan.desconocido:
        return 'Sin plan';
    }
  }

  static String _mapPlanToString(LugarPlan plan) {
    switch (plan) {
      case LugarPlan.basico:
        return 'basico';
      case LugarPlan.premium:
        return 'premium';
      case LugarPlan.pro:
        return 'pro';
      case LugarPlan.prueba:
        return 'prueba';
      case LugarPlan.desconocido:
        return 'desconocido';
    }
  }

  /// Actualizar el plan del lugar actual en Firestore y refrescar caché.
  static Future<void> updatePlan(LugarPlan newPlan) async {
    final lugarId = await LugarHelper.getLugarId();
    if (lugarId == null) {
      throw Exception('No se pudo obtener el lugar actual para actualizar el plan.');
    }

    await FirebaseFirestore.instance
        .collection('lugares')
        .doc(lugarId)
        .update({'plan': _mapPlanToString(newPlan)});

    _cachedLugarId = lugarId;
    _cachedPlan = newPlan;
  }

  /// Capacidad efectiva de sedes para el lugar actual (null = ilimitadas).
  static Future<int?> getLugarMaxSedes() async {
    final lugarId = await LugarHelper.getLugarId();
    if (lugarId == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('lugares')
        .doc(lugarId)
        .get();

    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;

    final planStr = data['plan'] as String?;
    final plan = _mapStringToPlan(planStr);
    final dynamic maxSedesField = data['maxSedes'];

    int? maxSedes;
    if (maxSedesField is num) {
      maxSedes = maxSedesField.toInt();
    } else {
      maxSedes = defaultMaxSedesForPlan(plan);
    }

    return maxSedes;
  }

  /// Capacidad efectiva de canchas para el lugar actual (null = ilimitadas).
  static Future<int?> getLugarMaxCanchas() async {
    final lugarId = await LugarHelper.getLugarId();
    if (lugarId == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('lugares')
        .doc(lugarId)
        .get();

    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;

    final planStr = data['plan'] as String?;
    final plan = _mapStringToPlan(planStr);
    final dynamic maxCanchasField = data['maxCanchas'];

    int? maxCanchas;
    if (maxCanchasField is num) {
      maxCanchas = maxCanchasField.toInt();
    } else {
      maxCanchas = defaultMaxCanchasForPlan(plan);
    }

    return maxCanchas;
  }

  /// Verificar si una funcionalidad está permitida para un plan dado.
  static bool isFeatureAllowed(LugarPlan plan, PlanFeature feature) {
    switch (feature) {
      case PlanFeature.gestionClientes:
      case PlanFeature.reservasRecurrentes:
      case PlanFeature.promocionesHoras:
        // PREMIUM y PRO tienen estas funcionalidades
        return plan == LugarPlan.premium || plan == LugarPlan.pro;
      case PlanFeature.auditoriaAvanzada:
        // Solo PRO
        return plan == LugarPlan.pro;
    }
  }

  /// Nombre legible del plan requerido para mostrar en el modal.
  static String requiredPlanName(PlanFeature feature) {
    switch (feature) {
      case PlanFeature.auditoriaAvanzada:
        return 'Plan Pro';
      case PlanFeature.gestionClientes:
      case PlanFeature.reservasRecurrentes:
      case PlanFeature.promocionesHoras:
        return 'Plan Premium';
    }
  }

  /// Mensaje descriptivo de la funcionalidad, para usar en el modal.
  static String featureDisplayName(PlanFeature feature) {
    switch (feature) {
      case PlanFeature.gestionClientes:
        return 'Gestión de clientes';
      case PlanFeature.reservasRecurrentes:
        return 'Reservas fijas (recurrentes)';
      case PlanFeature.promocionesHoras:
        return 'Promociones de horas';
      case PlanFeature.auditoriaAvanzada:
        return 'Auditoría avanzada';
    }
  }

  /// Verifica el plan y, si no alcanza, muestra un modal elegante de mejora de plan.
  ///
  /// Devuelve true si se permite usar la funcionalidad, false si está bloqueada.
  static Future<bool> ensureFeatureAvailable(
    BuildContext context,
    PlanFeature feature,
  ) async {
    final plan = await getCurrentPlan();

    if (isFeatureAllowed(plan, feature)) {
      return true;
    }

    final requiredPlan = requiredPlanName(feature);
    final featureName = featureDisplayName(feature);

    if (!context.mounted) return false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.indigo.shade50,
                  Colors.white,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.workspace_premium,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Función disponible en $requiredPlan',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'La función "$featureName" no está incluida en tu plan actual.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Actualiza tu plan para desbloquear esta herramienta y gestionar mejor tu negocio.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Entendido'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return false;
  }
}

