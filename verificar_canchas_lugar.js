// Script para verificar y corregir canchas sin lugarId
const admin = require('firebase-admin');

// Inicializar Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
}

const db = admin.firestore();

async function verificarYCrearCanchasLugar() {
  console.log('🔍 Verificando canchas sin lugarId...');
  
  try {
    // Obtener todas las canchas
    const canchasSnapshot = await db.collection('canchas').get();
    console.log(`📊 Total de canchas encontradas: ${canchasSnapshot.size}`);
    
    let canchasSinLugar = 0;
    let canchasConLugar = 0;
    
    for (const canchaDoc of canchasSnapshot.docs) {
      const canchaData = canchaDoc.data();
      
      if (!canchaData.lugarId) {
        canchasSinLugar++;
        console.log(`❌ Cancha sin lugarId: ${canchaData.nombre} (ID: ${canchaDoc.id})`);
        
        // Intentar obtener lugarId de la sede asociada
        if (canchaData.sedeId) {
          try {
            const sedeDoc = await db.collection('sede').doc(canchaData.sedeId).get();
            if (sedeDoc.exists) {
              const sedeData = sedeDoc.data();
              if (sedeData.lugarId) {
                // Actualizar cancha con lugarId de la sede
                await db.collection('canchas').doc(canchaDoc.id).update({
                  lugarId: sedeData.lugarId
                });
                console.log(`✅ Cancha actualizada con lugarId: ${canchaData.nombre} -> lugarId: ${sedeData.lugarId}`);
                canchasConLugar++;
              } else {
                console.log(`⚠️  Sede sin lugarId: ${sedeData.nombre} (ID: ${canchaData.sedeId})`);
              }
            } else {
              console.log(`⚠️  Sede no encontrada: ${canchaData.sedeId}`);
            }
          } catch (error) {
            console.log(`❌ Error al obtener sede: ${error.message}`);
          }
        } else {
          console.log(`⚠️  Cancha sin sedeId: ${canchaData.nombre}`);
        }
      } else {
        canchasConLugar++;
        console.log(`✅ Cancha con lugarId: ${canchaData.nombre} -> lugarId: ${canchaData.lugarId}`);
      }
    }
    
    console.log('\n📊 RESUMEN:');
    console.log(`✅ Canchas con lugarId: ${canchasConLugar}`);
    console.log(`❌ Canchas sin lugarId: ${canchasSinLugar}`);
    
    // Verificar sedes sin lugarId
    console.log('\n🔍 Verificando sedes sin lugarId...');
    const sedesSnapshot = await db.collection('sede').get();
    let sedesSinLugar = 0;
    
    for (const sedeDoc of sedesSnapshot.docs) {
      const sedeData = sedeDoc.data();
      if (!sedeData.lugarId) {
        sedesSinLugar++;
        console.log(`❌ Sede sin lugarId: ${sedeData.nombre} (ID: ${sedeDoc.id})`);
      }
    }
    
    console.log(`📊 Sedes sin lugarId: ${sedesSinLugar}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

// Ejecutar script
verificarYCrearCanchasLugar()
  .then(() => {
    console.log('✅ Script completado');
    process.exit(0);
  })
  .catch((error) => {
    console.error('❌ Error en script:', error);
    process.exit(1);
  });
