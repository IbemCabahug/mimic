import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../security/auto_lock.dart';
import '../crypto/vault_crypto.dart';
import '../../core/theme/app_theme.dart';

/// A consistent Scaffold wrapper for every vault screen.
/// Automatically applies vaultTheme and wraps the body in AutoLockWrapper.
class VaultScaffold extends ConsumerWidget {
  final String? title;
  final bool showBackButton;
  final bool showLockButton;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget body;

  const VaultScaffold({
    super.key,
    this.title,
    this.showBackButton = true,
    this.showLockButton = true,
    this.actions,
    this.floatingActionButton,
    required this.body,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: vaultTheme,
      child: AutoLockWrapper(
        child: Scaffold(
          backgroundColor: VaultColors.background,
          appBar: AppBar(
            title: title != null
                ? Text(
                    title!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: VaultColors.accent,
                    ),
                  )
                : null,
            automaticallyImplyLeading: false,
            leading: showBackButton && Navigator.of(context).canPop()
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            actions: [
              ...?actions,
              if (showLockButton)
                IconButton(
                  icon: const Icon(Icons.lock_outline),
                  onPressed: () {
                    ref.read(vaultCryptoProvider).lock();
                    AutoLock().dispose();
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/vault-pin',
                      (route) => false,
                    );
                  },
                ),
            ],
          ),
          body: body,
          floatingActionButton: floatingActionButton,
        ),
      ),
    );
  }
}

/// A Card widget that scales down when pressed, providing a satisfying micro-interaction.
class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.width,
    this.height,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null) {
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap != null) {
      _controller.reverse();
      widget.onTap!();
    }
  }

  void _handleTapCancel() {
    if (widget.onTap != null) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: widget.width,
          height: widget.height,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: VaultColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A FloatingActionButton wrapper that applies entrance scale and fade transitions.
class AnimatedFAB extends StatefulWidget {
  final Widget child;

  const AnimatedFAB({
    super.key,
    required this.child,
  });

  @override
  State<AnimatedFAB> createState() => _AnimatedFABState();
}

class _AnimatedFABState extends State<AnimatedFAB> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

/// A row of dots indicating PIN entries, with spring animation overshoot on entry fill.
class PinDotIndicator extends StatelessWidget {
  final int filledCount;
  final int totalDots;

  const PinDotIndicator({
    super.key,
    required this.filledCount,
    this.totalDots = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalDots, (index) {
        final isFilled = index < filledCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            tween: Tween<double>(
              begin: 12.0,
              end: isFilled ? 14.0 : 12.0,
            ),
            builder: (context, size, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? VaultColors.accent : Colors.transparent,
                  border: Border.all(
                    color: isFilled ? VaultColors.accent : const Color(0xFFE0E0E0),
                    width: isFilled ? 0 : 2,
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
