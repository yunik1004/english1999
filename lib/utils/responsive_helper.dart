/// Responsive layout utilities for handling different screen sizes.
///
/// Provides breakpoint constants, screen size detection, and layout calculations
/// to create adaptive layouts that work well on mobile, tablet, and desktop.
class ResponsiveHelper {
  // Breakpoint constants
  /// Breakpoint for small mobile devices (portrait phones)
  static const double mobileBreakpoint = 600;

  /// Breakpoint for tablets and larger phones (landscape)
  static const double tabletBreakpoint = 900;

  /// Breakpoint for desktop and large tablets
  static const double desktopBreakpoint = 1200;

  /// Breakpoint for very large desktop screens
  static const double largeDesktopBreakpoint = 1536;

  // Maximum video widths
  /// Maximum video width on mobile devices (landscape)
  static const double maxVideoWidthMobile = 720;

  /// Maximum video width on desktop to prevent excessive sizing
  static const double maxVideoWidthDesktop = 1280;

  /// Determines if the screen is in mobile size range.
  ///
  /// Returns true for screens narrower than [tabletBreakpoint] (900px).
  static bool isMobile(double width) => width < tabletBreakpoint;

  /// Determines if the screen is in tablet size range.
  ///
  /// Returns true for screens between [tabletBreakpoint] (900px)
  /// and [desktopBreakpoint] (1200px).
  static bool isTablet(double width) =>
      width >= tabletBreakpoint && width < desktopBreakpoint;

  /// Determines if the screen is in desktop size range.
  ///
  /// Returns true for screens wider than [desktopBreakpoint] (1200px).
  static bool isDesktop(double width) => width >= desktopBreakpoint;

  /// Determines if horizontal (side-by-side) layout should be used.
  ///
  /// Returns true for screens wider than [tabletBreakpoint] (900px),
  /// indicating that video and transcription should appear side-by-side.
  static bool shouldUseHorizontalLayout(double width) =>
      width >= tabletBreakpoint;

  /// Calculates the maximum width constraint for the video player.
  ///
  /// Returns appropriate max width based on screen size:
  /// - Mobile portrait (< 600px): Full screen width
  /// - Mobile landscape (600-900px): 720px
  /// - Tablet/Small desktop (900-1536px): 60% of screen width
  /// - Large desktop (≥ 1536px): 1280px fixed maximum
  static double getVideoMaxWidth(double screenWidth) {
    if (screenWidth < mobileBreakpoint) return screenWidth;
    if (screenWidth < tabletBreakpoint) return maxVideoWidthMobile;
    if (screenWidth < largeDesktopBreakpoint) return screenWidth * 0.6;
    return maxVideoWidthDesktop;
  }

  /// Gets the flex ratio for the video player in horizontal layout.
  ///
  /// Returns:
  /// - 5 (50%) for all horizontal layouts (screens ≥ 900px)
  /// This ensures a balanced 50/50 split between video and transcription
  static int getVideoFlexRatio(double width) {
    return 5; // 50% across all screen sizes
  }

  /// Gets the flex ratio for the transcription list in horizontal layout.
  ///
  /// Returns:
  /// - 5 (50%) for all horizontal layouts (screens ≥ 900px)
  /// This ensures a balanced 50/50 split between video and transcription
  static int getTranscriptionFlexRatio(double width) {
    return 5; // 50% across all screen sizes
  }
}
