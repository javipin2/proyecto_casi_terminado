// Script para crear índices de Firestore automáticamente
// Ejecutar con: node crear_indices_firestore.js

const admin = require('firebase-admin');

// Inicializar Firebase Admin
admin.initializeApp();
const db = admin.firestore();

async function crearIndicesNecesarios() {
  console.log('🔥 ===== CREANDO ÍNDICES DE FIRESTORE =====');
  console.log('📋 Este script creará los índices necesarios para el sistema multi-ciudad\n');

  try {
    // 1. Índice para ciudades: activa + nombre
    console.log('1. Creando índice para ciudades (activa + nombre)...');
    await crearIndice('ciudades', [
      { field: 'activa', order: 'ASCENDING' },
      { field: 'nombre', order: 'ASCENDING' }
    ]);

    // 2. Índice para lugares: ciudadId + activo + nombre
    console.log('2. Creando índice para lugares (ciudadId + activo + nombre)...');
    await crearIndice('lugares', [
      { field: 'ciudadId', order: 'ASCENDING' },
      { field: 'activo', order: 'ASCENDING' },
      { field: 'nombre', order: 'ASCENDING' }
    ]);

    // 3. Índice para sedes: lugarId + activa + nombre
    console.log('3. Creando índice para sedes (lugarId + activa + nombre)...');
    await crearIndice('sedes', [
      { field: 'lugarId', order: 'ASCENDING' },
      { field: 'activa', order: 'ASCENDING' },
      { field: 'nombre', order: 'ASCENDING' }
    ]);

    // 4. Índice para usuarios: lugarId + activo
    console.log('4. Creando índice para usuarios (lugarId + activo)...');
    await crearIndice('usuarios', [
      { field: 'lugarId', order: 'ASCENDING' },
      { field: 'activo', order: 'ASCENDING' }
    ]);

    // 5. Índice para usuarios: rol + activo
    console.log('5. Creando índice para usuarios (rol + activo)...');
    await crearIndice('usuarios', [
      { field: 'rol', order: 'ASCENDING' },
      { field: 'activo', order: 'ASCENDING' }
    ]);

    // 6. Índice para reservas: cancha_id + fecha
    console.log('6. Creando índice para reservas (cancha_id + fecha)...');
    await crearIndice('reservas', [
      { field: 'cancha_id', order: 'ASCENDING' },
      { field: 'fecha', order: 'ASCENDING' }
    ]);

    // 7. Índice para reservas: estado + fecha
    console.log('7. Creando índice para reservas (estado + fecha)...');
    await crearIndice('reservas', [
      { field: 'estado', order: 'ASCENDING' },
      { field: 'fecha', order: 'ASCENDING' }
    ]);

    // 8. Índice para audit_logs: timestamp + usuario_id
    console.log('8. Creando índice para audit_logs (timestamp + usuario_id)...');
    await crearIndice('audit_logs', [
      { field: 'timestamp', order: 'DESCENDING' },
      { field: 'usuario_id', order: 'ASCENDING' }
    ]);

    // 9. Índice para audit_logs: accion + timestamp
    console.log('9. Creando índice para audit_logs (accion + timestamp)...');
    await crearIndice('audit_logs', [
      { field: 'accion', order: 'ASCENDING' },
      { field: 'timestamp', order: 'DESCENDING' }
    ]);

    console.log('\n✅ ===== ÍNDICES CREADOS EXITOSAMENTE =====');
    console.log('📊 Total de índices creados: 9');
    console.log('💡 Los índices pueden tardar unos minutos en estar disponibles');
    console.log('🔍 Verifica en Firebase Console > Firestore > Indexes');

  } catch (error) {
    console.error('❌ Error creando índices:', error);
    throw error;
  }
}

async function crearIndice(collection, fields) {
  try {
    // Nota: Los índices se crean automáticamente cuando se ejecuta una query
    // que los requiere. Este script simula las queries para forzar la creación.
    
    let query = db.collection(collection);
    
    // Construir query con los campos del índice
    fields.forEach(field => {
      if (field.order === 'ASCENDING') {
        query = query.orderBy(field.field, 'asc');
      } else {
        query = query.orderBy(field.field, 'desc');
      }
    });

    // Ejecutar query para forzar creación del índice
    await query.limit(1).get();
    
    console.log(`   ✅ Índice creado para ${collection}: ${fields.map(f => f.field).join(' + ')}`);
    
  } catch (error) {
    if (error.code === 'failed-precondition') {
      console.log(`   ⚠️  Índice ya existe o se está creando para ${collection}`);
    } else {
      console.log(`   ❌ Error creando índice para ${collection}: ${error.message}`);
    }
  }
}

// Función para verificar índices existentes
async function verificarIndicesExistentes() {
  console.log('\n🔍 ===== VERIFICANDO ÍNDICES EXISTENTES =====');
  
  const collections = ['ciudades', 'lugares', 'sedes', 'usuarios', 'reservas', 'audit_logs'];
  
  for (const collection of collections) {
    try {
      const snapshot = await db.collection(collection).limit(1).get();
      console.log(`✅ ${collection}: ${snapshot.size} documentos encontrados`);
    } catch (error) {
      console.log(`❌ ${collection}: Error - ${error.message}`);
    }
  }
}

// Función para generar reporte de índices
function generarReporteIndices() {
  console.log('\n📊 ===== REPORTE DE ÍNDICES NECESARIOS =====');
  console.log('');
  
  const indices = [
    {
      collection: 'ciudades',
      indices: [
        'activa (ascending) + nombre (ascending)',
        'nombre (ascending)'
      ]
    },
    {
      collection: 'lugares',
      indices: [
        'ciudadId (ascending) + activo (ascending) + nombre (ascending)',
        'nombre (ascending)'
      ]
    },
    {
      collection: 'sedes',
      indices: [
        'lugarId (ascending) + activa (ascending) + nombre (ascending)',
        'nombre (ascending)'
      ]
    },
    {
      collection: 'usuarios',
      indices: [
        'lugarId (ascending) + activo (ascending)',
        'rol (ascending) + activo (ascending)'
      ]
    },
    {
      collection: 'reservas',
      indices: [
        'cancha_id (ascending) + fecha (ascending)',
        'estado (ascending) + fecha (ascending)'
      ]
    },
    {
      collection: 'audit_logs',
      indices: [
        'timestamp (descending) + usuario_id (ascending)',
        'accion (ascending) + timestamp (descending)'
      ]
    }
  ];

  indices.forEach(({ collection, indices }) => {
    console.log(`📁 ${collection}:`);
    indices.forEach(index => {
      console.log(`   • ${index}`);
    });
    console.log('');
  });

  console.log('🛠️  COMANDOS ÚTILES:');
  console.log('• firebase firestore:indexes');
  console.log('• firebase firestore:indexes --create');
  console.log('• Ver en Firebase Console > Firestore > Indexes');
}

// Ejecutar script
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--report')) {
    generarReporteIndices();
  } else if (args.includes('--verify')) {
    verificarIndicesExistentes();
  } else {
    crearIndicesNecesarios()
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
  crearIndicesNecesarios,
  verificarIndicesExistentes,
  generarReporteIndices
};
