/* GardeFlow Web/PWA Firebase Cloud Messaging background worker.
 * This file must be served under the deployed Flutter base path; no secrets.
 * Never cache or persist patient information or user device identifiers here.
 */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCdB6aJmUb_iBsrvgZqbcXsuqJEM_lL1I0',
  authDomain: 'planninghm6.firebaseapp.com',
  projectId: 'planninghm6',
  storageBucket: 'planninghm6.firebasestorage.app',
  messagingSenderId: '298887284540',
  appId: '1:298887284540:web:b8689ebd4e96cce6d24039',
});

const messaging = firebase.messaging();

// FCM itself displays webpush.notification payloads in the background.
// Do not call showNotification for them or users may receive duplicates.
messaging.onBackgroundMessage((payload) => {
  if (payload.notification || payload.data?.kind !== 'practice_daily_challenge') {
    return;
  }
  const data = payload.data || {};
  return self.registration.showNotification(
    data.title || 'Défi quotidien · GardeFlow Practice',
    {
      body: data.body || 'Vos 10 QCM du jour vous attendent.',
      tag: 'practice_daily_challenge:' + (data.resourceId || ''),
      data: {kind: 'practice_daily_challenge'},
    },
  );
});
