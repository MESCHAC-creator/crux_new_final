# 🏗️ CRUX 2026 — ARCHITECTURE TECHNIQUE & FEATURES DÉTAILLÉES

## I. ARCHITECTURE GLOBALE

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CRUX SYSTEM ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  CLIENT LAYER (Presentation)                              │  │
│  ├─────────────────────────────────────────────────────────────┤  │
│  │  Desktop (Tauri)    │  Mobile (RN)     │  Web (Next.js)   │  │
│  │  - 5MB binary       │ - iOS/Android    │ - PWA-ready      │  │
│  │  - Native perf      │ - Touch-optimized│ - Browser native │  │
│  │  - System tray      │ - Background svc │ - Serverless OK  │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                            ↓↓↓                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  SYNC/SIGNALING LAYER (Real-time)                         │  │
│  ├─────────────────────────────────────────────────────────────┤  │
│  │  WebSocket (signaling)  →  gRPC (streaming metadata)      │  │
│  │  Message queue (Redis)  →  State sync (CRDT-like)         │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                            ↓↓↓                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  MEDIA LAYER (WebRTC + Optimization)                      │  │
│  ├─────────────────────────────────────────────────────────────┤  │
│  │  Peer Connection (native WebRTC API)                      │  │
│  │  Codec negotiation: AV1 → VP9 → H.264 (fallback)        │  │
│  │  NACK-based retransmission (minimize latency)             │  │
│  │  Adaptive bitrate (RTCStats every 500ms)                  │  │
│  │  Jitter buffer (tuned for low latency)                    │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                            ↓↓↓                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  BACKEND LAYER (Business Logic)                           │  │
│  ├─────────────────────────────────────────────────────────────┤  │
│  │  Go service + Rust hot-path functions                     │  │
│  │  - Session management (FastAPI-like)                      │  │
│  │  - Presence tracking (Redis pub/sub)                      │  │
│  │  - Recording orchestration (FFmpeg)                       │  │
│  │  - Transcription (Whisper local + API fallback)          │  │
│  │  - Permission checks (rego/OPA policies)                  │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                            ↓↓↓                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  DATA LAYER (Persistence & Analytics)                     │  │
│  ├─────────────────────────────────────────────────────────────┤  │
│  │  PostgreSQL (meetings, users, recordings)                 │  │
│  │  Redis (cache, sessions, presence)                        │  │
│  │  S3-compatible (recordings, transcripts)                  │  │
│  │  MeiliSearch (cross-meeting search)                       │  │
│  │  ClickHouse (analytics, metrics)                          │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  INFRASTRUCTURE                                            │  │
│  ├─────────────────────────────────────────────────────────────┤  │
│  │  Edge nodes (SFU) — Cloudflare, Fly.io, or custom        │  │
│  │  CDN for static content                                   │  │
│  │  Kubernetes for orchestration                            │  │
│  │  Observability: Prometheus + Grafana                     │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## II. PERFORMANCE TARGETS (vs Competitors)

### **Desktop App Resource Usage**

```
                CPU %      RAM MB     Disk MB
Zoom            6%         400        250
Google Meet     16%        963        150 (browser-based)
Microsoft Teams 12%        700        400
CRUX Target     <5%        <300       100

Latency (P95):
Zoom            120ms
Google Meet     150ms
Microsoft Teams 140ms
CRUX Target     <100ms

Codec Efficiency (bitrate for equivalent quality):
H.264           1 Mbps (baseline)
VP9             0.7 Mbps (30% savings)
AV1             0.5 Mbps (50% savings vs H.264)

Encoding Time (1080p 30fps):
H.264 (x264)    3.2 Gbps (real-time)
VP9 (libvpx-vp9) 0.8 Gbps (4x slower, but adaptive bitrate handles)
AV1 (libaom)    0.4 Gbps (8x slower, but worth for bandwidth savings)

Strategy: Use AV1 for recording, VP9 for calls (balance)
```

### **Network Efficiency**

```
Initial Connection: 2-3 seconds (vs Zoom 4-5, Meet 6-7)
  • Pre-connection: DNS prefetch, WebRTC peer connection start (1s)
  • ICE gathering: 0.5-1s
  • Media flow: 0.5-1s

Bandwidth Usage (5-person call):
  Incoming: 2.5-4 Mbps (HD)
  Outgoing: 1-2 Mbps (encode profile)
  Zoom: ~3.5 Mbps
  Meet: ~4 Mbps
  CRUX: ~2.5 Mbps (better codec negotiation)

Adaptive Bitrate (RTCStats-based):
  • Every 500ms, check stats
  • If RTT > 200ms OR loss > 5%, drop quality
  • Smooth transitions (no buffering)
```

---

## III. KILLER FEATURES SPECIFICATIONS

### **1. Multi-Call Mode**

**What**: Rejoin 2+ calls simultanément (comme plusieurs tabs mais synchronisées)

