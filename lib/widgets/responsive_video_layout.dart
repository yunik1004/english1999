import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../utils/responsive_helper.dart';

/// A responsive layout widget that adapts the arrangement of video player
/// and transcription list based on screen size.
///
/// On mobile devices (< 900px), displays a vertical layout with video on top
/// and transcription below. On larger screens (≥ 900px), displays a horizontal
/// side-by-side layout with video on the left and transcription on the right.
///
/// Uses a StatefulWidget to prevent layout thrashing during continuous window
/// resizing by only switching layouts when crossing the tablet breakpoint.
class ResponsiveVideoLayout extends StatefulWidget {
  /// The video player widget to display
  final Widget videoPlayer;

  /// The transcription list widget to display
  final Widget transcriptionList;

  const ResponsiveVideoLayout({
    super.key,
    required this.videoPlayer,
    required this.transcriptionList,
  });

  @override
  State<ResponsiveVideoLayout> createState() => _ResponsiveVideoLayoutState();
}

class _ResponsiveVideoLayoutState extends State<ResponsiveVideoLayout> {
  bool? _cachedUseHorizontalLayout;
  double? _lastScreenWidth;
  int? _cachedVideoFlex;
  int? _cachedTranscriptionFlex;

  // Use a GlobalKey to preserve the video player widget across layout changes
  final GlobalKey _videoPlayerKey = GlobalKey();

  // Track the split ratio for resizable layout (0.0 to 1.0)
  double _splitRatio = 0.5; // Default 50/50 split for horizontal layout
  double _verticalSplitRatio = 0.4; // Default 40/60 split for vertical layout
  bool _isDraggingDivider = false;
  bool _isDraggingVerticalDivider = false;

  // Cache layout dimensions to avoid recalculation
  double _cachedTotalWidth = 0;
  double _cachedTotalHeight = 0;

  /// Determines if the layout should switch between horizontal and vertical.
  ///
  /// Only switches when crossing the tablet breakpoint (900px) to prevent
  /// layout thrashing during continuous resizing.
  bool _shouldUpdateLayout(double newScreenWidth) {
    if (_lastScreenWidth == null) return true;

    final oldWidth = _lastScreenWidth!;

    // Only update when crossing the tablet breakpoint
    final crossedTablet = (oldWidth < ResponsiveHelper.tabletBreakpoint) !=
                          (newScreenWidth < ResponsiveHelper.tabletBreakpoint);

    return crossedTablet;
  }

  /// Determines if flex ratios should be updated.
  ///
  /// Updates when crossing desktop or large desktop breakpoints.
  bool _shouldUpdateFlexRatios(double newScreenWidth) {
    if (_lastScreenWidth == null) return true;

    final oldWidth = _lastScreenWidth!;

    // Update flex ratios when crossing desktop breakpoints
    final crossedDesktop = (oldWidth < ResponsiveHelper.desktopBreakpoint) !=
                           (newScreenWidth < ResponsiveHelper.desktopBreakpoint);
    final crossedLargeDesktop = (oldWidth < ResponsiveHelper.largeDesktopBreakpoint) !=
                                (newScreenWidth < ResponsiveHelper.largeDesktopBreakpoint);

    return crossedDesktop || crossedLargeDesktop;
  }

  /// Determines if the pointer is within the horizontal divider zone.
  ///
  /// Used to detect when dragging should start for horizontal resizing.
  bool _isPointerInHorizontalDividerZone(Offset position) {
    if (_cachedTotalWidth == 0) return false;
    final dividerStart = _cachedTotalWidth * _splitRatio;
    final dividerEnd = dividerStart + 16; // Divider width
    return position.dx >= dividerStart && position.dx <= dividerEnd;
  }

  /// Determines if the pointer is within the vertical divider zone.
  ///
  /// Used to detect when dragging should start for vertical resizing.
  bool _isPointerInVerticalDividerZone(Offset position) {
    if (_cachedTotalHeight == 0) return false;
    final dividerStart = _cachedTotalHeight * _verticalSplitRatio;
    final dividerEnd = dividerStart + 16; // Divider height
    return position.dy >= dividerStart && position.dy <= dividerEnd;
  }

