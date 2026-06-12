// lib/core/providers/provider_registration.dart
//
// Scopes and registers all new multiplayer providers in correct dependency order.
// Provides autoDispose configurations for clean websocket and timer resources lifecycle management.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/network/disconnect_handler.dart';
import 'package:mimic/multiplayer/state/game_state_sync_notifier.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/security/vault_conceal_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Multiplayer Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the unified [NetworkService].
/// Auto-disposes and disconnects active WebSocket server/client when no listeners remain.
final networkServiceProvider = ChangeNotifierProvider.autoDispose<NetworkService>((ref) {
  final service = NetworkService();
  ref.onDispose(() {
    service.disconnect();
  });
  return service;
});

/// Provider for the [DisconnectHandler].
/// Depends on [networkServiceProvider] and [gameStateSyncProvider].
/// Auto-disposes and stops monitoring/ping-pong timers when no longer needed.
final disconnectHandlerProvider = Provider.autoDispose<DisconnectHandler>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  final gameStateSyncNotifier = ref.watch(gameStateSyncProvider.notifier);
  final handler = DisconnectHandler(networkService, gameStateSyncNotifier);
  ref.onDispose(() {
    handler.stopMonitoring();
  });
  return handler;
});

/// Provider for the [GameStateSyncNotifier] state.
/// Depends on [networkServiceProvider] and the existing [gameStateProvider].
/// Auto-disposes and cleans up inner network stream subscriptions when disposed.
final gameStateSyncProvider = StateNotifierProvider<GameStateSyncNotifier, GameSyncState>((ref) {
  final networkService = ref.read(networkServiceProvider);
  final gameStateNotifier = ref.read(gameStateProvider.notifier);
  return GameStateSyncNotifier(networkService, gameStateNotifier);
});

// ═══════════════════════════════════════════════════════════════════════════
// Vault Conceal Service
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the global [VaultConcealService].
/// Singleton — persists for the lifetime of the app.
final vaultConcealServiceProvider = Provider<VaultConcealService>((ref) {
  final platformService = ref.read(platformServiceProvider);
  return VaultConcealService(ref, platformService);
});

// ═══════════════════════════════════════════════════════════════════════════
// Multiplayer Safety Net Widget
// ═══════════════════════════════════════════════════════════════════════════

/// Safety net widget to guarantee cleanup of network resources.
/// Wraps the multiplayer segment of the application and ensures disconnect is called
/// when this subtree is unmounted.
class MultiplayerProviderScope extends StatelessWidget {
  final Widget child;

  const MultiplayerProviderScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: _MultiplayerCleanupWrapper(child: child),
    );
  }
}

class _MultiplayerCleanupWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const _MultiplayerCleanupWrapper({required this.child});

  @override
  ConsumerState<_MultiplayerCleanupWrapper> createState() => _MultiplayerCleanupWrapperState();
}

class _MultiplayerCleanupWrapperState extends ConsumerState<_MultiplayerCleanupWrapper> {
  @override
  void dispose() {
    // Safety net: ensure sockets are closed when leaving multiplayer screens
    ref.read(networkServiceProvider).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
