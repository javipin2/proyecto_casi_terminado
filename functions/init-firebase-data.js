/**
 * Script de inicialización de datos en Firestore
 * Ejecutar cuando tengas el nuevo proyecto Firebase configurado.
 *
 * Uso (desde la raíz del proyecto):
 *   node functions/init-firebase-data.js
 *
 * Requisitos:
 *   - Descarga la clave de cuenta de servicio desde Firebase Console:
 *     Project Settings > Service accounts > Generate new private key
 *   - Define la variable de entorno:
 *     set GOOGLE_APPLICATION_CREDENTIALS=ruta\a\tu-service-account.json
 *   - Ejecuta el script
 */

const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function initConfig() {
  const configRef = db.collection('config').doc('admin_control');
  const doc = await configRef.get();

  if (!doc.exists) {
    await configRef.set({
      control_total_activado: false,
      fecha_creacion: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ config/admin_control creado');
  } else {
    console.log('⏭️  config/admin_control ya existe');
  }
}

async function initAppConfig() {
  const versionRef = db.collection('app_config').doc('version_control');
  const doc = await versionRef.get();

  if (!doc.exists) {
    await versionRef.set({
      current_version: '1.0.0',
      minimum_required_version: '1.0.0',
      force_update: false,
      update_message: 'Nueva versión disponible con mejoras importantes',
      download_url: '',
      is_play_store_available: false,
      play_store_url: 'https://play.google.com/store/apps/details?id=com.example.app',
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
      new_features: [
        'Mejoras en la interfaz de usuario',
        'Corrección de errores menores',
        'Optimización de rendimiento',
      ],
      maintenance_mode: false,
      maintenance_message: 'La aplicación está temporalmente en mantenimiento. Intenta más tarde.',
    });
    console.log('✅ app_config/version_control creado');
  } else {
    console.log('⏭️  app_config/version_control ya existe');
  }
}

async function createSuperAdminUser(uid, email) {
  const userRef = db.collection('usuarios').doc(uid);
  const doc = await userRef.get();

  if (!doc.exists) {
    await userRef.set({
      rol: 'superadmin',
      email: email,
      creado_en: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`✅ usuarios/${uid} creado como superadmin`);
  } else {
    await userRef.update({ rol: 'superadmin' });
    console.log(`✅ usuarios/${uid} actualizado a superadmin`);
  }
}

async function main() {
  const args = process.argv.slice(2);
  const superadminIdx = args.indexOf('--superadmin');

  try {
    console.log('Iniciando inicialización de Firestore...\n');

    await initConfig();
    await initAppConfig();

    if (superadminIdx !== -1 && args[superadminIdx + 1] && args[superadminIdx + 2]) {
      const uid = args[superadminIdx + 1];
      const email = args[superadminIdx + 2];
      await createSuperAdminUser(uid, email);
    } else {
      console.log('\n💡 Para crear el primer superadmin:');
      console.log('   1. Crea un usuario en Firebase Console > Authentication > Add user');
      console.log('   2. Ejecuta: node functions/init-firebase-data.js --superadmin <UID> <email>');
      console.log('   3. El UID lo encuentras en Authentication > Users');
    }

    console.log('\n✅ Inicialización completada.');
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

main();
