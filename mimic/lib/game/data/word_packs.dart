// lib/game/data/word_packs.dart
import 'package:flutter/material.dart';

class WordPair {
  final String realWord;
  final String mimicWord;

  /// GENERALIZED describing angles for the real word — the FREE tier.
  /// Mood, category, and how people behave around it: enough to unstick a
  /// player with nothing to say, but deliberately not the signature props,
  /// because a too-specific blurb is the answer recited back — the table
  /// solves the word from the description alone. Authored per pair, never
  /// containing the word itself nor its twin (word_context_test enforces
  /// both). Every free blurb ends in a describing nudge (Describe...,
  /// Talk about...) — the shape the tier tests pin down).
  ///
  /// Empty for pairs that have not been authored; the info button hides.
  final String realWordContext;

  /// Same, for the mimic word — the Mimic gets equal-quality help for
  /// their own word, and nothing about the word they are pretending to
  /// have.
  ///
  /// Contexts are written in ENGLISH for every language pack (owner's
  /// call — localized context text reads as "cringe" to Filipino and
  /// Cebuano players; their pairs inherit these English definitions at
  /// pack-merge time, see getPacksForLanguage). The same anti-leak rules
  /// apply: never the word itself, never its twin, in any language.
  final String mimicWordContext;

  /// DETAILED describing angles — the PRO tier: the concrete props,
  /// sensory specifics and vivid scene details the free tier withholds.
  /// Falls back to the free tier when empty (pairs synced from older
  /// peers carry only the free fields).
  final String realWordProContext;

  /// Same, for the mimic word.
  final String mimicWordProContext;

