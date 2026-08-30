# CRUX Web Deployment Guide

## Overview
CRUX supports web deployment via GitHub Pages, allowing users to join meetings directly from their browser without installing the app. The web version is generated from the same Flutter codebase as the mobile app, ensuring identical functionality and design.

## GitHub Pages Setup

### Automatic Deployment
The project includes a GitHub Actions workflow (`.github/workflows/deploy-web.yml`) that automatically builds and deploys the Flutter web app to GitHub Pages when you push to the `main`, `master`, or `schac` branch.

The workflow uses the `peaceiris/actions-gh-pages@v3` action for reliable deployment to the `gh-pages` branch.

### Manual Setup
1. Create a new branch named `gh-pages` in your repository
2. Go to your GitHub repository settings
3. Navigate to "Pages" section
4. Set "Source" to "Deploy from a branch"
5. Select "gh-pages" branch and "/ (root)" folder
6. The workflow will automatically handle the deployment

### Configuration
The workflow uses the following configuration:
- **Flutter Version**: 3.24.0 (stable channel)
- **Base URL**: `/crux_new_final/` (adjust based on your repository name)
- **Build Command**: `flutter build web --release --base-href /crux_new_final/`
- **Deployment**: peaceiris/actions-gh-pages@v3 to gh-pages branch

## Environment Variables
Configure these secrets in your GitHub repository settings:
- `LIVEKIT_WSS_URL`: Your LiveKit WebSocket URL
- `LIVEKIT_TOKEN_SERVER_URL`: Your token server URL
- `FIREBASE_PROJECT_ID`: Your Firebase project ID
- `APP_BASE_URL`: Your application base URL

## Accessing the Web App

### Direct Meeting Join
Users can join meetings directly via:
- Main web app: `https://[username].github.io/crux_new_final/`
- Join page: `https://[username].github.io/crux_new_final/join.html`

### Repository URL Structure
- Repository: `https://github.com/schac-hub/crux_new_final`
- GitHub Pages: `https://schac-hub.github.io/crux_new_final/`
- Join page: `https://schac-hub.github.io/crux_new_final/join.html`

### Meeting Code Format
Meeting codes are 8-character alphanumeric strings (e.g., `ABCDEF12`).

## Features Available in Web Version

### Core Meeting Features
- ✅ Join meetings with audio/video
- ✅ Microphone toggle
- ✅ Camera toggle
- ✅ Screen sharing (presenter)
- ✅ Participant list
- ✅ Basic meeting controls
- ✅ Network status indicators
- ✅ Responsive design for mobile browsers
- ✅ Reactions (emojis)
- ✅ Hand raising
- ✅ Live captions (speech-to-text)
- ✅ Chat functionality
- ✅ Host controls (mute all, etc.)

### Browser Compatibility
- ✅ Chrome (Android & Desktop) - Full support
- ✅ Safari (iOS & Desktop) - Full support
- ✅ Firefox (Desktop) - Full support
- ✅ Edge (Desktop) - Full support

### Mobile Browser Support
- iOS Safari: Full support with camera/microphone
- Android Chrome: Full support with camera/microphone
- Requires HTTPS for camera/microphone access

## Testing the Web Deployment

### Local Testing
```bash
flutter build web --release
flutter run -d chrome --release
```

### Production Testing
1. Push to main/master/schac branch
2. Wait for GitHub Actions to complete
3. Access the deployed URL
4. Test meeting join functionality

## Performance Optimization

### Build Size
- The web build is optimized for performance
- Uses code splitting and lazy loading
- Assets are compressed automatically

### Loading Time
- Target: < 5 seconds on 4G
- Progressive loading for media streams
- Optimized asset delivery

### Memory Usage
- Target: < 8MB additional vs mobile
- Efficient participant rendering (max 10 visible)
- Smart caching and garbage collection

## Security Considerations

### HTTPS Required
- Camera/microphone access requires HTTPS
- GitHub Pages provides HTTPS automatically
- Production deployments must use secure connections

### API Security
- All API calls use environment variables
- Firebase authentication enforced
- LiveKit tokens generated server-side
- Rate limiting on token server

### Data Protection
- User data encrypted in transit
- No sensitive data stored locally
- Firebase security rules enforced
- GDPR/CCPA compliant

## Troubleshooting

### Build Failures
- Check Flutter version compatibility
- Verify all dependencies are up to date
- Review GitHub Actions logs
- Ensure environment variables are set

### Deployment Issues
- Ensure GitHub Pages is enabled
- Check workflow permissions
- Verify base URL configuration
- Check branch protection rules

### Runtime Issues
- Check browser console for errors
- Verify API keys and URLs
- Test camera/microphone permissions
- Check WebRTC support

### Performance Issues
- Test on target browsers
- Monitor network conditions
- Check participant count
- Verify device capabilities

## Architecture

### Same Codebase
The web version is built from the exact same Flutter codebase as the mobile app:
- Same screens and components
- Same business logic
- Same state management
- Same theme and styling
- Same Firebase integration

### Platform-Specific Adaptations
- Browser-specific WebRTC handling
- Camera/microphone permission dialogs
- Keyboard shortcuts for desktop
- Touch gestures for mobile
- Responsive layout adaptation

## Monitoring

### GitHub Actions Logs
- Build duration and success rate
- Deployment status
- Error tracking

### Web Analytics
- Page load times
- User engagement metrics
- Feature usage statistics
- Error reporting

## Future Enhancements

### Planned Features
- [ ] PWA support for offline access
- [ ] Enhanced mobile browser experience
- [ ] Advanced screen sharing options
- [ ] In-meeting file sharing
- [ ] Collaborative whiteboard
- [ ] Polls and Q&A
- [ ] Cloud recording
- [ ] Live captions in multiple languages

### Browser APIs
- WebRTC for real-time communication
- Screen Capture API for sharing
- Media Devices API for camera/mic access
- Notification API for meeting alerts
- Clipboard API for meeting codes
- Geolocation for timezone detection

## Support

For issues related to:
- **Deployment**: Check GitHub Actions logs
- **Functionality**: Review browser console
- **Configuration**: Verify environment variables
- **Performance**: Test on target browsers
- **Security**: Review Firebase rules

## Updates

This deployment guide will be updated as new features are added to the web version.