**Technical Implementation**:
```dart
// CRUX data model
class CallContext {
  String id;
  String title;
  bool isActive;       // Active or background
  int participantCount;
  Duration duration;
  bool hasUnreadChat;
}

// In app state
List<CallContext> activeCalls;  // [call1, call2]
CallContext? focusedCall;       // call1 (active)
```

**UI/UX**:
- Taskbar shows all calls (click to switch)
- System tray notification per call
- Audio from focused call only (others muted)
- Quick-switch hotkey: `Ctrl+Tab`

**Use Cases**:
- Remote job candidates interview while watching webinar
- Support team handling multiple client calls
- Day trading watching multiple charts while in standup

---

### **2. Screen Overlay (Participants Visible During Share)**

**What**: Au lieu de cacher les participants quand on partage l'écran, les afficher en PIP/mini-window

**Technical Implementation**:
```javascript
// WebRTC constraints
const constraints = {
  video: {
    displaySurface: 'monitor',  // or 'window'
    logicalSurface: true,
    cursor: 'always'
  },
  audio: false
};

// Rendering
const canvasContext = screenShareCanvas.getContext('2d');
// Draw shared screen at (0, 0)
canvasContext.drawImage(screenShareStream, 0, 0);
// Draw participant avatars overlay at bottom-right (opacity 0.8)
for (participant in remoteParticipants) {
  canvasContext.drawImage(
    participant.video,
    width - 150,  // bottom-right corner
    height - 150,
    120, 90       // 120x90 video tile
  );
}
```

**Use Cases**:
- Teaching (see student faces while teaching)
- Presentations (see audience reactions)
- Support (see customer face while screensharing)

---

### **3. Collaborative Cursor**

**What**: Tous les curseurs visibles sur l'écran partagé (pour annotations collaboratives)

**Implementation**:
```javascript
// Broadcast cursor position via signaling layer
const mouseMoveHandler = (e) => {
  const x = (e.clientX / window.innerWidth) * 100;  // %
  const y = (e.clientY / window.innerHeight) * 100;
  
  signalingChannel.send({
    type: 'cursor_move',
    x: x,
    y: y,
    userId: currentUser.id
  });
};

// Render remote cursors on canvas
remoteParticipants.forEach(p => {
  if (p.cursor) {
    drawCursor(p.cursor.x, p.cursor.y, p.color, p.name);
  }
});
```

**Use Cases**:
- Design reviews (everyone pointing at same element)
- Code reviews (pair programming feeling)
- Collaborative whiteboarding

---

### **4. Room Templates**

**What**: Breakout rooms pré-configurées pour différents use-cases

**Templates**:
```javascript
const roomTemplates = {
  'icebreaker': {
    name: 'Icebreaker',
    roomCount: 5,
    duration: 15,
    prompt: 'Share: What did you have for lunch?'
  },
  'workshop': {
    name: 'Workshop Session',
    roomCount: 3,
    duration: 45,
    prompt: 'Work on assigned problem',
    tools: ['whiteboard', 'code_editor', 'screen_share']
  },
  'retrospective': {
    name: 'Retrospective',
    roomCount: 2,
    duration: 30,
    sections: [
      { title: 'What went well?', time: 10 },
      { title: 'What could be better?', time: 10 },
      { title: 'Action items', time: 10 }
    ]
  },
  'brainstorm': {
    name: 'Brainstorming',
    roomCount: 4,
    duration: 25,
    tools: ['whiteboard', 'timer'],
    timer: true
  }
};
```

---

### **5. Meeting Health Dashboard**

**What**: RTCStats affichés en temps réel (latence, jitter, packet loss, bande passante)

**Real-time Metrics**:
```javascript
const stats = {
  connection: {
    roundTripTime: 45,        // ms
    availableOutgoingBitrate: 2500000,  // bps
    availableIncomingBitrate: 3000000,
  },
  inbound: {
    bytesReceived: 125000000,  // bytes
    packetsReceived: 95000,
    packetsLost: 150,
    jitter: 12,  // ms
    fractionLost: 0.0016  // 0.16%
  },
  outbound: {
    bytesSent: 85000000,
    packetsSent: 88000,
    qualityLimitation: 'none',  // 'cpu' or 'bandwidth'
  },
  audio: {
    volume: -32,  // dBFS
    echoCancellation: true,
    noiseSuppression: true
  }
};
```

**UI Widget**:
- Red: problèmes critiques (> 50ms latency, > 5% loss)
- Yellow: dégradation (20-50ms, 1-5% loss)
- Green: optimal

---

### **6. Persistent Chat**

**What**: Chat survit entre les sessions de réunion récurrente (contrairement à Meet/Zoom où chat se vide après)

**Implementation**:
```sql
-- Table structure
meetings:         recurring meeting template
meeting_sessions: individual session (2024-12-01 14:00)
chat_messages:    tied to recurring_meeting_id (not session_id)

-- Query
SELECT * FROM chat_messages 
WHERE recurring_meeting_id = 'weekly-standup'
ORDER BY created_at DESC
LIMIT 50;

-- Result: Toutes les messages de toutes les sessions
```

