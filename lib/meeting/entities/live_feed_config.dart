enum FeedLayout { vertical, horizontal, grid }

enum FeedDensity { compact, normal, spacious }

class LiveFeedConfig {
  final FeedLayout layout;
  final FeedDensity density;
  final double feedWidth;
  final double feedHeight;
  final int maxVisibleItems;
  final bool autoScroll;
  final Duration scrollDelay;
  final bool showAudioIndicators;
  final bool showBadges;

  const LiveFeedConfig({
    this.layout = FeedLayout.vertical,
    this.density = FeedDensity.normal,
    this.feedWidth = 80.0,
    this.feedHeight = 56.0,
    this.maxVisibleItems = 8,
    this.autoScroll = true,
    this.scrollDelay = const Duration(seconds: 5),
    this.showAudioIndicators = true,
    this.showBadges = true,
  });

  LiveFeedConfig copyWith({
    FeedLayout? layout,
    FeedDensity? density,
    double? feedWidth,
    double? feedHeight,
    int? maxVisibleItems,
    bool? autoScroll,
    Duration? scrollDelay,
    bool? showAudioIndicators,
    bool? showBadges,
  }) {
    return LiveFeedConfig(
      layout: layout ?? this.layout,
      density: density ?? this.density,
      feedWidth: feedWidth ?? this.feedWidth,
      feedHeight: feedHeight ?? this.feedHeight,
      maxVisibleItems: maxVisibleItems ?? this.maxVisibleItems,
      autoScroll: autoScroll ?? this.autoScroll,
      scrollDelay: scrollDelay ?? this.scrollDelay,
      showAudioIndicators: showAudioIndicators ?? this.showAudioIndicators,
      showBadges: showBadges ?? this.showBadges,
    );
  }

  static LiveFeedConfig compact() => const LiveFeedConfig(
    layout: FeedLayout.vertical,
    density: FeedDensity.compact,
    feedWidth: 60.0,
    feedHeight: 48.0,
    maxVisibleItems: 10,
  );

  static LiveFeedConfig spacious() => const LiveFeedConfig(
    layout: FeedLayout.vertical,
    density: FeedDensity.spacious,
    feedWidth: 100.0,
    feedHeight: 72.0,
    maxVisibleItems: 6,
  );
}
