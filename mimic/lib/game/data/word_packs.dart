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

  static const List<String> supportedLanguages = ['en', 'fil', 'ceb'];

  static const Map<String, List<WordPair>> _filPairs = {
    'dark_places': [
      WordPair(realWord: 'Sementeryo', mimicWord: 'Hardin'),        // Cemetery / Garden
      WordPair(realWord: 'Nitso', mimicWord: 'Silong'),             // Crypt / Basement
      WordPair(realWord: 'Mental', mimicWord: 'Ospital'),           // Asylum / Hospital
      WordPair(realWord: 'Mawsoleo', mimicWord: 'Aklatan'),         // Mausoleum / Library
      WordPair(realWord: 'Katakumba', mimicWord: 'Lagusan'),        // Catacombs / Tunnel
      WordPair(realWord: 'Morge', mimicWord: 'Freezer'),            // Morgue / Coldroom
      WordPair(realWord: 'Kabin', mimicWord: 'Kubo'),               // Cabin / Cottage
      WordPair(realWord: 'Latian', mimicWord: 'Lawa'),              // Swamp / Lake
      WordPair(realWord: 'Attic', mimicWord: 'Bodega'),             // Attic / Storeroom
      WordPair(realWord: 'Libingan', mimicWord: 'Parke'),           // Graveyard / Park
      WordPair(realWord: 'Piitan', mimicWord: 'Bilangguan'),        // Dungeon / Prison
      WordPair(realWord: 'Parola', mimicWord: 'Bantayan'),          // Lighthouse / Watchtower
      WordPair(realWord: 'Labirinto', mimicWord: 'Hardin'),         // Maze / Garden
      WordPair(realWord: 'Gubat', mimicWord: 'Kakahuyan'),          // Forest / Woods
      WordPair(realWord: 'Katayan', mimicWord: 'Kusina'),           // Abattoir / Kitchen
      WordPair(realWord: 'Minahan', mimicWord: 'Kuweba'),           // Mine / Cave
      WordPair(realWord: 'Guho', mimicWord: 'Kastilyo'),            // Ruins / Castle
      WordPair(realWord: 'Imburnal', mimicWord: 'Tubo'),            // Sewer / Pipeline
      WordPair(realWord: 'Bayan ng Multo', mimicWord: 'Baryo'),     // Ghost Town / Village
      WordPair(realWord: 'Bobeda', mimicWord: 'Kaha'),              // Vault / Safe
    ],
    'the_occult': [
      WordPair(realWord: 'Seance', mimicWord: 'Pagpupulong'),       // Séance / Meeting
      WordPair(realWord: 'Ritwal', mimicWord: 'Seremonya'),         // Ritual / Ceremony
      WordPair(realWord: 'Kulto', mimicWord: 'Klub'),               // Coven / Club
      WordPair(realWord: 'Aklat-Mahika', mimicWord: 'Talaarawan'),  // Grimoire / Diary
      WordPair(realWord: 'Pentagrama', mimicWord: 'Bituin'),        // Pentagram / Star
      WordPair(realWord: 'Sumpa', mimicWord: 'Malas'),              // Curse / Bad Luck
      WordPair(realWord: 'Demonyo', mimicWord: 'Anino'),            // Daemon / Shadow
      WordPair(realWord: 'Kulam', mimicWord: 'Hiling'),             // Spell / Wish
      WordPair(realWord: 'Altar', mimicWord: 'Mesa'),               // Altar / Table
      WordPair(realWord: 'Pag-aalay', mimicWord: 'Donasyon'),       // Sacrificing / Donation
      WordPair(realWord: 'Eksorsismo', mimicWord: 'Paglilinis'),    // Exorcism / Cleansing
      WordPair(realWord: 'Tarot', mimicWord: 'Baraha'),             // Tarot / Card
      WordPair(realWord: 'Kalis', mimicWord: 'Tasa'),               // Chalice / Cup
      WordPair(realWord: 'Anting-anting', mimicWord: 'Alahas'),     // Amulet / Jewelry
      WordPair(realWord: 'Multo', mimicWord: 'Ilusyon'),            // Ghost / Illusion
      WordPair(realWord: 'Poltergeist', mimicWord: 'Simoy'),        // Poltergeist / Breeze
      WordPair(realWord: 'Kaldero', mimicWord: 'Palayok'),          // Cauldron / Pot
      WordPair(realWord: 'Agimat', mimicWord: 'Keychain'),          // Talisman / Keychain
      WordPair(realWord: 'Nekromansya', mimicWord: 'Kasaysayan'),   // Necromancy / History
      WordPair(realWord: 'Mangkukulam', mimicWord: 'Salamangkero'), // Warlock / Magician
    ],
    'crime_scene': [
      WordPair(realWord: 'Alibi', mimicWord: 'Dahilan'),            // Alibi / Excuse
      WordPair(realWord: 'Ebidensya', mimicWord: 'Palatandaan'),    // Evidence / Clue
      WordPair(realWord: 'Suspetsado', mimicWord: 'Estranghero'),   // Suspect / Stranger
      WordPair(realWord: 'Pagpaslang', mimicWord: 'Aksidente'),     // Murder / Accident
      WordPair(realWord: 'Lason', mimicWord: 'Gamot'),              // Poison / Medicine
      WordPair(realWord: 'Sandata', mimicWord: 'Kasangkapan'),      // Weapon / Tool
      WordPair(realWord: 'Dugo', mimicWord: 'Pintura'),             // Blood / Paint
      WordPair(realWord: 'Biktima', mimicWord: 'Pasyente'),         // Victim / Patient
      WordPair(realWord: 'Bakas ng Paa', mimicWord: 'Dumi'),        // Footprint / Dirt
      WordPair(realWord: 'Autopsiya', mimicWord: 'Tsekap'),         // Autopsy / Checkup
      WordPair(realWord: 'Detektib', mimicWord: 'Pulis'),           // Detective / Officer
      WordPair(realWord: 'Pinangyarihan', mimicWord: 'Silid'),      // Crime Scene / Room
      WordPair(realWord: 'Motibo', mimicWord: 'Rason'),             // Motive / Reason
      WordPair(realWord: 'Saksi', mimicWord: 'Tagamasid'),          // Witness / Bystander
      WordPair(realWord: 'Bangkay', mimicWord: 'Manyika'),          // Corpse / Dummy
      WordPair(realWord: 'Bakas ng Daliri', mimicWord: 'Mantsa'),   // Fingerprint / Smudge
      WordPair(realWord: 'Pangingikil', mimicWord: 'Sulat'),        // Blackmail / Letter
      WordPair(realWord: 'Pagdukot', mimicWord: 'Pagbisita'),       // Kidnapping / Visit
      WordPair(realWord: 'Cyanide', mimicWord: 'Asukal'),           // Cyanide / Sugar
      WordPair(realWord: 'Pantubos', mimicWord: 'Bayad'),           // Ransom / Payment
    ],
    'survival_horror': [
      WordPair(realWord: 'Zombie', mimicWord: 'May Sakit'),         // Zombie / Sick Person
      WordPair(realWord: 'Bunker', mimicWord: 'Silungan'),          // Bunker / Shelter
      WordPair(realWord: 'Bitag', mimicWord: 'Sagabal'),            // Trap / Obstacle
      WordPair(realWord: 'Flashlight', mimicWord: 'Kandila'),       // Flashlight / Candle
      WordPair(realWord: 'Susi', mimicWord: 'Kandado'),             // Key / Lock
      WordPair(realWord: 'Serum', mimicWord: 'Bakuna'),             // Serum / Vaccine
      WordPair(realWord: 'Eskopeta', mimicWord: 'Pistola'),         // Shotgun / Pistol
      WordPair(realWord: 'Radyo', mimicWord: 'Telepono'),           // Radio / Phone
      WordPair(realWord: 'Hamog', mimicWord: 'Ulap'),               // Fog / Cloud
      WordPair(realWord: 'Halimaw', mimicWord: 'Hayop'),            // Monster / Animal
      WordPair(realWord: 'Ligtas na Silid', mimicWord: 'Kwarto'),   // Safe Room / Bedroom
      WordPair(realWord: 'Impeksyon', mimicWord: 'Sakit'),          // Infection / Disease
      WordPair(realWord: 'Benda', mimicWord: 'Teyp'),               // Bandage / Tape
      WordPair(realWord: 'Generator', mimicWord: 'Makina'),         // Generator / Engine
      WordPair(realWord: 'Chainsaw', mimicWord: 'Pamutol'),         // Chainsaw / Cutter
      WordPair(realWord: 'Pagkasindak', mimicWord: 'Takot'),        // Panic / Scare
      WordPair(realWord: 'Rasyon', mimicWord: 'Pagkain'),           // Rations / Food
      WordPair(realWord: 'Barikada', mimicWord: 'Pinto'),           // Barricade / Door
      WordPair(realWord: 'Flare', mimicWord: 'Sulo'),               // Flare / Torch
      WordPair(realWord: 'Mutasyon', mimicWord: 'Peklat'),          // Mutation / Scar
    ],
    'everyday_dread': [
      WordPair(realWord: 'Insomnia', mimicWord: 'Pagkapagod'),      // Insomnia / Tiredness
      WordPair(realWord: 'Paranoya', mimicWord: 'Pagkabalisa'),     // Paranoia / Anxiety
      WordPair(realWord: 'Anino', mimicWord: 'Silweta'),            // Shadow / Silhouette
      WordPair(realWord: 'Bangungot', mimicWord: 'Panaginip'),      // Nightmare / Dream
      WordPair(realWord: 'Bulong', mimicWord: 'Ungol'),             // Whispers / Murmurs
      WordPair(realWord: 'Doppelganger', mimicWord: 'Kambal'),      // Doppelganger / Twin
      WordPair(realWord: 'Stalker', mimicWord: 'Tagahanga'),        // Stalker / Fan
      WordPair(realWord: 'Pagkabulok', mimicWord: 'Kalawang'),      // Decay / Rust
      WordPair(realWord: 'Repleksyon', mimicWord: 'Salamin'),       // Reflection / Mirror
      WordPair(realWord: 'Pag-iisa', mimicWord: 'Kalungkutan'),     // Isolation / Loneliness
      WordPair(realWord: 'Static', mimicWord: 'Ingay'),             // Static / White Noise
      WordPair(realWord: 'Manloloob', mimicWord: 'Bisita'),         // Intruder / Guest
      WordPair(realWord: 'Halusinasyon', mimicWord: 'Malikmata'),   // Hallucination / Mirage
      WordPair(realWord: 'Dilim', mimicWord: 'Lamlam'),             // Darkness / Dimness
      WordPair(realWord: 'Bangin', mimicWord: 'Butas'),             // Abyss / Hole
      WordPair(realWord: 'Obsesyon', mimicWord: 'Libangan'),        // Obsession / Hobby
      WordPair(realWord: 'Pobya', mimicWord: 'Takot'),              // Phobia / Fear
      WordPair(realWord: 'Malamig na Lugar', mimicWord: 'Simoy'),   // Cold Spot / Draft
      WordPair(realWord: 'Glitch', mimicWord: 'Mali'),              // Glitch / Error
      WordPair(realWord: 'Kutob', mimicWord: 'Isip'),               // Premonition / Thought
    ],
  };

  static const Map<String, List<WordPair>> _cebPairs = {
    'dark_places': [
      WordPair(realWord: 'Sementeryo', mimicWord: 'Tanaman'),       // Cemetery / Garden
      WordPair(realWord: 'Nitso', mimicWord: 'Silong'),             // Crypt / Basement
      WordPair(realWord: 'Mental', mimicWord: 'Ospital'),           // Asylum / Hospital
      WordPair(realWord: 'Mawsoleo', mimicWord: 'Librarya'),        // Mausoleum / Library
      WordPair(realWord: 'Katakumba', mimicWord: 'Tunel'),          // Catacombs / Tunnel
      WordPair(realWord: 'Morge', mimicWord: 'Freezer'),            // Morgue / Coldroom
      WordPair(realWord: 'Kabin', mimicWord: 'Payag'),              // Cabin / Cottage
      WordPair(realWord: 'Lamakan', mimicWord: 'Lanaw'),            // Swamp / Lake
      WordPair(realWord: 'Attic', mimicWord: 'Bodega'),             // Attic / Storeroom
      WordPair(realWord: 'Lubnganan', mimicWord: 'Parke'),          // Graveyard / Park
      WordPair(realWord: 'Piitan', mimicWord: 'Bilanggoan'),        // Dungeon / Prison
      WordPair(realWord: 'Parola', mimicWord: 'Bantayan'),          // Lighthouse / Watchtower
      WordPair(realWord: 'Labirinto', mimicWord: 'Tanaman'),        // Maze / Garden
      WordPair(realWord: 'Lasang', mimicWord: 'Kakahoyan'),         // Forest / Woods
      WordPair(realWord: 'Katayanan', mimicWord: 'Kusina'),         // Abattoir / Kitchen
      WordPair(realWord: 'Minahan', mimicWord: 'Langub'),           // Mine / Cave
      WordPair(realWord: 'Kagun-oban', mimicWord: 'Kastilyo'),      // Ruins / Castle
      WordPair(realWord: 'Imburnal', mimicWord: 'Tubo'),            // Sewer / Pipeline
      WordPair(realWord: 'Lungsod sa Multo', mimicWord: 'Baryo'),   // Ghost Town / Village
      WordPair(realWord: 'Bobeda', mimicWord: 'Kaha'),              // Vault / Safe
    ],
    'the_occult': [
      WordPair(realWord: 'Seance', mimicWord: 'Tigom'),             // Séance / Meeting
      WordPair(realWord: 'Ritwal', mimicWord: 'Seremonya'),         // Ritual / Ceremony
      WordPair(realWord: 'Kulto', mimicWord: 'Klub'),               // Coven / Club
      WordPair(realWord: 'Libro sa Salamangka', mimicWord: 'Talaadlawan'), // Grimoire / Diary
      WordPair(realWord: 'Pentagrama', mimicWord: 'Bituon'),        // Pentagram / Star
      WordPair(realWord: 'Tunglo', mimicWord: 'Malas'),             // Curse / Bad Luck
      WordPair(realWord: 'Demonyo', mimicWord: 'Landong'),          // Daemon / Shadow
      WordPair(realWord: 'Barang', mimicWord: 'Pangandoy'),         // Spell / Wish
      WordPair(realWord: 'Altar', mimicWord: 'Lamesa'),             // Altar / Table
      WordPair(realWord: 'Halad', mimicWord: 'Donasyon'),           // Sacrificing / Donation
      WordPair(realWord: 'Eksorsismo', mimicWord: 'Paghinlo'),      // Exorcism / Cleansing
      WordPair(realWord: 'Tarot', mimicWord: 'Baraha'),             // Tarot / Card
      WordPair(realWord: 'Kalis', mimicWord: 'Tasa'),               // Chalice / Cup
      WordPair(realWord: 'Anting-anting', mimicWord: 'Alahas'),     // Amulet / Jewelry
      WordPair(realWord: 'Multo', mimicWord: 'Ilusyon'),            // Ghost / Illusion
      WordPair(realWord: 'Poltergeist', mimicWord: 'Huyohoy'),      // Poltergeist / Breeze
      WordPair(realWord: 'Kaldero', mimicWord: 'Kulon'),            // Cauldron / Pot
      WordPair(realWord: 'Agimat', mimicWord: 'Keychain'),          // Talisman / Keychain
      WordPair(realWord: 'Nekromansya', mimicWord: 'Kasaysayan'),   // Necromancy / History
      WordPair(realWord: 'Mamarang', mimicWord: 'Salamangkero'),    // Warlock / Magician
    ],
    'crime_scene': [
      WordPair(realWord: 'Alibi', mimicWord: 'Pasangil'),           // Alibi / Excuse
      WordPair(realWord: 'Ebidensya', mimicWord: 'Timailhan'),      // Evidence / Clue
      WordPair(realWord: 'Suspetsado', mimicWord: 'Estranghero'),   // Suspect / Stranger
      WordPair(realWord: 'Pagpatay', mimicWord: 'Aksidente'),       // Murder / Accident
      WordPair(realWord: 'Hilo', mimicWord: 'Tambal'),              // Poison / Medicine
      WordPair(realWord: 'Hinagiban', mimicWord: 'Galamiton'),      // Weapon / Tool
      WordPair(realWord: 'Dugo', mimicWord: 'Pintura'),             // Blood / Paint
      WordPair(realWord: 'Biktima', mimicWord: 'Pasyente'),         // Victim / Patient
      WordPair(realWord: 'Tunob', mimicWord: 'Hugaw'),              // Footprint / Dirt
      WordPair(realWord: 'Autopsiya', mimicWord: 'Checkup'),        // Autopsy / Checkup
      WordPair(realWord: 'Detektib', mimicWord: 'Pulis'),           // Detective / Officer
      WordPair(realWord: 'Dapit sa Krimen', mimicWord: 'Kwarto'),   // Crime Scene / Room
      WordPair(realWord: 'Motibo', mimicWord: 'Hinungdan'),         // Motive / Reason
      WordPair(realWord: 'Saksi', mimicWord: 'Tigtan-aw'),          // Witness / Bystander
      WordPair(realWord: 'Minatay', mimicWord: 'Manika'),           // Corpse / Dummy
      WordPair(realWord: 'Marka sa Tudlo', mimicWord: 'Mansa'),     // Fingerprint / Smudge
      WordPair(realWord: 'Pangilkil', mimicWord: 'Sulat'),          // Blackmail / Letter
      WordPair(realWord: 'Pagdagit', mimicWord: 'Pagbisita'),       // Kidnapping / Visit
      WordPair(realWord: 'Cyanide', mimicWord: 'Asukar'),           // Cyanide / Sugar
      WordPair(realWord: 'Lukat', mimicWord: 'Bayad'),              // Ransom / Payment
    ],
    'survival_horror': [
      WordPair(realWord: 'Zombie', mimicWord: 'Masakiton'),         // Zombie / Sick Person
      WordPair(realWord: 'Bunker', mimicWord: 'Silonganan'),        // Bunker / Shelter
      WordPair(realWord: 'Lit-ag', mimicWord: 'Babag'),             // Trap / Obstacle
      WordPair(realWord: 'Flashlight', mimicWord: 'Kandila'),       // Flashlight / Candle
      WordPair(realWord: 'Yawi', mimicWord: 'Kandado'),             // Key / Lock
      WordPair(realWord: 'Serum', mimicWord: 'Bakuna'),             // Serum / Vaccine
      WordPair(realWord: 'Eskopeta', mimicWord: 'Pistola'),         // Shotgun / Pistol
      WordPair(realWord: 'Radyo', mimicWord: 'Telepono'),           // Radio / Phone
      WordPair(realWord: 'Gabon', mimicWord: 'Panganod'),           // Fog / Cloud
      WordPair(realWord: 'Halimaw', mimicWord: 'Hayop'),            // Monster / Animal
      WordPair(realWord: 'Luwas nga Kwarto', mimicWord: 'Tulganan'),// Safe Room / Bedroom
      WordPair(realWord: 'Impeksyon', mimicWord: 'Sakit'),          // Infection / Disease
      WordPair(realWord: 'Benda', mimicWord: 'Teyp'),               // Bandage / Tape
      WordPair(realWord: 'Generator', mimicWord: 'Makina'),         // Generator / Engine
      WordPair(realWord: 'Chainsaw', mimicWord: 'Pamutol'),         // Chainsaw / Cutter
      WordPair(realWord: 'Kalisang', mimicWord: 'Kahadlok'),        // Panic / Scare
      WordPair(realWord: 'Rasyon', mimicWord: 'Pagkaon'),           // Rations / Food
      WordPair(realWord: 'Barikada', mimicWord: 'Pultahan'),        // Barricade / Door
      WordPair(realWord: 'Flare', mimicWord: 'Sulo'),               // Flare / Torch
      WordPair(realWord: 'Mutasyon', mimicWord: 'Uwat'),            // Mutation / Scar
    ],
    'everyday_dread': [
      WordPair(realWord: 'Insomnia', mimicWord: 'Kakapoy'),         // Insomnia / Tiredness
      WordPair(realWord: 'Paranoya', mimicWord: 'Kabalaka'),        // Paranoia / Anxiety
      WordPair(realWord: 'Landong', mimicWord: 'Silweta'),          // Shadow / Silhouette
      WordPair(realWord: 'Bangungot', mimicWord: 'Damgo'),          // Nightmare / Dream
      WordPair(realWord: 'Hunghong', mimicWord: 'Bagulbol'),        // Whispers / Murmurs
      WordPair(realWord: 'Doppelganger', mimicWord: 'Kaluha'),      // Doppelganger / Twin
      WordPair(realWord: 'Stalker', mimicWord: 'Fan'),              // Stalker / Fan
      WordPair(realWord: 'Pagkadunot', mimicWord: 'Taya'),          // Decay / Rust
      WordPair(realWord: 'Repleksyon', mimicWord: 'Samin'),         // Reflection / Mirror
      WordPair(realWord: 'Pag-inusara', mimicWord: 'Kamingaw'),     // Isolation / Loneliness
      WordPair(realWord: 'Static', mimicWord: 'Saba'),              // Static / White Noise
      WordPair(realWord: 'Manunulod', mimicWord: 'Bisita'),         // Intruder / Guest
      WordPair(realWord: 'Halusinasyon', mimicWord: 'Malikmata'),   // Hallucination / Mirage
      WordPair(realWord: 'Kangitngit', mimicWord: 'Hanap'),         // Darkness / Dimness
      WordPair(realWord: 'Bung-aw', mimicWord: 'Lungag'),           // Abyss / Hole
      WordPair(realWord: 'Obsesyon', mimicWord: 'Kalingawan'),      // Obsession / Hobby
      WordPair(realWord: 'Pobya', mimicWord: 'Kahadlok'),           // Phobia / Fear
      WordPair(realWord: 'Bugnaw nga Dapit', mimicWord: 'Huyohoy'), // Cold Spot / Draft
      WordPair(realWord: 'Glitch', mimicWord: 'Sayop'),             // Glitch / Error
      WordPair(realWord: 'Kutob', mimicWord: 'Hunahuna'),           // Premonition / Thought
    ],
  };

  /// Returns the pack list for the given language code ('en', 'fil', 'ceb').
  /// English metadata (id/name/description/category/icon) is preserved; only the
  /// word pairs are swapped. Falls back to English pairs for any missing pack.
  static List<WordPack> getPacksForLanguage(String code) {
    if (code == 'en') return packs;
    final Map<String, List<WordPair>>? langMap =
        code == 'fil' ? _filPairs : (code == 'ceb' ? _cebPairs : null);
    if (langMap == null) return packs;
    return packs.map((p) {
      final localized = langMap[p.id];
      return WordPack(
        id: p.id,
        name: p.name,
        description: p.description,
        category: p.category,
        icon: p.icon,
        pairs: (localized == null || localized.isEmpty) ? p.pairs : localized,
      );
    }).toList();
  }
}
