// lib/vault/trigger/trigger_detector.dart
import 'dart:async';
import 'package:flutter/material.dart';

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

class TriggerDetector extends StatefulWidget {
  final List<int> tapSequence;
  final Duration timeout;
  final VoidCallback onTrigger;

  const TriggerDetector({
    super.key,
    required this.tapSequence,
    required this.onTrigger,
    this.timeout = const Duration(seconds: 3),
  });

  @override
  State<TriggerDetector> createState() => _TriggerDetectorState();
}

class _TriggerDetectorState extends State<TriggerDetector> {
  final List<int> _tapHistory = [];
  Timer? _resetTimer;
  late TriggerCallbackRegistry _registry;

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

  void _recordTap(int index) {
    _tapHistory.add(index);

    _resetTimer?.cancel();
    _resetTimer = Timer(widget.timeout, () {
      if (mounted) {
        setState(() {
          _tapHistory.clear();
        });
      }
    });

    if (_tapHistory.length == widget.tapSequence.length) {
      bool matches = true;
      for (int i = 0; i < widget.tapSequence.length; i++) {
        if (_tapHistory[i] != widget.tapSequence[i]) {
          matches = false;
          break;
        }
      }

      if (matches) {
        _triggerActivated();
      }
    }
  }

  void _triggerActivated() {
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
