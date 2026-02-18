import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../providers/video_player_provider.dart';
import '../utils/responsive_helper.dart';

/// Video player widget with responsive width constraints.
///
/// Uses a StatefulWidget to prevent unnecessary rebuilds during window resize,
/// only updating when crossing major breakpoint thresholds.
class VideoPlayerWidget extends StatefulWidget {
  const VideoPlayerWidget({super.key});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  double? _cachedMaxWidth;
  double? _lastScreenWidth;

  /// Determines if the widget should rebuild based on screen width change.
  ///
  /// Only rebuilds when crossing breakpoint thresholds to prevent
  /// disrupting video playback during continuous resizing.
  bool _shouldUpdateMaxWidth(double newScreenWidth) {
    if (_lastScreenWidth == null) return true;

    final oldWidth = _lastScreenWidth!;

    // Check if we crossed any major breakpoint
    final crossedMobile = (oldWidth < ResponsiveHelper.mobileBreakpoint) !=
                          (newScreenWidth < ResponsiveHelper.mobileBreakpoint);
    final crossedTablet = (oldWidth < ResponsiveHelper.tabletBreakpoint) !=
                          (newScreenWidth < ResponsiveHelper.tabletBreakpoint);
    final crossedDesktop = (oldWidth < ResponsiveHelper.desktopBreakpoint) !=
                           (newScreenWidth < ResponsiveHelper.desktopBreakpoint);
    final crossedLargeDesktop = (oldWidth < ResponsiveHelper.largeDesktopBreakpoint) !=
                                (newScreenWidth < ResponsiveHelper.largeDesktopBreakpoint);

    return crossedMobile || crossedTablet || crossedDesktop || crossedLargeDesktop;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;

        // Only update max width when crossing breakpoint thresholds
        if (_shouldUpdateMaxWidth(screenWidth)) {
          _cachedMaxWidth = ResponsiveHelper.getVideoMaxWidth(screenWidth);
          _lastScreenWidth = screenWidth;
        }

        final maxVideoWidth = _cachedMaxWidth ?? screenWidth;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxVideoWidth),
            child: Consumer<MediaPlayerProvider>(
              // Use child parameter to prevent rebuilding the player
              child: const _StableYoutubePlayer(),
              builder: (context, provider, child) {
                if (provider.errorMessage != null) {
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                provider.errorMessage!,
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                if (!provider.isInitialized || provider.controller == null) {
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: const Color(0xFF0D0A08),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Loading video...',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // Return the stable player child that won't rebuild
                return child!;
              },
            ),
          ),
        );
      },
    );
  }
}

/// A stable YouTube player widget that maintains its state across rebuilds.
///
/// This widget is passed as the `child` parameter to Consumer, which means
/// it won't be rebuilt when the provider notifies listeners, preventing
/// interruptions to video playback during layout changes.
class _StableYoutubePlayer extends StatefulWidget {
  const _StableYoutubePlayer();

  @override
  State<_StableYoutubePlayer> createState() => _StableYoutubePlayerState();
}

class _StableYoutubePlayerState extends State<_StableYoutubePlayer>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Get the controller without listening to changes
    final provider = Provider.of<MediaPlayerProvider>(context, listen: false);

    if (provider.controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: const Color(0xFF0D0A08),
          child: Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: YoutubePlayer(
        controller: provider.controller!,
        aspectRatio: 16 / 9,
      ),
    );
  }
}
