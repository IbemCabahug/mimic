// lib/vault/trigger/trigger_detector.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/providers/provider_registration.dart'
    show networkServiceProvider;
import 'package:mimic/multiplayer/network/network_service.dart'
    show isMultiplayerSessionActive;
import 'gesture_window.dart';

class TriggerCallbackRegistry {
  static final TriggerCallbackRegistry _instance = TriggerCallbackRegistry._internal();
  factory TriggerCallbackRegistry() => _instance;
  TriggerCallbackRegistry._internal();

  void Function(int index)? _onTap;

  void setOnTap(void Function(int index)? callback) {
    _onTap = callback;
  }

  void recordTap(int index) {
    _onTap?.call(index);
  }
}

class TriggerDetector extends ConsumerStatefulWidget {
  final List<int>? tapSequence;
  final Future<bool> Function(List<int> taps)? verifier;
  final int? verifyLength;
  final Duration timeout;
  final VoidCallback onTrigger;

  const TriggerDetector({
    super.key,
    this.tapSequence,
    this.verifier,
    this.verifyLength,
    required this.onTrigger,
    this.timeout = const Duration(seconds: 3),
  }) : assert(
          (tapSequence != null && verifier == null && verifyLength == null) ||
              (tapSequence == null && verifier != null && verifyLength != null),
          'TriggerDetector requires either tapSequence OR (verifier AND verifyLength)',
        );

  @override
  ConsumerState<TriggerDetector> createState() => _TriggerDetectorState();
}

class _TriggerDetectorState extends ConsumerState<TriggerDetector> {
  final List<int> _tapHistory = [];
  Timer? _resetTimer;
  late TriggerCallbackRegistry _registry;
  bool _verifying = false;
  bool _recheckPending = false;

  @override
  void initState() {
    super.initState();
    _registry = TriggerCallbackRegistry();
    _registry.setOnTap(_recordTap);
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _registry.setOnTap(null);
    super.dispose();
  }

  void _startVerification() {
    final length = widget.verifyLength;
    final verifier = widget.verifier;
    if (length == null || verifier == null) return;

    final window = trailingWindow(_tapHistory, length);
    if (window == null) return;

    _verifying = true;
    // Verification is asynchronous because it may perform a key derivation;
    // on Android that work crosses a platform channel and does not block the UI isolate.
    verifier(window).then((matched) {
      _verifying = false;
      if (matched && mounted) {
        _triggerActivated();
      } else if (_recheckPending) {
        // Recursion is bounded because _recheckPending is cleared before the call.
        _recheckPending = false;
        _startVerification();
      }
    }).catchError((_) {
      _verifying = false;
      _recheckPending = false;
    });
  }

  void _recordTap(int index) {
    _tapHistory.add(index);

    _resetTimer?.cancel();
    _resetTimer = Timer(widget.timeout, () {
      if (mounted) {
        setState(() {
          _tapHistory.clear();
          _recheckPending = false;
        });
      }
    });

    final fixedSequence = widget.tapSequence;
    if (fixedSequence != null) {
      if (_tapHistory.length == fixedSequence.length) {
        bool matches = true;
        for (int i = 0; i < fixedSequence.length; i++) {
          if (_tapHistory[i] != fixedSequence[i]) {
            matches = false;
            break;
          }
        }

        if (matches) {
          _triggerActivated();
        }
      }
      return;
    }

    if (widget.verifier != null && widget.verifyLength != null) {
      if (_verifying) {
        _recheckPending = true;
        return;
      }
      _startVerification();
    }
  }

  void _triggerActivated() {
    final netService = ref.read(networkServiceProvider);
    if (isMultiplayerSessionActive(netService)) {
      _tapHistory.clear();
      return;
    }

    _resetTimer?.cancel();
    _tapHistory.clear();

    if (mounted) {
      final overlayState = Overlay.of(context);
      late OverlayEntry overlayEntry;
      overlayEntry = OverlayEntry(
        builder: (context) => _FlashOverlay(
          onCompleted: () {
            overlayEntry.remove();
            widget.onTrigger();
          },
        ),
      );

      overlayState.insert(overlayEntry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

class _FlashOverlay extends StatefulWidget {
  final VoidCallback onCompleted;

  const _FlashOverlay({required this.onCompleted});

  @override
  State<_FlashOverlay> createState() => _FlashOverlayState();
}

class _FlashOverlayState extends State<_FlashOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          widget.onCompleted();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        color: Colors.white,
      ),
    );
  }
}
