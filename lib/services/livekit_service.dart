import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        developer.log("Utilisateur non connecté.");
        return null;
      }

      final idToken = await user.getIdToken(true);

      final uri = Uri.parse(
        "${AppConfig.livekitTokenServerUrl}/livekit-token",
      ).replace(
        queryParameters: {
          "room": room,
          "identity": identity,
          "name": name,
          "isHost": isHost.toString(),
        },
      );

      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $idToken",
          "Content-Type": "application/json",
        },
      ).timeout(AppConfig.tokenTimeout);

      developer.log("HTTP ${response.statusCode}");

      developer.log(response.body);

      if (response.statusCode != 200) {
        return null;
      }

      final body = jsonDecode(response.body);

      if (body["token"] == null) {
        return null;
      }

      return body["token"];
    } catch (e) {
      developer.log("Erreur LiveKit : $e");
      return null;
    }
  }
}
