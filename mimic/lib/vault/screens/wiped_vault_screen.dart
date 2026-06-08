// mimic/lib/vault/screens/wiped_vault_screen.dart
import 'package:flutter/material.dart';

class WipedVaultScreen extends StatelessWidget {
  const WipedVaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 72,
                color: Color(0xFF534AB7),
              ),
              const SizedBox(height: 24),
              const Text(
                'Vault Hidden',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your vault is currently hidden for safety.\nUse your 12-word recovery phrase to restore access.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B6B6B),
                  fontFamily: 'Inter',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushNamed('/vault-enter-recovery');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF534AB7),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Restore Vault',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          _buildGameHome(context),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                    (_) => false,
                  );
                },
                child: const Text(
                  'Not now — return to game',
                  style: TextStyle(
                    color: Color(0xFF888780),
                    fontSize: 14,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameHome(BuildContext context) {
    // Route back to game home using the root route
    // This avoids importing game layer from vault layer
    return Navigator(
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => _GameHomePlaceholder(),
          settings: const RouteSettings(name: '/'),
        );
      },
    );
  }
}

class _GameHomePlaceholder extends StatelessWidget {
  const _GameHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    // Minimal placeholder — in production this would redirect via the app's main navigator
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: Center(
        child: TextButton(
          onPressed: () {
            // Navigate to home through the app's root navigator
            Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
          },
          child: const Text(
            'Return to Game',
            style: TextStyle(color: Color(0xFF7F77DD), fontSize: 18),
          ),
        ),
      ),
    );
  }
}
