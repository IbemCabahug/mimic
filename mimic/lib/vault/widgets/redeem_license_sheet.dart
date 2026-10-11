// lib/vault/widgets/redeem_license_sheet.dart
//
// Modern, offline redemption bottom sheet for Mimic Pro activation codes.
// Supports direct GCash/PayMongo purchases, manual tester keys, and instant offline unlock.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../services/license_service.dart';
import '../services/pro_status_service.dart';

/// Configurable payment checkout URL (e.g., PayMongo link for GCash payments).
/// Can be customized at build-time via `--dart-define=PAYMENT_CHECKOUT_URL=...`.
const String kPaymentCheckoutUrl = String.fromEnvironment(
  'PAYMENT_CHECKOUT_URL',
  defaultValue: 'https://pm.link/org-uqgth9gweyKvi2DJvVkWyXXH/RF4Wp1A',
);

/// Opens the Mimic Pro offline license redemption sheet.
Future<bool?> showRedeemLicenseSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const RedeemLicenseSheet(),
  );
}

class RedeemLicenseSheet extends ConsumerStatefulWidget {
  const RedeemLicenseSheet({super.key});

  @override
  ConsumerState<RedeemLicenseSheet> createState() => _RedeemLicenseSheetState();
}

class _RedeemLicenseSheetState extends ConsumerState<RedeemLicenseSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.trim().isNotEmpty) {
      var cleaned = text.trim().toUpperCase();
      if (cleaned.startsWith('MIMIC-')) {
        cleaned = cleaned.substring(6);
      } else if (cleaned.startsWith('MIMIC')) {
        cleaned = cleaned.substring(5);
      }
      cleaned = cleaned.replaceAll(RegExp(r'[^0-9A-F]'), '');
      if (cleaned.length > 16) cleaned = cleaned.substring(0, 16);

      final buffer = StringBuffer();
      for (int i = 0; i < cleaned.length; i++) {
        if (i > 0 && i % 4 == 0) buffer.write('-');
        buffer.write(cleaned[i]);
      }
      _controller.text = buffer.toString();
      setState(() => _errorMessage = null);
    }
  }

  Future<void> _handleRedeem() async {
    var rawInput = _controller.text.trim();
    if (rawInput.isEmpty) {
      setState(() => _errorMessage = 'Please enter your 16-character activation code.');
      return;
    }

    if (!rawInput.toUpperCase().startsWith('MIMIC')) {
      rawInput = 'MIMIC-$rawInput';
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final licenseService = ref.read(licenseServiceProvider);
      final result = await licenseService.redeemKey(rawInput);

      if (!mounted) return;

      if (result.isSuccess) {
        ref.invalidate(isProProvider);
        setState(() {
          _isSuccess = true;
          _isLoading = false;
        });

        // Auto-close after showing celebration
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'Invalid activation code. Please try again.';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _launchPaymentUrl() async {
    final uri = Uri.tryParse(kPaymentCheckoutUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open payment link. Please check your browser.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: VaultColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 24,
        right: 24,
        bottom: bottomInset + 24,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top drag bar
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

              // Header
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
                          Icons.vpn_key_rounded,
                          color: VaultColors.accent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Redeem Activation Code',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: VaultColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Offline Pro Lifetime License',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: VaultColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: VaultColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              if (_isSuccess) ...[
                // Success celebration view
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: VaultColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: VaultColors.success.withOpacity(0.3)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.check_circle, color: VaultColors.success, size: 54),
                      SizedBox(height: 12),
                      Text(
                        'Mimic Pro Activated! ⭐',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: VaultColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Lifetime Pro features are now unlocked permanently on this device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: VaultColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                // Instructions banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VaultColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E0D6)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.mark_email_read_outlined,
                          color: VaultColors.accent, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'If you purchased via GCash or online, enter the 16-character code sent to your email.',
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

                // Key input field
                TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_LicenseKeyInputFormatter()],
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: VaultColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'ACTIVATION CODE',
                    prefixText: 'MIMIC- ',
                    prefixStyle: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: VaultColors.accent,
                    ),
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    hintStyle: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 13,
                      letterSpacing: 1.0,
                      color: VaultColors.textSecondary.withOpacity(0.4),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFDCD8CE)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: VaultColors.accent, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste_rounded, color: VaultColors.accent),
                      tooltip: 'Paste from Clipboard',
                      onPressed: _pasteFromClipboard,
                    ),
                  ),
                  onChanged: (val) {
                    if (_errorMessage != null) {
                      setState(() => _errorMessage = null);
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Error message
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

                // Redeem Action Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRedeem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VaultColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Activate Pro',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 14),

                // Buy via GCash option
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E0D6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          color: Color(0xFF007DFE), size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Need an activation key?',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: VaultColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Pay ₱99 with GCash / Maya to receive a key instantly.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: VaultColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _launchPaymentUrl,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF007DFE),
                          side: const BorderSide(color: Color(0xFF007DFE)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Buy ₱99',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Automatically strips redundant 'MIMIC-' prefix, uppercase-converts hex chars,
/// limits to 16 hex characters, and inserts dashes every 4 characters.
class _LicenseKeyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.toUpperCase();
    if (text.startsWith('MIMIC-')) {
      text = text.substring(6);
    } else if (text.startsWith('MIMIC')) {
      text = text.substring(5);
    }

    final hexChars = text.replaceAll(RegExp(r'[^0-9A-F]'), '');
    final limited = hexChars.length > 16 ? hexChars.substring(0, 16) : hexChars;

    final buffer = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(limited[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
