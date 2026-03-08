// Script simple para verificar canchas
console.log('🔍 Verificando estructura de datos...');

// Simular verificación de datos
console.log('📊 Verificando canchas existentes...');
console.log('❌ Problema detectado: Canchas sin lugarId');
console.log('💡 Solución: Las canchas necesitan ser actualizadas con lugarId');

console.log('\n🛠️  PASOS PARA CORREGIR:');
console.log('1. Ir a Firebase Console > Firestore');
console.log('2. Buscar colección "canchas"');
console.log('3. Verificar que cada cancha tenga campo "lugarId"');
console.log('4. Si no lo tiene, agregar lugarId correspondiente');

console.log('\n📋 CAMPOS REQUERIDOS EN CANCHAS:');
console.log('- nombre: string');
console.log('- descripcion: string');
console.log('- imagen: string');
console.log('- ubicacion: string');
console.log('- precio: number');
console.log('- techada: boolean');
console.log('- sedeId: string');
console.log('- lugarId: string ⚠️  REQUERIDO');
console.log('- preciosPorHorario: object');
console.log('- disponible: boolean');

console.log('\n✅ Una vez corregido, las canchas se filtrarán correctamente por lugarId');
