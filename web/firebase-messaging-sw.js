// FCM service worker — handles background web push notifications
// (when the TouchGrass tab is not in focus).
//
// To enable background web push you also need a VAPID key:
// Firebase Console → Project Settings → Cloud Messaging →
// Web Push Certificates → Generate key pair.
// Then call FirebaseMessaging.instance.getToken(vapidKey: 'YOUR_VAPID_KEY')
// on app start so FCM can register the browser subscription.

importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDzigC9UF0ffHWN6WzJmzPNRpIAodqw3XA',
  authDomain: 'touchgrass-today.firebaseapp.com',
  projectId: 'touchgrass-today',
  storageBucket: 'touchgrass-today.firebasestorage.app',
  messagingSenderId: '760620662222',
  appId: '1:760620662222:web:ebb0cf64619e43dca53f9f',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  const title = (payload.notification && payload.notification.title) || 'TouchGrass';
  const options = {
    body: (payload.notification && payload.notification.body) || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  };
  return self.registration.showNotification(title, options);
});
