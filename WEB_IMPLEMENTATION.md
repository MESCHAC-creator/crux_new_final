# CRUX Web Implementation Documentation

## Overview
This document describes the web implementation of CRUX video conferencing application, enabling users to join meetings directly from their browser without installing the mobile app.

## Architecture

### Existing Web Structure
The web implementation uses a vanilla JavaScript approach with Firebase and LiveKit, separate from the Flutter mobile app:

- **Frontend**: Pure HTML/CSS/JavaScript (no framework)
- **Backend**: Firebase Firestore + LiveKit Server SDK
- **Real-time**: Firebase Realtime Database for presence and chat
- **Video**: LiveKit WebRTC for audio/video streaming

### File Structure
```
web/
├── public/
│   ├── index.html              # Landing page with quick join
│   ├── join/
│   │   └── index.html          # Meeting join interface
│   ├── app/
│   │   └── index.html          # User dashboard
│   ├── login/
│   │   └── index.html          # Authentication
│   ├── signup/
│   │   └── index.html          # Registration
│   ├── css/
│   │   └── crux.css            # Shared styles
│   └── js/
│       └── firebase.js          # Firebase configuration
└── index.html                 # Flutter web entry point
```

## Key Features Implemented

### 1. Meeting Access via Code
- **Quick Join**: Users can enter meeting codes directly on the landing page
- **URL-based Access**: Direct links like `https://crux.app/join/CODE123`
- **Validation**: 8-character alphanumeric codes with automatic uppercase conversion
- **Keyboard Shortcut**: Press "/" to focus the code input field

### 2. Authentication
- **Firebase Auth**: Anonymous authentication for quick meeting access
- **User Accounts**: Full Google Sign-In for registered users
- **Session Management**: Persistent sessions with Firebase
- **Profile Sync**: Name and profile synchronization across platforms

### 3. Video Conferencing Core
- **LiveKit Integration**: WebRTC-based video/audio streaming
- **Adaptive Quality**: Automatic quality adjustment based on network conditions
- **Multi-participant Support**: Grid layout for multiple participants
- **Screen Sharing**: Desktop sharing with LiveKit ScreenShare API
- **Active Speaker Detection**: Visual highlighting of current speaker

### 4. Meeting Controls
- **Microphone Toggle**: Enable/disable microphone with visual feedback
- **Camera Toggle**: Enable/disable camera with visual feedback
- **Screen Share**: Start/stop screen sharing
- **Chat Panel**: Real-time text messaging
- **Participants List**: View all participants with status indicators
- **Lock Meeting**: Host can lock meeting (waiting room)
- **Whiteboard**: Collaborative drawing canvas
- **Reactions**: Emoji reactions with animations
- **Hand Raising**: Raise hand to speak
- **Leave Meeting**: Clean disconnect and cleanup

### 5. Mobile Optimization
- **Responsive Design**: Adapts to mobile screens (portrait/landscape)
- **Touch Support**: Touch events for canvas drawing
- **Camera Switch**: Long-press camera button to switch front/back
- **Fullscreen Mode**: Toggle fullscreen for better viewing
- **Performance**: Optimized for mobile browsers

### 6. Security Features
- **Firebase Security Rules**: Server-side validation
- **Token-based Authentication**: LiveKit tokens with expiration
- **Input Validation**: All user inputs validated and sanitized
- **Rate Limiting**: Backend rate limiting for API calls
- **HTTPS Only**: Secure connections required

## Technical Implementation Details

### Firebase Integration
```javascript
// Firebase Initialization
const app = initializeApp(FIREBASE_CONFIG);
const auth = getAuth(app);
const db = getFirestore(app);

// Real-time meeting updates
onSnapshot(doc(db, 'meetings', meetingId), (snap) => {
  // Handle meeting state changes
});
```

### LiveKit Integration
```javascript
// Room connection
const room = new LiveKit.Room({
  adaptiveStream: true,
  dynacast: true,
  videoCaptureDefaults: {
    resolution: LiveKit.VideoPresets.h720.resolution,
  }
});

await room.connect(livekitUrl, token);
```

### Data Synchronization
- **Presence**: Real-time participant status (mic, camera, connection)
- **Chat**: Firebase Firestore collection for message persistence
- **Reactions**: Firestore collection for emoji reactions
- **Whiteboard**: Firestore collection for drawing coordinates
- **Hand Raising**: Firestore field for raised hands

