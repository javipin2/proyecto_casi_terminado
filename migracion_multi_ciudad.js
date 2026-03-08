// Script de migración para convertir el sistema a multi-ciudad
// Ejecutar en Firebase Functions o en un entorno Node.js con acceso a Firestore

const admin = require('firebase-admin');

// Inicializar Firebase Admin
admin.initializeApp();
const db = admin.firestore();

async function migrarSistemaMultiCiudad() {
  console.log('Iniciando migración a sistema multi-ciudad...');
  
  try {
    // 1. Crear ciudad por defecto
    console.log('1. Creando ciudad por defecto...');
    const ciudadRef = await db.collection('ciudades').add({
      nombre: 'Ciudad Principal',
      codigo: 'CP',
      activa: true,
      createdAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now()
    });
    console.log(`Ciudad creada con ID: ${ciudadRef.id}`);
    
    // 2. Crear lugar por defecto
    console.log('2. Creando lugar por defecto...');
    const lugarRef = await db.collection('lugares').add({
      nombre: 'Lugar Principal',
      ciudadId: ciudadRef.id,
      direccion: 'Dirección principal',
      telefono: '3000000000',
      activo: true,
      createdAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now()
    });
    console.log(`Lugar creado con ID: ${lugarRef.id}`);
    
    // 3. Actualizar sedes existentes
    console.log('3. Actualizando sedes existentes...');
    const sedesSnapshot = await db.collection('sedes').get();
    const batch = db.batch();
    
    sedesSnapshot.forEach(doc => {
      batch.update(doc.ref, {
        lugarId: lugarRef.id,
        updatedAt: admin.firestore.Timestamp.now()
      });
    });
    
    await batch.commit();
    console.log(`${sedesSnapshot.size} sedes actualizadas`);
    
    // 4. Crear usuario programador por defecto
    console.log('4. Creando usuario programador por defecto...');
    await db.collection('usuarios').add({
      nombre: 'Programador Principal',
      email: 'programador@empresa.com',
      rol: 'programador',
      lugarId: '', // Vacío para programador global
      activo: true,
      createdAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now()
    });
    console.log('Usuario programador creado');
    
    // 5. Crear usuario superadmin por defecto
    console.log('5. Creando usuario superadmin por defecto...');
    await db.collection('usuarios').add({
      nombre: 'Super Administrador',
      email: 'superadmin@empresa.com',
      rol: 'superadmin',
      lugarId: lugarRef.id,
      activo: true,
      createdAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now()
    });
    console.log('Usuario superadmin creado');
    
    // 6. Crear usuario admin por defecto
    console.log('6. Creando usuario admin por defecto...');
    await db.collection('usuarios').add({
      nombre: 'Administrador Principal',
      email: 'admin@empresa.com',
      rol: 'admin',
      lugarId: lugarRef.id,
      activo: true,
      createdAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now()
    });
    console.log('Usuario admin creado');
    
    console.log('✅ Migración completada exitosamente!');
    console.log('\n📋 Resumen de la migración:');
    console.log(`- Ciudad creada: ${ciudadRef.id}`);
    console.log(`- Lugar creado: ${lugarRef.id}`);
    console.log(`- Sedes actualizadas: ${sedesSnapshot.size}`);
    console.log('- Usuarios creados: 3 (programador, superadmin, admin)');
    
    console.log('\n🔐 Credenciales de acceso:');
    console.log('Programador: programador@empresa.com');
    console.log('Super Admin: superadmin@empresa.com');
    console.log('Admin: admin@empresa.com');
    console.log('\n⚠️  IMPORTANTE: Configura las contraseñas en Firebase Authentication');
    
  } catch (error) {
    console.error('❌ Error durante la migración:', error);
    throw error;
  }
}

// Función para crear ciudades adicionales
async function crearCiudadesAdicionales() {
  console.log('Creando ciudades adicionales...');
  
  const ciudades = [
    { nombre: 'Bogotá', codigo: 'BOG' },
    { nombre: 'Medellín', codigo: 'MED' },
    { nombre: 'Cali', codigo: 'CAL' },
    { nombre: 'Barranquilla', codigo: 'BAQ' },
    { nombre: 'Cartagena', codigo: 'CTG' }
  ];
  
  for (const ciudad of ciudades) {
    await db.collection('ciudades').add({
      nombre: ciudad.nombre,
      codigo: ciudad.codigo,
      activa: true,
      createdAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now()
    });
    console.log(`Ciudad ${ciudad.nombre} creada`);
  }
}

// Función para crear lugares adicionales
async function crearLugaresAdicionales() {
  console.log('Creando lugares adicionales...');
  
  // Obtener todas las ciudades
  const ciudadesSnapshot = await db.collection('ciudades').get();
  
  for (const ciudadDoc of ciudadesSnapshot.docs) {
    const ciudadData = ciudadDoc.data();
    
    // Crear 2-3 lugares por ciudad
    const lugares = [
      { nombre: `Centro Comercial ${ciudadData.nombre}`, direccion: 'Dirección 1', telefono: '3001111111' },
      { nombre: `Club Deportivo ${ciudadData.nombre}`, direccion: 'Dirección 2', telefono: '3002222222' },
      { nombre: `Complejo Deportivo ${ciudadData.nombre}`, direccion: 'Dirección 3', telefono: '3003333333' }
    ];
    
    for (const lugar of lugares) {
      await db.collection('lugares').add({
        nombre: lugar.nombre,
        ciudadId: ciudadDoc.id,
        direccion: lugar.direccion,
        telefono: lugar.telefono,
        activo: true,
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now()
      });
    }
    
    console.log(`Lugares creados para ${ciudadData.nombre}`);
  }
}

// Ejecutar migración
if (require.main === module) {
  migrarSistemaMultiCiudad()
    .then(() => {
      console.log('Migración completada');
      process.exit(0);
    })
    .catch((error) => {
      console.error('Error en migración:', error);
      process.exit(1);
    });
}

module.exports = {
  migrarSistemaMultiCiudad,
  crearCiudadesAdicionales,
  crearLugaresAdicionales
};
