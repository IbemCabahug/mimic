// lib/vault/widgets/paywall_sheet.dart
//
// Phase 2P Step 3: Pro Paywall Sheet UI.
//
// Features:
// 1. One-time lifetime purchase presentation (₱99 localized from Play).
// 2. Strict multi-tap debouncing and concurrency guards.
// 3. Offline resilience (informative offline banner with retry action).
// 4. Honest value proposition (Pro features listed, protective floor guaranteed free).
// 5. Heartfelt indie gratitude note and celebration state upon purchase.
// 6. Restore purchases flow with clear feedback.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../services/billing_service.dart';
import '../services/pro_status_service.dart';

/// Opens the Mimic Pro paywall bottom sheet.
Future<void> showPaywallSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const PaywallSheet(),
  );
}

/// The stateful paywall modal bottom sheet.
class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key});

  @override
  ConsumerState<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<PaywallSheet> {
  bool _isPurchasing = false;
  bool _isRestoring = false;
  String? _errorMessage;
  String? _infoMessage;
  StreamSubscription<void>? _entitlementSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initBilling();
    });
  }

  Future<void> _initBilling() async {
    final billing = ref.read(billingServiceProvider);
    _entitlementSub = billing.entitlementChanged.listen((_) {
      if (!mounted) return;
      ref.invalidate(isProProvider);
    });

    if (billing.proProductDetails == null) {
      await billing.init();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _entitlementSub?.cancel();
    super.dispose();
  }

  Future<void> _handleBuy() async {
    if (_isPurchasing || _isRestoring) return; // Debounce guard
    setState(() {
      _isPurchasing = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final billing = ref.read(billingServiceProvider);
      final ok = await billing.buyPro();
      if (!ok && mounted) {
        setState(() {
          final err = billing.lastError;
          if (err != null && err.contains('unavailable')) {
            _errorMessage = 'Google Play is currently unavailable. Check your connection.';
          } else if (err != null && err.contains('before a known product')) {
            _errorMessage = 'Could not load product. Connect to internet and try again.';
          } else {
            _errorMessage = 'Purchase could not be started. Please try again.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _handleRestore() async {
    if (_isPurchasing || _isRestoring) return; // Debounce guard
    setState(() {
      _isRestoring = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final billing = ref.read(billingServiceProvider);
      await billing.restore();
      // Allow the purchase stream to settle
      await Future<void>.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      final isPro = await ref.read(proStatusServiceProvider).isPro();
      if (isPro) {
        ref.invalidate(isProProvider);
        setState(() {
          _infoMessage = 'Purchases restored successfully!';
        });
      } else {
        setState(() {
          _infoMessage = 'No active Pro purchase found on this Google account.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not restore purchases. Check your connection.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProAsync = ref.watch(isProProvider);
    final isPro = isProAsync.valueOrNull ?? false;
    final billing = ref.watch(billingServiceProvider);
    final product = billing.proProductDetails;

    return Container(
      decoration: const BoxDecoration(
        color: VaultColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCD8CE),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Close button and header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: VaultColors.accent.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.workspace_premium,
                          color: VaultColors.accent,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MIMIC PRO',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: VaultColors.textPrimary,
                            ),
                          ),
                          Text(
                            isPro ? 'Supporter Active' : 'Lifetime Upgrade',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: VaultColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: VaultColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Celebration view if Pro is already unlocked
              if (isPro) ...[
                _buildCelebrationCard(context),
              ] else ...[
                // Pro Feature Benefits list
                _buildBenefitTile(
                  icon: Icons.bolt,
                  title: 'Quick-Entry Shortcut',
                  description:
                      'Long-press the home title to jump straight to your vault PIN without the decoy gesture.',
                ),
                const SizedBox(height: 12),
                _buildBenefitTile(
                  icon: Icons.timer,
                  title: 'Extended Auto-Lock Timeouts',
                  description:
                      'Keep your vault accessible for 15 or 30 minutes while working with files.',
                ),
                const SizedBox(height: 12),
                _buildBenefitTile(
                  icon: Icons.wifi_off,
                  title: '100% Offline Independence',
                  description:
                      'Once unlocked, Pro works offline forever with zero servers or telemetry.',
                ),
                const SizedBox(height: 16),

                // Golden Rule Guarantee Callout
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VaultColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E0D6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: VaultColors.accent, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Core security, AES-256 encryption, decoy PINs, intruder selfies, and data export are 100% free forever.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: VaultColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Heartfelt Indie Gratitude Pledge
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: VaultColors.accent.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.favorite,
                              color: Color(0xFFE05353), size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'Support Independent Development',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: VaultColors.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mimic is built without investors, ads, or tracking. Your one-time upgrade directly fuels future updates and keeps true privacy accessible. We are deeply grateful for your support!',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: VaultColors.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Error or Info banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: VaultColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: VaultColors.error.withOpacity(0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: VaultColors.error,
                      ),
                    ),
                  ),
                ],
                if (_infoMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: VaultColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: VaultColors.success.withOpacity(0.3)),
                    ),
                    child: Text(
                      _infoMessage!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: VaultColors.success,
                      ),
                    ),
                  ),
                ],

                // Offline Notice if product cannot be loaded
                if (product == null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off,
                            color: Color(0xFFEA580C), size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Connect to internet once to load Google Play pricing.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: Color(0xFF9A3412),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _initBilling,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Retry',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEA580C),
                              )),
                        ),
                      ],
                    ),
                  ),
                ],

                // Primary Purchase Button
                ElevatedButton(
                  onPressed: (_isPurchasing || _isRestoring) ? null : _handleBuy,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VaultColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isPurchasing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Unlock Lifetime Pro • ${product?.price ?? '₱99.00'}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 8),

                // Restore Purchases Button
                Center(
                  child: TextButton(
                    onPressed: (_isPurchasing || _isRestoring)
                        ? null
                        : _handleRestore,
                    style: TextButton.styleFrom(
                      foregroundColor: VaultColors.textSecondary,
                    ),
                    child: _isRestoring
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: VaultColors.accent,
                            ),
                          )
                        : const Text(
                            'Already purchased? Restore Purchases',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitTile({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: VaultColors.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: VaultColors.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: VaultColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: VaultColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCelebrationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FBF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VaultColors.success.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VaultColors.success.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline,
                color: VaultColors.success, size: 36),
          ),
          const SizedBox(height: 12),
          const Text(
            'Thank You For Your Support! 🎉',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: VaultColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'You are an official Mimic Pro backer. Your one-time purchase keeps Mimic independent, private, and 100% ad-free.\n\nAll Pro features are permanently unlocked on this Google account.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: VaultColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Enjoy Mimic Pro',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
