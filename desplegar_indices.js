// Script para desplegar índices de Firestore
// Ejecutar con: node desplegar_indices.js

const { execSync } = require('child_process');

console.log('🚀 Desplegando índices de Firestore...');

try {
  // Desplegar índices
  execSync('firebase deploy --only firestore:indexes', { stdio: 'inherit' });
  console.log('✅ Índices desplegados correctamente');
} catch (error) {
  console.error('❌ Error desplegando índices:', error.message);
  console.log('\n📋 Pasos manuales:');
  console.log('1. Ve a Firebase Console: https://console.firebase.google.com/');
  console.log('2. Selecciona tu proyecto');
  console.log('3. Ve a Firestore Database > Indexes');
  console.log('4. Haz clic en "Create Index"');
  console.log('5. Crea los siguientes índices:');
  console.log('');
  console.log('Índice 1 - Canchas por lugarId:');
  console.log('  Collection: canchas');
  console.log('  Fields: lugarId (Ascending)');
  console.log('');
  console.log('Índice 2 - Reservas por fecha, cancha y horario:');
  console.log('  Collection: reservas');
  console.log('  Fields: fecha (Ascending), cancha_id (Ascending), horario (Ascending)');
  console.log('');
  console.log('Índice 3 - Peticiones por estado:');
  console.log('  Collection: peticiones');
  console.log('  Fields: estado (Ascending)');
}
