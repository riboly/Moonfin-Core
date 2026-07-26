import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../util/platform_detection.dart';

/// Top-right Windows chrome: show caption buttons only while the pointer is
/// over the corner, then auto-hide shortly after the pointer leaves.
class WindowControlChrome extends StatefulWidget {
  const WindowControlChrome({super.key});

  @override
  State<WindowControlChrome> createState() => _WindowControlChromeState();
}

class _WindowControlChromeState extends State<WindowControlChrome> {
  static const Duration _hideDelay = Duration(seconds: 2);
  static const Duration _fadeDuration = Duration(milliseconds: 160);

  bool _visible = false;
  bool _hovering = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _show() {
    _hideTimer?.cancel();
    if (!_visible || !_hovering) {
      setState(() {
        _hovering = true;
        _visible = true;
      });
    } else {
      _hovering = true;
    }
  }

  void _scheduleHide() {
    _hovering = false;
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted || _hovering) return;
      setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetection.isWindows) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      onEnter: (_) => _show(),
      onExit: (_) => _scheduleHide(),
      // Slightly larger than the 3 buttons so the top-right corner is easy to hit
      // while the chrome is hidden.
      child: SizedBox(
        width: 140,
        height: 48,
        child: Align(
          alignment: Alignment.topRight,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: _fadeDuration,
            curve: Curves.easeOut,
            child: const WindowControlButtons(),
          ),
        ),
      ),
    );
  }
}

/// In-app replacement for the native Windows caption buttons.
///
/// The native title bar is removed on Windows, so these controls remain
/// available inside the Flutter UI. On other platforms this widget is empty.
class WindowControlButtons extends StatefulWidget {
  const WindowControlButtons({super.key});

  @override
  State<WindowControlButtons> createState() => _WindowControlButtonsState();
}

class _WindowControlButtonsState extends State<WindowControlButtons>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (PlatformDetection.isWindows) {
      windowManager.addListener(this);
      unawaited(_syncMaximizedState());
    }
  }

  @override
  void dispose() {
    if (PlatformDetection.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncMaximizedState() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted && isMaximized != _isMaximized) {
      setState(() => _isMaximized = isMaximized);
    }
  }

  Future<void> _toggleMaximized() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetection.isWindows) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowControlButton(
          icon: Icons.remove,
          tooltip: 'Minimize',
          onPressed: windowManager.minimize,
        ),
        _WindowControlButton(
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          tooltip: _isMaximized ? 'Restore' : 'Maximize',
          onPressed: _toggleMaximized,
        ),
        _WindowControlButton(
          icon: Icons.close,
          tooltip: 'Close',
          hoverColor: const Color(0xffC42B1C),
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 42,
        height: 36,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 17,
          splashRadius: 18,
          tooltip: tooltip,
          color: Colors.white,
          hoverColor: hoverColor ?? Colors.white.withValues(alpha: 0.14),
          splashColor: Colors.white.withValues(alpha: 0.2),
          onPressed: () => unawaited(onPressed()),
          icon: Icon(icon),
        ),
      ),
    );
  }
}

/// Makes an otherwise empty Flutter region drag the frameless Windows window.
class WindowDragRegion extends StatelessWidget {
  const WindowDragRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetection.isWindows) return child;
    return DragToMoveArea(child: child);
  }
}
