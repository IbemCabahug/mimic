// lib/game/services/word_silhouette_resolver.dart

enum WordSilhouetteType {
  dagger,
  scythe,
  skull,
  coffin,
  mansion,
  candle,
  mirror,
  poison,
  noose,
  chainsaw,
  grimoire,
  aswangWings,
  beastClaws,
  specter,
  spider,
  eye,
  forestTree,
  doll,
  graveyard,
  altar,
  key,
  mask,
  moon,
  generalHorror,
}

class WordSilhouetteResolver {
  static const Map<String, WordSilhouetteType> _keywordMap = {
    // Weapons / Blades
    'dagger': WordSilhouetteType.dagger,
    'knife': WordSilhouetteType.dagger,
    'blade': WordSilhouetteType.dagger,
    'sword': WordSilhouetteType.dagger,
    'cleaver': WordSilhouetteType.dagger,
    'scalpel': WordSilhouetteType.dagger,
    'machete': WordSilhouetteType.dagger,
    'cutlass': WordSilhouetteType.dagger,

    // Reaping / Heavy Tools
    'scythe': WordSilhouetteType.scythe,
    'sickle': WordSilhouetteType.scythe,
    'reaper': WordSilhouetteType.scythe,
    'chainsaw': WordSilhouetteType.chainsaw,
    'axe': WordSilhouetteType.chainsaw,
    'ax': WordSilhouetteType.chainsaw,
    'hammer': WordSilhouetteType.chainsaw,
    'crowbar': WordSilhouetteType.chainsaw,

    // Death / Remains
    'skull': WordSilhouetteType.skull,
    'skeleton': WordSilhouetteType.skull,
    'bone': WordSilhouetteType.skull,
    'corpse': WordSilhouetteType.skull,
    'body': WordSilhouetteType.skull,
    'remains': WordSilhouetteType.skull,
    'coffin': WordSilhouetteType.coffin,
    'casket': WordSilhouetteType.coffin,
    'sarcophagus': WordSilhouetteType.coffin,
    'tomb': WordSilhouetteType.coffin,
    'crypt': WordSilhouetteType.coffin,
    'graveyard': WordSilhouetteType.graveyard,
    'cemetery': WordSilhouetteType.graveyard,
    'headstone': WordSilhouetteType.graveyard,
    'grave': WordSilhouetteType.graveyard,

    // Architecture / Places
    'mansion': WordSilhouetteType.mansion,
    'manor': WordSilhouetteType.mansion,
    'house': WordSilhouetteType.mansion,
    'asylum': WordSilhouetteType.mansion,
    'castle': WordSilhouetteType.mansion,
    'tower': WordSilhouetteType.mansion,
    'hospital': WordSilhouetteType.mansion,
    'cabin': WordSilhouetteType.mansion,
    'dungeon': WordSilhouetteType.mansion,
    'cellar': WordSilhouetteType.mansion,
    'attic': WordSilhouetteType.mansion,

    // Fire / Light / Flame
    'candle': WordSilhouetteType.candle,
    'flame': WordSilhouetteType.candle,
    'fire': WordSilhouetteType.candle,
    'torch': WordSilhouetteType.candle,
    'lantern': WordSilhouetteType.candle,
    'santelmo': WordSilhouetteType.candle,

    // Mirrors / Glass
    'mirror': WordSilhouetteType.mirror,
    'glass': WordSilhouetteType.mirror,
    'reflection': WordSilhouetteType.mirror,

    // Poison / Liquids / Chemicals
    'poison': WordSilhouetteType.poison,
    'arsenic': WordSilhouetteType.poison,
    'cyanide': WordSilhouetteType.poison,
    'vial': WordSilhouetteType.poison,
    'potion': WordSilhouetteType.poison,
    'syringe': WordSilhouetteType.poison,
    'acid': WordSilhouetteType.poison,
    'venom': WordSilhouetteType.poison,
    'toxin': WordSilhouetteType.poison,

    // Rope / Restraints
    'noose': WordSilhouetteType.noose,
    'rope': WordSilhouetteType.noose,
    'gallows': WordSilhouetteType.noose,
    'strangle': WordSilhouetteType.noose,
    'chains': WordSilhouetteType.key,
    'key': WordSilhouetteType.key,
    'lock': WordSilhouetteType.key,
    'cage': WordSilhouetteType.key,

    // Grimoires / Tomes / Books
    'book': WordSilhouetteType.grimoire,
    'grimoire': WordSilhouetteType.grimoire,
    'tome': WordSilhouetteType.grimoire,
    'scroll': WordSilhouetteType.grimoire,
    'diary': WordSilhouetteType.grimoire,
    'bible': WordSilhouetteType.grimoire,

    // Wings / Aerial Entities
    'wings': WordSilhouetteType.aswangWings,
    'aswang': WordSilhouetteType.aswangWings,
    'manananggal': WordSilhouetteType.aswangWings,
    'wakwak': WordSilhouetteType.aswangWings,
    'bat': WordSilhouetteType.aswangWings,
    'gargoyle': WordSilhouetteType.aswangWings,
    'bird': WordSilhouetteType.aswangWings,
    'minokawa': WordSilhouetteType.aswangWings,

    // Claws / Beasts / Monsters
    'claws': WordSilhouetteType.beastClaws,
    'beast': WordSilhouetteType.beastClaws,
    'monster': WordSilhouetteType.beastClaws,
    'wolf': WordSilhouetteType.beastClaws,
    'werewolf': WordSilhouetteType.beastClaws,
    'tikbalang': WordSilhouetteType.beastClaws,
    'sigbin': WordSilhouetteType.beastClaws,
    'chupacabra': WordSilhouetteType.beastClaws,
    'amomongo': WordSilhouetteType.beastClaws,

    // Phantoms / Wraiths / Apparitions
    'ghost': WordSilhouetteType.specter,
    'specter': WordSilhouetteType.specter,
    'phantom': WordSilhouetteType.specter,
    'wraith': WordSilhouetteType.specter,
    'spirit': WordSilhouetteType.specter,
    'multo': WordSilhouetteType.specter,
    'white lady': WordSilhouetteType.specter,
    'red lady': WordSilhouetteType.specter,
    'pugot': WordSilhouetteType.specter,

    // Arachnids / Vermin / Hexes
    'spider': WordSilhouetteType.spider,
    'web': WordSilhouetteType.spider,
    'insect': WordSilhouetteType.spider,
    'mambabarang': WordSilhouetteType.spider,
    'mangkukulam': WordSilhouetteType.spider,

    // Eyes / Perception
    'eye': WordSilhouetteType.eye,
    'watcher': WordSilhouetteType.eye,
    'cyclops': WordSilhouetteType.eye,
    'bungisngis': WordSilhouetteType.eye,

    // Trees / Forest / Folklore
    'tree': WordSilhouetteType.forestTree,
    'forest': WordSilhouetteType.forestTree,
    'woods': WordSilhouetteType.forestTree,
    'balete': WordSilhouetteType.forestTree,
    'kapre': WordSilhouetteType.forestTree,
    'nuno': WordSilhouetteType.forestTree,
    'duwende': WordSilhouetteType.forestTree,
    'swamp': WordSilhouetteType.forestTree,

    // Dolls / Effigies
    'doll': WordSilhouetteType.doll,
    'puppet': WordSilhouetteType.doll,
    'tiyanak': WordSilhouetteType.doll,
    'patianak': WordSilhouetteType.doll,
    'voodoo': WordSilhouetteType.doll,

    // Rituals / Occult Altars
    'altar': WordSilhouetteType.altar,
    'pentagram': WordSilhouetteType.altar,
    'ritual': WordSilhouetteType.altar,
    'chalice': WordSilhouetteType.altar,
    'cauldron': WordSilhouetteType.altar,

    // Masks / Identity
    'mask': WordSilhouetteType.mask,
    'mimic': WordSilhouetteType.mask,
    'disguise': WordSilhouetteType.mask,

    // Moon / Night
    'moon': WordSilhouetteType.moon,
    'eclipse': WordSilhouetteType.moon,
    'bakunawa': WordSilhouetteType.moon,
    'night': WordSilhouetteType.moon,
  };