**Use Cases**:
- Weekly standups (voir l'historique des anciennes mises à jour)
- Recurring client calls (contexte persistant)
- Team channels

---

### **7. Smart Noise Suppression**

**What**: ML-based noise cancellation qui apprend votre environnement

**Implementation**:
```python
# Uses: TensorFlow Lite + on-device processing
# On first call, record 30s ambient noise profile
ambient_profile = AudioPreprocessor.record_ambient(duration=30)

# For each subsequent call, filter relative to that profile
for audio_frame in stream:
    # 1. Spectral subtraction (remove ambient frequencies)
    cleaned = spectral_subtract(audio_frame, ambient_profile)
    # 2. ML-based cleanup (TensorFlow Lite LSTM)
    enhanced = ml_denoise(cleaned, model='ns-lite.tflite')
    output_stream.write(enhanced)
```

**Advantage over Zoom/Meet**:
- Learns YOUR office acoustics
- Persists across calls (doesn't reset)
- Works offline (no cloud required)

---

### **8. Async Video Messages**

**What**: Leave video voicemails in team, available later

**UX Flow**:
```
1. Click "Leave async message"
2. 60-second video capture
3. Transcription auto (+ AI summary)
4. Sent to team
5. Playable in-app + email notification
6. Replies also async (thread)
```

**Use Cases**:
- Async-first teams (distributed across timezones)
- Status updates (say more than text)
- One-way demos/updates

---

## IV. DESIGN SYSTEM 2026 (ZERO INCONSISTENCY)

### **Color Palette**
```
Primary:      #0066FF (Focus, primary actions)
Secondary:   #FF6B35 (Warnings, secondary)
Success:     #00C853 (Positive actions)
Error:       #FF3333 (Destructive, critical)
Surface:     #FFFFFF (Light) / #1A1A1A (Dark)
Overlay:     #000000 @ 8% opacity (surfaces)

Semantic colors NEVER used inconsistently:
- Blue always means "interactive"
- Red always means "danger"
- Green always means "success"
```

### **Typography**
```
Font Family: Inter (system font fallback)
                   
Headings:
  H1: 32px, 700 weight, -0.5px tracking
  H2: 28px, 700 weight, -0.25px tracking
  H3: 24px, 600 weight, 0px tracking
  
Body:
  Body: 16px, 400 weight, 0.5px tracking
  Small: 14px, 400 weight, 0.25px tracking
  
Monospace:
  Code: Courier New, 13px

RULE: Every text element has ONE source of truth
```

### **Spacing System**
```
Base unit: 8px

Tokens:
  xs:  4px
  sm:  8px
  md:  16px
  lg:  24px
  xl:  32px
  2xl: 48px

RULE: Never use arbitrary spacing (10px, 13px, 37px)
```

### **Component Consistency**
```
Buttons:
  • Filled: Used for primary actions
  • Outlined: Used for secondary actions
  • Ghost: Used for tertiary actions
  • NEVER mix (no filled + outlined on same bar)

Modals:
  • Always have close button (⊗) top-right
  • Always have backdrop (blur + opacity)
  • Always center on screen (not offset)
  
Forms:
  • Label ALWAYS above field (never inline)
  • Error text ALWAYS below field (red, 12px)
  • Required indicator: red asterisk after label
  
Status indicators:
  • Red dot = error/offline
  • Yellow dot = warning/connecting
  • Green dot = ok/online
  • Blue dot = new/notification
  (NEVER other uses)
```

---

## V. PERFORMANCE OPTIMIZATION CHECKLIST

- [ ] Desktop app uses native rendering (Tauri Canvas/WebGPU)
- [ ] Mobile app uses React Native > Flutter (better perf)
- [ ] WebRTC uses H.264 (HW-accelerated) as fallback
- [ ] Adaptive bitrate kicks in < 500ms
- [ ] TURN servers in all regions (< 20ms latency)
- [ ] Front-end code-split (lazy-load features)
- [ ] Database indexes on (user_id, meeting_id, created_at)
- [ ] Redis cache for frequently accessed data (profiles, settings)
- [ ] CDN for static assets (99.9% hit ratio target)
- [ ] Service worker for offline capability
- [ ] Throttling/debouncing on all user input handlers
- [ ] Image optimization (WebP, AVIF)
- [ ] Database query profiling (no N+1 queries)

---

## VI. PRIVACY & SECURITY ARCHITECTURE

### **Default E2EE (Unlike Meet)**

```
Signal-like architecture:
1. Double Ratchet Algorithm (forward secrecy)
2. Per-message keys (break one, not entire session)
3. Key material in system keystore (not app memory)
4. Perfect Forward Secrecy by default

Implementation:
• Use libsignal (open-source, audited)
• Server never sees plaintext (SFU encryption-aware)
• Client-side transcription (no upload)
```

### **On-Device Processing (No Cloud Bleed)**

```
Processing chain:
Screen Share → FFmpeg (local) → VP9 (local)
            ↓
        Annotations (local)
            ↓
        Upload to S3 (encrypted)
            
NO intermediate step on server unencrypted
```

---

**Next: Implement key features & validate market fit**
