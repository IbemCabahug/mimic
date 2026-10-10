// mimic/lib/vault/screens/vault_settings_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto/vault_crypto.dart';
import '../crypto/keystore_service.dart';
import '../../core/services/platform_service.dart';
import '../../core/services/stealth_mode_service.dart';
import '../../core/services/launcher_icon_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/biometric_providers.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/biometric_unlock_store.dart';
import '../../core/providers/provider_registration.dart' show vaultConcealServiceProvider;
import '../security/panic_mode.dart';
import '../security/auto_lock.dart';
import '../security/vault_conceal_service.dart';
import '../security/duress_service.dart';
import '../security/decoy_vault_service.dart';
import '../services/vault_theme_service.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/router/app_router.dart';
import 'gesture_setup_screen.dart';
import '../services/pro_status_service.dart';
import '../services/billing_service.dart';
import '../services/quick_entry_service.dart';
import '../services/vault_wipe_service.dart';
import '../services/video_thumbnail_service.dart';
import '../services/intruder_service.dart';
import '../trigger/gesture_store.dart';
import '../widgets/paywall_sheet.dart';

class VaultSettingsScreen extends ConsumerStatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  ConsumerState<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends ConsumerState<VaultSettingsScreen> {
  bool _hasRecoveryBlob = false;
  bool _hasGesture = false;
  bool _isLoadingBiometric = false;
  bool _shakeEnabled = false;
  ShakeSensitivity _shakeSensitivity = ShakeSensitivity.medium;
  bool _intruderCaptureEnabled = false;
  // F7: the persisted foreground-idle choice in whole minutes; null until
  // loaded. Pro-gated options are offered only when [ref] reports Pro.
  int? _idleTimeoutMinutes;

  // F27: the persisted quick-entry preference; null until loaded. The
  // entry check itself happens at tap time on the game screen — this
  // field only drives the toggle and its subtitle.
  bool? _quickEntryEnabled;
  bool _hasDecoyPin = false;
  bool _hasDuressPin = false;

  @override
  void initState() {
    super.initState();
    _checkRecoveryBlob();
    _checkGesture();
    _loadShakePref();
    _loadIntruderCapturePref();
    _loadIdleTimeoutPref();
    _loadQuickEntryPref();
    _checkDecoyPin();
    _checkDuressPin();
  }

  Future<void> _checkDecoyPin() async {
    final enabled = await ref.read(decoyVaultServiceProvider).isDecoyPinEnabled();
    if (mounted) {
      setState(() => _hasDecoyPin = enabled);
    }
  }

  Future<void> _checkDuressPin() async {
    final enabled = await ref.read(duressServiceProvider).isFakePinEnabled();
    if (mounted) {
      setState(() => _hasDuressPin = enabled);
    }
  }

