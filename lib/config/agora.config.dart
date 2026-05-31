class AgoraConfig {
  // ✅ VOS INFOS AGORA
  static const String appId = '729bb936e5084d53897e43c58ee8e946';

  static const String appCertificate = '93fb3c3df2d840bd94da85a24115ac43';

  static const String tokenServerUrl = 'http://localhost:8081';

  static const int defaultVideoWidth = 1280;
  static const int defaultVideoHeight = 720;
  static const int defaultVideoFramerate = 30;
  static const int defaultVideoBitrate = 2500;

  static const int tokenExpireTime = 3600;
  static const bool enableAgoraLogging = true;
}

class AgoraVideoQuality {
  static const lowQuality = {
    'width': 320,
    'height': 240,
    'frameRate': 15,
    'bitrate': 500,
  };

  static const mediumQuality = {
    'width': 640,
    'height': 480,
    'frameRate': 24,
    'bitrate': 1200,
  };

  static const highQuality = {
    'width': 1280,
    'height': 720,
    'frameRate': 30,
    'bitrate': 2500,
  };

  static const ultraHighQuality = {
    'width': 1920,
    'height': 1080,
    'frameRate': 30,
    'bitrate': 4500,
  };
}