  /// Sets the dragging state at the HTML/CSS level for web platform.
  ///
  /// This disables pointer events on all iframes (including YouTube player)
  /// to prevent them from intercepting drag events.
  void _setWebDraggingState(bool isDragging) {
    if (kIsWeb) {
      final body = web.document.body;
      if (body != null) {
        if (isDragging) {
          body.classList.add('flutter-dragging');
          print('DEBUG: Added flutter-dragging class to body');
        } else {
          body.classList.remove('flutter-dragging');
          print('DEBUG: Removed flutter-dragging class from body');
        }
      } else {
        print('DEBUG: body is null!');
      }
    } else {
      print('DEBUG: Not running on web platform');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;

        // Update layout type only when crossing major breakpoint
        if (_shouldUpdateLayout(screenWidth)) {
          _cachedUseHorizontalLayout =
              ResponsiveHelper.shouldUseHorizontalLayout(screenWidth);
          _lastScreenWidth = screenWidth;
        }

        // Update flex ratios when crossing desktop breakpoints
        if (_shouldUpdateFlexRatios(screenWidth)) {
          _cachedVideoFlex = ResponsiveHelper.getVideoFlexRatio(screenWidth);
          _cachedTranscriptionFlex =
              ResponsiveHelper.getTranscriptionFlexRatio(screenWidth);
          _lastScreenWidth = screenWidth;
        }

        final useHorizontalLayout = _cachedUseHorizontalLayout ??
            ResponsiveHelper.shouldUseHorizontalLayout(screenWidth);

        if (useHorizontalLayout) {
          final videoFlex = _cachedVideoFlex ??
              ResponsiveHelper.getVideoFlexRatio(screenWidth);
          final transcriptionFlex = _cachedTranscriptionFlex ??
              ResponsiveHelper.getTranscriptionFlexRatio(screenWidth);
          return _buildHorizontalLayout(videoFlex, transcriptionFlex);
        } else {
          return _buildVerticalLayout();
        }
      },
    );
  }

  /// Builds the vertical layout for mobile devices.
  ///
  /// Layout structure:
  /// - Video player at top (resizable height)
  /// - Draggable horizontal divider
  /// - Transcription list below (resizable height)
  ///
  /// Uses a permanent event interceptor to prevent iframe interference during drag.
  Widget _buildVerticalLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _cachedTotalHeight = MediaQuery.of(context).size.height;
        final videoHeight = _cachedTotalHeight * _verticalSplitRatio;

        return Stack(
          children: [
            Column(
              children: [
                // Video player section (top)
                SizedBox(
                  height: videoHeight,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      ignoring: _isDraggingVerticalDivider,
                      child: KeyedSubtree(
                        key: _videoPlayerKey,
                        child: widget.videoPlayer,
                      ),
                    ),
                  ),
                ),
                // Visual divider (no longer handles events)
                MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: Container(
                    height: 16,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        height: 1,
                        color: const Color(0xFF8B6F47),
                      ),
                    ),
                  ),
                ),
                // Transcription list section (bottom)
                Expanded(
                  child: IgnorePointer(
                    ignoring: _isDraggingVerticalDivider,
                    child: Container(
                      color: const Color(0xFF1C1410),
                      child: widget.transcriptionList,
                    ),
                  ),
                ),
              ],
            ),
            // Permanent event interceptor (always present)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (details) {
                  print('DEBUG: Vertical onPointerDown at ${details.localPosition}, totalHeight: $_cachedTotalHeight, ratio: $_verticalSplitRatio');
                  if (_isPointerInVerticalDividerZone(details.localPosition)) {
                    print('DEBUG: Inside vertical divider zone - starting drag');
                    _setWebDraggingState(true);
                    setState(() {
                      _isDraggingVerticalDivider = true;
                    });
                  } else {
                    print('DEBUG: Outside vertical divider zone');
                  }
                },
                onPointerMove: (details) {
                  if (_isDraggingVerticalDivider) {
                    setState(() {
                      final newRatio = _verticalSplitRatio + (details.delta.dy / _cachedTotalHeight);
                      _verticalSplitRatio = newRatio.clamp(0.2, 0.7);
                    });
                  }
                },
                onPointerUp: (_) {
                  if (_isDraggingVerticalDivider) {
                    _setWebDraggingState(false);
                    setState(() {
                      _isDraggingVerticalDivider = false;
                    });
                  }
                },
                onPointerCancel: (_) {
                  if (_isDraggingVerticalDivider) {
                    _setWebDraggingState(false);
                    setState(() {
                      _isDraggingVerticalDivider = false;
                    });
                  }
                },
                child: _isDraggingVerticalDivider
                    ? MouseRegion(
                        cursor: SystemMouseCursors.resizeRow,
                        child: AbsorbPointer(
                          absorbing: true,
                          child: Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: Colors.transparent,
                          ),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Builds the horizontal layout for tablets and desktop.
  ///
  /// Layout structure:
  /// - Video player on left (resizable width, full height available)
  /// - Draggable vertical divider
  /// - Transcription list on right (resizable width, scrollable)
  ///
  /// Uses a permanent event interceptor to prevent iframe interference during drag.
  Widget _buildHorizontalLayout(int videoFlex, int transcriptionFlex) {
    final screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = kToolbarHeight;
    final maxVideoHeight = screenHeight - appBarHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        _cachedTotalWidth = constraints.maxWidth;

        return Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Video player section (left side)
                SizedBox(
                  width: _cachedTotalWidth * _splitRatio,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      ignoring: _isDraggingDivider,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxVideoHeight,
                          ),
                          child: KeyedSubtree(
                            key: _videoPlayerKey,
                            child: widget.videoPlayer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Visual divider (no longer handles events)
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Container(
                    width: 16,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 1,
                        color: const Color(0xFF8B6F47),
                      ),
                    ),
                  ),
                ),
                // Transcription list section (right side)
                SizedBox(
                  width: _cachedTotalWidth * (1 - _splitRatio) - 16,
                  child: IgnorePointer(
                    ignoring: _isDraggingDivider,
                    child: Container(
                      color: const Color(0xFF1C1410),
                      child: widget.transcriptionList,
                    ),
                  ),
                ),
              ],
            ),
            // Permanent event interceptor (always present)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (details) {
                  print('DEBUG: Horizontal onPointerDown at ${details.localPosition}, totalWidth: $_cachedTotalWidth, ratio: $_splitRatio');
                  if (_isPointerInHorizontalDividerZone(details.localPosition)) {
                    print('DEBUG: Inside horizontal divider zone - starting drag');
                    _setWebDraggingState(true);
                    setState(() {
                      _isDraggingDivider = true;
                    });
                  } else {
                    print('DEBUG: Outside horizontal divider zone');
                  }
                },
                onPointerMove: (details) {
                  if (_isDraggingDivider) {
                    setState(() {
                      final newRatio = _splitRatio + (details.delta.dx / _cachedTotalWidth);
                      _splitRatio = newRatio.clamp(0.2, 0.8);
                    });
                  }
                },
                onPointerUp: (_) {
                  if (_isDraggingDivider) {
                    _setWebDraggingState(false);
                    setState(() {
                      _isDraggingDivider = false;
                    });
                  }
                },
                onPointerCancel: (_) {
                  if (_isDraggingDivider) {
                    _setWebDraggingState(false);
                    setState(() {
                      _isDraggingDivider = false;
                    });
                  }
                },
                child: _isDraggingDivider
                    ? MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: AbsorbPointer(
                          absorbing: true,
                          child: Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: Colors.transparent,
                          ),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }
}
