// Public Firebase web configuration for the PRODUCTION project
// (little-blue-cart-prod). These values are not secrets: the app ships the
// same kind in google-services.json. Access is decided by Firebase sign-in
// plus the admin claim, and by the adminSendAnnouncement function and the
// Firestore rules refusing non-admins.
// Registered with: firebase apps:create WEB "LBM admin console" --project prod
// The dev project's copy is firebase-config.dev.js (swap the file to point the
// console at dev while testing).
window.LBM_FIREBASE_CONFIG = {
  projectId: "little-blue-cart-prod",
  appId: "1:19665063635:web:0e8fdba94e52f5b59f8e26",
  storageBucket: "little-blue-cart-prod.firebasestorage.app",
  apiKey: "AIzaSyAlf9oBADYIghMrotIRFfeldtoMH3Fi7-I",
  authDomain: "little-blue-cart-prod.firebaseapp.com",
  messagingSenderId: "19665063635",
  functionsRegion: "us-central1",
};
