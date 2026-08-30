# CRUX Web Deployment Guide

## Overview
CRUX now supports web deployment via GitHub Pages, allowing users to join meetings directly from their browser without installing the app.

## GitHub Pages Setup

### Automatic Deployment
The project includes a GitHub Actions workflow (`.github/workflows/deploy-web.yml`) that automatically builds and deploys the Flutter web app to GitHub Pages when you push to the `main` or `master` branch.

### Manual Setup
1. Go to your GitHub repository settings
2. Navigate to "Pages" section
3. Set "Source" to "GitHub Actions"
4. The workflow will automatically handle the deployment

### Configuration
The workflow uses the following configuration:
- **Flutter Version**: 3.24.0 (stable channel)
- **Base URL**: `/crux_new_final/` (adjust based on your repository name)
- **Build Command**: `flutter build web --release --base-href /crux_new_final/`

## Environment Variables
Make sure these secrets are configured in your GitHub repository settings:
- `LIVEKIT_WSS_URL`: Your LiveKit WebSocket URL
- `LIVEKIT_TOKEN_SERVER_URL`: Your token server URL
- `FIREBASE_PROJECT_ID`: Your Firebase project ID
- `APP_BASE_URL`: Your application base URL

## Accessing the Web App

### Direct Meeting Join
Users can join meetings directly via:
- Main web app: `https://[username].github.io/crux_new_final/`
- Join page: `https://[username].github.io/crux_new_final/join.html`

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

### Browser Compatibility
- ✅ Chrome (Android & Desktop)
- ✅ Safari (iOS & Desktop)
- ✅ Firefox (Desktop)
- ✅ Edge (Desktop)

### Mobile Browser Support
- iOS Safari: Full support
- Android Chrome: Full support
- Requires HTTPS for camera/microphone access

## Testing the Web Deployment

### Local Testing
```bash
flutter build web --release
flutter run -d chrome --release
```

### Production Testing
1. Push to main branch
2. Wait for GitHub Actions to complete
3. Access the deployed URL
4. Test meeting join functionality

## Troubleshooting

### Build Failures
- Check Flutter version compatibility
- Verify all dependencies are up to date
- Review GitHub Actions logs

### Deployment Issues
- Ensure GitHub Pages is enabled
- Check workflow permissions
- Verify base URL configuration

### Runtime Issues
- Check browser console for errors
- Verify API keys and URLs
- Test camera/microphone permissions

## Performance Optimization

### Build Size
- The web build is optimized for performance
- Uses code splitting and lazy loading
- Assets are compressed automatically

### Loading Time
- Target: < 5 seconds on 4G
- Progressive loading for media streams
- Optimized asset delivery

## Security Considerations

### HTTPS Required
- Camera/microphone access requires HTTPS
- GitHub Pages provides HTTPS automatically
- Production deployments must use secure connections

### API Security
- All API calls use environment variables
- Firebase authentication enforced
- LiveKit tokens generated server-side

## Future Enhancements

### Planned Features
- [ ] PWA support for offline access
- [ ] Enhanced mobile browser experience
- [ ] Advanced screen sharing options
- [ ] In-meeting chat
- [ ] Recording capabilities
- [ ] Live captions

### Browser APIs
- WebRTC for real-time communication
- Screen Capture API for sharing
- Media Devices API for camera/mic access
- Notification API for meeting alerts

## Support

For issues related to:
- **Deployment**: Check GitHub Actions logs
- **Functionality**: Review browser console
- **Configuration**: Verify environment variables
- **Performance**: Test on target browsers

## Updates

This deployment guide will be updated as new features are added to the web version.