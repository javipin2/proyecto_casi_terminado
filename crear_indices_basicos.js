// Script simple para crear índices básicos de Firestore
// Ejecutar con: node crear_indices_basicos.js

const admin = require('firebase-admin');

// Inicializar Firebase Admin
admin.initializeApp();
const db = admin.firestore();

async function crearIndicesBasicos() {
  console.log('🔥 ===== CREANDO ÍNDICES BÁSICOS =====');
  console.log('📋 Creando índices esenciales para el sistema multi-ciudad\n');

  try {
    // 1. Índice simple para ciudades: solo nombre
    console.log('1. Creando índice simple para ciudades (nombre)...');
    await crearIndiceSimple('ciudades', 'nombre');

    // 2. Índice simple para lugares: solo nombre  
    console.log('2. Creando índice simple para lugares (nombre)...');
    await crearIndiceSimple('lugares', 'nombre');

    // 3. Índice simple para sedes: solo nombre
    console.log('3. Creando índice simple para sedes (nombre)...');
    await crearIndiceSimple('sedes', 'nombre');

    // 4. Índice simple para usuarios: solo rol
    console.log('4. Creando índice simple para usuarios (rol)...');
    await crearIndiceSimple('usuarios', 'rol');

    console.log('\n✅ ===== ÍNDICES BÁSICOS CREADOS =====');
    console.log('📊 Total de índices creados: 4');
    console.log('💡 Los índices pueden tardar unos minutos en estar disponibles');
    console.log('🔍 Verifica en Firebase Console > Firestore > Indexes');

  } catch (error) {
    console.error('❌ Error creando índices:', error);
    throw error;
  }
}

async function crearIndiceSimple(collection, field) {
  try {
    // Crear query simple para forzar creación del índice
    const query = db.collection(collection).orderBy(field);
    await query.limit(1).get();
    
    console.log(`   ✅ Índice creado para ${collection}: ${field}`);
    
  } catch (error) {
    if (error.code === 'failed-precondition') {
      console.log(`   ⚠️  Índice ya existe o se está creando para ${collection}`);
    } else {
      console.log(`   ❌ Error creando índice para ${collection}: ${error.message}`);
    }
  }
}

// Función para verificar que las colecciones existen
async function verificarColecciones() {
  console.log('\n🔍 ===== VERIFICANDO COLECCIONES =====');
  
  const collections = ['ciudades', 'lugares', 'sedes', 'usuarios'];
  
  for (const collection of collections) {
    try {
      const snapshot = await db.collection(collection).limit(1).get();
      console.log(`✅ ${collection}: ${snapshot.size} documentos encontrados`);
    } catch (error) {
      console.log(`❌ ${collection}: Error - ${error.message}`);
    }
  }
}

// Ejecutar script
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--verify')) {
    verificarColecciones();
  } else {
    crearIndicesBasicos()
      .then(() => {
        console.log('\n🎉 Proceso completado exitosamente');
        process.exit(0);
      })
      .catch((error) => {
        console.error('💥 Error en el proceso:', error);
        process.exit(1);
      });
  }
}

module.exports = {
  crearIndicesBasicos,
  verificarColecciones
};