## Mobile Browser Compatibility

### Supported Browsers
- **Android**: Chrome 80+, Firefox 75+, Edge 80+
- **iOS**: Safari 13+, Chrome 90+
- **Desktop**: Chrome 80+, Firefox 75+, Safari 13+, Edge 80+

### Mobile-Specific Features
- **Touch Events**: Canvas drawing with touch support
- **Orientation Changes**: Adaptive layout for portrait/landscape
- **Network Awareness**: Reconnection on network changes
- **Battery Optimization**: Adaptive streaming to save battery

## Testing Guide

### Manual Testing Steps

1. **Landing Page Test**
   - Open `https://crux.app` in mobile browser
   - Enter meeting code and join
   - Verify authentication flow

2. **Meeting Join Test**
   - Create meeting from mobile app
   - Open meeting link in mobile browser
   - Verify audio/video connection
   - Test all controls

3. **Cross-Platform Test**
   - Join meeting from mobile browser
   - Join same meeting from mobile app
   - Verify audio/video sync
   - Test chat across platforms

4. **Network Test**
   - Test on 4G network
   - Test on WiFi
   - Test network interruption recovery

### Automated Testing
```bash
# Run Firebase emulators for local testing
firebase emulators:start

# Test web interface locally
cd web/public
python -m http.server 8080
```

## Limitations and Known Issues

### Current Limitations
1. **No Local Recording**: Browser recording not implemented (requires permission complexity)
2. **No Transcription**: Real-time transcription not available
3. **Limited Camera Controls**: Basic front/back toggle only on mobile
4. **No Background Blur**: Virtual backgrounds not supported in web version
5. **File Sharing**: File transfer not implemented in web chat

### Browser-Specific Issues
- **iOS Safari**: Some limitations on camera access permissions
- **Android Chrome**: Screen sharing requires Android 5+
- **Firefox**: Some WebRTC features may vary

## Performance Optimization

### Load Performance
- **Bundle Size**: < 200KB initial load
- **Lazy Loading**: LiveKit SDK loaded on-demand
- **Caching**: Service worker for offline support
- **CDN**: Firebase SDK served via CDN

### Runtime Performance
- **Adaptive Streaming**: Automatic quality adjustment
- **CPU Usage**: Optimized for mobile processors
- **Memory Management**: Cleanup on participant disconnect
- **Network Usage**: Efficient video compression

## Security Considerations

### Data Protection
- **End-to-End Encryption**: LiveKit E2E encryption
- **Secure Tokens**: Short-lived JWT tokens
- **Input Sanitization**: All inputs validated and escaped
- **HTTPS Only**: No insecure connections allowed

### Privacy
- **Anonymous Access**: No account required for basic meetings
- **Data Minimization**: Only essential data collected
- **Local Processing**: Video processed locally before transmission
- **No Tracking**: No third-party analytics

## Future Enhancements

### Planned Features
1. **Local Recording**: Browser-based meeting recording
2. **Virtual Backgrounds**: AI-powered background blur/replacement
3. **Advanced Camera Controls**: Zoom, pan, brightness adjustment
4. **File Sharing**: In-meeting file transfer
5. **Breakout Rooms**: Small group discussions
6. **Polls and Q&A**: Interactive meeting features

### Technical Improvements
1. **PWA Support**: Progressive Web App for offline use
2. **Web Workers**: Better performance with background processing
3. **WebAssembly**: Hardware-accelerated video processing
4. **WebGPU**: Next-generation graphics API support

## Troubleshooting

### Common Issues

**Problem**: Camera/microphone not working
- **Solution**: Check browser permissions, ensure HTTPS, try different browser

**Problem**: Poor video quality
- **Solution**: Check network connection, close other apps, try adaptive streaming

**Problem**: Cannot join meeting
- **Solution**: Verify meeting code, check internet connection, ensure meeting is active

**Problem**: Screen sharing not working
- **Solution**: Check browser support, ensure permission granted, try Chrome/Edge

### Debug Mode
Enable debug logging by adding `?debug=true` to URL for detailed console output.

## Conclusion

The CRUX web implementation provides a comprehensive browser-based meeting experience that closely matches the mobile app functionality while maintaining the existing Flutter app structure. Users can join meetings seamlessly from any modern browser without installation, with support for all essential meeting features.