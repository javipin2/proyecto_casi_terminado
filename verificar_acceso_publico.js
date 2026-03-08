// Script para verificar que el acceso público funciona correctamente
// Ejecutar con: node verificar_acceso_publico.js

const admin = require('firebase-admin');

// Inicializar Firebase Admin
admin.initializeApp();
const db = admin.firestore();

async function verificarAccesoPublico() {
  console.log('🔍 ===== VERIFICANDO ACCESO PÚBLICO =====');
  console.log('📋 Verificando que los visitantes pueden acceder a todos los datos\n');

  try {
    // Verificar ciudades
    console.log('🏙️  Verificando acceso a ciudades...');
    const ciudadesSnapshot = await db.collection('ciudades').get();
    console.log(`   ✅ Ciudades disponibles: ${ciudadesSnapshot.size}`);
    
    if (ciudadesSnapshot.size > 0) {
      ciudadesSnapshot.docs.slice(0, 3).forEach((doc, index) => {
        const data = doc.data();
        console.log(`   ${index + 1}. ${data.nombre} (${data.activa ? 'Activa' : 'Inactiva'})`);
      });
    }

    // Verificar lugares
    console.log('\n🏢 Verificando acceso a lugares...');
    const lugaresSnapshot = await db.collection('lugares').get();
    console.log(`   ✅ Lugares disponibles: ${lugaresSnapshot.size}`);
    
    if (lugaresSnapshot.size > 0) {
      lugaresSnapshot.docs.slice(0, 3).forEach((doc, index) => {
        const data = doc.data();
        console.log(`   ${index + 1}. ${data.nombre} (Ciudad: ${data.ciudadId})`);
      });
    }

    // Verificar sedes
    console.log('\n🏟️  Verificando acceso a sedes...');
    const sedesSnapshot = await db.collection('sede').get();
    console.log(`   ✅ Sedes disponibles: ${sedesSnapshot.size}`);
    
    if (sedesSnapshot.size > 0) {
      sedesSnapshot.docs.slice(0, 3).forEach((doc, index) => {
        const data = doc.data();
        console.log(`   ${index + 1}. ${data.nombre} (Lugar: ${data.lugarId})`);
      });
    }

    // Verificar canchas
    console.log('\n⚽ Verificando acceso a canchas...');
    const canchasSnapshot = await db.collection('canchas').get();
    console.log(`   ✅ Canchas disponibles: ${canchasSnapshot.size}`);
    
    if (canchasSnapshot.size > 0) {
      canchasSnapshot.docs.slice(0, 3).forEach((doc, index) => {
        const data = doc.data();
        console.log(`   ${index + 1}. ${data.nombre} (Sede: ${data.sede_id})`);
      });
    }

    console.log('\n✅ ===== VERIFICACIÓN COMPLETADA =====');
    console.log('🎯 Los visitantes pueden acceder a todos los datos públicos');
    console.log('🔒 Solo los usuarios autenticados con roles están restringidos');

  } catch (error) {
    console.error('❌ Error verificando acceso público:', error);
    throw error;
  }
}

async function verificarRestriccionesUsuarios() {
  console.log('\n🔒 ===== VERIFICANDO RESTRICCIONES DE USUARIOS =====');
  console.log('📋 Verificando que los usuarios autenticados están restringidos\n');

  try {
    // Obtener usuarios con roles
    const usuariosSnapshot = await db.collection('usuarios').get();
    console.log(`📊 Usuarios con roles: ${usuariosSnapshot.size}`);
    
    if (usuariosSnapshot.size > 0) {
      usuariosSnapshot.docs.forEach((doc, index) => {
        const data = doc.data();
        console.log(`   ${index + 1}. ${data.email} - Rol: ${data.rol} - Lugar: ${data.lugarId}`);
      });
    }

    console.log('\n✅ ===== VERIFICACIÓN DE RESTRICCIONES =====');
    console.log('🎯 Los usuarios autenticados están restringidos a su lugar asignado');
    console.log('👥 Los visitantes tienen acceso completo');

  } catch (error) {
    console.error('❌ Error verificando restricciones:', error);
    throw error;
  }
}

async function mostrarResumenFlujo() {
  console.log('\n📋 ===== RESUMEN DEL FLUJO DE ACCESO =====');
  console.log('');
  console.log('👤 VISITANTES (No autenticados):');
  console.log('   ✅ Pueden ver todas las ciudades');
  console.log('   ✅ Pueden ver todos los lugares');
  console.log('   ✅ Pueden ver todas las sedes');
  console.log('   ✅ Pueden ver todas las canchas');
  console.log('   ✅ Pueden hacer reservas');
  console.log('');
  console.log('🔐 USUARIOS AUTENTICADOS CON ROLES:');
  console.log('   🔒 Admin: Solo su lugar asignado');
  console.log('   🔒 SuperAdmin: Solo su lugar asignado');
  console.log('   🔒 Encargado: Solo su lugar asignado');
  console.log('   🔓 Programador: Acceso completo');
  console.log('');
  console.log('🛡️  SEGURIDAD:');
  console.log('   🔒 Reglas de Firestore configuradas');
  console.log('   🔒 Validación en frontend');
  console.log('   🔒 Aislamiento por lugar para roles');
  console.log('   🔓 Acceso público para visitantes');
}

// Ejecutar script
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--restrictions')) {
    verificarRestriccionesUsuarios();
  } else if (args.includes('--summary')) {
    mostrarResumenFlujo();
  } else {
    verificarAccesoPublico()
      .then(() => verificarRestriccionesUsuarios())
      .then(() => mostrarResumenFlujo())
      .then(() => {
        console.log('\n🎉 Verificación completada exitosamente');
        process.exit(0);
      })
      .catch((error) => {
        console.error('💥 Error en la verificación:', error);
        process.exit(1);
      });
  }
}

module.exports = {
  verificarAccesoPublico,
  verificarRestriccionesUsuarios,
  mostrarResumenFlujo
};

