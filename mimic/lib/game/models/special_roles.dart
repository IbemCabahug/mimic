// lib/game/models/special_roles.dart
//
// Special role definitions for Nightmare mode.
// Each role grants a unique ability or handicap that adds strategic depth
// to the social deduction gameplay.
//
// Roles are assigned randomly at the start of a Nightmare-mode round.
// Only non-Mimic players receive special roles.

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Role Enum
// ═══════════════════════════════════════════════════════════════════════════

/// Special roles available in Nightmare mode.
enum SpecialRole {
  /// No special role assigned.
  none,

  /// The Informant: Receives a single letter hint from the real word.
  /// This helps narrow down who might be the Mimic, but can be misleading
  /// if the Mimic's fake word shares that letter.
  informant,

  /// The Paranoid: Sees randomized fake suspicion indicators on other players.
  /// Their UI shows elevated suspicion bars that don't reflect reality,
  /// making it harder for them to trust their own judgment.
  paranoid,

  /// The Ally: Knows the identity of one other confirmed innocent player.
  /// They can coordinate with that player, but revealing this information
  /// publicly risks tipping off the Mimic(s).
  ally,
}

// ═══════════════════════════════════════════════════════════════════════════
// Role Display Extension
// ═══════════════════════════════════════════════════════════════════════════

extension SpecialRoleDisplay on SpecialRole {
  /// Display name shown to the player.
  String get displayName {
    switch (this) {
      case SpecialRole.none:
        return 'No Role';
      case SpecialRole.informant:
        return 'The Informant';
      case SpecialRole.paranoid:
        return 'The Paranoid';
      case SpecialRole.ally:
        return 'The Ally';
    }
  }

  /// Short description of what the role does.
  String get description {
    switch (this) {
      case SpecialRole.none:
        return 'You have no special ability this round.';
      case SpecialRole.informant:
        return 'You receive a single letter from the real word. '
            'Use it wisely — the Mimic may share that letter.';
      case SpecialRole.paranoid:
        return 'Your suspicion indicators are unreliable. '
            'Trust your instincts, not the meters.';
      case SpecialRole.ally:
        return 'You know one player who is definitely innocent. '
            'Coordinate carefully without revealing your role.';
    }
  }

  /// Icon associated with this role.
  IconData get icon {
    switch (this) {
      case SpecialRole.none:
        return Icons.person;
      case SpecialRole.informant:
        return Icons.search;
      case SpecialRole.paranoid:
        return Icons.psychology_alt;
      case SpecialRole.ally:
        return Icons.handshake;
    }
  }

  /// Theme color for this role's UI elements.
  Color get color {
    switch (this) {
      case SpecialRole.none:
        return const Color(0xFF6B7280);
      case SpecialRole.informant:
        return const Color(0xFF3B82F6);
      case SpecialRole.paranoid:
        return const Color(0xFFF59E0B);
      case SpecialRole.ally:
        return const Color(0xFF22C55E);
    }
  }

