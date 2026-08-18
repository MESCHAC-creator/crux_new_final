// Shared Firebase config — web app (registered 2026-06-11)
export const FIREBASE_CONFIG = {
  apiKey: "AIzaSyArg6eFPp6trk50fCRGC_xqPgslkIa5WTE",
  authDomain: "crux-3c6be.firebaseapp.com",
  projectId: "crux-3c6be",
  storageBucket: "crux-3c6be.firebasestorage.app",
  messagingSenderId: "33175700363",
  appId: "1:33175700363:web:8dff2f40e10d1ead66658e",
  measurementId: "G-6GVHG2D4YB"
};

export const ICE_CONFIG = {
  iceServers: [
    // Google STUN (always free, no auth needed)
    { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302',
             'stun:stun2.l.google.com:19302', 'stun:stun3.l.google.com:19302',
             'stun:stun4.l.google.com:19302', 'stun:stun.cloudflare.com:3478'] },
    // Open Relay TURN (public, free, good for 80% of NAT traversal cases)
    { urls: ['turn:openrelay.metered.ca:80',  'turn:openrelay.metered.ca:443',
             'turn:openrelay.metered.ca:443?transport=tcp', 'turns:openrelay.metered.ca:443'],
      username: 'openrelayproject', credential: 'openrelayproject' },
    // Backup: numb.viagenie.ca public TURN
    { urls: 'turn:numb.viagenie.ca', username: 'webrtc@live.com', credential: 'muazkh' },
  ],
  sdpSemantics: 'unified-plan',
  iceTransportPolicy: 'all',
};

// Generate a 12-char meeting ID (uppercase alphanumeric, matches Flutter UUID slice)
export function generateMeetingId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return Array.from({length: 12}, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

export function formatDate(ts) {
  if (!ts) return '';
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  return d.toLocaleDateString('fr-FR', { day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' });
}

export function toast(msg, duration = 3000) {
  let el = document.getElementById('toast');
  if (!el) { el = document.createElement('div'); el.id = 'toast'; document.body.appendChild(el); }
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show'), duration);
}

export function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

// Redirect to login if not authenticated
export function requireAuth(auth, onUser) {
  return new Promise(resolve => {
    const unsub = auth.onAuthStateChanged(user => {
      unsub();
      if (!user || user.isAnonymous) {
        window.location.href = '../login/?next=' + encodeURIComponent(location.pathname + location.search);
      } else {
        if (onUser) onUser(user);
        resolve(user);
      }
    });
  });
}
