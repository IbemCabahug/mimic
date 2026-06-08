// mimic/lib/vault/screens/set_duress_pin_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../security/duress_service.dart';

class SetDuressPinScreen extends ConsumerStatefulWidget {
  const SetDuressPinScreen({super.key});

  @override
  ConsumerState<SetDuressPinScreen> createState() => _SetDuressPinScreenState();
}

class _SetDuressPinScreenState extends ConsumerState<SetDuressPinScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _hasExistingPin = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    _checkExistingPin();
  }

  Future<void> _checkExistingPin() async {
    final enabled = await ref.read(duressServiceProvider).isFakePinEnabled();
    if (mounted) {
      setState(() => _hasExistingPin = enabled);
    }
  }

  Future<void> _submitPin() async {
    final pin = _pinController.text;
    if (pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 digits');
      return;
    }

    if (!_showConfirm) {
      setState(() {
        _showConfirm = true;
        _error = null;
      });
      return;
    }

    final confirm = _confirmController.text;
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match');
      _confirmController.clear();
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(duressServiceProvider).setFakePin(pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Duress PIN saved'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to save PIN: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Duress PIN?',
          style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter', color: VaultColors.textPrimary),
        ),
        content: Text(
          'This will disable the fake PIN feature. The admin panel will no longer be accessible via a secret PIN.',
          style: TextStyle(fontFamily: 'Inter', color: VaultColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Remove', style: TextStyle(color: VaultColors.error, fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(duressServiceProvider).clearFakePin();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Duress PIN removed'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _hasExistingPin ? 'Change Duress PIN' : 'Set Duress PIN',
          style: TextStyle(color: VaultColors.accent, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Inter'),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter a fake PIN that opens the admin panel instead of your vault.',
              style: TextStyle(fontSize: 14, color: VaultColors.textSecondary, fontFamily: 'Inter'),
            ),
            SizedBox(height: 32),
            _PinDots(pin: _pinController.text, maxLength: 8),
            SizedBox(height: 24),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              style: TextStyle(color: VaultColors.textPrimary, fontFamily: 'Inter'),
              decoration: InputDecoration(
                labelText: _showConfirm ? 'New PIN' : 'Enter Duress PIN',
                labelStyle: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter'),
                counterText: '',
                filled: true,
                fillColor: VaultColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: VaultColors.accent),
                ),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_showConfirm) ...[
              SizedBox(height: 16),
              _PinDots(pin: _confirmController.text, maxLength: 8),
              SizedBox(height: 24),
              TextField(
                controller: _confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: TextStyle(color: VaultColors.textPrimary, fontFamily: 'Inter'),
                decoration: InputDecoration(
                  labelText: 'Confirm Duress PIN',
                  labelStyle: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter'),
                  counterText: '',
                  filled: true,
                  fillColor: VaultColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: VaultColors.accent),
                  ),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
            ],
            if (_error != null) ...[
              SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: VaultColors.error, fontSize: 13, fontFamily: 'Inter'),
              ),
            ],
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: VaultColors.accent,
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      _hasExistingPin ? 'Update PIN' : (_showConfirm ? 'Confirm PIN' : 'Continue'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
                    ),
            ),
            if (_hasExistingPin) ...[
              SizedBox(height: 12),
              TextButton(
                onPressed: _removePin,
                style: TextButton.styleFrom(foregroundColor: VaultColors.error),
                child: Text(
                  'Remove Duress PIN',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  final String pin;
  final int maxLength;

  const _PinDots({required this.pin, required this.maxLength});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxLength, (index) {
        final filled = index < pin.length;
        return Container(
          width: 16,
          height: 16,
          margin: EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? VaultColors.accent : VaultColors.surface,
            border: Border.all(color: VaultColors.accent.withValues(alpha: 0.3)),
          ),
        );
      }),
    );
  }
}