  /// Emoji for quick identification.
  String get emoji {
    switch (this) {
      case SpecialRole.none:
        return '👤';
      case SpecialRole.informant:
        return '🔍';
      case SpecialRole.paranoid:
        return '🫣';
      case SpecialRole.ally:
        return '🤝';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Role Assignment
// ═══════════════════════════════════════════════════════════════════════════

/// Holds the role assignment for a single player in a round.
class RoleAssignment {
  /// The player's ID.
  final String playerId;

  /// The assigned special role.
  final SpecialRole role;

  /// Role-specific data payload.
  /// - Informant: `{'letter': 'A', 'position': 2}` — a single letter hint
  /// - Paranoid: `{'fakeSuspicions': {'player1': 0.8, 'player2': 0.6}}` — fake indicators
  /// - Ally: `{'allyPlayerId': 'player3'}` — the known innocent's ID
  /// - None: empty map
  final Map<String, dynamic> roleData;

  const RoleAssignment({
    required this.playerId,
    required this.role,
    this.roleData = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'playerId': playerId,
      'role': role.name,
      'roleData': roleData,
    };
  }

  factory RoleAssignment.fromJson(Map<String, dynamic> json) {
    return RoleAssignment(
      playerId: json['playerId'] as String? ?? '',
      role: SpecialRole.values.firstWhere(
        (r) => r.name == (json['role'] as String?),
        orElse: () => SpecialRole.none,
      ),
      roleData:
          (json['roleData'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Role Assigner
// ═══════════════════════════════════════════════════════════════════════════

/// Assigns special roles to players for Nightmare mode rounds.
class RoleAssigner {
  RoleAssigner._(); // Prevent instantiation

  /// Assign special roles to non-Mimic players.
  ///
  /// - [innocentPlayerIds]: List of player IDs who are NOT mimics.
  /// - [mimicPlayerIds]: List of Mimic player IDs (for exclusion).
  /// - [realWord]: The real word for this round (needed for Informant hint).
  ///
  /// Returns a list of [RoleAssignment]s for all players.
  /// Each innocent gets one role (or none if there aren't enough players).
  /// Mimics always receive [SpecialRole.none].
  static List<RoleAssignment> assignRoles({
    required List<String> innocentPlayerIds,
    required List<String> mimicPlayerIds,
    required String realWord,
  }) {
    final random = math.Random();
    final assignments = <RoleAssignment>[];

    // Mimics get no special role
    for (final mimicId in mimicPlayerIds) {
      assignments.add(RoleAssignment(
        playerId: mimicId,
        role: SpecialRole.none,
      ));
    }

    if (innocentPlayerIds.isEmpty) return assignments;

    // Available roles to distribute (excluding none)
    final availableRoles = [
      SpecialRole.informant,
      SpecialRole.paranoid,
      SpecialRole.ally,
    ];

    // Shuffle innocents for random assignment
    final shuffledInnocents = List<String>.from(innocentPlayerIds)
      ..shuffle(random);

    for (int i = 0; i < shuffledInnocents.length; i++) {
      final playerId = shuffledInnocents[i];

      if (i < availableRoles.length) {
        final role = availableRoles[i];
        final roleData = _generateRoleData(
          role: role,
          playerId: playerId,
          innocentPlayerIds: innocentPlayerIds,
          realWord: realWord,
          random: random,
        );

        assignments.add(RoleAssignment(
          playerId: playerId,
          role: role,
          roleData: roleData,
        ));
      } else {
        // More innocents than roles — extras get no special role
        assignments.add(RoleAssignment(
          playerId: playerId,
          role: SpecialRole.none,
        ));
      }
    }

    return assignments;
  }

  /// Generate role-specific data for a given role assignment.
  static Map<String, dynamic> _generateRoleData({
    required SpecialRole role,
    required String playerId,
    required List<String> innocentPlayerIds,
    required String realWord,
    required math.Random random,
  }) {
    switch (role) {
      case SpecialRole.informant:
        return _generateInformantData(realWord, random);
      case SpecialRole.paranoid:
        return _generateParanoidData(innocentPlayerIds, playerId, random);
      case SpecialRole.ally:
        return _generateAllyData(innocentPlayerIds, playerId, random);
      case SpecialRole.none:
        return {};
    }
  }

  /// Generate Informant hint: one random letter from the real word.
  static Map<String, dynamic> _generateInformantData(
    String realWord,
    math.Random random,
  ) {
    if (realWord.isEmpty) return {};

    final position = random.nextInt(realWord.length);
    final letter = realWord[position].toUpperCase();

    return {
      'letter': letter,
      'position': position,
    };
  }

  /// Generate Paranoid fake suspicion indicators.
  static Map<String, dynamic> _generateParanoidData(
    List<String> innocentPlayerIds,
    String paranoidPlayerId,
    math.Random random,
  ) {
    final fakeSuspicions = <String, double>{};
    for (final pid in innocentPlayerIds) {
      if (pid != paranoidPlayerId) {
        // Generate misleading suspicion values (higher than normal)
        fakeSuspicions[pid] = 0.3 + random.nextDouble() * 0.6;
      }
    }
    return {'fakeSuspicions': fakeSuspicions};
  }

  /// Generate Ally data: pick one other confirmed innocent player.
  static Map<String, dynamic> _generateAllyData(
    List<String> innocentPlayerIds,
    String allyPlayerId,
    math.Random random,
  ) {
    final otherInnocents =
        innocentPlayerIds.where((id) => id != allyPlayerId).toList();
    if (otherInnocents.isEmpty) return {};

    final allyTarget = otherInnocents[random.nextInt(otherInnocents.length)];
    return {'allyPlayerId': allyTarget};
  }
}
