import 'dart:ui';
import 'package:flutter/material.dart';
import '../entities/speaker_state.dart';
import '../entities/live_feed_config.dart';

class ConferenceLayoutEngine {
  final Size screenSize;
  final SpeakerState speakerState;
  final LiveFeedConfig feedConfig;
  final int participantCount;

  ConferenceLayoutEngine({
    required this.screenSize,
    required this.speakerState,
    required this.feedConfig,
    required this.participantCount,
  });

  LayoutMetrics calculateLayout() {
    switch (speakerState.mode) {
      case SpeakerMode.single:
        return _calculateSingleSpeakerLayout();
      case SpeakerMode.dual:
        return _calculateDualSpeakerLayout();
      case SpeakerMode.screenshare:
        return _calculateScreenshareLayout();
      case SpeakerMode.gallery:
        return _calculateGalleryLayout();
    }
  }

  LayoutMetrics _calculateSingleSpeakerLayout() {
    final speakerWidth = screenSize.width * 0.70;
    final speakerHeight = screenSize.height * 0.70;
    final feedWidth = feedConfig.feedWidth;
    
    return LayoutMetrics(
      speakerArea: Rect.fromLTWH(
        (screenSize.width - speakerWidth) / 2,
        screenSize.height * 0.05,
        speakerWidth,
        speakerHeight,
      ),
      feedArea: Rect.fromLTWH(
        screenSize.width - feedWidth - 16,
        screenSize.height * 0.10,
        feedWidth,
        screenSize.height * 0.80,
      ),
      controlsArea: Rect.fromLTWH(
        (screenSize.width - 200) / 2,
        screenSize.height - 80,
        200,
        60,
      ),
      speakerScale: 1.0,
      feedVisible: true,
    );
  }

  LayoutMetrics _calculateDualSpeakerLayout() {
    final speakerWidth = screenSize.width * 0.45;
    final speakerHeight = screenSize.height * 0.65;
    
    return LayoutMetrics(
      speakerArea: Rect.fromLTWH(
        (screenSize.width - speakerWidth * 2) / 2,
        screenSize.height * 0.05,
        speakerWidth * 2,
        speakerHeight,
      ),
      feedArea: Rect.fromLTWH(
        screenSize.width - feedConfig.feedWidth - 16,
        screenSize.height * 0.10,
        feedConfig.feedWidth,
        screenSize.height * 0.70,
      ),
      controlsArea: Rect.fromLTWH(
        (screenSize.width - 200) / 2,
        screenSize.height - 80,
        200,
        60,
      ),
      speakerScale: 0.9,
      feedVisible: true,
    );
  }

  LayoutMetrics _calculateScreenshareLayout() {
    final shareWidth = screenSize.width * 0.80;
    final shareHeight = screenSize.height * 0.75;
    
    return LayoutMetrics(
      speakerArea: Rect.fromLTWH(
        (screenSize.width - shareWidth) / 2,
        screenSize.height * 0.05,
        shareWidth,
        shareHeight,
      ),
      feedArea: Rect.fromLTWH(
        screenSize.width - feedConfig.feedWidth - 16,
        screenSize.height * 0.10,
        feedConfig.feedWidth,
        screenSize.height * 0.70,
      ),
      controlsArea: Rect.fromLTWH(
        (screenSize.width - 200) / 2,
        screenSize.height - 80,
        200,
        60,
      ),
      speakerScale: 1.0,
      feedVisible: true,
    );
  }

  LayoutMetrics _calculateGalleryLayout() {
    final columns = _calculateGridColumns();
    final rows = _calculateGridRows(columns);
    final tileWidth = (screenSize.width - 32) / columns;
    final tileHeight = (screenSize.height - 100) / rows;
    
    return LayoutMetrics(
      speakerArea: Rect.fromLTWH(16, 60, screenSize.width - 32, screenSize.height - 160),
      feedArea: Rect.zero,
      controlsArea: Rect.fromLTWH(
        (screenSize.width - 200) / 2,
        screenSize.height - 80,
        200,
        60,
      ),
      speakerScale: 1.0,
      feedVisible: false,
      gridColumns: columns,
      gridRows: rows,
      tileSize: Size(tileWidth, tileHeight),
    );
  }

  int _calculateGridColumns() {
    if (screenSize.width < 600) return 1;
    if (screenSize.width < 900) return 2;
    if (screenSize.width < 1200) return 3;
    return 4;
  }

  int _calculateGridRows(int columns) {
    final tiles = participantCount;
    return (tiles / columns).ceil().clamp(1, 5);
  }

  static bool shouldUseGalleryMode(int participantCount) {
    return participantCount > 8;
  }

  static SpeakerMode determineSpeakerMode({
    required bool hasScreenShare,
    required int participantCount,
    required bool forceDual,
  }) {
    if (hasScreenShare) return SpeakerMode.screenshare;
    if (forceDual) return SpeakerMode.dual;
    if (shouldUseGalleryMode(participantCount)) return SpeakerMode.gallery;
    return SpeakerMode.single;
  }
}

class LayoutMetrics {
  final Rect speakerArea;
  final Rect feedArea;
  final Rect controlsArea;
  final double speakerScale;
  final bool feedVisible;
  final int? gridColumns;
  final int? gridRows;
  final Size? tileSize;

  const LayoutMetrics({
    required this.speakerArea,
    required this.feedArea,
    required this.controlsArea,
    required this.speakerScale,
    required this.feedVisible,
    this.gridColumns,
    this.gridRows,
    this.tileSize,
  });

  bool get isGridLayout => gridColumns != null && gridRows != null;
}