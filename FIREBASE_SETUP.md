# Configuración de Firebase - TuCanchaFacil

Este documento describe cómo configurar Firebase desde cero cuando crees un nuevo proyecto (por ejemplo, tras perder la cuenta anterior).

## Resumen de lo que se ha generado

| Archivo | Descripción |
|---------|-------------|
| `firestore.indexes.json` | Índices compuestos para todas las consultas de la app |
| `firestore.rules` | Reglas de seguridad de Firestore |
| `storage.rules` | Reglas de seguridad de Storage |
| `firebase.json` | Configuración actualizada con Firestore y Storage |
| `functions/init-firebase-data.js` | Script para crear datos iniciales (config, app_config) |

---

## Paso 1: Crear proyecto en Firebase Console

1. Ve a [Firebase Console](https://console.firebase.google.com/)
2. Crea un nuevo proyecto (o usa uno existente)
3. Anota el **Project ID**

---

## Paso 2: Habilitar servicios

### Authentication
- Ve a **Authentication** > **Sign-in method**
- Habilita **Email/Password**

### Firestore Database
- Ve a **Firestore Database** > **Create database**
- Elige modo **Producción** (las reglas se desplegarán después)
- Selecciona ubicación (ej: `us-central1`)

### Storage
- Ve a **Storage** > **Get started**
- Usa las reglas por defecto temporalmente (se sobrescribirán al desplegar)

### Cloud Functions (opcional, para limpieza de reservas)
- Se habilita automáticamente al desplegar functions

---

## Paso 3: Vincular proyecto local

```bash
# Instalar Firebase CLI si no lo tienes
npm install -g firebase-tools

# Iniciar sesión
firebase login

# Vincular al proyecto (reemplaza con tu Project ID)
firebase use tu-nuevo-project-id
```

---

## Paso 4: Actualizar .firebaserc

Edita `.firebaserc` y cambia el project ID:

```json
{
  "projects": {
    "default": "tu-nuevo-project-id"
  }
}
```

---

## Paso 5: Regenerar firebase_options.dart (Flutter)

```bash
# Instalar FlutterFire CLI si no lo tienes
dart pub global activate flutterfire_cli

# Configurar Firebase para Flutter
flutterfire configure
```

Esto generará `lib/firebase_options.dart` con las credenciales del nuevo proyecto.

---

## Paso 6: Desplegar reglas e índices

```bash
# Desplegar reglas de Firestore
firebase deploy --only firestore

# Desplegar reglas de Storage
firebase deploy --only storage

# Los índices se crean automáticamente con firestore (pueden tardar unos minutos)
```

---

## Paso 7: Inicializar datos en Firestore

1. **Descargar cuenta de servicio:**
   - Firebase Console > Project Settings (engranaje) > Service accounts
   - Click en **Generate new private key**

2. **Configurar variable de entorno (Windows PowerShell):**
   ```powershell
   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\ruta\a\tu-service-account.json"
   ```

3. **Ejecutar script de inicialización:**
   ```bash
   node functions/init-firebase-data.js
   ```

4. **Crear primer superadmin:**
   - Crea un usuario en **Authentication** > **Add user** (email + contraseña)
   - Copia el **UID** del usuario
   - Ejecuta:
   ```bash
   node functions/init-firebase-data.js --superadmin <UID> <email>
   ```

---

## Paso 8: Desplegar Cloud Functions (opcional)

```bash
firebase deploy --only functions
```

---

## Paso 9: Desplegar Hosting (si usas web)

```bash
flutter build web
firebase deploy --only hosting
```

---

## Colecciones de Firestore usadas por la app

| Colección | Uso |
|-----------|-----|
| `reservas` | Reservas confirmadas |
| `reservas_temporales` | Bloqueos temporales durante reserva |
| `reservas_recurrentes` | Reservas semanales recurrentes |
| `reservas_pendientes` | (Cloud Functions) Reservas pendientes de expiración |
| `reservas_historial` | (Cloud Functions) Historial de expiradas |
| `canchas` | Canchas por sede |
| `sede` | Sedes |
| `clientes` | Clientes |
| `usuarios` | Usuarios admin (uid = doc id, campo `rol`) |
| `peticiones` | Peticiones de cambio de precio |
| `config` | Config global (admin_control) |
| `app_config` | Versión de app (version_control) |
| `horarios` | Horarios disponibles |
| `auditoria` | Log de auditoría |
| `alertas_criticas` | Alertas críticas |

---

## Documentos que crea el script init-firebase-data.js

- `config/admin_control` – Control total de admins
- `app_config/version_control` – Versión mínima, actualización forzada, mantenimiento

---

## Rutas de Storage

- `sede/{nombre}_{timestamp}.jpg` – Imágenes de sedes
- `canchas/{timestamp}.jpg` – Canchas nuevas
- `canchas/{canchaId}_{timestamp}.jpg` – Canchas editadas

---

## Notas importantes

1. **Emulador:** Si `public/index.html` tiene `useEmulator=true`, cámbialo a `false` para producción.
2. **Project ID:** Actualiza todas las referencias a `canchas-la-jugada` por tu nuevo project ID.
3. **Índices:** Los índices compuestos pueden tardar varios minutos en crearse. Si una consulta falla, revisa la consola de Firebase para ver el enlace de creación automática del índice.
