import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ciudad_preference_service.dart';

/// ID del canal de notificaciones Android para promociones.
const String androidChannelIdPromociones = 'promociones';

/// Clave VAPID para FCM en web (Cloud Messaging key pair). Necesaria para que getToken en web devuelva un token válido para push.
const String _webVapidKey =
    'BLvpYxLqgXyrlHcfAtaWjXYP7SJn4ws5K3h6e7Mh3X4hJVdbHzYal5SW3jB2jcd8GTgQUKnT9mgjQzaF5cbZrmk';

/// Clave para persistir un ID estable por instalación (evita crear un doc nuevo por cada refresh del token).
const String _fcmDeviceIdKey = 'fcm_device_id';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('PushNotificationService: background message ${message.messageId}');
}

/// Servicio de notificaciones push por ciudad.
/// Los usuarios (sin login) reciben promociones solo de la ciudad seleccionada (web y móvil).
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;

  PushNotificationService._();

  /// Si se asigna, se llama cuando el permiso de notificaciones está denegado/bloqueado.
  /// Útil para mostrar un SnackBar o diálogo en la app (ej.: desde un context con navigatorKey).
  static void Function(String message)? onPermissionDenied;

  /// Mensajes de permiso denegado pendientes (p. ej. antes de tener context). La app puede leer y mostrar.
  static final List<String> pendingPermissionDeniedMessages = [];

  static void _notifyPermissionDenied(String message) {
    pendingPermissionDeniedMessages.add(message);
    onPermissionDenied?.call(message);
  }

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _deviceId;

  /// Identificador estable por instalación de la app. El backend lo usa para actualizar
  /// el mismo documento cuando el token FCM cambia, en lugar de crear uno nuevo.
  Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_fcmDeviceIdKey);
    if (id == null || id.isEmpty) {
      id = _generateDeviceId();
      await prefs.setString(_fcmDeviceIdKey, id);
    }
    _deviceId = id;
    return id;
  }

  static String _generateDeviceId() {
    final r = DateTime.now().microsecondsSinceEpoch;
    final values = List<int>.generate(16, (i) => ((r + i * 31) * (i + 7)) & 0xff);
    return values.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Inicializa FCM y registra el token con la ciudad en caché (si hay).
  /// Escucha el refresh del token para actualizar el mismo registro en backend.
  Future<void> initialize() async {
    if (_initialized) return;

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
    await _requestPermissionIfNeeded();
    await _initLocalNotifications();
    _setupMessageHandlers();
    _setupTokenRefreshListener();
    _initialized = true;
    await registerTokenWithCurrentCiudad();
    debugPrint('PushNotificationService: initialized (notificaciones por ciudad)');
  }

  void _setupTokenRefreshListener() {
    _messaging.onTokenRefresh.listen((String newToken) {
      debugPrint('PushNotificationService: token refreshed, re-registering');
      registerTokenWithCurrentCiudad();
    });
  }

  Future<void> _requestPermissionIfNeeded() async {
    if (kIsWeb) {
      try {
        final settings = await _messaging.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          await _messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );
        }
      } catch (_) {}
      return;
    }
    final settings = await _messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) return;
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      const channel = AndroidNotificationChannel(
        androidChannelIdPromociones,
        'Promociones TuCanchaFácil',
        description: 'Nuevas promociones de canchas',
        importance: Importance.high,
        playSound: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  void _onLocalNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      debugPrint('PushNotificationService: local notification tapped $payload');
    }
  }

  /// Plataforma actual para el backend.
  String get _platform {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'web';
  }

  /// Obtiene el token FCM. En web pide permiso antes si hace falta.
  Future<String?> _getToken() async {
    if (kIsWeb) {
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        final permission = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (permission != AuthorizationStatus.authorized &&
            permission != AuthorizationStatus.provisional) {
          const msg =
              'Para recibir promociones, permite notificaciones en la configuración del sitio '
              '(icono de candado en la barra de direcciones → Notificaciones → Permitir).';
          debugPrint('PushNotificationService: permiso denegado o bloqueado. $msg');
          _notifyPermissionDenied(msg);
          return null;
        }
      }
    }
    try {
      if (kIsWeb) {
        return await _messaging.getToken(vapidKey: _webVapidKey);
      }
      return await _messaging.getToken();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-blocked' || e.message?.contains('permission') == true) {
        const msg =
            'Notificaciones bloqueadas. Actívalas en la configuración del sitio para recibir promociones.';
        debugPrint('PushNotificationService: $msg');
        _notifyPermissionDenied(msg);
      } else {
        debugPrint('PushNotificationService: getToken error ${e.code} ${e.message}');
      }
      return null;
    } catch (e) {
      if (e.toString().contains('permission-blocked') ||
          e.toString().contains('permission')) {
        const msg =
            'Notificaciones bloqueadas. Actívalas en la configuración del sitio para recibir promociones.';
        debugPrint('PushNotificationService: $msg');
        _notifyPermissionDenied(msg);
      } else {
        debugPrint('PushNotificationService: getToken error $e');
      }
      return null;
    }
  }

  /// Registra el token con la ciudad actual en caché. Llamar al iniciar la app.
  Future<void> registerTokenWithCurrentCiudad() async {
    final ciudad = await CiudadPreferenceService.getSelectedCiudad();
    if (ciudad == null) {
      debugPrint('PushNotificationService: sin ciudad seleccionada, no se registra token');
      return;
    }
    await updateCiudadForNotifications(ciudad.id);
  }

  /// Actualiza el registro para que las notificaciones lleguen solo de [ciudadId].
  /// Si [lugarId] se proporciona (admins), las notificaciones de auditoría se filtran por lugar.
  /// Usa un deviceId estable para que el backend actualice el mismo documento en vez de crear otro.
  Future<void> updateCiudadForNotifications(String? ciudadId, {String? lugarId}) async {
    final effectiveCiudadId = ciudadId?.trim();
    if (effectiveCiudadId == null || effectiveCiudadId.isEmpty) return;
    String? token = await _getToken();
    if (token == null) {
      await Future.delayed(const Duration(milliseconds: 800));
      token = await _getToken();
    }
    if (token == null) {
      debugPrint('PushNotificationService: no token, no se puede registrar ciudad');
      return;
    }
    try {
      final deviceId = await _getOrCreateDeviceId();
      final data = <String, dynamic>{
        'token': token,
        'deviceId': deviceId,
        'ciudadId': effectiveCiudadId,
        'platform': _platform,
      };
      if (lugarId != null && lugarId.isNotEmpty) {
        data['lugarId'] = lugarId;
      }
      final callable = FirebaseFunctions.instance.httpsCallable('registerFcmToken');
      await callable.call(data);
      debugPrint('PushNotificationService: registrado para ciudad $effectiveCiudadId${lugarId != null ? ', lugar $lugarId' : ''}');
    } catch (e) {
      debugPrint('PushNotificationService: registerFcmToken error $e');
    }
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('PushNotificationService: foreground message ${message.messageId}');
      final notification = message.notification;
      if (notification != null) {
        _showLocalNotification(
          id: message.hashCode,
          title: notification.title ?? 'TuCanchaFácil',
          body: notification.body ?? '',
          payload: message.data['promocionId'] ?? message.data['lugarId'] ?? '',
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('PushNotificationService: opened from message ${message.messageId}');
      _handleNotificationTap(message);
    });

    _messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) _handleNotificationTap(message);
    });
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final type = data['type'];
    if (type == 'promocion') {
      debugPrint('PushNotificationService: open promocion ${data['promocionId']}');
    } else if (type == 'auditoria') {
      debugPrint('PushNotificationService: open auditoria ${data['auditId']}');
    }
  }

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String payload = '',
  }) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      androidChannelIdPromociones,
      'Promociones TuCanchaFácil',
      channelDescription: 'Nuevas promociones de canchas',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
    await _localNotifications.show(id, title, body, details, payload: payload);
  }
}