  const WordPair({
    required this.realWord,
    required this.mimicWord,
    this.realWordContext = '',
    this.mimicWordContext = '',
    this.realWordProContext = '',
    this.mimicWordProContext = '',
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
        WordPair(
          realWord: 'Cemetery',
          mimicWord: 'Garden',
          realWordContext:
              'A quiet outdoor place nobody visits for fun. Set the heavy mood and why people keep their voices low there.',
          mimicWordContext:
              'A green, living space someone tends on purpose, and it shows. Describe the care it needs and the calm it gives.',
          realWordProContext:
              'Rows of carved stone markers under grey skies, fresh flowers left by mourners, iron gates, quiet paths where visitors speak in hushed voices.',
          mimicWordProContext:
              'Tended beds of blooms and vegetables, a trowel and a watering can, buzzing bees, dirt under the fingernails after an afternoon of planting.',
        ),
        WordPair(
          realWord: 'Crypt',
          mimicWord: 'Basement',
          realWordContext:
              'A stone resting spot below the main floor, old and hushed. Describe the chill and why people rarely linger.',
          mimicWordContext:
              'The lower level of a house, cooler and darker than the rest. Talk about what gets kept down there.',
          realWordProContext:
              'Stone chambers beneath old churches, coffins stacked in niches, cold stale air, carved names above sealed shelves.',
          mimicWordProContext:
              'The lowest floor of a house, concrete steps leading down, storage boxes, a boiler humming in the corner.',
        ),
        WordPair(
          realWord: 'Asylum',
          mimicWord: 'Hospital',
          realWordContext:
              'A big institution for minds that needed help, remembered more for its dark reputation. Describe how such places feel.',
          mimicWordContext:
              'A place you go when the body fails, full of sharp smells and beeping. Describe the waiting and the worry.',
          realWordProContext:
              'A vast old institution for the troubled mind, padded cells, long corridors with barred windows, wheelchairs left to rust.',
          mimicWordProContext:
              'Wards and waiting areas, nurses on their rounds, beeping monitors, the smell of antiseptic, visitors gathered at bedsides.',
        ),
        WordPair(
          realWord: 'Mausoleum',
          mimicWord: 'Library',
          realWordContext:
              'A grand stone building that holds the dead above ground. Describe the marble, the silence, the iron gates.',
          mimicWordContext:
              'A hushed hall of shelves where everyone whispers. Talk about the smell of old paper and the rule about quiet.',
          realWordProContext:
              'A grand stone building raised above graves, family names carved over the door, steps leading down into silence.',
          mimicWordProContext:
              'Tall shelves of bound volumes, ladders on rails, reading desks and green lamps, the hush of pages turning.',
        ),
        WordPair(
          realWord: 'Catacombs',
          mimicWord: 'Tunnel',
          realWordContext:
              'Long underground passages lined with the buried dead. Describe the damp dark and how easy it is to get lost.',
          mimicWordContext:
              'A narrow man-made passage through earth or rock, leading somewhere unknown. Describe the echo and the dark ahead.',
          realWordProContext:
              'Underground corridors of bone, skulls stacked into the walls, narrow passages winding far beneath a city.',
          mimicWordProContext:
              'A long hollow passage bored through earth or rock, rails or pipes inside, one way in and one way out.',
        ),
        WordPair(
          realWord: 'Morgue',
          mimicWord: 'Coldroom',
          realWordContext:
              'A clinical, tiled room where the recently dead are kept and examined. Describe the steel, the chill, the labels.',
          mimicWordContext:
              'A walk-in fridge for perishables, cold enough to see your breath. Talk about the hum and what the shelves hold.',
          realWordProContext:
              'Steel drawers for the deceased, toe tags and gurneys, a medical examiner at work, the chill of refrigeration.',
          mimicWordProContext:
              'A refrigerated room where perishables wait, frost on the shelves, stacked crates, breath visible in the air.',
        ),
        WordPair(
          realWord: 'Cabin',
          mimicWord: 'Cottage',
          realWordContext:
              'A rough wooden retreat far from anyone, charming by day and eerie by night. Describe the isolation and the creaks.',
          mimicWordContext:
              'A small, snug home in the countryside, cute and a little too quiet. Describe the flowers by the door and the slow pace.',
          realWordProContext:
              'A remote wooden retreat deep in the trees, log walls, a fireplace, an ax by the door, no neighbor for miles.',
          mimicWordProContext:
              'A small cozy country home, thatch or stone, flower boxes on the sill, a tidy path to the gate.',
        ),
        WordPair(
          realWord: 'Swamp',
          mimicWord: 'Lake',
          realWordContext:
              'Waterlogged ground that swallows footprints and secrets alike. Describe the smell, the fog, the things just below.',
          mimicWordContext:
              'A wide still water surface that mirrors everything and hides the rest. Describe the calm above and what swims under.',
          realWordProContext:
              'Waterlogged ground and cypress roots, mist over stagnant water, things sliding off the banks, feet sinking slowly.',
          mimicWordProContext:
              'A wide body of still water, boats and fishing docks, ripples at sunset, swimmers on hot afternoons.',
        ),
        WordPair(
          realWord: 'Attic',
          mimicWord: 'Storeroom',
          realWordContext:
              'The space under the roof, reached by a folding stair, full of dust and family history. Describe what gets forgotten up there.',
          mimicWordContext:
              'A plain room where spare things wait to be needed again. Talk about the stacked boxes and the dim single bulb.',
          realWordProContext:
              'The space under the roof, cobwebs and trunks of old photographs, creaking boards, one bare bulb on a cord.',
          mimicWordProContext:
              'A back room of stacked shelves and boxes, inventory lists, a rolling ladder, things saved for someday.',
        ),
        WordPair(
          realWord: 'Graveyard',
          mimicWord: 'Park',
          realWordContext:
              'An outdoor field of permanent residents. Describe the stones in rows and the hush between the trees.',
          mimicWordContext:
              'A public green space with benches, paths, and children shouting. Describe the ordinary daytime life of the city.',
          realWordProContext:
              'Open grounds of headstones and plots, groundskeepers with mowers, wilting wreaths, dates carved in stone.',
          mimicWordProContext:
              'Benches and playgrounds, jogging paths, picnic blankets, dogs on leashes, a fountain in the middle.',
        ),
        WordPair(
          realWord: 'Dungeon',
          mimicWord: 'Prison',
          realWordContext:
              'A windowless cell deep below a keep, built so no one leaves. Describe the cold stone and the iron.',
          mimicWordContext:
              'An institution of cells and bars where time is the sentence. Describe the routine, the clang, the long nights.',
          realWordProContext:
              'The underground cells of a castle, chains on the walls, torch brackets, iron doors with slots for eyes.',
          mimicWordProContext:
              'Cells and exercise yards, guards and uniforms, visiting hours, bars on every window.',
        ),
        WordPair(
          realWord: 'Lighthouse',
          mimicWord: 'Watchtower',
          realWordContext:
              'A tall lonely beacon at the edge of the land, sweeping light over danger. Describe the spiral stairs and the fog signal.',
          mimicWordContext:
              'A high lookout built to see trouble coming first. Describe the long view and the lonely shift up top.',
          realWordProContext:
              'A tall lonely tower by the sea, a rotating beam sweeping the water, a spiral stair, the keeper climbing at dusk.',
          mimicWordProContext:
              'A high lookout post, binoculars and radio checks, a wide view in every direction, wind at the top.',
        ),
        WordPair(
          realWord: 'Maze',
          mimicWord: 'Garden',
          realWordContext:
              'Deliberately confusing paths where every turn looks the same. Describe the hedges and the worry of walking in circles.',
          mimicWordContext:
              'A plot of cultivated beauty that took years of patience. Describe the rows, the blooms, the dirt under the nails.',
          realWordProContext:
              'Hedges or stone walls forming confusing paths, dead ends and turning twice, echoes of footsteps, no straight way out.',
          mimicWordProContext:
              'Flowerbeds, lawns and fountains, a vegetable patch, shears and a watering can, butterflies drifting through.',
        ),
        WordPair(
          realWord: 'Forest',
          mimicWord: 'Woods',
          realWordContext:
              'Tree upon tree until the way back stops being obvious. Describe the hush, the canopy, the feeling of being watched.',
          mimicWordContext:
              'Smaller, friendlier trees near home, daylight filtering through leaves. Describe the paths and the birdsong.',
          realWordProContext:
              'Deep, dense and old, wolves somewhere between the trunks, paths that vanish, a canopy that swallows the sky.',
          mimicWordProContext:
              'Trees and trails close to town, bird calls, fallen branches, sunlight through the leaves, a spot for picnics.',
        ),
        WordPair(
          realWord: 'Abattoir',
          mimicWord: 'Kitchen',
          realWordContext:
              'An industrial end-point for livestock, all steel hooks and hoses. Describe the smell and why floors are always washed.',
          mimicWordContext:
              'The warm heart of a home where meals are made. Describe the clatter, the heat, the mess that tastes good after.',
          realWordProContext:
              'A slaughterhouse, steel hooks on rails, drains in the floor, aprons and hoses, the smell of iron everywhere.',
          mimicWordProContext:
              'Counters, knives and pans, a stove and oven, recipes taped to the wall, the smell of onions frying.',
        ),
        WordPair(
          realWord: 'Mine',
          mimicWord: 'Cave',
          realWordContext:
              'A honeycomb of shafts dug for treasure, dark as soon as the lamp dies. Describe the dust and the distant rumbles.',
          mimicWordContext:
              'A natural hollow carved by water over ages. Describe the drip, the echoing dark, the strange stone shapes.',
          realWordProContext:
              'Shafts and elevators dropping deep, headlamps in blackness, carts on rails, timber supports, dust that never settles.',
          mimicWordProContext:
              'Natural hollows in rock, stalactites and dripping water, bats overhead, a flashlight beam on stone.',
        ),
        WordPair(
          realWord: 'Ruins',
          mimicWord: 'Castle',
          realWordContext:
              'The bones of something grand that time knocked down. Describe the broken arches and weeds growing through floors.',
          mimicWordContext:
              'A fortress of thick walls and banners, built for sieges. Describe the stone, the halls, the sense of old power.',
          realWordProContext:
              'Broken columns and collapsed walls, rubble underfoot, the remains of something grand left to fall apart.',
          mimicWordProContext:
              'Turrets and banners, drawbridges, great stone halls, a throne, suits of armor standing in corridors.',
        ),
        WordPair(
          realWord: 'Sewer',
          mimicWord: 'Pipeline',
          realWordContext:
              'The city beneath the city, carrying everything away. Describe the smell, the rats, the flowing dark.',
          mimicWordContext:
              'Long metal veins that move water or fuel for miles. Describe the joints, the hum, the slow corrosion.',
          realWordProContext:
              'Tunnels beneath the streets, murky flowing water, rat eyes in the beam, grate-light from the world above.',
          mimicWordProContext:
              'Long joined pipes carrying gas or oil, valves and gauges, welding sparks, a hiss at every joint.',
        ),
        WordPair(
          realWord: 'Ghost Town',
          mimicWord: 'Village',
          realWordContext:
              'A whole settlement where everyone left in a hurry. Describe the swung-open doors and the dust on everything.',
          mimicWordContext:
              'A small rural cluster of homes where everybody knows everybody. Describe the gossip and the single street.',
          realWordProContext:
              'An abandoned settlement, boarded saloons, wind through empty streets, wagons left where they stopped.',
          mimicWordProContext:
              'A small rural community, a square and a chapel, neighbors greeting each other, stalls on market day.',
        ),
        WordPair(
          realWord: 'Vault',
          mimicWord: 'Safe',
          realWordContext:
              'A reinforced box of secrets behind heavy steel. Describe the combinations and what people trust to it.',
          mimicWordContext:
              'The one place valuables sleep undisturbed, opened by code or dial. Describe the click and the weight of the door.',
          realWordProContext:
              'The armored treasure chamber of a bank, massive round doors, combination dials, timed mechanisms, guards outside.',
          mimicWordProContext:
              'A steel box for valuables, a dial or keypad, bolts sunk into concrete, hidden behind a painting.',
        ),
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
        WordPair(
          realWord: 'Séance',
          mimicWord: 'Meeting',
          realWordContext:
              'Sitting in a dark circle, holding hands, calling for a sign. Describe the candle ring and the held breath.',
          mimicWordContext:
              'People gathered around one table for one purpose. Describe the agendas, the nods, the person running it.',
          realWordProContext:
              'Hands joined around a table in candlelight, calling to the departed, sudden knocks, a medium slipping into a trance.',
          mimicWordProContext:
              'Agendas, minutes and handshakes, a long conference table, people taking turns to speak, decisions made together.',
        ),
        WordPair(
          realWord: 'Ritual',
          mimicWord: 'Ceremony',
          realWordContext:
              'Steps performed in strict order because tradition demands it. Describe the circle, the chanting, the appointed hour.',
          mimicWordContext:
              'A formal occasion with a script everyone half-knows. Describe the dress, the vows, the applause at the end.',
          realWordProContext:
              'Candles set in a circle, chalk symbols on the floor, chanted words at midnight, robes and an offering bowl.',
          mimicWordProContext:
              'Vows and speeches, formal robes, guests seated in rows, music and petals, two lives joined before a crowd.',
        ),
        WordPair(
          realWord: 'Coven',
          mimicWord: 'Club',
          realWordContext:
              'A secret sisterhood that meets at night and keeps its rules. Describe the initiation and the hush around the name.',
          mimicWordContext:
              'A loud room you pay to enter, where the bass replaces talk. Describe the queue, the stamp, the dancing dark.',
          realWordProContext:
              'A hidden sisterhood of witches, twelve and one gathering under the full moon, oaths sworn and secrets shared.',
          mimicWordProContext:
              'Members and membership cards, loud music and a dance floor, a bar in the corner, open until late.',
        ),
        WordPair(
          realWord: 'Grimoire',
          mimicWord: 'Diary',
          realWordContext:
              'A bound book of instructions no shop would sell. Describe the cracked leather and the warnings on page one.',
          mimicWordContext:
              'A private book of days, written for no reader but the author. Describe the clasp, the hidden thoughts, the confessions.',
          realWordProContext:
              'A bound book of spells written in ink and blood, warning sigils on the cover, pages that stir when opened.',
          mimicWordProContext:
              'A journal of private thoughts, dated entries and confessions, a ribbon bookmark, hidden under a pillow.',
        ),
        WordPair(
          realWord: 'Pentagram',
          mimicWord: 'Star',
          realWordContext:
              'A five-pointed figure drawn inside a ring for power. Describe the chalk, the candles at each point.',
          mimicWordContext:
              'A distant burning point in the night sky that sailors trusted. Describe the cold light and what people ask of it.',
          realWordProContext:
              'A five-pointed figure drawn in salt or chalk, enclosed in a circle, points of power, glowing at the center.',
          mimicWordProContext:
              'A burning point of light impossibly far away, constellations drawn between them, wishes made on the first one out.',
        ),
        WordPair(
          realWord: 'Curse',
          mimicWord: 'Bad Luck',
          realWordContext:
              'A hex that follows a person home and ruins everything quietly. Describe how it was earned and how it clings.',
          mimicWordContext:
              'When everything goes wrong at once and nobody knows why. Describe the run of misfortune and the shrugging fatalism.',
          realWordProContext:
              'A spoken doom that follows a bloodline, cracked mirrors, salt spilled with intent, misfortune that hunts.',
          mimicWordProContext:
              'Everything going wrong at once, torn laces and missed buses, a streak that finally has to turn.',
        ),
        WordPair(
          realWord: 'Daemon',
          mimicWord: 'Shadow',
          realWordContext:
              'An attendant entity with its own agenda, bound or bargained with. Describe the deal, the price, the fine print.',
          mimicWordContext:
              'The dark shape that copies your every move on the wall. Describe how it stretches and shrinks with the light.',
          realWordProContext:
              'An ancient spirit with its own will, bargains struck at a price, whispers at the edge of hearing.',
          mimicWordProContext:
              'The dark shape cast when a body blocks the light, stretching long at sunset, copying every move.',
        ),
        WordPair(
          realWord: 'Spell',
          mimicWord: 'Wish',
          realWordContext:
              'Words of power arranged just so, spoken or written to bend the world. Describe the rhymes and the ingredients.',
          mimicWordContext:
              'A hope aimed at the universe, usually with eyes shut. Describe the eyelashes, the coins in fountains, the secrecy.',
          realWordProContext:
              'Words of power that bend the world, components and gestures, something spoken three times to take hold.',
          mimicWordProContext:
              'Eyelashes blown away, birthday candles, coins dropped in fountains, a hope sent silently to the universe.',
        ),
        WordPair(
          realWord: 'Altar',
          mimicWord: 'Table',
          realWordContext:
              'The sacred centre where offerings are laid and vows are made. Describe the cloth, the candles, what must never touch it.',
          mimicWordContext:
              'Four legs and a flat top that carries the whole household. Describe the meals, the clutter, the marks that never come out.',
          realWordProContext:
              'A stone slab where offerings burn, runes carved along the edge, candles at each corner, old stains that never wash.',
          mimicWordProContext:
              'Four legs and a flat top, chairs pulled up around it, meals and paperwork and conversations shared across it.',
        ),
        WordPair(
          realWord: 'Sacrificing',
          mimicWord: 'Donation',
          realWordContext:
              'Giving up something precious to gain something greater. Describe the smoke, the price, the trembling hands.',
          mimicWordContext:
              'Money or goods handed over expecting nothing back. Describe the tin, the receipts, the quiet generosity.',
          realWordProContext:
              'An offering surrendered at the knife edge, smoke rising to something listening, the precious thing given up for power.',
          mimicWordProContext:
              'Goods or money given freely to a cause, receipts and gratitude, a box passed around the room.',
        ),
        WordPair(
          realWord: 'Exorcism',
          mimicWord: 'Cleansing',
          realWordContext:
              'A high-stakes rite to drive something out of a person or place. Describe the Latin, the sweat, the hours past dawn.',
          mimicWordContext:
              'A deep, ritual scrubbing that leaves a place feeling new. Describe the vinegar smell and the opened windows.',
          realWordProContext:
              'Rites to drive out a possessing spirit, holy water and scripture, a body fighting the thing that holds it.',
          mimicWordProContext:
              'A thorough wash to purify, windows thrown open, smoke and scrubbing, everything made clean and new again.',
        ),
        WordPair(
          realWord: 'Tarot',
          mimicWord: 'Card',
          realWordContext:
              'Seventy-eight illustrated futures dealt onto a cloth. Describe the shuffle, the spread, the meanings people fear.',
          mimicWordContext:
              'A small coated rectangle that turns everything into games or fortunes. Describe the deck and the shuffling.',
          realWordProContext:
              'A deck of seventy-eight arcana, spreads laid on a cloth, the reader turning fate face up one by one.',
          mimicWordProContext:
              'A small stiff rectangle dealt in games, suits and numbers, shuffled and cut, held close to the chest.',
        ),
        WordPair(
          realWord: 'Chalice',
          mimicWord: 'Cup',
          realWordContext:
              'An ornate vessel used for the most serious toasts and rites. Describe the gold rim and what it must never hold.',
          mimicWordContext:
              'The everyday vessel of morning rituals and shared drinks. Describe the steam, the chipped edge, the refill.',
          realWordProContext:
              'An ornate goblet on the altar, wine-dark liquid, runes on the stem, raised high while words are spoken over it.',
          mimicWordProContext:
              'A drinking vessel, steam or foam at the rim, raised in toasts, set down on a saucer.',
        ),
        WordPair(
          realWord: 'Amulet',
          mimicWord: 'Jewelry',
          realWordContext:
              'A worn charm believed to turn away harm. Describe the leather cord, the worn engraving, where it touches skin.',
          mimicWordContext:
              'Worn adornment that signals wealth or love. Describe the clasp, the sparkle, the little box it came in.',
          realWordProContext:
              'A charged charm worn against evil, a symbol sealed in metal, warm against the skin, never taken off.',
          mimicWordProContext:
              'Rings, necklaces and earrings, polished silver and gold, glitter at the throat, gifts in little boxes.',
        ),
        WordPair(
          realWord: 'Ghost',
          mimicWord: 'Illusion',
          realWordContext:
              'The departed who stayed behind, felt more than seen. Describe the cold patch and the sound of invisible footsteps.',
          mimicWordContext:
              'Something your eyes insist is there while reason disagrees. Describe the shimmer at the edge of vision.',
          realWordProContext:
              'The lingering dead, cold spots and slammed doors, a figure seen once and never again, unfinished business.',
          mimicWordProContext:
              'Something seen that is not really there, a trick of light or mind, gone when approached.',
        ),
        WordPair(
          realWord: 'Poltergeist',
          mimicWord: 'Breeze',
          realWordContext:
              'The unseen tenant that throws things and slams doors at night. Describe the noises and the furniture out of place.',
          mimicWordContext:
              'Moving air you feel but cannot see, arriving uninvited. Describe the lifted curtains and the chill on the neck.',
          realWordProContext:
              'An unseen hurler of objects, furniture moving on its own, scratches inside the walls, chaos after dark.',
          mimicWordProContext:
              'A gentle current of air, curtains stirring, leaves skipping down a path, sweet relief on a hot day.',
        ),
        WordPair(
          realWord: 'Cauldron',
          mimicWord: 'Pot',
          realWordContext:
              'A great black vessel for brews that must never boil dry. Describe the fire beneath and the bubbling surface.',
          mimicWordContext:
              'A humble cooking vessel for soups and stews. Describe the handle burns and the lid rattling at a simmer.',
          realWordProContext:
              'A great black vessel over open fire, brews of bone and herb, bubbles that answer what is asked of them.',
          mimicWordProContext:
              'A rounded cooking vessel with a handle, soups and stews, steam escaping the lid, clattering on the stove.',
        ),
        WordPair(
          realWord: 'Talisman',
          mimicWord: 'Keychain',
          realWordContext:
              'An object of power carried against bad luck and worse company. Describe how it must never leave the body.',
          mimicWordContext:
              'The jingling ring that holds every door to your life. Describe the weight of it in a pocket and what dangles there.',
          realWordProContext:
              'An object of power carried close, engraved signs, charged under a full moon, hidden from every other eye.',
          mimicWordProContext:
              'A ring of keys and charms jingling in a pocket, fobs and trinkets, handed over at the valet stand.',
        ),
        WordPair(
          realWord: 'Necromancy',
          mimicWord: 'History',
          realWordContext:
              'The forbidden art of asking the dead to answer. Describe the grave-dirt, the questions, the cost of replies.',
          mimicWordContext:
              'Everything that already happened, kept and argued over. Describe the archives, the dates, the winners who wrote it.',
          realWordProContext:
              'Raising and questioning the dead, grave dust and candles, the forbidden school where death answers back.',
          mimicWordProContext:
              'The study of what came before, dates and documents, museums and archives, old lessons told aloud.',
        ),
        WordPair(
          realWord: 'Warlock',
          mimicWord: 'Magician',
          realWordContext:
              'A man who traded comfort for power and answers to no school. Describe the bargains and the lingering smell of ozone.',
          mimicWordContext:
              'A performer of impossible things for gasping rooms. Describe the top hat, the misdirection, the reveal.',
          realWordProContext:
              'A male witch bound to dark pacts, rings of power, a tower lit at strange hours, debts coming due.',
          mimicWordProContext:
              'A stage performer in a cape, cards and doves, sleight of hand, a top hat and a flourish.',
        ),
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
        WordPair(
          realWord: 'Alibi',
          mimicWord: 'Excuse',
          realWordContext:
              'The tested claim of where you were when it happened. Describe the witnesses who can break it or make it.',
          mimicWordContext:
              'The tidy reason for lateness nobody quite believes. Describe the delivery and the small tell that gives it away.',
          realWordProContext:
              'Proof you were somewhere else when it happened, timestamps, receipts, a witness who swears by you.',
          mimicWordProContext:
              'A reason offered to soften blame, half-true at best, told quickly to slip out of trouble.',
        ),
        WordPair(
          realWord: 'Evidence',
          mimicWord: 'Clue',
          realWordContext:
              'The physical remainder that points one way and not another. Describe the bagging, the tagging, the chain of hands.',
          mimicWordContext:
              'The small detail that changes the whole picture once noticed. Describe how it hides in plain sight.',
          realWordProContext:
              'Sealed bags and a chain of custody, samples sent to the lab, what finally convinces a jury.',
          mimicWordProContext:
              'A small detail that points the way, followed one by one toward the answer.',
        ),
        WordPair(
          realWord: 'Suspect',
          mimicWord: 'Stranger',
          realWordContext:
              'The person the questions circle back to, again and again. Describe the nervous habits and the contradictory story.',
          mimicWordContext:
              'The unfamiliar face in a place of familiar ones. Describe the wrongness everyone felt but nobody could name.',
          realWordProContext:
              'The one the detectives keep coming back to, prints on file, a story that changes each telling.',
          mimicWordProContext:
              'A face you do not know, an unfamiliar figure at the edge of the party, no name to give.',
        ),
        WordPair(
          realWord: 'Murder',
          mimicWord: 'Accident',
          realWordContext:
              'A death with intent behind it, however well hidden. Describe the planning and the wrong-shaped grief.',
          mimicWordContext:
              'The tragic meeting of bad timing and bad luck, nobody at the wheel. Describe the investigation that must still happen.',
          realWordProContext:
              'A planned killing, premeditated, a body and someone who meant every part of it.',
          mimicWordProContext:
              'A mishap no one intended, a slip, a fall, terrible timing and apologies all around.',
        ),
        WordPair(
          realWord: 'Poison',
          mimicWord: 'Medicine',
          realWordContext:
              'The silent method that needs no strength, only patience. Describe the bitter taste and the stomach turning.',
          mimicWordContext:
              'The measured help that heals at one dose and harms at another. Describe the labels, the spoon, the pharmacy bag.',
          realWordProContext:
              'Tasteless drops stirred into a glass, symptoms that look like illness, a small vial in a coat pocket.',
          mimicWordProContext:
              'A remedy taken on schedule, dosage printed on the label, a spoonful that helps it go down.',
        ),
        WordPair(
          realWord: 'Weapon',
          mimicWord: 'Tool',
          realWordContext:
              'Whatever was within reach when rage or plan took over. Describe the grip marks and the intent behind the choice.',
          mimicWordContext:
              'An ordinary implement that makes hard hands strong. Describe the workshop drawer and the calluses it builds.',
          realWordProContext:
              'Something wielded to harm, prints on the grip, found wiped clean but never quite clean.',
          mimicWordProContext:
              'An implement made for a job, a workbench and a pegboard, the right one makes the work easy.',
        ),
        WordPair(
          realWord: 'Blood',
          mimicWord: 'Paint',
          realWordContext:
              'The proof the body cannot refuse to give. Describe the spatter patterns and what they say about force.',
          mimicWordContext:
              'A wet, deliberate coat of colour that covers everything beneath. Describe the fumes and the second coat.',
          realWordProContext:
              'Spatter patterns read by experts, pools beneath the body, luminol showing what was wiped away.',
          mimicWordProContext:
              'Pigment in a can, rollers and brushes, primer and coats, a fresh stroke drying on the wall.',
        ),
        WordPair(
          realWord: 'Victim',
          mimicWord: 'Patient',
          realWordContext:
              'The one who bore the worst of it and cannot speak now. Describe the life interrupted and the ones left asking why.',
          mimicWordContext:
              'The one in the bed, waiting on results and visiting hours. Describe the wristband and the questions for the doctor.',
          realWordProContext:
              'The one who suffered, next of kin notified, a life cut short and a case opened.',
          mimicWordProContext:
              'Someone in care, a wristband and a chart, rounds and checkups, resting in a gown.',
        ),
        WordPair(
          realWord: 'Footprint',
          mimicWord: 'Dirt',
          realWordContext:
              'The step that stayed behind long after the walker fled. Describe the tread pattern and the measuring beside it.',
          mimicWordContext:
              'The dust and grime of a place, on boots and sleeves. Describe what the soil says about where someone has been.',
          realWordProContext:
              'Treads pressed into soil, cast in plaster, a stride length, a weight, a direction of travel.',
          mimicWordProContext:
              'Earth and dust, mud on boots, stains on the knees, swept away by morning.',
        ),
        WordPair(
          realWord: 'Autopsy',
          mimicWord: 'Checkup',
          realWordContext:
              'The clinical conversation with the dead, charted in detail. Describe the Y-incision and the small sample jars.',
          mimicWordContext:
              'The routine once-over that either reassures or changes everything. Describe the cold stethoscope and the forms.',
          realWordProContext:
              'The body examined for answers, cause of death written and signed, findings that can undo a story.',
          mimicWordProContext:
              'A routine exam, stethoscope and blood-pressure cuff, a clean bill of health at the end.',
        ),
        WordPair(
          realWord: 'Detective',
          mimicWord: 'Officer',
          realWordContext:
              'The one who lives inside the question until it breaks. Describe the messy desk, the coffee, the hunches that pay off.',
          mimicWordContext:
              'The uniformed presence that holds the line at the tape. Describe the chatter and the squared posture.',
          realWordProContext:
              'A driven investigator, case board and red string, trench coat, questions nobody wants asked.',
          mimicWordProContext:
              'A uniformed servant of the law, patrols and citations, a badge and a radio on the shoulder.',
        ),
        WordPair(
          realWord: 'Crime Scene',
          mimicWord: 'Room',
          realWordContext:
              'The taped-off square where everything went wrong. Describe the chalk lines, the flashlights, the hush.',
          mimicWordContext:
              'Four walls and a doorway that frame everything that happens indoors. Describe what the furniture admits.',
          realWordProContext:
              'Cordoned off with yellow tape, chalk outlines, investigators in shoe covers, flashbulbs in the dark.',
          mimicWordProContext:
              'Four walls and a way in, furniture arranged inside, a place to be in or to leave.',
        ),
        WordPair(
          realWord: 'Motive',
          mimicWord: 'Reason',
          realWordContext:
              'The why beneath the what: money, jealousy, revenge. Describe the thread that ties people to the deed.',
          mimicWordContext:
              'The sensible-sounding because behind any choice. Describe how it bends when pressure arrives.',
          realWordProContext:
              'Greed, jealousy, revenge — the why behind the deed, hunted down before anything else.',
          mimicWordProContext:
              'The explanation behind an action, asked of a child and accepted at face value.',
        ),
        WordPair(
          realWord: 'Witness',
          mimicWord: 'Bystander',
          realWordContext:
              'The reluctant pair of eyes that saw too much. Describe the hesitation before speaking and the fear after.',
          mimicWordContext:
              'The onlooker at the edge of events, phone already out. Describe the crowd and the recording nobody asked for.',
          realWordProContext:
              'The eyes that saw it happen, a statement taken twice, protection offered when they talk.',
          mimicWordProContext:
              'A passerby who happened to watch, phone out, unsure whether to step closer or away.',
        ),
        WordPair(
          realWord: 'Corpse',
          mimicWord: 'Dummy',
          realWordContext:
              'The body at the centre of every question, silent as stone. Describe the stillness and the care taken around it.',
          mimicWordContext:
              'A life-sized stand-in that fools the eye for a second. Describe the stitched seams and the painted face.',
          realWordProContext:
              'What remains when life leaves, laid out under a sheet, identified by teeth and records.',
          mimicWordProContext:
              'A stuffed figure standing in for a person, a crash-test head, a punching bag in the gym.',
        ),
        WordPair(
          realWord: 'Fingerprint',
          mimicWord: 'Smudge',
          realWordContext:
              'The unique spiral signature left by a careless touch. Describe the dusting brush and the lifted print.',
          mimicWordContext:
              'The half-erased smear where a hand passed in haste. Describe the swipe marks on glass and steel.',
          realWordProContext:
              'Whorls and ridges lifted with powder, matched in seconds against a database of millions.',
          mimicWordProContext:
              'A blurred mark left by a careless thumb, wiped off the glass with a sleeve.',
        ),
        WordPair(
          realWord: 'Blackmail',
          mimicWord: 'Letter',
          realWordContext:
              'A quiet trade: silence bought, reputations spared. Describe the anonymous notes and the dread of the mailbox.',
          mimicWordContext:
              'Words sealed and sent to someone specific. Describe the stamp, the handwriting, the way it changes a morning.',
          realWordProContext:
              'Secrets sold back to their owner, threats in an unmarked envelope, pay up or be exposed.',
          mimicWordProContext:
              'Words set down on paper, sealed and sent, anything from a love note to a resignation.',
        ),
        WordPair(
          realWord: 'Kidnapping',
          mimicWord: 'Visit',
          realWordContext:
              'A person taken, a demand expected, a clock started. Describe the empty bedroom and the dropped toy.',
          mimicWordContext:
              'Someone calling at your door, expected or not. Describe the knock, the politeness, the too-long stay.',
          realWordProContext:
              'Taken in a van, a phone call with demands, a family waiting sleepless for news.',
          mimicWordProContext:
              'Dropping by unannounced, knocking and being welcomed, guests with gifts, staying for tea.',
        ),
        WordPair(
          realWord: 'Cyanide',
          mimicWord: 'Sugar',
          realWordContext:
              'The famous fast-acting end, one grain away, bitter as almonds. Describe the thin line between dose and disaster.',
          mimicWordContext:
              'The sweet white everyday crystals in every kitchen. Describe the spoonfuls and the bowl on the counter.',
          realWordProContext:
              'Bitter almonds in the cup, a single gram between life and the grave, the classic choice of poisoners.',
          mimicWordProContext:
              'White granules stirred into coffee, sweetness in cubes and packets, spooned over berries.',
        ),
        WordPair(
          realWord: 'Ransom',
          mimicWord: 'Payment',
          realWordContext:
              'The price put on a human life, delivered in unmarked bills. Describe the briefcase and the midnight drop point.',
          mimicWordContext:
              'What changes hands when the debt comes due. Describe the envelope, the schedule, the receipt kept carefully.',
          realWordProContext:
              'Money demanded for a life, unmarked bills in a case, a midnight drop and a countdown.',
          mimicWordProContext:
              'What is handed over for goods or services, invoices and change, installments on time.',
        ),
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
        WordPair(
          realWord: 'Zombie',
          mimicWord: 'Sick Person',
          realWordContext:
              'The walking dead that shamble toward any noise. Describe the grey skin, the lurch, the crowd that never tires.',
          mimicWordContext:
              'Someone feverish and fading, needing care more than fear. Describe the blankets, the soup, the sweat.',
          realWordProContext:
              'The walking dead, bitten and turning, shambling hordes drawn to noise, stopped only by destroying the brain.',
          mimicWordProContext:
              'Fever and chills, tissues and soup, bed rest and remedies, back on their feet within days.',
        ),
        WordPair(
          realWord: 'Bunker',
          mimicWord: 'Shelter',
          realWordContext:
              'A buried concrete refuge built for the world ending. Describe the blast doors and the canned years inside.',
          mimicWordContext:
              'Anywhere body and hope can hold out until help comes. Describe the crowded cots and the waiting.',
          realWordProContext:
              'A buried concrete refuge, steel doors and filtered air, months of tinned supplies below the ground.',
          mimicWordProContext:
              'A roof over the stranded, cots and blankets, soup served in lines, storms waited out together.',
        ),
        WordPair(
          realWord: 'Trap',
          mimicWord: 'Obstacle',
          realWordContext:
              'A hidden mechanism that punishes the careless step. Describe the trigger wire and the snap that follows.',
          mimicWordContext:
              'Whatever stands between you and the way forward. Describe the wall, the blockade, the puzzle of getting past.',
          realWordProContext:
              'Wire and bait under leaves, spikes or nets, something deliberately built to catch and hold.',
          mimicWordProContext:
              'Something in the way, a wall between you and the goal, climbed over or gone around.',
        ),
        WordPair(
          realWord: 'Flashlight',
          mimicWord: 'Candle',
          realWordContext:
              'The beam that keeps the dark honest, as long as batteries last. Describe the clicking switch and the sweeping cone.',
          mimicWordContext:
              'A small naked flame with its own trembling halo. Describe the wax tears and the dark pressing close.',
          realWordProContext:
              'A beam cutting the dark, dying batteries, a click that gives you away, swept nervously across the trees.',
          mimicWordProContext:
              'A wick standing in wax, a small trembling flame, wax pooling, shadows dancing on the walls.',
        ),
        WordPair(
          realWord: 'Key',
          mimicWord: 'Lock',
          realWordContext:
              'The small cold thing that decides who gets in. Describe the teeth, the ring, the panic of a missing pocket.',
          mimicWordContext:
              'The stubborn mechanism between you and what matters. Describe the tumblers and the jiggle that opens nothing.',
          realWordProContext:
              'A small cold thing that opens what matters, teeth and a groove, carried on a chain or under a mat.',
          mimicWordProContext:
              'A bolted fastening, tumblers and clicks, chains and heavy shackles, keeping everything shut.',
        ),
        WordPair(
          realWord: 'Serum',
          mimicWord: 'Vaccine',
          realWordContext:
              'The experimental dose that might save or change you. Describe the cold vial and the trembling needle.',
          mimicWordContext:
              'The preventives queued in refrigerated rows for the whole town. Describe the sore arms and the lined-up sleeves.',
          realWordProContext:
              'The only cure in a glass vial, experiments and side effects, fought over in the ruins of a lab.',
          mimicWordProContext:
              'A preventive shot at the clinic, a small needle, a sore arm, records kept in a folded card.',
        ),
        WordPair(
          realWord: 'Shotgun',
          mimicWord: 'Pistol',
          realWordContext:
              'The loud, room-clearing answer kept above the fireplace. Describe the pump action and the recoil.',
          mimicWordContext:
              'The compact sidearm that fits in a waistband. Describe the checkered grip and the hollow weight of it.',
          realWordProContext:
              'A long gun that scatters shot, pumped and ready, propped by the door of the last safe place.',
          mimicWordProContext:
              'A small handheld firearm, holstered at the hip, rounds counted, kept out of sight.',
        ),
        WordPair(
          realWord: 'Radio',
          mimicWord: 'Phone',
          realWordContext:
              'The crackling box of voices that may be your only rescue. Describe the hiss and the battery anxiety.',
          mimicWordContext:
              'The thin glass slab of everyone you know, one bar from dead. Describe the silence when it does not ring.',
          realWordProContext:
              'Static and emergency broadcasts, a hand-cranked set, voices calling into the void for other survivors.',
          mimicWordProContext:
              'Calls and messages in a pocket, screens and rings, contacts and photographs, always within reach.',
        ),
        WordPair(
          realWord: 'Fog',
          mimicWord: 'Cloud',
          realWordContext:
              'A grey blindness you can walk into and vanish in. Describe the muffled world and shapes that arrive early.',
          mimicWordContext:
              'The slow drifting shape above that changes and refuses to stay. Describe the shade it throws on fields.',
          realWordProContext:
              'Thick grey blindness rolling in, shapes lost at arm length, damp silence, footsteps swallowed.',
          mimicWordProContext:
              'White masses drifting overhead, shapes of animals in them, darkening before rain or a storm.',
        ),
        WordPair(
          realWord: 'Monster',
          mimicWord: 'Animal',
          realWordContext:
              'The thing that should not exist, hunting by instinct. Describe the sound it makes before you see it.',
          mimicWordContext:
              'The fellow creatures of fur and instinct, wild or tame. Describe the tracks and the eyes in the headlights.',
          realWordProContext:
              'Something that should not exist, too many limbs or none, hungry and utterly wrong.',
          mimicWordProContext:
              'A living creature of fur and instinct, wild or tamed, tracked by paw prints and calls.',
        ),
        WordPair(
          realWord: 'Safe Room',
          mimicWord: 'Bedroom',
          realWordContext:
              'The one reinforced space where the night cannot follow. Describe the steel barrier and the breath you finally take.',
          mimicWordContext:
              'The quiet personal space of bed and belongings where days begin and end. Describe the nightstand and the pillow.',
          realWordProContext:
              'The one reinforced place left, a barred entrance, a camera in the corner, supplies stacked, breath held.',
          mimicWordProContext:
              'A bed and a dresser, a lamp on the nightstand, curtains drawn, where every day begins and ends.',
        ),
        WordPair(
          realWord: 'Infection',
          mimicWord: 'Disease',
          realWordContext:
              'The spreading invader inside a wound or a bite. Describe the spreading heat and the red lines climbing.',
          mimicWordContext:
              'The long illness that reshapes a whole life. Describe the cough, the clinics, the careful elbow.',
          realWordProContext:
              'Bite marks spreading black veins, quarantine tape, the countdown to turning, amputation as the only hope.',
          mimicWordProContext:
              'An illness passed between bodies, coughs and clinics, bed rest until it passes.',
        ),
        WordPair(
          realWord: 'Bandage',
          mimicWord: 'Tape',
          realWordContext:
              'The wrapped strip that holds a body together by pressure. Describe the gauze and the careful knots.',
          mimicWordContext:
              'The sticky grey roll that fixes everything temporarily. Describe the torn strips and the sticky residue.',
          realWordProContext:
              'Gauze wound tight over a wound, pressure and knots, praying the bite is clean.',
          mimicWordProContext:
              'A sticky roll that binds and mends, torn with the teeth, holding packages and posters alike.',
        ),
        WordPair(
          realWord: 'Generator',
          mimicWord: 'Engine',
          realWordContext:
              'The fuel-hungry machine that hums when the grid fails. Describe the fumes and the countdown on the can.',
          mimicWordContext:
              'The burning heart of every machine, judged by its sound. Describe the sputter, the oil smell, the tuning.',
          realWordProContext:
              'The machine keeping the lights on, fuel cans and cables, a roar in the dark, sputtering at the worst moment.',
          mimicWordProContext:
              'Pistons and fuel turning wheels, horsepower, a rumble under the hood, tuned by mechanics.',
        ),
        WordPair(
          realWord: 'Chainsaw',
          mimicWord: 'Cutter',
          realWordContext:
              'The roaring two-stroke blade that makes its own arguments. Describe the pull cord and the flying chips.',
          mimicWordContext:
              'Whatever severs: shears, blades, the right edge for the job. Describe the clean cut and the worn edge.',
          realWordProContext:
              'A roaring blade on a bar, sawdust and worse in the air, pulled to life with a ripcord.',
          mimicWordProContext:
              'Any implement that divides, shears and blades, scissors through paper, clean edges left behind.',
        ),
        WordPair(
          realWord: 'Panic',
          mimicWord: 'Scare',
          realWordContext:
              'The moment the body votes before the mind does. Describe the sprint, the breath, the blind choices.',
          mimicWordContext:
              'The sharp jolt that lands in the chest and vanishes laughing. Describe the creak that turned out to be nothing.',
          realWordProContext:
              'Hearts hammering, breath ragged, a stampede of instinct when the lights die all at once.',
          mimicWordProContext:
              'A jolt at a sudden noise, a figure leaping out, a jump and then laughter.',
        ),
        WordPair(
          realWord: 'Rations',
          mimicWord: 'Food',
          realWordContext:
              'The counted, portioned sustenance that keeps morale alive. Describe the wrappers and the tiny luxuries.',
          mimicWordContext:
              'The meals that mark the day and gather people around. Describe the cooking smell and the empty plates.',
          realWordProContext:
              'Counted tins and sealed packs, halves measured out, hunger accepted as the new rule.',
          mimicWordProContext:
              'Meals and snacks, recipes and feasts, groceries bagged, tables set for company.',
        ),
        WordPair(
          realWord: 'Barricade',
          mimicWord: 'Door',
          realWordContext:
              'Whatever heavy furniture can be stacked against the opening. Describe the shelf, the desk, the precious seconds.',
          mimicWordContext:
              'The hinged threshold every arrival must announce itself at. Describe the knock and the handle turning.',
          realWordProContext:
              'Boards nailed across the frame, furniture piled high, keeping what is out there from getting in.',
          mimicWordProContext:
              'A panel that swings on hinges, knobs and knocks, opened for guests, closed for quiet.',
        ),
        WordPair(
          realWord: 'Flare',
          mimicWord: 'Torch',
          realWordContext:
              'The hissing red light that turns night into a warning. Describe the fizzing sparks and the long shadows.',
          mimicWordContext:
              'The oldest portable fire, guttering when the wind argues. Describe the pitch smoke and the wavering halo.',
          realWordProContext:
              'A hissing red star of burning light, cracked and lit to be seen, waved at distant rescuers.',
          mimicWordProContext:
              'A burning stick carried through the night, pitch and flame, moths circling the glow.',
        ),
        WordPair(
          realWord: 'Mutation',
          mimicWord: 'Scar',
          realWordContext:
              'The body rewritten by something it should never have touched. Describe the new geometry and what it costs.',
          mimicWordContext:
              'The mark an old wound leaves behind, smooth and pale. Describe the story it tells without words.',
          realWordProContext:
              'Flesh grown wrong, extra eyes and limbs, the change spreading outward from the wound.',
          mimicWordProContext:
              'A mark where an old wound closed, a story written on the skin, felt but no longer hurt.',
        ),
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
        WordPair(
          realWord: 'Insomnia',
          mimicWord: 'Tiredness',
          realWordContext:
              'The long arithmetic of ceiling-staring between false sleeps. Describe the small hours and the alarm that comes too fast.',
          mimicWordContext:
              'The heavy-limbed fog after too little rest. Describe the coffee that stops working and the yawns that spread.',
          realWordProContext:
              'Staring at the ceiling at three in the morning, every creak louder, exhausted yet unable to slip away.',
          mimicWordProContext:
              'Heavy eyelids and yawns, dragging feet, coffee that stops helping, asleep the moment they sit down.',
        ),
        WordPair(
          realWord: 'Paranoia',
          mimicWord: 'Anxiety',
          realWordContext:
              'The certainty that the pattern is about you. Describe the checking, the re-checking, the curtains twitching.',
          mimicWordContext:
              'The buzzing dread with no address, humming under the ribs. Describe the rehearsed speeches for things that never happen.',
          realWordProContext:
              'The certainty of being watched, meaning behind every glance, checking the lock twice, then again.',
          mimicWordProContext:
              'A racing heart before a speech, worst cases imagined, a knot that will not loosen.',
        ),
        WordPair(
          realWord: 'Shadow',
          mimicWord: 'Silhouette',
          realWordContext:
              'The dark companion every light source creates. Describe how it copies you and never quite matches.',
          mimicWordContext:
              'A shape read against the light, flat and black and unidentified. Describe the outline on the curtain.',
          realWordProContext:
              'Something dark that follows your steps, sometimes moving a beat late, never quite matching your feet.',
          mimicWordProContext:
              'A flat black outline cast on a wall, profile and pose readable, made by light behind a figure.',
        ),
        WordPair(
          realWord: 'Nightmare',
          mimicWord: 'Dream',
          realWordContext:
              'The sleep that turns on you and seals the exits. Describe the falling, the running, the waking with a shout.',
          mimicWordContext:
              'The nightly film your own head screens for you alone. Describe the impossibilities that feel completely normal.',
          realWordProContext:
              'Waking with a scream, chased and falling, the horror that feels real until the lamp snaps on.',
          mimicWordProContext:
              'A film played by the sleeping mind, flying or teeth falling out, gone by breakfast, sometimes half remembered.',
        ),
        WordPair(
          realWord: 'Whispers',
          mimicWord: 'Murmurs',
          realWordContext:
              'Speech just under hearing, aimed at you or at nothing. Describe the hiss at the edge of a silent room.',
          mimicWordContext:
              'The low blended voice of many people talking at once. Describe the din through a wall and the words you almost catch.',
          realWordProContext:
              'Your name spoken softly from an empty room, breath at the ear, sibilants moving along the walls.',
          mimicWordProContext:
              'Low indistinct voices across a room, a crowd heard through a wall, words too soft to catch.',
        ),
        WordPair(
          realWord: 'Doppelganger',
          mimicWord: 'Twin',
          realWordContext:
              'The exact copy of you that waves from a crowd you are not in. Describe the wrongness of your own face at a distance.',
          mimicWordContext:
              'The sibling who shared a face and a birthday and nothing else. Describe the swapped coats and the mistaken names.',
          realWordProContext:
              'Your exact face walking past you, seen entering your own home, wearing what you wore yesterday.',
          mimicWordProContext:
              'A sibling born from one egg, identical laughs and faces, mistaken for each other all their lives.',
        ),
        WordPair(
          realWord: 'Stalker',
          mimicWord: 'Fan',
          realWordContext:
              'The fixed attention that outlasts rejection and distance. Describe the footsteps that stop when you stop.',
          mimicWordContext:
              'The admirer who knows too much about someone famous. Describe the posters and the long line in the rain.',
          realWordProContext:
              'Always three steps behind, letters with no stamp, knowing things no outsider should know.',
          mimicWordProContext:
              'Devotion from the front row, posters held high, every release memorized, a name screamed with joy.',
        ),
        WordPair(
          realWord: 'Decay',
          mimicWord: 'Rust',
          realWordContext:
              'The slow undoing of everything left unattended. Describe the soft wood, the mold bloom, the smell of endings.',
          mimicWordContext:
              'The orange bloom that eats metal left in the weather. Describe the flaking red-brown and the seized hinge.',
          realWordProContext:
              'Slow rot taking a house apart, plaster falling, wood gone soft, the smell of something ending.',
          mimicWordProContext:
              'Orange flaking on old iron, seized hinges, rough patina spreading where the paint once was.',
        ),
        WordPair(
          realWord: 'Reflection',
          mimicWord: 'Mirror',
          realWordContext:
              'The light-thrown copy that moves when you move and waits when you wait. Describe the glass edge and the doubt.',
          mimicWordContext:
              'The silvered glass that answers every glance. Describe the fogged patch and the face you expect and do not see.',
          realWordProContext:
              'The figure in the glass that waits a half-second too long, seen over your shoulder, gone when you turn.',
          mimicWordProContext:
              'A polished glass that shows your face exactly, fogged by breath, cracked for seven years of misfortune.',
        ),
        WordPair(
          realWord: 'Isolation',
          mimicWord: 'Loneliness',
          realWordContext:
              'The long distance between you and every other heartbeat. Describe the one-sided conversations and the closed blinds.',
          mimicWordContext:
              'The crowd-shaped ache of being unknown. Describe the phone that never rings and the empty side of the bed.',
          realWordProContext:
              'Cut off, weeks without a voice, a door sealed from the outside, silence with weight to it.',
          mimicWordProContext:
              'The ache of an empty room, a phone with no messages, surrounded by people and still unseen.',
        ),
        WordPair(
          realWord: 'Static',
          mimicWord: 'White Noise',
          realWordContext:
              'The meaningless crackle between stations that never resolves. Describe the snow on the screen and the hiss.',
          mimicWordContext:
              'The even, sourceless hum that covers every other sound. Describe the fan you run for company at night.',
          realWordProContext:
              'A dead channel hissing, faces bleeding through the snow, a signal coming from somewhere silent.',
          mimicWordProContext:
              'A soft even hum of every frequency at once, sleep machines and fans, a steady sound that masks the rest.',
        ),
        WordPair(
          realWord: 'Intruder',
          mimicWord: 'Guest',
          realWordContext:
              'The unauthorized presence in a private place. Describe the moved chair and the wet footprints by the window.',
          mimicWordContext:
              'The invited company that overstays its welcome. Describe the polite smile and the cup that never empties.',
          realWordProContext:
              'Wet footprints that are not yours, a step opening downstairs, someone else inside the house.',
          mimicWordProContext:
              'An expected arrival, coat taken at the entrance, tea poured, staying politely past goodbye.',
        ),
        WordPair(
          realWord: 'Hallucination',
          mimicWord: 'Mirage',
          realWordContext:
              'The perception with nothing behind it, real to every sense. Describe the corner-of-the-eye figure that is not there.',
          mimicWordContext:
              'The beautiful false promise shimmering over hot ground. Describe the water that recedes as you approach.',
          realWordProContext:
              'Seeing what is not there, figures at the window, voices with no source, wide awake the whole time.',
          mimicWordProContext:
              'Water shimmering on a hot road, an oasis that recedes, a shape dissolved by distance.',
        ),
        WordPair(
          realWord: 'Darkness',
          mimicWord: 'Dimness',
          realWordContext:
              'The full absence of light where eyes make up nonsense. Describe the hand you cannot see and the sounds that grow.',
          mimicWordContext:
              'The weaker, watered version of the dark that never quite resolves. Describe the shapes that will not commit.',
          realWordProContext:
              'A full absence of light, a hand before the face invisible, sounds only, and it never ends.',
          mimicWordProContext:
              'Fading light at dusk, the reach of a single candle, shapes still guessed at the edge.',
        ),
        WordPair(
          realWord: 'Abyss',
          mimicWord: 'Hole',
          realWordContext:
              'The depth with no visible floor and a very long echo. Describe the edge, the pebble drop, the waiting dark.',
          mimicWordContext:
              'An opening in what should be solid, going further than it should. Describe the rim and the cold air rising.',
          realWordProContext:
              'A depth with no bottom, a throat of stone, the pull you feel when leaning too far over the edge.',
          mimicWordProContext:
              'An opening bored through something, dug or fallen into, a view of the other side.',
        ),
        WordPair(
          realWord: 'Obsession',
          mimicWord: 'Hobby',
          realWordContext:
              'The notion that crowds out every other notion. Describe the ritual of returning to it, hour after hour.',
          mimicWordContext:
              'The pastime that fills weekends and spare drawers. Describe the supplies, the progress, the gentle pride.',
          realWordProContext:
              'A fixation that eats whole days, collections grown wrong, the same thought circling without rest.',
          mimicWordProContext:
              'A pastime loved in free hours, tools and supplies, shelves of slow progress, joy in the making.',
        ),
        WordPair(
          realWord: 'Phobia',
          mimicWord: 'Fear',
          realWordContext:
              'The specific terror with a name and a heartbeat of its own. Describe the sweating palms and the avoidance maps.',
          mimicWordContext:
              'The ancient alarm that fires whether or not it should. Describe the cold hands and the loud heart.',
          realWordProContext:
              'A terror pinned to one thing, spiders or heights or small spaces, a body that betrays at the sight.',
          mimicWordProContext:
              'An alarm raised inside the chest when danger shows, cold hands before the drop, relief when it passes.',
        ),
        WordPair(
          realWord: 'Cold Spot',
          mimicWord: 'Draft',
          realWordContext:
              'The patch of air that is suddenly, wrongly winter. Describe walking through it and stopping still.',
          mimicWordContext:
              'The moving air that finds every gap and every neck. Describe the flickering flame it bends.',
          realWordProContext:
              'One corner of the room suddenly winter, breath visible indoors, a presence walking through.',
          mimicWordProContext:
              'A sliver of air sliding under the door, curtains breathing, a chill chasing the warm room.',
        ),
        WordPair(
          realWord: 'Glitch',
          mimicWord: 'Error',
          realWordContext:
              'The world skipping like a scratched disc. Describe the frozen frame and the jump that swallows a second.',
          mimicWordContext:
              'The small mistake that quietly corrupts the whole output. Describe the red underline and the wrong total.',
          realWordProContext:
              'Reality skipping frames, walls flickering, the same stranger passing twice in one minute.',
          mimicWordProContext:
              'A wrong line of code, a crash and a restart, warnings in the console, fixed in the next patch.',
        ),
        WordPair(
          realWord: 'Premonition',
          mimicWord: 'Thought',
          realWordContext:
              'The knowing that arrives before any reason for it. Describe the certainty about the phone about to ring.',
          mimicWordContext:
              'The private sentence your head runs all day. Describe the loops it takes and the ones you cannot stop.',
          realWordProContext:
              'Knowing before it happens, dreams that come true, a dread with a date attached.',
          mimicWordProContext:
              'A notion passing through the mind, considered, kept or dismissed, silent and weightless.',
        ),
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
  ///
  /// Contexts are merged by parallel index — the localized list is a 1:1
  /// translation of the base list (verified by word_context_test), so the
  /// localized pair at index i inherits the English definition of the base
  /// pair at index i. Contexts are English-only for every language (owner's
  /// call — localized context text reads as "cringe" to Filipino and
  /// Cebuano players, who are comfortable reading English descriptions).
  static List<WordPack> getPacksForLanguage(String code) {
    if (code == 'en') return packs;
    final Map<String, List<WordPair>>? langMap =
        code == 'fil' ? _filPairs : (code == 'ceb' ? _cebPairs : null);
    if (langMap == null) return packs;
    return packs.map((p) {
      final localized = langMap[p.id];
      if (localized == null || localized.isEmpty) return p;
      final merged = <WordPair>[];
      for (var i = 0; i < localized.length; i++) {
        final lp = localized[i];
        final base = i < p.pairs.length ? p.pairs[i] : null;
        merged.add(WordPair(
          realWord: lp.realWord,
          mimicWord: lp.mimicWord,
          realWordContext: base?.realWordContext ?? '',
          mimicWordContext: base?.mimicWordContext ?? '',
          realWordProContext: base?.realWordProContext ?? '',
          mimicWordProContext: base?.mimicWordProContext ?? '',
        ));
      }
      return WordPack(
        id: p.id,
        name: p.name,
        description: p.description,
        category: p.category,
        icon: p.icon,
        pairs: merged,
      );
    }).toList();
  }
}
