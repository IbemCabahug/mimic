// lib/game/data/word_packs.dart
import 'package:flutter/material.dart';

class WordPair {
  final String realWord;
  final String mimicWord;

  const WordPair({
    required this.realWord,
    required this.mimicWord,
  });
}

class WordPack {
  final String id;
  final String name;
  final String description;
  final String category;
  final IconData icon;
  final List<WordPair> pairs;

  const WordPack({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.icon,
    required this.pairs,
  });
}

class WordPackData {
  static const List<WordPack> packs = [
    // 1. Dark Places
    WordPack(
      id: 'dark_places',
      name: 'Dark Places',
      description: 'Sinister locations, haunted buildings, and forgotten corners of dread.',
      category: 'Locations',
      icon: Icons.domain_disabled_outlined,
      pairs: [
        WordPair(realWord: 'Cemetery', mimicWord: 'Garden'),
        WordPair(realWord: 'Crypt', mimicWord: 'Basement'),
        WordPair(realWord: 'Asylum', mimicWord: 'Hospital'),
        WordPair(realWord: 'Mausoleum', mimicWord: 'Library'),
        WordPair(realWord: 'Catacombs', mimicWord: 'Tunnel'),
        WordPair(realWord: 'Morgue', mimicWord: 'Coldroom'),
        WordPair(realWord: 'Cabin', mimicWord: 'Cottage'),
        WordPair(realWord: 'Swamp', mimicWord: 'Lake'),
        WordPair(realWord: 'Attic', mimicWord: 'Storeroom'),
        WordPair(realWord: 'Graveyard', mimicWord: 'Park'),
        WordPair(realWord: 'Dungeon', mimicWord: 'Prison'),
        WordPair(realWord: 'Lighthouse', mimicWord: 'Watchtower'),
        WordPair(realWord: 'Maze', mimicWord: 'Garden'),
        WordPair(realWord: 'Forest', mimicWord: 'Woods'),
        WordPair(realWord: 'Abattoir', mimicWord: 'Kitchen'),
        WordPair(realWord: 'Mine', mimicWord: 'Cave'),
        WordPair(realWord: 'Ruins', mimicWord: 'Castle'),
        WordPair(realWord: 'Sewer', mimicWord: 'Pipeline'),
        WordPair(realWord: 'Ghost Town', mimicWord: 'Village'),
        WordPair(realWord: 'Vault', mimicWord: 'Safe'),
      ],
    ),

    // 2. The Occult
    WordPack(
      id: 'the_occult',
      name: 'The Occult',
      description: 'Forbidden rituals, dark magic, and supernatural forces.',
      category: 'Supernatural',
      icon: Icons.auto_awesome_sharp,
      pairs: [
        WordPair(realWord: 'Séance', mimicWord: 'Meeting'),
        WordPair(realWord: 'Ritual', mimicWord: 'Ceremony'),
        WordPair(realWord: 'Coven', mimicWord: 'Club'),
        WordPair(realWord: 'Grimoire', mimicWord: 'Diary'),
        WordPair(realWord: 'Pentagram', mimicWord: 'Star'),
        WordPair(realWord: 'Curse', mimicWord: 'Bad Luck'),
        WordPair(realWord: 'Daemon', mimicWord: 'Shadow'),
        WordPair(realWord: 'Spell', mimicWord: 'Wish'),
        WordPair(realWord: 'Altar', mimicWord: 'Table'),
        WordPair(realWord: 'Sacrificing', mimicWord: 'Donation'),
        WordPair(realWord: 'Exorcism', mimicWord: 'Cleansing'),
        WordPair(realWord: 'Tarot', mimicWord: 'Card'),
        WordPair(realWord: 'Chalice', mimicWord: 'Cup'),
        WordPair(realWord: 'Amulet', mimicWord: 'Jewelry'),
        WordPair(realWord: 'Ghost', mimicWord: 'Illusion'),
        WordPair(realWord: 'Poltergeist', mimicWord: 'Breeze'),
        WordPair(realWord: 'Cauldron', mimicWord: 'Pot'),
        WordPair(realWord: 'Talisman', mimicWord: 'Keychain'),
        WordPair(realWord: 'Necromancy', mimicWord: 'History'),
        WordPair(realWord: 'Warlock', mimicWord: 'Magician'),
      ],
    ),

    // 3. Crime Scene
    WordPack(
      id: 'crime_scene',
      name: 'Crime Scene',
      description: 'Murder mysteries, detective clues, and cold-blooded conspiracies.',
      category: 'Thriller',
      icon: Icons.search_off_outlined,
      pairs: [
        WordPair(realWord: 'Alibi', mimicWord: 'Excuse'),
        WordPair(realWord: 'Evidence', mimicWord: 'Clue'),
        WordPair(realWord: 'Suspect', mimicWord: 'Stranger'),
        WordPair(realWord: 'Murder', mimicWord: 'Accident'),
        WordPair(realWord: 'Poison', mimicWord: 'Medicine'),
        WordPair(realWord: 'Weapon', mimicWord: 'Tool'),
        WordPair(realWord: 'Blood', mimicWord: 'Paint'),
        WordPair(realWord: 'Victim', mimicWord: 'Patient'),
        WordPair(realWord: 'Footprint', mimicWord: 'Dirt'),
        WordPair(realWord: 'Autopsy', mimicWord: 'Checkup'),
        WordPair(realWord: 'Detective', mimicWord: 'Officer'),
        WordPair(realWord: 'Crime Scene', mimicWord: 'Room'),
        WordPair(realWord: 'Motive', mimicWord: 'Reason'),
        WordPair(realWord: 'Witness', mimicWord: 'Bystander'),
        WordPair(realWord: 'Corpse', mimicWord: 'Dummy'),
        WordPair(realWord: 'Fingerprint', mimicWord: 'Smudge'),
        WordPair(realWord: 'Blackmail', mimicWord: 'Letter'),
        WordPair(realWord: 'Kidnapping', mimicWord: 'Visit'),
        WordPair(realWord: 'Cyanide', mimicWord: 'Sugar'),
        WordPair(realWord: 'Ransom', mimicWord: 'Payment'),
      ],
    ),

    // 4. Survival Horror
    WordPack(
      id: 'survival_horror',
      name: 'Survival Horror',
      description: 'Apocalypse tools, infected entities, and narrow escapes.',
      category: 'Survival',
      icon: Icons.running_with_errors_outlined,
      pairs: [
        WordPair(realWord: 'Zombie', mimicWord: 'Sick Person'),
        WordPair(realWord: 'Bunker', mimicWord: 'Shelter'),
        WordPair(realWord: 'Trap', mimicWord: 'Obstacle'),
        WordPair(realWord: 'Flashlight', mimicWord: 'Candle'),
        WordPair(realWord: 'Key', mimicWord: 'Lock'),
        WordPair(realWord: 'Serum', mimicWord: 'Vaccine'),
        WordPair(realWord: 'Shotgun', mimicWord: 'Pistol'),
        WordPair(realWord: 'Radio', mimicWord: 'Phone'),
        WordPair(realWord: 'Fog', mimicWord: 'Cloud'),
        WordPair(realWord: 'Monster', mimicWord: 'Animal'),
        WordPair(realWord: 'Safe Room', mimicWord: 'Bedroom'),
        WordPair(realWord: 'Infection', mimicWord: 'Disease'),
        WordPair(realWord: 'Bandage', mimicWord: 'Tape'),
        WordPair(realWord: 'Generator', mimicWord: 'Engine'),
        WordPair(realWord: 'Chainsaw', mimicWord: 'Cutter'),
        WordPair(realWord: 'Panic', mimicWord: 'Scare'),
        WordPair(realWord: 'Rations', mimicWord: 'Food'),
        WordPair(realWord: 'Barricade', mimicWord: 'Door'),
        WordPair(realWord: 'Flare', mimicWord: 'Torch'),
        WordPair(realWord: 'Mutation', mimicWord: 'Scar'),
      ],
    ),

    // 5. Everyday Dread
    WordPack(
      id: 'everyday_dread',
      name: 'Everyday Dread',
      description: 'Mundane fears, psychological terrors, and domestic anxieties.',
      category: 'Psychological',
      icon: Icons.remove_red_eye_outlined,
      pairs: [
        WordPair(realWord: 'Insomnia', mimicWord: 'Tiredness'),
        WordPair(realWord: 'Paranoia', mimicWord: 'Anxiety'),
        WordPair(realWord: 'Shadow', mimicWord: 'Silhouette'),
        WordPair(realWord: 'Nightmare', mimicWord: 'Dream'),
        WordPair(realWord: 'Whispers', mimicWord: 'Murmurs'),
        WordPair(realWord: 'Doppelganger', mimicWord: 'Twin'),
        WordPair(realWord: 'Stalker', mimicWord: 'Fan'),
        WordPair(realWord: 'Decay', mimicWord: 'Rust'),
        WordPair(realWord: 'Reflection', mimicWord: 'Mirror'),
        WordPair(realWord: 'Isolation', mimicWord: 'Loneliness'),
        WordPair(realWord: 'Static', mimicWord: 'White Noise'),
        WordPair(realWord: 'Intruder', mimicWord: 'Guest'),
        WordPair(realWord: 'Hallucination', mimicWord: 'Mirage'),
        WordPair(realWord: 'Darkness', mimicWord: 'Dimness'),
        WordPair(realWord: 'Abyss', mimicWord: 'Hole'),
        WordPair(realWord: 'Obsession', mimicWord: 'Hobby'),
        WordPair(realWord: 'Phobia', mimicWord: 'Fear'),
        WordPair(realWord: 'Cold Spot', mimicWord: 'Draft'),
        WordPair(realWord: 'Glitch', mimicWord: 'Error'),
        WordPair(realWord: 'Premonition', mimicWord: 'Thought'),
      ],
    ),
  ];
}
