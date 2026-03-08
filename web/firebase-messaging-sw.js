// Service worker para FCM (notificaciones push en web).
// Debe estar en web/ para que se sirva como JS (no HTML).
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyD57tk7priOgb45wXC7YJNqn9NZTTH0jtw',
  appId: '1:185214677471:web:fa3326285cba36efff946a',
  messagingSenderId: '185214677471',
  projectId: 'proyecto-20bae',
  authDomain: 'proyecto-20bae.firebaseapp.com',
  storageBucket: 'proyecto-20bae.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  const title = payload.notification?.title || 'TuCanchaFacil';
  const options = {
    body: payload.notification?.body || '',
    icon: payload.notification?.image || 'https://cdn-icons-png.flaticon.com/512/3307/3307972.png',
    data: payload.data || {},
  };
  return self.registration.showNotification(title, options);
});
