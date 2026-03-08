# Configuración de notificaciones push en web

Para que las notificaciones lleguen en el navegador, sigue estos pasos:

## 1. VAPID Key (obligatorio)

1. Ve a [Firebase Console](https://console.firebase.google.com) → tu proyecto
2. **Project Settings** (icono ⚙️) → pestaña **Cloud Messaging**
3. En **Web configuration** → **Web Push certificates**
4. Haz clic en **Generate key pair** (o usa el par existente)
5. Copia la **clave pública** (empieza con `B...`)

6. En `lib/services/push_notification_service.dart`, reemplaza la constante vacía:
```dart
const String _vapidKeyWeb = 'TU_CLAVE_VAPID_AQUI';
```

## 2. FCM Registration API

1. Ve a [Google Cloud Console](https://console.cloud.google.com) → selecciona el proyecto de Firebase
2. **APIs & Services** → **Library**
3. Busca **FCM Registration API**
4. Si no está habilitada, haz clic en **Enable**

## 3. Firebase Cloud Messaging API

1. En la misma biblioteca de APIs, busca **Firebase Cloud Messaging API**
2. Asegúrate de que esté **habilitada**

## 4. Verificar que el token se registra

En la consola del navegador deberías ver:
- `PushNotificationService: registrado para ciudad [id]` → el token se guardó correctamente

Si ves `no token` o `registerFcmToken error`, revisa los pasos 1–3.

## 5. Probar

1. Abre la app web, selecciona una ciudad
2. Desde el panel admin, crea una promoción en un lugar de **esa misma ciudad**
3. Deberías recibir la notificación (con la pestaña abierta o en segundo plano)