  /// Resolves a silhouette archetype based on word content and category fallback.
  static WordSilhouetteType resolve(String word, {String? category}) {
    final lower = word.toLowerCase().trim();

    // 1. Direct keyword check
    for (final entry in _keywordMap.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }

    // 2. Category fallback
    final cat = (category ?? '').toLowerCase();
    if (cat.contains('place') || cat.contains('location') || cat.contains('dark places')) {
      return WordSilhouetteType.mansion;
    }
    if (cat.contains('weapon') || cat.contains('murder') || cat.contains('crime')) {
      return WordSilhouetteType.dagger;
    }
    if (cat.contains('survival')) {
      return WordSilhouetteType.chainsaw;
    }
    if (cat.contains('artifact') || cat.contains('curse') || cat.contains('cursed')) {
      return WordSilhouetteType.grimoire;
    }
    if (cat.contains('ritual') || cat.contains('dark rituals') || cat.contains('occult')) {
      return WordSilhouetteType.altar;
    }
    if (cat.contains('monster') || cat.contains('being') || cat.contains('creature')) {
      return WordSilhouetteType.beastClaws;
    }
    if (cat.contains('folklore') || cat.contains('legend') || cat.contains('philippine')) {
      return WordSilhouetteType.aswangWings;
    }

    return WordSilhouetteType.generalHorror;
  }
}
