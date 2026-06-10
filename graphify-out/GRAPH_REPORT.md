# Graph Report - crux_new_final  (2026-06-10)

## Corpus Check
- 70 files · ~84,144 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1673 nodes · 2231 edges · 73 communities (62 shown, 11 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 4 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7edb2120`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 75|Community 75]]

## God Nodes (most connected - your core abstractions)
1. `LocaleProvider` - 95 edges
2. `ThemeProvider` - 20 edges
3. `MainActivity` - 13 edges
4. `CallForegroundService` - 12 edges
5. `ColorProvider` - 9 edges
6. `Intent` - 7 edges
7. `_ProfileScreenState` - 7 edges
8. `_SettingsScreenState` - 7 edges
9. `build` - 7 edges
10. `_VideoCallScreenState` - 6 edges

## Surprising Connections (you probably didn't know these)
- `_buildError` --references--> `LocaleProvider`  [EXTRACTED]
  lib/screens/device_verification_screen.dart → lib/providers/locale_provider.dart
- `build` --references--> `LocaleProvider`  [EXTRACTED]
  lib/screens/home_screen.dart → lib/providers/locale_provider.dart
- `_buildEmptyState` --references--> `LocaleProvider`  [EXTRACTED]
  lib/screens/home_screen.dart → lib/providers/locale_provider.dart
- `_logout` --references--> `LocaleProvider`  [EXTRACTED]
  lib/screens/home_screen.dart → lib/providers/locale_provider.dart
- `_shareApp` --references--> `LocaleProvider`  [EXTRACTED]
  lib/screens/home_screen.dart → lib/providers/locale_provider.dart

## Import Cycles
- None detected.

## Communities (73 total, 11 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.01
Nodes (359): ../constants/app_constants.dart, MediaStream?, meeting_report_screen.dart, package:flutter_webrtc/flutter_webrtc.dart, package:permission_handler/permission_handler.dart, package:speech_to_text/speech_to_text.dart, ProService, RTCPeerConnection? (+351 more)

### Community 1 - "Community 1"
Cohesion: 0.04
Nodes (52): _authService, _bgController, build, _buttonController, _buttonFade, _buttonScale, _buttonSlide, _contentController (+44 more)

### Community 2 - "Community 2"
Cohesion: 0.04
Nodes (52): _authService, _bgController, build, _buildFooter, _buildHeader, _buildSignUpButton, _buttonController, _buttonFade (+44 more)

### Community 3 - "Community 3"
Cohesion: 0.04
Nodes (46): LocaleProvider, build, _buildActivitiesPanel, _buildAgendaPanel, _buildChatInput, _buildChatMessages, _buildChatPanel, _buildControls (+38 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (43): admit, admitAll, AppLocalizations, appName, camera, chat, _current, _currentLanguage (+35 more)

### Community 5 - "Community 5"
Cohesion: 0.05
Nodes (40): static const Duration, AppConstants, cacheDuration, defaultBorderRadius, defaultElevation, defaultMeetingLanguage, defaultPadding, firebaseProjectId (+32 more)

### Community 6 - "Community 6"
Cohesion: 0.05
Nodes (39): accent, accentGradient, accentLight, AppColors, AppColorsPalette, awayYellow, bgGradient1, bgGradient2 (+31 more)

### Community 7 - "Community 7"
Cohesion: 0.05
Nodes (38): dart:ui, activeColor, _animCtrl, _camDefault, child, color, createState, dispose (+30 more)

### Community 8 - "Community 8"
Cohesion: 0.05
Nodes (39): package:image_picker/image_picker.dart, package:path_provider/path_provider.dart, _animCtrl, _auth, _buildAvatar, _changePassword, child, color (+31 more)

### Community 9 - "Community 9"
Cohesion: 0.05
Nodes (39): _authService, build, _buildChatTab, _buildEmptyState, _buildGreetingHeader, _buildHomeTab, _buildQuickActions, _buildSectionHeader (+31 more)

### Community 10 - "Community 10"
Cohesion: 0.05
Nodes (38): static const Color, static const LinearGradient, accentGolden, accentOrange, borderGray, cloudWhite, coolBackgroundGradient, coolGradient (+30 more)

### Community 11 - "Community 11"
Cohesion: 0.06
Nodes (35): Color?, Color get, int get, LinearGradient get, package:flutter_secure_storage/flutter_secure_storage.dart, package:url_launcher/url_launcher.dart, ColorOption, end (+27 more)

### Community 12 - "Community 12"
Cohesion: 0.06
Nodes (50): AuthWrapper, _AuthWrapperState, QuerySnapshot, LoginScreen, _LoginScreenState, ProfileScreen, _ProfileScreenState, SignUpScreen (+42 more)

### Community 13 - "Community 13"
Cohesion: 0.05
Nodes (36): bool?, class, firebase_options.dart, _authStream, blockReason, createState, _flutterUnsupportedLocales, _initDeepLinks (+28 more)

### Community 14 - "Community 14"
Cohesion: 0.10
Nodes (12): Int, FlutterEngine, Boolean, Configuration, CallForegroundService, MainActivity, FlutterActivity, IBinder (+4 more)

### Community 15 - "Community 15"
Cohesion: 0.06
Nodes (32): Animation, AnimationController, dart:math, _bgController, build, _buildLoader, _buildLogo, _buildRipple (+24 more)

### Community 16 - "Community 16"
Cohesion: 0.06
Nodes (32): package:firebase_messaging/firebase_messaging.dart, package:flutter_local_notifications/flutter_local_notifications.dart, package:timezone/data/latest_all.dart, package:timezone/timezone.dart, _createChannels, getToken, _handleBackgroundMessage, _handleForegroundMessage (+24 more)

### Community 17 - "Community 17"
Cohesion: 0.07
Nodes (28): _DeviceBlockedApp, MyApp, _MeetingCard, _QuickAction, _FloatingCircle, _GlassTextField, _Badge, _BottomSheetTile (+20 more)

### Community 18 - "Community 18"
Cohesion: 0.08
Nodes (25): BuildContext, double get, EdgeInsets get, num, Size get, T? get, BuildContextExtensions, containsKeyIgnoreCase (+17 more)

### Community 19 - "Community 19"
Cohesion: 0.09
Nodes (21): channelName, copyWith, createdAt, description, endTime, fromJson, id, isLocked (+13 more)

### Community 20 - "Community 20"
Cohesion: 0.10
Nodes (20): dart:async, MeetingModel? get, MeetingService, addParticipant, _clearError, clearMeeting, createMeeting, _currentMeeting (+12 more)

### Community 21 - "Community 21"
Cohesion: 0.10
Nodes (20): FirebaseAuth, ../models/user_model.dart, package:firebase_auth/firebase_auth.dart, package:google_sign_in/google_sign_in.dart, _auth, AuthService, authStateChanges, currentUser (+12 more)

### Community 22 - "Community 22"
Cohesion: 0.06
Nodes (31): dart:convert, dart:typed_data, FirebaseFirestore, ../models/meeting_model.dart, package:cloud_firestore/cloud_firestore.dart, package:uuid/uuid.dart, addCoHost, addParticipant (+23 more)

### Community 23 - "Community 23"
Cohesion: 0.10
Nodes (20): AppRoutes, generateRoute, home, login, meeting, privacy, profile, settings (+12 more)

### Community 24 - "Community 24"
Cohesion: 0.10
Nodes (19): AuthService, _authService, _authSub, _clearError, _currentUser, dispose, _error, _isLoading (+11 more)

### Community 25 - "Community 25"
Cohesion: 0.11
Nodes (19): package:share_plus/share_plus.dart, build, _copyId, createState, _endMeeting, initState, isHost, meetingId (+11 more)

### Community 27 - "Community 27"
Cohesion: 0.11
Nodes (18): _CheckboxRow, _ConsentCard, ConsentScreen, _ConsentScreenState, createState, icon, isDark, label (+10 more)

### Community 28 - "Community 28"
Cohesion: 0.11
Nodes (17): ../models/meeting_report_model.dart, package:flutter/services.dart, build, _buildActions, _buildHeader, _buildParticipants, _buildStatsGrid, color (+9 more)

### Community 29 - "Community 29"
Cohesion: 0.11
Nodes (17): cleanErrorMessage, cleanErrorMessageL, ErrorHandlerService, getFirebaseErrorMessage, getFirebaseErrorMessageL, getMeetingErrorMessage, getMeetingErrorMessageL, _instance (+9 more)

### Community 30 - "Community 30"
Cohesion: 0.12
Nodes (16): backgroundColor, build, createState, height, icon, isFullWidth, isLoading, _isPressed (+8 more)

### Community 31 - "Community 31"
Cohesion: 0.05
Nodes (43): meeting_screen.dart, build, _buildForm, _buildNotFound, _checkMeeting, controller, createState, dispose (+35 more)

### Community 32 - "Community 32"
Cohesion: 0.13
Nodes (14): double?, EdgeInsets?, backgroundColor, borderRadius, build, createState, icon, isFullWidth (+6 more)

### Community 33 - "Community 33"
Cohesion: 0.13
Nodes (14): IconData?, build, color, _HostControlButton, HostControlsPanel, icon, isRecording, label (+6 more)

### Community 34 - "Community 34"
Cohesion: 0.14
Nodes (13): DateTime, durationSeconds, endedAt, fromJson, hostId, hostName, meetingId, MeetingReportModel (+5 more)

### Community 35 - "Community 35"
Cohesion: 0.14
Nodes (13): author, dependencies, axios, firebase-admin, firebase-functions, description, keywords, license (+5 more)

### Community 36 - "Community 36"
Cohesion: 0.14
Nodes (13): copyWith, createdAt, email, fromJson, isOnline, name, profileImageUrl, toJson (+5 more)

### Community 37 - "Community 37"
Cohesion: 0.14
Nodes (13): notification_service.dart, _instance, _log, _notificationService, sendAchievementNotification, sendDailyReminder, sendFriendActivityNotification, sendMeetingStartingNotification (+5 more)

### Community 38 - "Community 38"
Cohesion: 0.17
Nodes (12): Offset, package:flutter_animate/flutter_animate.dart, ../theme/premium_colors.dart, build, createState, emoji, FloatingReaction, _FloatingReactionState (+4 more)

### Community 39 - "Community 39"
Cohesion: 0.14
Nodes (13): package:intl/intl.dart, return, AppFormatter, capitalize, formatBytes, formatDate, formatDateTime, formatDuration (+5 more)

### Community 40 - "Community 40"
Cohesion: 0.15
Nodes (12): colors.dart, static const double, static const List, AppStyles, AppTheme, radiusLarge, radiusMedium, radiusSmall (+4 more)

### Community 41 - "Community 41"
Cohesion: 0.15
Nodes (12): dart:io, package:device_info_plus/device_info_plus.dart, package:package_info_plus/package_info_plus.dart, DeviceVerificationService, _getAvailableStorageSpace, _instance, _isIOSVersionValid, _isJailbroken (+4 more)

### Community 42 - "Community 42"
Cohesion: 0.18
Nodes (10): MeetingModel, ../theme/colors.dart, build, _formatTime, _getStatusColor, _getStatusText, meeting, MeetingCard (+2 more)

### Community 44 - "Community 44"
Cohesion: 0.15
Nodes (16): ColorProvider, ThemeProvider, Route /privacy, Route /terms, build, build, PrivacyPolicyScreen, build (+8 more)

### Community 45 - "Community 45"
Cohesion: 0.20
Nodes (9): ../l10n/app_translations.dart, _containsMaliciousPatterns, InputValidator, sanitize, validateChatMessage, validateDescription, validateMeetingName, validatePassword (+1 more)

### Community 46 - "Community 46"
Cohesion: 0.20
Nodes (9): package:logger/logger.dart, ErrorLogger, _instance, logError, logFailedOperation, logFirestoreError, _logger, static final ErrorLogger (+1 more)

### Community 47 - "Community 47"
Cohesion: 0.09
Nodes (21): package:provider/provider.dart, ../providers/locale_provider.dart, ../providers/theme_provider.dart, body, cardColor, _Header, icon, isDark (+13 more)

### Community 48 - "Community 48"
Cohesion: 0.22
Nodes (8): bool get, package:flutter/material.dart, package:shared_preferences/shared_preferences.dart, isDark, _load, setDarkMode, _themeMode, ThemeMode get

### Community 49 - "Community 49"
Cohesion: 0.22
Nodes (8): Locale, Locale get, _languageLabel, languages, _load, _locale, setLanguage, static const Map

### Community 50 - "Community 50"
Cohesion: 0.20
Nodes (10): package:google_fonts/google_fonts.dart, build, _buildError, createState, DeviceVerificationScreen, _DeviceVerificationScreenState, initState, onVerified (+2 more)

### Community 51 - "Community 51"
Cohesion: 0.25
Nodes (7): Config, environment, firebaseProjectId, isDevelopment, isProduction, static bool get, static const String

### Community 53 - "Community 53"
Cohesion: 0.29
Nodes (6): AppConstants, freeMinutes, paymentUrl, proPriceFcfa, proPriceUsd, static const int

### Community 54 - "Community 54"
Cohesion: 0.29
Nodes (6): android, DefaultFirebaseOptions, ios, package:firebase_core/firebase_core.dart, package:flutter/foundation.dart, static const FirebaseOptions

### Community 55 - "Community 55"
Cohesion: 0.29
Nodes (6): validateEmail, validateMeetingName, validateName, validatePassword, validatePhoneNumber, Validators

### Community 56 - "Community 56"
Cohesion: 0.25
Nodes (8): build, _handleDeepLink, MaterialPageRoute, _buildMeetingsTab, _buildRecentMeetings, _createMeeting, _joinById, _joinCall

### Community 58 - "Community 58"
Cohesion: 0.40
Nodes (5): CupertinoLocalizations, _FallbackCupertinoLocalizationsDelegate, _FallbackMaterialLocalizationsDelegate, LocalizationsDelegate, MaterialLocalizations

### Community 59 - "Community 59"
Cohesion: 0.40
Nodes (4): admin, axios, db, functions

### Community 61 - "Community 61"
Cohesion: 0.50
Nodes (4): _WbElement, _WbShape, _WbStroke, _WbText

### Community 62 - "Community 62"
Cohesion: 0.67
Nodes (3): ChangeNotifier, CruxAuthProvider, MeetingProvider

### Community 65 - "Community 65"
Cohesion: 0.67
Nodes (3): Route /profile, _buildBottomNav, _buildTopBar

## Knowledge Gaps
- **1204 isolated node(s):** `IBinder`, `Int`, `Notification`, `FlutterEngine`, `Configuration` (+1199 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `LocaleProvider` connect `Community 3` to `Community 0`, `Community 1`, `Community 2`, `Community 71`, `Community 8`, `Community 9`, `Community 7`, `Community 12`, `Community 44`, `Community 47`, `Community 49`, `Community 50`, `Community 56`, `Community 25`, `Community 62`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Why does `_FallbackMaterialLocalizationsDelegate` connect `Community 58` to `Community 13`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Why does `_VideoCallScreenState` connect `Community 12` to `Community 0`, `Community 3`?**
  _High betweenness centrality (0.007) - this node is a cross-community bridge._
- **What connects `IBinder`, `Int`, `Notification` to the rest of the system?**
  _1204 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.005555555555555556 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.03773584905660377 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.03773584905660377 - nodes in this community are weakly interconnected._