  Future<void> _loadShakePref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _shakeEnabled = prefs.getBool('shake_wipe_enabled') ?? false;
        _shakeSensitivity = ShakeSensitivity.fromCode(
          prefs.getString('shake_sensitivity'),
        );
      });
    }
  }

  Future<void> _loadIntruderCapturePref() async {
    final enabled = await IntruderService.isEnabled();
    if (mounted) {
      setState(() => _intruderCaptureEnabled = enabled);
    }
  }

  Future<void> _onIntruderCaptureToggle(bool value) async {
    if (value) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Intruder Photo Capture'),
          content: const Text(
            'When enabled, Mimic uses the front camera to take a photo after 3 failed PIN attempts.\n\n'
            '• Photos are encrypted with AES-256 and stored strictly on this device.\n'
            '• No photos or data are ever transmitted over the internet or cloud.\n'
            '• You can view or delete captured photos anytime in Intruder Logs.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (agreed != true) return;
    }
    await IntruderService.setEnabled(value);
    if (mounted) {
      setState(() => _intruderCaptureEnabled = value);
    }
  }

  /// F7: reads the persisted foreground-idle choice so the tile subtitle
  /// reflects it. Missing/foreign values stay null (the AutoLock default
  /// applies); the dialog still offers the full list.
  ///
  /// The stored number is CLAMPED here before display, exactly as
  /// [AutoLock.loadIdleTimeout] clamps it before running: a value below the
  /// protective floor reads as the floor, and a Pro value above the
  /// caller's ceiling reads as that ceiling. Without this the subtitle
  /// would promise a lapsed install "30 min idle" while the timer actually
  /// fired at 10 — the UI must report what runs, not what is stored.
  Future<void> _loadIdleTimeoutPref() async {
    final platformService = ref.read(platformServiceProvider);
    int? minutes;
    try {
      minutes = int.tryParse(
        await platformService.secureRead('auto_lock_idle_minutes') ?? '',
      );
    } catch (_) {
      minutes = null;
    }
    if (minutes != null) {
      final isPro = await ref.read(proStatusServiceProvider).isPro();
      final ceiling =
          isPro ? AutoLock.absoluteIdleCap : AutoLock.freeIdleCeiling;
      final wanted = Duration(minutes: minutes);
      minutes = (wanted < AutoLock.defaultIdleTimeout
              ? AutoLock.defaultIdleTimeout
              : (wanted > ceiling ? ceiling : wanted))
          .inMinutes;
    }
    if (mounted) {
      setState(() => _idleTimeoutMinutes = minutes);
    }
  }

  /// F27: reads the quick-entry preference for the toggle. Missing or
  /// unreadable storage reads as OFF (QuickEntryService semantics).
  Future<void> _loadQuickEntryPref() async {
    final enabled = await ref.read(quickEntryServiceProvider).isEnabled();
    if (mounted) {
      setState(() => _quickEntryEnabled = enabled);
    }
  }

  /// F27 toggle handler. Pro-gated at use time: a lapsed install's stale
  /// 'true' keeps working the same way — the home-screen check re-reads
  /// isPro() every tap, so lapse degrades silently to an ordinary game
  /// tap (the golden rule), and this toggle honestly reflects and fixes
  /// the stored preference either way. Turning OFF is allowed for
  /// everyone (a protective direction is never gated).
  Future<void> _onQuickEntryToggle(bool value) async {
    // Turning OFF is never Pro-gated.
    if (!value) {
      try {
        await ref.read(quickEntryServiceProvider).setEnabled(false);
        if (mounted) setState(() => _quickEntryEnabled = false);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save the setting')),
          );
        }
      }
      return;
    }
    // Turning ON requires Pro. Stated in words on the locked control —
    // same pattern as the F7 dialog rows.
    final isPro = await ref.read(proStatusServiceProvider).isPro();
    if (!mounted) return;
    if (!isPro) {
      showPaywallSheet(context);
      return;
    }
    try {
      await ref.read(quickEntryServiceProvider).setEnabled(true);
      if (mounted) setState(() => _quickEntryEnabled = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the setting')),
        );
      }
    }
  }

  /// F27 subtitle: current state, or 'Off' while the value loads.
  String _quickEntrySubtitle() {
    if (_quickEntryEnabled == null) return 'Off';
    return _quickEntryEnabled! ? 'On' : 'Off';
  }

  /// F7 subtitle: the current choice, or the protective default while the
  /// stored value loads (or when it is missing/foreign).
  String _idleTimeoutSubtitle() {
    if (_idleTimeoutMinutes == null) {
      return 'Lock the vault after an idle delay (currently 5 min)';
    }
    return 'Lock the vault after $_idleTimeoutMinutes min idle';
  }

  /// F7: free choices run 5–10 min; Pro choices extend to 30 min (the
  /// suspend ceiling — nothing the user picks can outlive the backstop).
  /// Non-Pro users SEE the Pro rows with a PRO badge, an explanatory
  /// subtitle, and a DISABLED control (`enabled: isPro` nulls the tap, so
  /// the row cannot be picked and does not silently change anything). The
  /// gate is stated in words on the locked row itself, not in a tap
  /// response. Pro-only persistence is guarded twice: the dialog filters,
  /// and AutoLock clamps at load (a stale Pro value on a lapsed install
  /// degrades to the free ceiling, never a lockout).
  Future<void> _showIdleTimeoutDialog() async {
    final platformService = ref.read(platformServiceProvider);
    final proService = ref.read(proStatusServiceProvider);
    final isPro = await proService.isPro();
    if (!mounted) return;
    const freeChoices = [5, 10];
    const proChoices = [15, 30];
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Auto-lock when idle'),
        content: SizedBox(
          width: double.maxFinite,
          child: RadioGroup<int>(
            groupValue: _idleTimeoutMinutes,
            onChanged: (value) {
              if (value != null) Navigator.of(dialogContext).pop(value);
            },
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final minutes in freeChoices)
                  RadioListTile<int>(
                    title: Text('$minutes min'),
                    value: minutes,
                  ),
                for (final minutes in proChoices)
                  RadioListTile<int>(
                    title: Row(
                      children: [
                        Text('$minutes min'),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: VaultColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PRO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: VaultColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    value: minutes,
                    enabled: isPro,
                    subtitle: isPro
                        ? null
                        : const Text('Pro only — upgrade to unlock'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isPro)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                showPaywallSheet(context);
              },
              child: const Text('Unlock Pro'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    // Second guard: a non-Pro pick above the free ceiling is rejected even
    // if the dialog filter is ever bypassed.
    if (!isPro && picked > AutoLock.freeIdleCeiling.inMinutes) return;
    try {
      await platformService.secureWrite(
        'auto_lock_idle_minutes',
        picked.toString(),
      );
    } catch (_) {
      return;
    }
    if (mounted) {
      setState(() {
        _idleTimeoutMinutes = picked;
      });
    }
    // F7: the live timer follows the persisted choice. loadIdleTimeout
    // re-reads storage and clamps to the caller's Pro ceiling, so a stale
    // Pro value on a lapsed install degrades to the free ceiling here too.
    await AutoLock().loadIdleTimeout(
      isPro: await proService.isPro(),
    );
  }

  Future<void> _checkRecoveryBlob() async {
    final platformService = ref.read(platformServiceProvider);
    final blob = await platformService.secureRead('recovery_blob');
    if (mounted) {
      setState(() {
        _hasRecoveryBlob = blob != null && blob.isNotEmpty;
      });
    }
  }

  Future<void> _checkGesture() async {
    try {
      final store = GestureStore();
      final has = await store.hasGesture();
      if (mounted) {
        setState(() {
          _hasGesture = has;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasGesture = false;
        });
      }
    }
  }

  Future<void> _onBiometricSelection(BiometricLayer? selection) async {
    final biometricService = ref.read(biometricServiceProvider);
    final unlockStore = ref.read(biometricUnlockStoreProvider);
    
    if (selection == BiometricLayer.vault) {
      final pin = await _promptForVaultPin();
      if (pin != null && pin.isNotEmpty) {
        setState(() => _isLoadingBiometric = true);
        try {
          await unlockStore.writeBioSecret(pin);
          await unlockStore.disable(BiometricLayer.admin);
          if (mounted) {
            ref.invalidate(biometricEnabledProvider(BiometricLayer.vault));
            ref.invalidate(biometricEnabledProvider(BiometricLayer.admin));
          }
        } on BiometricCancelledException {
          if (mounted) {
            ref.invalidate(biometricEnabledProvider(BiometricLayer.vault));
            ref.invalidate(biometricEnabledProvider(BiometricLayer.admin));
          }
        } on BiometricKeyInvalidatedException {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Fingerprint changed - unlock with your PIN to re-enable'),
                backgroundColor: VaultColors.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
            ref.invalidate(biometricEnabledProvider(BiometricLayer.vault));
            ref.invalidate(biometricEnabledProvider(BiometricLayer.admin));
          }
        } on BiometricUnavailableException {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Biometric unlock is unavailable on this device'),
                backgroundColor: VaultColors.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
            ref.invalidate(biometricEnabledProvider(BiometricLayer.vault));
            ref.invalidate(biometricEnabledProvider(BiometricLayer.admin));
          }
        } finally {
          if (mounted) setState(() => _isLoadingBiometric = false);
        }
      }
    } else if (selection == BiometricLayer.admin) {
      setState(() => _isLoadingBiometric = true);
      final result = await biometricService.authenticate(reason: 'Unlock');
      if (mounted) setState(() => _isLoadingBiometric = false);
      if (result == BiometricResult.success) {
        await unlockStore.enable(BiometricLayer.admin, '');
        await unlockStore.disable(BiometricLayer.vault);
        ref.invalidate(biometricEnabledProvider(BiometricLayer.vault));
        ref.invalidate(biometricEnabledProvider(BiometricLayer.admin));
      }
    } else {
      await unlockStore.disable(BiometricLayer.vault);
      await unlockStore.disable(BiometricLayer.admin);
      ref.invalidate(biometricEnabledProvider(BiometricLayer.vault));
      ref.invalidate(biometricEnabledProvider(BiometricLayer.admin));
    }
  }

  Future<void> _onShakeToggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shake_wipe_enabled', value);
    if (mounted) {
      setState(() => _shakeEnabled = value);
    }
  }

  Future<void> _onSensitivityChanged(ShakeSensitivity sensitivity) async {
    final concealService = ref.read(vaultConcealServiceProvider);
    await concealService.setSensitivity(sensitivity);
    if (mounted) {
      setState(() => _shakeSensitivity = sensitivity);
    }
  }

  Future<void> _onHideAppIconToggle(bool hide) async {
    if (hide) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Hide app icon?',
            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter'),
          ),
          content: const Text(
            "Mimic's icon will disappear from your home screen and app drawer. To reopen it, go to Android Settings > Apps > Mimic > Open, then turn this off again. Continue?",
            style: TextStyle(fontFamily: 'Inter'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hide', style: TextStyle(color: VaultColors.accent, fontFamily: 'Inter')),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        ref.read(launcherIconProvider.notifier).setIconVisible(false);
      }
    } else {
      ref.read(launcherIconProvider.notifier).setIconVisible(true);
    }
  }

  void _lockVault() {
    final crypto = ref.read(vaultCryptoProvider);
    crypto.lock();
    PanicMode().dispose();
    AutoLock().dispose();
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRouter.vaultPinRoute,
      AppRouter.isNotVaultRoute,
    );
  }

  void _showChangePinDialog() {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? error;
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Change PIN',
            style: TextStyle(
              color: VaultColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPinField(currentPinController, 'Current PIN'),
              const SizedBox(height: 12),
              _buildPinField(newPinController, 'New PIN'),
              const SizedBox(height: 12),
              _buildPinField(confirmPinController, 'Confirm New PIN'),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(color: VaultColors.error, fontSize: 13, fontFamily: 'Inter'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
            ),
            TextButton(
              onPressed: isProcessing ? null : () async {
                final currentPin = currentPinController.text;
                final newPin = newPinController.text;
                final confirmPin = confirmPinController.text;

                if (currentPin.isEmpty) {
                  setDialogState(() => error = 'Please enter your current PIN');
                  return;
                }
                if (newPin.length < 4) {
                  setDialogState(() => error = 'New PIN must be at least 4 digits');
                  return;
                }
                if (newPin != confirmPin) {
                  setDialogState(() => error = 'PINs do not match');
                  return;
                }
                if (newPin == currentPin) {
                  setDialogState(() => error = 'New PIN must be different from current PIN');
                  return;
                }

                setDialogState(() {
                  isProcessing = true;
                  error = null;
                });

                try {
                  final crypto = ref.read(vaultCryptoProvider);
                  final isCurrentValid = await crypto.verifyPin(currentPin);
                  if (!isCurrentValid) {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        isProcessing = false;
                        error = 'Incorrect current PIN';
                      });
                    }
                    return;
                  }

                  // AUDIT-05: Prevent Master PIN from colliding with active Duress PIN or Decoy PIN
                  final duressService = ref.read(duressServiceProvider);
                  final isDuressPin = await duressService.isFakePin(newPin);
                  if (isDuressPin) {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        isProcessing = false;
                        error = 'This PIN is unavailable. Please choose a different PIN.';
                      });
                    }
                    return;
                  }

                  final isDecoyPin = await ref.read(decoyVaultServiceProvider).hasStoredDecoyPinMatch(newPin);
                  if (isDecoyPin) {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        isProcessing = false;
                        error = 'This PIN is unavailable. Please choose a different PIN.';
                      });
                    }
                    return;
                  }

                  // Preserve the data key (DEK): changePin re-wraps the SAME key under the new PIN.
                  // NEVER delete the salt/hash or call initialize() here — that creates a new key
                  // and permanently orphans all encrypted photos, videos, and documents.
                  await crypto.changePin(newPin);

                  // AUDIT-04: Invalidate biometric secret on PIN change
                  try {
                    await ref.read(biometricUnlockStoreProvider).clearBioSecret();
                  } catch (_) {}

                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('PIN changed successfully'),
                        backgroundColor: VaultColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    setDialogState(() {
                      isProcessing = false;
                      error = 'Failed to change PIN: $e';
                    });
                  }
                }
              },
              child: isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: VaultColors.accent,
                      ),
                    )
                  : const Text(
                      'Change',
                      style: TextStyle(color: VaultColors.accent, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptForVaultPin() async {
    // Intentionally not disposed here because showDialog returns before the dialog finishes closing.
    final pinController = TextEditingController();
    String? error;
    bool isProcessing = false;

    final enteredPin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Confirm Vault PIN',
            style: TextStyle(
              color: VaultColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPinField(pinController, 'Vault PIN'),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(color: VaultColors.error, fontSize: 13, fontFamily: 'Inter'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
            ),
            TextButton(
              onPressed: isProcessing
                  ? null
                  : () async {
                      final pin = pinController.text;
                      if (pin.isEmpty) {
                        setDialogState(() => error = 'Please enter your PIN');
                        return;
                      }

                      setDialogState(() {
                        isProcessing = true;
                        error = null;
                      });

                      final crypto = ref.read(vaultCryptoProvider);
                      final isValid = await crypto.verifyPin(pin);

                      if (!isValid) {
                        setDialogState(() {
                          isProcessing = false;
                          error = 'Incorrect PIN';
                        });
                        return;
                      }

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(pin);
                      }
                    },
              child: const Text('Confirm', style: TextStyle(color: VaultColors.accent, fontFamily: 'Inter')),
            ),
          ],
        ),
      ),
    );

    return enteredPin;
  }

  Widget _buildPinField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 8,
      style: const TextStyle(color: VaultColors.textPrimary, fontFamily: 'Inter'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter'),
        counterText: '',
        filled: true,
        fillColor: VaultColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VaultColors.accent),
        ),
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear All Vault Data',
          style: TextStyle(
            color: VaultColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
          ),
        ),
        content: const Text(
          'This will permanently delete all encrypted files, notes, audio recordings, and break-in logs. This action cannot be undone.',
          style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              // One owner for the whole content wipe: closes the services'
              // open SQLite connections (a live handle keeps serving deleted
              // rows), drops every content database + sidecar, purges the
              // shared blob directory, intruder evidence, decrypted temp
              // dirs, and every content metadata key — while leaving the
              // PIN/keystore/recovery/duress/gesture state alone so the
              // vault still unlocks (r28 Phase 10.1). The old handler only
              // deleted web-only meta keys, which is why photos, videos,
              // documents, notes and thumbnails survived on the device.
              try {
                await ref.read(vaultWipeServiceProvider).wipeAllContent();
              } catch (_) {}
              // Drop any decrypted video frames still held in memory for
              // this unlock (thumbnails are memory-only by design, F23).
              try {
                ref.read(videoThumbnailCacheProvider.notifier).wipe();
              } catch (_) {}
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('All vault data cleared'),
                    backgroundColor: VaultColors.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            child: const Text(
              'Delete Everything',
              style: TextStyle(color: VaultColors.error, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool stealth = ref.watch(stealthModeProvider);
    final bool iconVisible = ref.watch(launcherIconProvider);
    // F27: the quick-entry row is a Pro feature — hidden entirely for free
    // installs (the toggle handler still re-checks isPro() at use time, so
    // a lapsed install that somehow reaches the row cannot turn it on).
    final bool isPro = ref.watch(isProProvider).valueOrNull ?? false;

    return VaultScaffold(
      title: 'Settings',
      showLockButton: false,
      actions: [
        // Dev/billing-simulation entry is DEBUG-ONLY by construction: gated on
        // kDebugMode alone (not kBillingSimulationEnabled) so a release or
        // profile APK can never surface it, even if the simulation flag is
        // accidentally re-enabled. See pro_status_service.dart (P0-1 teardown).
        if (kDebugMode)
          IconButton(
            icon: const Icon(Icons.build_circle_outlined, color: VaultColors.accent),
            tooltip: 'Billing Simulation Suite',
            onPressed: () => _showDevSimulationSheet(context),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // Mimic Pro Supporter / Upgrade Card
          isPro ? _buildProSupporterBanner() : _buildProUpgradeCard(),

          // Security Section
          _buildSectionHeader('Security'),
          _buildSettingsTile(
            icon: Icons.lock_outline,
            title: 'Change PIN',
            subtitle: 'Update your vault access PIN',
            onTap: _showChangePinDialog,
          ),
          _buildSettingsTile(
            icon: Icons.lock,
            title: 'Lock Vault',
            subtitle: 'Lock vault and return to PIN screen',
            onTap: _lockVault,
            iconColor: VaultColors.error,
          ),
          _buildSettingsTile(
            icon: Icons.vpn_key_outlined,
            title: 'Recovery Phrase',
            subtitle: _hasRecoveryBlob
                ? 'Recovery phrase is set up'
                : 'Set up a 12-word backup to recover vault access',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-recovery-phrase');
            },
            trailing: _hasRecoveryBlob
                ? const Icon(Icons.check_circle, color: VaultColors.success, size: 20)
                : null,
          ),
          _buildSettingsTile(
            icon: Icons.touch_app,
            title: 'Unlock Gesture',
            subtitle: _hasGesture
                ? 'Change the three taps that open your vault'
                : 'Choose the three taps that open your vault',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => GestureSetupScreen(
                    allowCancel: true,
                    onComplete: () {
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      _checkGesture();
                    },
                  ),
                ),
              );
            },
            trailing: _hasGesture
                ? const Icon(Icons.check_circle, color: VaultColors.success, size: 20)
                : null,
          ),
          _buildSettingsTile(
            icon: Icons.fingerprint,
            title: 'Biometric Unlock',
            subtitle: 'Choose what biometric unlock does',
            onTap: () {},
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Consumer(
              builder: (context, ref, child) {
                final isVault = ref.watch(biometricEnabledProvider(BiometricLayer.vault)).valueOrNull ?? false;
                final isAdmin = ref.watch(biometricEnabledProvider(BiometricLayer.admin)).valueOrNull ?? false;
                final selected = isVault ? 'vault' : (isAdmin ? 'admin' : 'off');
                
                if (_isLoadingBiometric) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: VaultColors.accent)
                      )
                    ),
                  );
                }
                
                return Column(
                  children: [
                    RadioListTile<String>(
                      title: const Text('Off', style: TextStyle(color: VaultColors.textPrimary, fontSize: 14)),
                      value: 'off',
                      groupValue: selected,
                      onChanged: (val) => _onBiometricSelection(null),
                      activeColor: VaultColors.accent,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<String>(
                      title: const Text('Vault (shortcut)', style: TextStyle(color: VaultColors.textPrimary, fontSize: 14)),
                      value: 'vault',
                      groupValue: selected,
                      onChanged: (val) => _onBiometricSelection(BiometricLayer.vault),
                      activeColor: VaultColors.accent,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<String>(
                      title: const Text('Admin panel (decoy)', style: TextStyle(color: VaultColors.textPrimary, fontSize: 14)),
                      value: 'admin',
                      groupValue: selected,
                      onChanged: (val) => _onBiometricSelection(BiometricLayer.admin),
                      activeColor: VaultColors.accent,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                );
              },
            ),
          ),
          _buildSettingsTile(
            icon: Icons.admin_panel_settings,
            title: 'Duress PIN',
            subtitle: _hasDuressPin
                ? 'Duress PIN active — opens admin panel instead of your vault'
                : 'Fake PIN that opens the admin panel instead of your vault',
            trailing: _hasDuressPin
                ? const Icon(Icons.check_circle, color: VaultColors.success, size: 20)
                : null,
            onTap: () {
              Navigator.of(context)
                  .pushNamed('/vault-set-duress-pin')
                  .then((_) => _checkDuressPin());
            },
          ),
          _buildSettingsTile(
            icon: Icons.hide_source_outlined,
            title: 'Decoy Vault (Ghost Album)',
            subtitle: !isPro
                ? 'Fake PIN that opens a harmless decoy vault for plausible deniability'
                : _hasDecoyPin
                    ? 'Decoy PIN active — opens harmless ghost vault'
                    : 'Fake PIN that opens a harmless decoy vault for plausible deniability',
            trailing: !isPro
                ? _buildProBadge()
                : _hasDecoyPin
                    ? const Icon(Icons.check_circle, color: VaultColors.success, size: 20)
                    : null,
            onTap: () {
              if (!isPro) {
                showPaywallSheet(context);
                return;
              }
              Navigator.of(context)
                  .pushNamed('/vault-set-decoy-pin')
                  .then((_) => _checkDecoyPin());
            },
          ),
          _buildSettingsTile(
            icon: Icons.vibration,
            title: 'Shake to Hide',
            subtitle: 'Shaking instantly hides your vault',
            onTap: () {},
            trailing: Switch(
              value: _shakeEnabled,
              onChanged: (value) => _onShakeToggle(value),
              activeThumbColor: VaultColors.accent,
            ),
          ),
          // F7: foreground-idle auto-lock timeout. The tile's tap opens a
          // dialog listing the free choices plus the Pro choices (badge).
          // The background grace is intentionally NOT listed here — it is
          // fixed at 1 minute by design (see auto_lock.dart).
          _buildSettingsTile(
            icon: Icons.timer_outlined,
            title: 'Auto-lock when idle',
            subtitle: _idleTimeoutSubtitle(),
            onTap: _showIdleTimeoutDialog,
          ),
          // F27: the Pro quick-entry toggle — visible for all users, but
          // gated for free: a PRO badge replaces the switch, and tapping
          // the tile opens the paywall. Pro users get the live toggle.
          // The handler additionally asks isPro() at use time (turning ON
          // is gated; turning OFF is allowed for everyone — a protective
          // direction is never gated). The subtitle carries the honest
          // warning the spec requires: what the shortcut skips, and the
          // coercion note.
          _buildSettingsTile(
            icon: Icons.bolt_outlined,
            title: 'Quick entry to the vault',
            subtitle: isPro
                ? '${_quickEntrySubtitle()}: long-press the MIMIC '
                    'title on the game home to skip the tap gesture. Your '
                    'PIN, biometrics, lockout and break-in log are unchanged, '
                    'and anyone holding your unlocked phone can reach this '
                    'screen and turn it on.'
                : 'Long-press the MIMIC title on the game home to skip the tap gesture',
            trailing: isPro
                ? Switch(
                    value: _quickEntryEnabled ?? false,
                    onChanged: _onQuickEntryToggle,
                    activeThumbColor: VaultColors.accent,
                  )
                : _buildProBadge(),
            onTap: isPro
                ? () {}
                : () => showPaywallSheet(context),
          ),
          // Shake Sensitivity selector — only active when shake is enabled
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Shake Sensitivity',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: VaultColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                SegmentedButton<ShakeSensitivity>(
                  segments: const [
                    ButtonSegment(
                      value: ShakeSensitivity.low,
                      label: Text('Low'),
                    ),
                    ButtonSegment(
                      value: ShakeSensitivity.medium,
                      label: Text('Med'),
                    ),
                    ButtonSegment(
                      value: ShakeSensitivity.high,
                      label: Text('High'),
                    ),
                  ],
                  selected: {_shakeSensitivity},
                  onSelectionChanged: _shakeEnabled
                      ? (selected) => _onSensitivityChanged(selected.first)
                      : null,
                  style: ButtonStyle(
                    textStyle: WidgetStatePropertyAll(
                      const TextStyle(fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Higher = easier to trigger; Lower = fewer accidental hides.',
                  style: TextStyle(
                    fontSize: 11,
                    color: _shakeEnabled
                        ? VaultColors.textTertiary
                        : VaultColors.textTertiary.withValues(alpha: 0.5),
                    fontFamily: 'Inter',
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          _buildSettingsTile(
            icon: Icons.visibility_off,
            title: 'Stealth Mode',
            subtitle: 'Hides all vault hints across the game. Secret unlock patterns still work.',
            onTap: null,
            trailing: Switch(
              value: stealth,
              onChanged: (value) => ref.read(stealthModeProvider.notifier).setStealthMode(value),
              activeThumbColor: VaultColors.accent,
            ),
          ),
          _buildSettingsTile(
            icon: Icons.visibility_off,
            title: 'Hide App Icon',
            subtitle: 'Removes Mimic from the app drawer. Reopen via Android Settings > Apps > Mimic > Open.',
            onTap: null,
            trailing: Switch(
              value: !iconVisible,
              onChanged: (value) => _onHideAppIconToggle(value),
              activeThumbColor: VaultColors.accent,
            ),
          ),

          const SizedBox(height: 24),

          // Backup Section
          _buildSectionHeader('Backup'),
          _buildSettingsTile(
            icon: Icons.upload_outlined,
            title: 'Export Vault',
            subtitle: 'Save an encrypted backup of your vault',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-export');
            },
          ),
          _buildSettingsTile(
            icon: Icons.download_outlined,
            title: 'Import Vault',
            subtitle: 'Restore vault from a .mimic backup file',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-import');
            },
          ),

          const SizedBox(height: 24),

          // Security Auditing Section
          _buildSectionHeader('Auditing'),
          _buildSettingsTile(
            icon: Icons.shield_outlined,
            title: 'Intruder Logs',
            subtitle: 'View failed PIN attempts and photo captures',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-breakin-logs');
            },
          ),
          _buildSettingsTile(
            icon: Icons.camera_alt_outlined,
            title: 'Capture Intruder Photos',
            subtitle: _intruderCaptureEnabled
                ? 'Enabled: front camera captures a photo after 3 failed attempts (stored locally)'
                : 'Disabled: no camera photos taken on failed attempts',
            onTap: () => _onIntruderCaptureToggle(!_intruderCaptureEnabled),
            trailing: Switch(
              value: _intruderCaptureEnabled,
              onChanged: (val) => _onIntruderCaptureToggle(val),
              activeThumbColor: VaultColors.accent,
            ),
          ),
          _buildSettingsTile(
            icon: Icons.speed,
            title: 'Diagnostics',
            subtitle: 'Timing and hardware checks',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-diagnostics');
            },
          ),

          const SizedBox(height: 24),

          // Appearance & Storage Section
          _buildSectionHeader('Appearance & Storage'),
          _buildSettingsTile(
            icon: Icons.palette_outlined,
            title: 'Vault Visual Theme',
            subtitle: 'Stealth and OLED color palettes (${ref.watch(vaultThemeProvider).name})',
            trailing: isPro ? null : _buildProBadge(),
            onTap: () {
              Navigator.of(context).pushNamed('/vault-theme-selector');
            },
          ),
          _buildSettingsTile(
            icon: Icons.cleaning_services_outlined,
            title: 'Storage Optimizer',
            subtitle: 'Find duplicate photos and videos over 20 MB',
            trailing: isPro ? null : _buildProBadge(),
            onTap: () {
              Navigator.of(context).pushNamed('/vault-storage-optimizer');
            },
          ),

          const SizedBox(height: 24),

          // Guide Section
          _buildSectionHeader('Guide'),
          _buildSettingsTile(
            icon: Icons.menu_book_outlined,
            title: 'Field Manual',
            subtitle: 'How the vault works, and how to stay hidden',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-manual');
            },
          ),

          const SizedBox(height: 24),

          // Danger Zone
          _buildSectionHeader('Danger Zone'),
          _buildSettingsTile(
            icon: Icons.delete_forever,
            title: 'Clear All Data',
            subtitle: 'Delete all encrypted files and notes',
            onTap: _showClearDataDialog,
            iconColor: VaultColors.error,
          ),

          // DEV-ONLY: Pro simulation and testing tools.
          // Gated on kDebugMode alone so this section — including the one-tap
          // "Toggle Local Pro Entitlement" that calls grantPro() — can NEVER
          // render in a release or profile APK, regardless of the simulation
          // flag. This closes the free-Pro bypass in distributed builds.
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('Developer & Billing Simulation'),
            ..._buildDevSimulationTiles(context),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showDevSimulationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: VaultColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Simulation & Testing Suite',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: VaultColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: VaultColors.textSecondary),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._buildDevSimulationTiles(context),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDevSimulationTiles(BuildContext context) {
    final isPro = ref.watch(isProProvider).valueOrNull ?? false;
    return [
      _buildSettingsTile(
        icon: Icons.science_outlined,
        title: 'Toggle Local Pro Entitlement',
        subtitle: isPro
            ? 'Currently PRO (in secure storage) — tap to revoke'
            : 'Currently FREE (in secure storage) — tap to grant',
        iconColor: isPro ? VaultColors.success : VaultColors.accent,
        onTap: () async {
          final proService = ref.read(proStatusServiceProvider);
          final wasPro = await proService.isPro();
          if (wasPro) {
            await proService.revokePro();
          } else {
            await proService.grantPro();
          }
          ref.invalidate(isProProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    wasPro ? 'Pro REVOKED locally' : 'Pro GRANTED locally'),
                backgroundColor:
                    wasPro ? VaultColors.error : VaultColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        },
      ),
      FutureBuilder<bool>(
        future: SimulatedBillingStore.hasAccountOwnedPro(),
        builder: (context, snapshot) {
          final hasAccountPro = snapshot.data ?? false;
          return _buildSettingsTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Simulated Play Account Ownership',
            subtitle: hasAccountPro
                ? 'Account OWNS Pro (Restore will succeed) — tap to reset'
                : 'Account EMPTY (Restore will report none) — tap to mark owned',
            iconColor: hasAccountPro
                ? VaultColors.success
                : VaultColors.textSecondary,
            onTap: () async {
              await SimulatedBillingStore.setAccountOwnedPro(!hasAccountPro);
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(!hasAccountPro
                        ? 'Simulated Play Account now OWNS Pro'
                        : 'Simulated Play Account RESET to empty'),
                    backgroundColor: !hasAccountPro
                        ? VaultColors.success
                        : VaultColors.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
          );
        },
      ),
      _buildSettingsTile(
        icon: Icons.signal_wifi_off_outlined,
        title: 'Simulate Billing Offline (Checks 22-23)',
        subtitle: SimulatedBillingStore.simulateOffline
            ? 'OFFLINE: Paywall displays orange offline banner'
            : 'ONLINE: Paywall loads ₱99.00 pricing normally',
        iconColor: SimulatedBillingStore.simulateOffline
            ? const Color(0xFFEA580C)
            : VaultColors.textSecondary,
        onTap: () async {
          SimulatedBillingStore.simulateOffline =
              !SimulatedBillingStore.simulateOffline;
          await ref.read(billingServiceProvider).reloadProductDetails();
          setState(() {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(SimulatedBillingStore.simulateOffline
                    ? 'Billing simulation set to OFFLINE (Orange banner active)'
                    : 'Billing simulation set to ONLINE (Pricing active)'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        },
      ),
      _buildSettingsTile(
        icon: Icons.shopping_bag_outlined,
        title: 'Launch Paywall Sheet',
        subtitle: 'Simulate purchase or restore directly through paywall modal',
        iconColor: VaultColors.accent,
        onTap: () => showPaywallSheet(context),
      ),
    ];
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: VaultColors.textTertiary,
          fontFamily: 'Inter',
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color iconColor = VaultColors.accent,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: VaultColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: VaultColors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          trailing: trailing ?? const Icon(Icons.chevron_right, color: VaultColors.textTertiary, size: 20),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildProSupporterBanner() {
    return InkWell(
      onTap: () => showPaywallSheet(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6FBF8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: VaultColors.success.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: VaultColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: VaultColors.success,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mimic Pro Supporter ⭐',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: VaultColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Lifetime unlock active — Thank you for your support!',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: VaultColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: VaultColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildProUpgradeCard() {
    return InkWell(
      onTap: () => showPaywallSheet(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF8F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: VaultColors.accent.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: VaultColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: VaultColors.accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unlock Mimic Pro',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: VaultColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Quick entry, 30-min idle timeout & support indie privacy.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: VaultColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: VaultColors.accent),
          ],
        ),
      ),
    );
  }

  Widget _buildProBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }
}
