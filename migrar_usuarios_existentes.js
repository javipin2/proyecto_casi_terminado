// Script para migrar usuarios existentes al nuevo formato
// Ejecutar con: node migrar_usuarios_existentes.js

const admin = require('firebase-admin');

// Inicializar Firebase Admin
admin.initializeApp();
const db = admin.firestore();

async function migrarUsuariosExistentes() {
  console.log('🔄 ===== MIGRANDO USUARIOS EXISTENTES =====');
  console.log('📋 Migrando usuarios al nuevo formato con UID como ID de documento\n');

  try {
    // Obtener todos los usuarios de la colección 'usuarios'
    const usuariosSnapshot = await db.collection('usuarios').get();
    
    console.log(`📊 Encontrados ${usuariosSnapshot.size} usuarios para migrar`);
    
    if (usuariosSnapshot.size === 0) {
      console.log('✅ No hay usuarios para migrar');
      return;
    }

    let migrados = 0;
    let errores = 0;

    for (const doc of usuariosSnapshot.docs) {
      try {
        const data = doc.data();
        const email = data.email;
        
        if (!email) {
          console.log(`⚠️  Usuario ${doc.id} sin email, saltando...`);
          continue;
        }

        // Buscar el usuario en Firebase Auth por email
        const userRecord = await admin.auth().getUserByEmail(email);
        
        if (userRecord) {
          // Crear nuevo documento con UID como ID
          await db.collection('usuarios').doc(userRecord.uid).set({
            ...data,
            'migrado': true,
            'migradoAt': admin.firestore.FieldValue.serverTimestamp(),
            'uidAnterior': doc.id,
          });

          // Eliminar documento anterior
          await doc.ref.delete();
          
          console.log(`✅ Usuario ${email} migrado exitosamente`);
          migrados++;
        } else {
          console.log(`⚠️  Usuario ${email} no encontrado en Firebase Auth`);
          errores++;
        }
        
      } catch (error) {
        console.log(`❌ Error migrando usuario ${doc.id}: ${error.message}`);
        errores++;
      }
    }

    console.log('\n📊 ===== RESUMEN DE MIGRACIÓN =====');
    console.log(`✅ Usuarios migrados: ${migrados}`);
    console.log(`❌ Errores: ${errores}`);
    console.log(`📋 Total procesados: ${usuariosSnapshot.size}`);

  } catch (error) {
    console.error('💥 Error en la migración:', error);
    throw error;
  }
}

// Función para verificar usuarios existentes
async function verificarUsuarios() {
  console.log('\n🔍 ===== VERIFICANDO USUARIOS EXISTENTES =====');
  
  try {
    // Verificar usuarios en Firestore
    const usuariosSnapshot = await db.collection('usuarios').get();
    console.log(`📊 Usuarios en Firestore: ${usuariosSnapshot.size}`);
    
    // Verificar usuarios en Firebase Auth
    const listUsersResult = await admin.auth().listUsers();
    console.log(`📊 Usuarios en Firebase Auth: ${listUsersResult.users.length}`);
    
    // Mostrar algunos ejemplos
    console.log('\n📋 Ejemplos de usuarios en Firestore:');
    usuariosSnapshot.docs.slice(0, 3).forEach((doc, index) => {
      const data = doc.data();
      console.log(`   ${index + 1}. ID: ${doc.id}, Email: ${data.email}, Rol: ${data.rol}`);
    });

  } catch (error) {
    console.error('❌ Error verificando usuarios:', error);
  }
}

// Función para crear usuario de ejemplo
async function crearUsuarioEjemplo() {
  console.log('\n🆕 ===== CREANDO USUARIO DE EJEMPLO =====');
  
  try {
    const email = 'ejemplo@test.com';
    const password = '123456';
    const nombre = 'Usuario Ejemplo';
    const rol = 'encargado';
    
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
      activo: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`✅ Usuario de ejemplo creado: ${email} (UID: ${userRecord.uid})`);
    
  } catch (error) {
    console.error('❌ Error creando usuario de ejemplo:', error);
  }
}

// Ejecutar script
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--verify')) {
    verificarUsuarios();
  } else if (args.includes('--example')) {
    crearUsuarioEjemplo();
  } else {
    migrarUsuariosExistentes()
      .then(() => {
        console.log('\n🎉 Migración completada exitosamente');
        process.exit(0);
      })
      .catch((error) => {
        console.error('💥 Error en la migración:', error);
        process.exit(1);
      });
  }
}

module.exports = {
  migrarUsuariosExistentes,
  verificarUsuarios,
  crearUsuarioEjemplo
};
