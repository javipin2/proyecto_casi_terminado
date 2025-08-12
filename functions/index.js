const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.cleanupPendingReservations = functions.pubsub.schedule('every 10 minutes').onRun(async (context) => {
  const now = admin.firestore.Timestamp.now();
  const oneHourAgo = new Date(now.toDate().getTime() - 60 * 60 * 1000);

  const pendingReservations = await admin.firestore()
    .collection('reservas_pendientes')
    .where('estado', '==', 'pendiente')
    .where('expira_en', '<=', oneHourAgo.getTime())
    .get();

  const batch = admin.firestore().batch();

  for (const doc of pendingReservations.docs) {
    const data = doc.data();
    batch.set(
      admin.firestore().collection('reservas_historial').doc(doc.id),
      {
        ...data,
        estado: 'expirada',
        procesado_en: admin.firestore.FieldValue.serverTimestamp(),
      }
    );
    batch.delete(doc.ref);
  }

  await batch.commit();
  console.log(`Processed ${pendingReservations.docs.length} expired reservations`);
});