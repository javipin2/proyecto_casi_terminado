// Script para actualizar usuarios existentes con ciudadId
// Ejecutar con: node actualizar_usuarios_ciudad.js

const admin = require('firebase-admin');

// Inicializar Firebase Admin
admin.initializeApp();
const db = admin.firestore();

async function actualizarUsuariosConCiudad() {
  console.log('🔄 ===== ACTUALIZANDO USUARIOS CON CIUDAD =====');
  console.log('📋 Agregando campo ciudadId a usuarios existentes\n');

  try {
    // Obtener todos los usuarios
    const usuariosSnapshot = await db.collection('usuarios').get();
    
    console.log(`📊 Encontrados ${usuariosSnapshot.size} usuarios para actualizar`);
    
    if (usuariosSnapshot.size === 0) {
      console.log('✅ No hay usuarios para actualizar');
      return;
    }

    let actualizados = 0;
    let errores = 0;

    for (const doc of usuariosSnapshot.docs) {
      try {
        const data = doc.data();
        const lugarId = data.lugarId;
        
        if (!lugarId) {
          console.log(`⚠️  Usuario ${doc.id} sin lugarId, saltando...`);
          continue;
        }

        // Obtener el lugar para encontrar su ciudad
        const lugarDoc = await db.collection('lugares').doc(lugarId).get();
        
        if (!lugarDoc.exists) {
          console.log(`⚠️  Lugar ${lugarId} no encontrado para usuario ${doc.id}`);
          continue;
        }

        const lugarData = lugarDoc.data();
        const ciudadId = lugarData.ciudadId;
        
        if (!ciudadId) {
          console.log(`⚠️  Lugar ${lugarId} sin ciudadId para usuario ${doc.id}`);
          continue;
        }

        // Actualizar usuario con ciudadId
        await db.collection('usuarios').doc(doc.id).update({
          ciudadId: ciudadId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        console.log(`✅ Usuario ${data.email} actualizado con ciudadId: ${ciudadId}`);
        actualizados++;
        
      } catch (error) {
        console.log(`❌ Error actualizando usuario ${doc.id}: ${error.message}`);
        errores++;
      }
    }

    console.log('\n📊 ===== RESUMEN DE ACTUALIZACIÓN =====');
    console.log(`✅ Usuarios actualizados: ${actualizados}`);
    console.log(`❌ Errores: ${errores}`);
    console.log(`📋 Total procesados: ${usuariosSnapshot.size}`);

  } catch (error) {
    console.error('💥 Error en la actualización:', error);
    throw error;
  }
}

// Función para verificar la estructura actual
async function verificarEstructuraUsuarios() {
  console.log('\n🔍 ===== VERIFICANDO ESTRUCTURA DE USUARIOS =====');
  
  try {
    const usuariosSnapshot = await db.collection('usuarios').get();
    
    console.log(`📊 Total de usuarios: ${usuariosSnapshot.size}`);
    
    let conLugarId = 0;
    let conCiudadId = 0;
    let sinLugarId = 0;
    
    usuariosSnapshot.docs.forEach((doc) => {
      const data = doc.data();
      if (data.lugarId) conLugarId++;
      if (data.ciudadId) conCiudadId++;
      if (!data.lugarId) sinLugarId++;
    });
    
    console.log(`📋 Usuarios con lugarId: ${conLugarId}`);
    console.log(`📋 Usuarios con ciudadId: ${conCiudadId}`);
    console.log(`📋 Usuarios sin lugarId: ${sinLugarId}`);
    
    // Mostrar algunos ejemplos
    console.log('\n📋 Ejemplos de usuarios:');
    usuariosSnapshot.docs.slice(0, 3).forEach((doc, index) => {
      const data = doc.data();
      console.log(`   ${index + 1}. Email: ${data.email}, Lugar: ${data.lugarId}, Ciudad: ${data.ciudadId}`);
    });

  } catch (error) {
    console.error('❌ Error verificando estructura:', error);
  }
}

// Función para crear usuario de ejemplo con ciudadId
async function crearUsuarioEjemploCompleto() {
  console.log('\n🆕 ===== CREANDO USUARIO DE EJEMPLO COMPLETO =====');
  
  try {
    const email = 'ejemplo@test.com';
    const password = '123456';
    const nombre = 'Usuario Ejemplo';
    const rol = 'encargado';
    const lugarId = 'lugar_ejemplo_id'; // Debe existir en la base de datos
    const ciudadId = 'ciudad_ejemplo_id'; // Debe existir en la base de datos
    
    // Crear usuario en Firebase Auth
    const userRecord = await admin.auth().createUser({
      email: email,
      password: password,
      displayName: nombre,
    });
    
    // Crear documento en Firestore con UID como ID
    await db.collection('usuarios').doc(userRecord.uid).set({
      email: email,
      rol: rol,
      nombre: nombre,
      lugarId: lugarId,
      ciudadId: ciudadId,
      activo: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`✅ Usuario de ejemplo creado: ${email} (UID: ${userRecord.uid})`);
    console.log(`   Lugar: ${lugarId}, Ciudad: ${ciudadId}`);
    
  } catch (error) {
    console.error('❌ Error creando usuario de ejemplo:', error);
  }
}

// Ejecutar script
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--verify')) {
    verificarEstructuraUsuarios();
  } else if (args.includes('--example')) {
    crearUsuarioEjemploCompleto();
  } else {
    actualizarUsuariosConCiudad()
      .then(() => {
        console.log('\n🎉 Actualización completada exitosamente');
        process.exit(0);
      })
      .catch((error) => {
        console.error('💥 Error en la actualización:', error);
        process.exit(1);
      });
  }
}

module.exports = {
  actualizarUsuariosConCiudad,
  verificarEstructuraUsuarios,
  crearUsuarioEjemploCompleto
};
