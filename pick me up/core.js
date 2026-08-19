(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.RiftwardCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const VERSION = 1;
  const SAVE_KEY = "riftward-save-v1";
  const PARTY_POSITIONS = ["Front A", "Front B", "Mid A", "Mid B", "Rear"];
  const RARITY_CAPS = { 1: 10, 2: 20, 3: 30, 4: 50, 5: 70, 6: 99, 7: 120 };
  const GROWTH_RANGES = {
    1: [3.4, 4.6, 20, 85],
    2: [4.0, 5.1, 30, 88],
    3: [4.7, 5.8, 40, 91],
    4: [5.3, 6.4, 50, 94],
    5: [5.9, 7.0, 60, 96],
    6: [6.6, 7.8, 72, 98],
    7: [7.4, 8.8, 85, 100],
  };

  const ROLES = {
    Guardian: {
      icon: "◇",
      line: "Front",
      description: "Protegge la linea e intercetta le minacce.",
      weights: [0.31, 0.04, 0.48, 0.17],
      attackRange: 48,
      cadence: 1.25,
      moveSpeed: 47,
      skill: ["Aegis Brace", "Riduce i danni e attira i nemici vicini.", 14],
    },
    Vanguard: {
      icon: "†",
      line: "Front",
      description: "Pressione offensiva, engage e danno ravvicinato.",
      weights: [0.47, 0.04, 0.28, 0.21],
      attackRange: 46,
      cadence: 1.0,
      moveSpeed: 55,
      skill: ["Driving Cleave", "Un colpo pesante che può spezzare la guardia.", 9],
    },
    Lancer: {
      icon: "↟",
      line: "Mid",
      description: "Controlla la distanza e arresta le cariche.",
      weights: [0.39, 0.04, 0.27, 0.3],
      attackRange: 76,
      cadence: 1.1,
      moveSpeed: 52,
      skill: ["Pinning Thrust", "Affondo preciso con breve immobilizzazione.", 10],
    },
    Ranger: {
      icon: "➶",
      line: "Rear",
      description: "Danno a distanza, munizioni limitate e scouting.",
      weights: [0.2, 0.08, 0.17, 0.55],
      attackRange: 255,
      cadence: 1.18,
      moveSpeed: 58,
      skill: ["Marked Shot", "Colpo ad alta precisione contro un bersaglio prioritario.", 11],
    },
    Mage: {
      icon: "✧",
      line: "Rear",
      description: "Controllo ad area e danno arcano.",
      weights: [0.05, 0.58, 0.18, 0.19],
      attackRange: 220,
      cadence: 1.42,
      moveSpeed: 46,
      skill: ["Ember Lattice", "Detonazione arcana che colpisce un gruppo.", 13],
    },
    Support: {
      icon: "+",
      line: "Mid",
      description: "Cura, stabilizza il morale e protegge gli alleati.",
      weights: [0.08, 0.46, 0.3, 0.16],
      attackRange: 170,
      cadence: 1.48,
      moveSpeed: 48,
      skill: ["Mend", "Cura l'alleato vivente con la salute più bassa.", 10],
    },
  };

  const FIRST_NAMES = [
    "Aella", "Bren", "Cael", "Doria", "Edrin", "Fara", "Galen", "Hesta", "Iven", "Kaia",
    "Loran", "Mira", "Neris", "Orin", "Pyria", "Quill", "Rhea", "Soren", "Tavia", "Ulric",
    "Veya", "Wren", "Yara", "Zephan", "Arlen", "Briar", "Cerys", "Dain", "Elowen", "Fenn",
  ];
  const LAST_NAMES = [
    "Ashfall", "Blackmere", "Cinder", "Dawnward", "Emberlain", "Frost", "Greywake", "Hollow",
    "Ironwood", "Jade", "Kestrel", "Lightfoot", "Mourn", "Nightglass", "Oakshield", "Pyre",
    "Rook", "Stoneveil", "Thorn", "Umber", "Vale", "Wyrd", "Yarrow", "Zephyr",
  ];
  const ORIGINS = [
    "Marche di Veyra", "Città sommersa di Oros", "Cintura mineraria di Khel", "Nomadi di Sable",
    "Isole di vetro", "Bosco di Talren", "Fortezza di Ardent", "Archivio di Myr", "Costa cinerea",
  ];
  const BACKGROUNDS = [
    "Milizia di confine", "Cacciatore di rovine", "Apprendista artigiano", "Guardia carovaniera",
    "Studioso errante", "Disertore imperiale", "Sopravvissuto del Rift", "Medico da campo",
  ];
  const PROFESSIONS = ["Fabbro", "Conciatore", "Cartografo", "Erborista", "Carpentiere", "Archivista", "Cuoco", "Minatore"];
  const TRAITS = [
    ["Nervi saldi", "Resiste meglio a Fear e Panic."],
    ["Istinto protettivo", "Reagisce più spesso al pericolo degli alleati."],
    ["Passo leggero", "Movimento ed evasione leggermente migliori."],
    ["Tenace", "Resta efficace anche quando è ferito."],
    ["Occhio clinico", "Impara più rapidamente dalle missioni difficili."],
    ["Testardo", "Grande coraggio, ma scarsa disciplina."],
    ["Frugale", "Consuma meno munizioni e risorse."],
    ["Socievole", "Costruisce legami più rapidamente."],
    ["Solitario", "Bond più lenti, stabilità personale maggiore."],
    ["Paura del fuoco", "Stress elevato in presenza di Burn."],
    ["Mano ferma", "Precisione migliorata sotto pressione."],
    ["Memoria lunga", "Gli eventi intensi decadono più lentamente."],
  ];
  const QUOTES = [
    "Datemi informazioni affidabili e farò il resto.",
    "Non prometto di non avere paura. Prometto di non sprecare la paura.",
    "La torre non cambia. Siamo noi a dover imparare.",
    "Una formazione è una promessa che facciamo gli uni agli altri.",
    "Se devo entrare nel Rift, voglio sapere chi protegge il ritorno.",
    "Ogni cicatrice è un rapporto scritto sulla pelle.",
  ];

  const EQUIPMENT_TEMPLATES = {
    Guardian: {
      main: ["Spada da presidio", "sword", 12],
      sub: ["Scudo a mandorla", "shield", 18],
      armor: ["Corazza di maglia", "mail", 19],
    },
    Vanguard: {
      main: ["Lama mercenaria", "sword", 16],
      sub: ["Pugnale di guardia", "blade", 5],
      armor: ["Brigantina", "mail", 13],
    },
    Lancer: {
      main: ["Lancia d'acciaio", "spear", 15],
      sub: ["Cinghia di presa", "grip", 4],
      armor: ["Giaco rinforzato", "leather", 11],
    },
    Ranger: {
      main: ["Arco corto laminato", "bow", 14],
      sub: ["Faretra da campo", "quiver", 24],
      armor: ["Cuoio da esploratore", "leather", 8],
    },
    Mage: {
      main: ["Verga di quarzo", "staff", 13],
      sub: ["Focus runico", "focus", 12],
      armor: ["Veste schermata", "cloth", 5],
    },
    Support: {
      main: ["Mazza cerimoniale", "mace", 10],
      sub: ["Focus votivo", "focus", 10],
      armor: ["Veste da campo", "cloth", 7],
    },
  };

  const STAGE_BLUEPRINTS = {
    1: {
      type: "Subjugation",
      name: "La strada spezzata",
      biome: "Bosco cinereo",
      stream: "CENERE SULLA FRONTIERA",
      objective: "Elimina tutte le minacce",
      description: "Predoni del Rift hanno chiuso l'unica via verso la torre. Un ingaggio breve, ma abbastanza vero da mostrare il prezzo di una formazione sbagliata.",
      duration: 52,
      hue: 154,
      clues: ["Forza nemica stimata: 5-7", "Nessuna unità aerea rilevata", "Il terreno favorisce la prima linea"],
      enemyWaves: [
        { at: 0, units: [{ kind: "raider", count: 4 }, { kind: "skirmisher", count: 1 }] },
        { at: 12, units: [{ kind: "raider", count: 2 }] },
      ],
    },
    2: {
      type: "Survival",
      name: "Campana nella nebbia",
      biome: "Borgo evacuato",
      stream: "CENERE SULLA FRONTIERA",
      objective: "Sopravvivi per 45 secondi",
      description: "La campana d'allarme attira sciami dalle case vuote. Il numero di uccisioni è secondario: risorse, munizioni e disciplina decidono la sopravvivenza.",
      duration: 45,
      hue: 190,
      clues: ["Sciami intervallati di circa 10 secondi", "Presenza di tiratori non confermata", "Ritirata disponibile"],
      enemyWaves: [
        { at: 0, units: [{ kind: "raider", count: 3 }] },
        { at: 9, units: [{ kind: "raider", count: 3 }, { kind: "archer", count: 1 }] },
        { at: 20, units: [{ kind: "skirmisher", count: 4 }] },
        { at: 31, units: [{ kind: "brute", count: 1 }, { kind: "raider", count: 3 }] },
      ],
    },
    3: {
      type: "Exploration",
      name: "Osservatorio sommerso",
      biome: "Rovine allagate",
      stream: "CENERE SULLA FRONTIERA",
      objective: "Metti in sicurezza 3 punti d'interesse",
      description: "Le mappe parlano di un osservatorio sotto il fango. Avanzare rivela informazioni persistenti sul climax dello Stream, ma ogni deviazione aumenta il rischio.",
      duration: 68,
      hue: 208,
      clues: ["Tre segnali dimensionali separati", "Bestie rapide pattugliano le passerelle", "Una debolezza del boss può essere scoperta"],
      enemyWaves: [
        { at: 0, units: [{ kind: "skirmisher", count: 3 }] },
        { at: 15, units: [{ kind: "raider", count: 3 }, { kind: "archer", count: 2 }] },
        { at: 31, units: [{ kind: "brute", count: 1 }, { kind: "skirmisher", count: 2 }] },
      ],
    },
    4: {
      type: "Defense",
      name: "L'ultima lanterna",
      biome: "Santuario in rovina",
      stream: "CENERE SULLA FRONTIERA",
      objective: "Proteggi il faro del Rift",
      description: "Il faro deve restare integro mentre l'Archivio decodifica le coordinate. Gli eroi scelgono quando intercettare e quando mantenere la linea.",
      duration: 50,
      hue: 36,
      clues: ["Integrità obiettivo: 100%", "I bruti privilegiano il faro", "La retroguardia sarà sotto pressione"],
      enemyWaves: [
        { at: 0, units: [{ kind: "raider", count: 4 }] },
        { at: 11, units: [{ kind: "archer", count: 2 }, { kind: "skirmisher", count: 2 }] },
        { at: 24, units: [{ kind: "brute", count: 2 }, { kind: "raider", count: 2 }] },
        { at: 37, units: [{ kind: "brute", count: 1 }, { kind: "skirmisher", count: 4 }] },
      ],
    },
    5: {
      type: "Boss",
      name: "Custode delle radici",
      biome: "Cuore del bosco",
      stream: "CENERE SULLA FRONTIERA // CLIMAX",
      objective: "Abbatti il Custode",
      description: "La minaccia nascosta dello Stream attende sotto la torre. Il Custode alterna urti, richiamo di progenie e un ruggito che mette alla prova il morale.",
      duration: 90,
      hue: 118,
      clues: ["Boss a tre soglie di furia", "Debolezza: attacchi a distanza dopo lo stagger", "Ruggito: rischio Fear sotto 45 Morale"],
      enemyWaves: [
        { at: 0, units: [{ kind: "boss", count: 1 }, { kind: "raider", count: 2 }] },
        { at: 22, units: [{ kind: "skirmisher", count: 3 }] },
        { at: 45, units: [{ kind: "raider", count: 3 }, { kind: "archer", count: 1 }] },
      ],
    },
  };

  const ENEMY_TEMPLATES = {
    raider: { name: "Predone cavo", hp: 155, attack: 17, defense: 7, speed: 43, range: 43, cadence: 1.25, hue: 8, threat: 1 },
    skirmisher: { name: "Segugio del Rift", hp: 112, attack: 15, defense: 4, speed: 66, range: 37, cadence: 0.92, hue: 278, threat: 1 },
    archer: { name: "Tiratore velato", hp: 105, attack: 16, defense: 3, speed: 39, range: 235, cadence: 1.38, hue: 330, threat: 2 },
    brute: { name: "Demolitore d'ossa", hp: 305, attack: 28, defense: 14, speed: 31, range: 51, cadence: 1.72, hue: 22, threat: 3 },
    boss: { name: "Custode delle radici", hp: 1850, attack: 35, defense: 21, speed: 29, range: 62, cadence: 1.55, hue: 112, threat: 8 },
  };

  function hashString(value) {
    let hash = 2166136261;
    const text = String(value);
    for (let i = 0; i < text.length; i += 1) {
      hash ^= text.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
  }

  function mulberry32(seed) {
    let value = seed >>> 0;
    return function random() {
      value += 0x6d2b79f5;
      let t = value;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function rngFrom(seed) {
    return mulberry32(hashString(seed));
  }

  function pick(rng, list) {
    return list[Math.floor(rng() * list.length)];
  }

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
  }

  function round(value, places) {
    const factor = 10 ** (places || 0);
    return Math.round(value * factor) / factor;
  }

  function uid(prefix, seed) {
    const a = hashString(`${seed}:a`).toString(36).slice(0, 6);
    const b = hashString(`${seed}:b`).toString(36).slice(0, 5);
    return `${prefix}-${a}${b}`.toUpperCase();
  }

  function makeWorldSeed() {
    if (typeof crypto !== "undefined" && crypto.getRandomValues) {
      const words = new Uint32Array(4);
      crypto.getRandomValues(words);
      return Array.from(words, (word) => word.toString(16).padStart(8, "0")).join("");
    }
    return `${Date.now().toString(16)}${Math.random().toString(16).slice(2)}`.padEnd(32, "0").slice(0, 32);
  }

  function stars(rarity) {
    return "★".repeat(Number(rarity) || 0);
  }

  function xpToNext(level, rarity) {
    const factors = { 1: 1, 2: 1.2, 3: 1.55, 4: 2, 5: 2.7, 6: 3.6, 7: 4.4 };
    return Math.round(25 * level ** 1.55 * (factors[rarity] || 1));
  }

  function makeEquipment(role, seed, qualityBoost) {
    const rng = rngFrom(`${seed}:equipment`);
    const template = EQUIPMENT_TEMPLATES[role];
    const quality = round(0.94 + rng() * 0.12 + (qualityBoost || 0), 2);
    const main = {
      id: uid("EQ", `${seed}:main`),
      name: template.main[0],
      slot: "main",
      type: template.main[1],
      grade: "D",
      quality,
      reinforcement: 0,
      durability: 100,
      weaponPower: Math.round(template.main[2] * quality),
      accuracy: role === "Ranger" ? 8 : 3,
      crit: role === "Vanguard" || role === "Ranger" ? 2 : 0,
    };
    const sub = {
      id: uid("EQ", `${seed}:sub`),
      name: template.sub[0],
      slot: "sub",
      type: template.sub[1],
      grade: "D",
      quality,
      reinforcement: 0,
      durability: 100,
      block: role === "Guardian" ? Math.round(template.sub[2] * quality) : 0,
      focus: role === "Mage" || role === "Support" ? Math.round(template.sub[2] * quality) : 0,
      ammo: role === "Ranger" ? Math.round(template.sub[2] * quality) : 0,
    };
    const armor = {
      id: uid("EQ", `${seed}:armor`),
      name: template.armor[0],
      slot: "armor",
      type: template.armor[1],
      grade: "D",
      quality,
      reinforcement: 0,
      durability: 100,
      armorDefense: Math.round(template.armor[2] * quality),
      hp: role === "Guardian" ? 30 : role === "Vanguard" || role === "Lancer" ? 15 : 0,
    };
    return { main, sub, armor, accessory: null };
  }

  function weightedStats(role, rng, rarity) {
    const weights = ROLES[role].weights;
    const baseBudget = 36 + rarity * 3 + Math.round(rng() * 7);
    const stats = weights.map((weight) => 7 + Math.round(baseBudget * weight + rng() * 3));
    return { str: stats[0], int: stats[1], sta: stats[2], agi: stats[3] };
  }

  function potentialAssessment(hero) {
    const potential = hero.potential;
    const observations = [];
    if (potential >= 90) observations.push("Ceiling impossibile da stimare");
    else if (potential >= 76) observations.push("Margine di crescita eccezionale");
    else if (potential >= 58) observations.push("Apprendimento sopra la media");
    else observations.push("Crescita metodica, non esplosiva");
    const entries = Object.entries(hero.personality).sort((a, b) => b[1] - a[1]);
    const strongest = entries[0][0];
    const labels = {
      courage: "Resta operativo sotto pressione",
      discipline: "Segue con precisione la formazione",
      aggression: "Cerca attivamente aperture offensive",
      altruism: "Dà priorità alla sicurezza degli alleati",
      composure: "Decisioni molto stabili nello stress",
      curiosity: "Nota dettagli utili durante lo scouting",
      loyalty: "Alta predisposizione alla fiducia",
    };
    observations.push(labels[strongest]);
    const statPairs = Object.entries(hero.stats).sort((a, b) => b[1] - a[1]);
    observations.push(`Affinità evidente: ${statPairs[0][0].toUpperCase()}`);
    observations.push("Potenziale numerico: non disponibile al Master");
    return observations;
  }

  function generateHero(seed, rarity, forcedRole, index) {
    const rng = rngFrom(`${seed}:hero:${index || 0}:${rarity}:${forcedRole || "random"}`);
    const roleNames = Object.keys(ROLES);
    const role = forcedRole || pick(rng, roleNames);
    const range = GROWTH_RANGES[rarity];
    const potential = Math.round(range[2] + rng() * (range[3] - range[2]));
    const growth = round(range[0] + rng() * (range[1] - range[0]) + Math.max(0, potential - 70) * 0.006, 2);
    const personality = {
      courage: Math.round(25 + rng() * 70),
      discipline: Math.round(20 + rng() * 76),
      aggression: Math.round(15 + rng() * 80),
      altruism: Math.round(15 + rng() * 80),
      composure: Math.round(20 + rng() * 75),
      curiosity: Math.round(15 + rng() * 80),
      loyalty: Math.round(25 + rng() * 65),
    };
    const first = pick(rng, FIRST_NAMES);
    const last = pick(rng, LAST_NAMES);
    const heroSeed = `${seed}:${first}:${last}:${index || 0}:${Math.floor(rng() * 1e9)}`;
    const roleSkill = ROLES[role].skill;
    const hero = {
      id: uid("H", heroSeed),
      seed: hashString(heroSeed).toString(16).padStart(8, "0"),
      name: `${first} ${last}`,
      nativeRarity: rarity,
      currentRarity: rarity,
      level: 1,
      xp: 0,
      potential,
      growth,
      growthVector: [...ROLES[role].weights],
      role,
      className: role,
      origin: pick(rng, ORIGINS),
      background: pick(rng, BACKGROUNDS),
      profession: pick(rng, PROFESSIONS),
      stats: weightedStats(role, rng, rarity),
      personality,
      traits: [pick(rng, TRAITS), pick(rng, TRAITS)].filter((trait, pos, arr) => arr.findIndex((candidate) => candidate[0] === trait[0]) === pos),
      skills: [
        { id: uid("SK", `${heroSeed}:role`), name: roleSkill[0], description: roleSkill[1], level: 1, xp: 0, cooldown: roleSkill[2], tier: "Lesser" },
        { id: uid("SK", `${heroSeed}:discipline`), name: "Field Discipline", description: "Esperienza pratica nel mantenere la formazione.", level: 1, xp: 0, cooldown: 0, tier: "Passive" },
      ],
      morale: Math.round(60 + rng() * 25),
      fatigue: Math.round(rng() * 9),
      injuries: [],
      equipment: makeEquipment(role, heroSeed),
      hue: Math.round(rng() * 350),
      skinHue: Math.round(16 + rng() * 25),
      quote: pick(rng, QUOTES),
      memories: [{ type: "SUMMONED", text: "Ha attraversato il Rift e ha visto il Nexus per la prima volta.", intensity: 30 }],
      missions: 0,
      victories: 0,
      kills: 0,
      state: "ALIVE",
      createdAt: Date.now(),
    };
    hero.assessment = potentialAssessment(hero);
    return hero;
  }

  function stageScale(floor) {
    return 0.82 + floor * 0.115;
  }

  function generateStage(worldSeed, floor) {
    const blueprint = STAGE_BLUEPRINTS[floor];
    if (!blueprint) return null;
    const rng = rngFrom(`${worldSeed}:floor:${floor}`);
    const variance = round(0.96 + rng() * 0.08, 3);
    const descriptor = JSON.parse(JSON.stringify(blueprint));
    descriptor.id = uid("STAGE", `${worldSeed}:${floor}`);
    descriptor.floor = floor;
    descriptor.seed = hashString(`${worldSeed}:floor:${floor}`).toString(16).padStart(8, "0");
    descriptor.threatBudget = Math.round(100 * floor ** 1.18 * variance);
    descriptor.worldVariance = variance;
    descriptor.rewardBudget = Math.round(450 * floor ** 1.12);
    descriptor.enemyScale = round(stageScale(floor), 3);
    descriptor.generatedAt = Date.now();
    return descriptor;
  }

  function addEvent(state, category, title, text, severity, payload) {
    const event = {
      id: uid("EV", `${Date.now()}:${state.events.length}:${title}`),
      timestamp: Date.now(),
      category,
      title,
      text,
      severity: severity || "info",
      payload: payload || null,
      read: false,
    };
    state.events.unshift(event);
    state.events = state.events.slice(0, 120);
    return event;
  }

  function addLedger(state, currency, delta, reason, source) {
    state.ledger.unshift({
      id: uid("TX", `${Date.now()}:${state.ledger.length}:${reason}`),
      timestamp: Date.now(),
      currency,
      delta,
      reason,
      source,
    });
    state.ledger = state.ledger.slice(0, 180);
  }

  function relationshipKey(heroA, heroB) {
    return [heroA, heroB].sort().join("::");
  }

  function initializeRelationships(state, hero) {
    state.heroes.forEach((other) => {
      if (other.id === hero.id || other.state !== "ALIVE") return;
      const rng = rngFrom(`${state.world.seed}:bond:${relationshipKey(hero.id, other.id)}`);
      state.relationships[relationshipKey(hero.id, other.id)] = Math.round(-8 + rng() * 34);
    });
  }

  function getBond(state, heroA, heroB) {
    if (!heroA || !heroB || heroA === heroB) return 0;
    return state.relationships[relationshipKey(heroA, heroB)] || 0;
  }

  function createInitialState(seed) {
    const worldSeed = seed || makeWorldSeed();
    const state = {
      version: VERSION,
      world: {
        id: uid("WORLD", worldSeed),
        seed: worldSeed,
        masterName: "Aster",
        currentFloor: 1,
        maxUnlockedFloor: 1,
        towerFloors: 100,
        completedFloors: [],
        gold: 220000,
        gems: 2500,
        promotionStones: 1,
        transcendentTickets: 0,
        materials: { ore: 8, leather: 6, wood: 7, cores: 0, medicine: 2, food: 6 },
        createdAt: Date.now(),
        lastSavedAt: Date.now(),
        offlineCapHours: 8,
      },
      heroes: [],
      party: [null, null, null, null, null],
      relationships: {},
      inventory: [],
      facilities: {
        summoning: { level: 1, unlocked: true },
        training: { level: 1, unlocked: true },
        armory: { level: 1, unlocked: true },
        warehouse: { level: 1, unlocked: true },
        lodging: { level: 1, unlocked: true },
        smithy: { level: 0, unlocked: false, unlockFloor: 5 },
        workshop: { level: 0, unlocked: false, unlockFloor: 5 },
        research: { level: 0, unlocked: false, unlockFloor: 10 },
        infirmary: { level: 0, unlocked: false, unlockFloor: 15 },
        synthesis: { level: 0, unlocked: false, unlockFloor: 15 },
        magic: { level: 0, unlocked: false, unlockFloor: 25 },
        dimensionGate: { level: 0, unlocked: false, unlockFloor: 50 },
      },
      stages: {},
      pity: { highGrade: 0, transcendent: 0, spark: 0 },
      events: [],
      ledger: [],
      memorial: [],
      settings: { reducedMotion: false, combatText: true, tutorialSeen: false },
      activeMission: null,
      summonCounter: 0,
    };

    const starterRoles = ["Guardian", "Vanguard", "Lancer", "Ranger", "Support", "Mage"];
    starterRoles.forEach((role, index) => {
      const rarity = index === 4 ? 2 : 1;
      const hero = generateHero(worldSeed, rarity, role, `starter-${index}`);
      state.heroes.push(hero);
      initializeRelationships(state, hero);
    });
    state.party = [state.heroes[0].id, state.heroes[1].id, state.heroes[2].id, state.heroes[3].id, state.heroes[4].id];
    state.stages[1] = { descriptor: generateStage(worldSeed, 1), attempts: 0, cleared: false, bestResult: null };
    addEvent(state, "SYSTEM", "Nexus riattivato", "Sei eroi attendono la prima valutazione. La Torre ha materializzato il Piano 1.", "good");
    addEvent(state, "INTEL", "Stream rilevato", "Cenere sulla Frontiera collega i primi cinque piani. Gli indizi ottenuti resteranno validi nei retry.", "info");
    addLedger(state, "gold", 220000, "Dotazione iniziale del Nexus", "onboarding");
    addLedger(state, "gems", 2500, "Riserva non acquistata del prototipo", "onboarding");
    return state;
  }

  function migrateState(input) {
    if (!input || !input.world || !Array.isArray(input.heroes)) return null;
    const state = input;
    state.version = VERSION;
    state.party = Array.isArray(state.party) ? state.party.slice(0, 5) : [null, null, null, null, null];
    while (state.party.length < 5) state.party.push(null);
    state.relationships ||= {};
    state.inventory ||= [];
    state.events ||= [];
    state.ledger ||= [];
    state.memorial ||= [];
    state.settings ||= { reducedMotion: false, combatText: true, tutorialSeen: true };
    state.stages ||= {};
    state.pity ||= { highGrade: 0, transcendent: 0, spark: 0 };
    state.summonCounter ||= 0;
    state.world.materials ||= { ore: 0, leather: 0, wood: 0, cores: 0, medicine: 0, food: 0 };
    if (state.activeMission) {
      state.activeMission = null;
      addEvent(state, "MISSION", "Collegamento interrotto", "La missione incompleta è stata registrata come fallimento. Le morti già avvenute restano definitive.", "warn");
    }
    return state;
  }

  function applyOfflineProgress(state, now) {
    const current = now || Date.now();
    const elapsedMs = Math.max(0, current - (state.world.lastSavedAt || current));
    const cappedHours = Math.min(state.world.offlineCapHours || 8, elapsedMs / 3600000);
    const worldHours = cappedHours * 3;
    if (worldHours < 0.05) return { worldHours: 0, recovered: 0 };
    let recovered = 0;
    state.heroes.forEach((hero) => {
      if (hero.state !== "ALIVE") return;
      const before = hero.fatigue;
      hero.fatigue = clamp(Math.round(hero.fatigue - worldHours * (5 + (state.facilities.lodging.level || 1))), 0, 100);
      hero.morale = clamp(Math.round(hero.morale + worldHours * 1.4), 0, 100);
      recovered += before - hero.fatigue;
    });
    if (cappedHours >= 0.25) addEvent(state, "REPORT", "Rapporto offline", `${round(worldHours, 1)} ore-Nexus risolte. Fatigue complessiva recuperata: ${recovered}.`, "info");
    state.world.lastSavedAt = current;
    return { worldHours: round(worldHours, 2), recovered };
  }

  function getStage(state, floor) {
    const target = Number(floor);
    if (target < 1 || target > 5 || target > state.world.maxUnlockedFloor) return null;
    if (!state.stages[target]) {
      state.stages[target] = { descriptor: generateStage(state.world.seed, target), attempts: 0, cleared: false, bestResult: null };
      addEvent(state, "INTEL", `Piano ${target} materializzato`, "Il descriptor è ora persistente: ogni retry userà la stessa missione, mappa e composizione chiave.", "info");
    }
    return state.stages[target];
  }

  function getAliveHeroes(state) {
    return state.heroes.filter((hero) => hero.state === "ALIVE");
  }

  function getPartyHeroes(state) {
    return state.party.map((id) => state.heroes.find((hero) => hero.id === id && hero.state === "ALIVE") || null);
  }

  function assignPartySlot(state, slot, heroId) {
    const index = clamp(Number(slot), 0, 4);
    const hero = state.heroes.find((candidate) => candidate.id === heroId && candidate.state === "ALIVE");
    if (!hero) return { ok: false, message: "Eroe non disponibile." };
    const prior = state.party.indexOf(heroId);
    if (prior >= 0) state.party[prior] = null;
    state.party[index] = heroId;
    return { ok: true };
  }

  function removePartySlot(state, slot) {
    const index = Number(slot);
    if (index >= 0 && index < 5) state.party[index] = null;
  }

  function autoFormParty(state) {
    const living = getAliveHeroes(state).filter((hero) => hero.fatigue < 85);
    const desired = ["Guardian", "Vanguard", "Lancer", "Support", "Ranger"];
    const chosen = [];
    desired.forEach((role) => {
      const candidate = living
        .filter((hero) => hero.role === role && !chosen.includes(hero))
        .sort((a, b) => heroPower(b) - heroPower(a))[0];
      if (candidate) chosen.push(candidate);
    });
    living
      .filter((hero) => !chosen.includes(hero))
      .sort((a, b) => heroPower(b) - heroPower(a))
      .forEach((hero) => {
        if (chosen.length < 5) chosen.push(hero);
      });
    state.party = chosen.slice(0, 5).map((hero) => hero.id);
    while (state.party.length < 5) state.party.push(null);
    return state.party;
  }

  function derivedStats(hero) {
    const equipment = Object.values(hero.equipment || {}).filter(Boolean);
    const weaponPower = equipment.reduce((sum, item) => sum + (item.weaponPower || 0), 0);
    const focusPower = equipment.reduce((sum, item) => sum + (item.focus || 0), 0);
    const armorDefense = equipment.reduce((sum, item) => sum + (item.armorDefense || 0), 0);
    const armorHp = equipment.reduce((sum, item) => sum + (item.hp || 0), 0);
    const accuracyBonus = equipment.reduce((sum, item) => sum + (item.accuracy || 0), 0);
    const critBonus = equipment.reduce((sum, item) => sum + (item.crit || 0), 0);
    const block = equipment.reduce((sum, item) => sum + (item.block || 0), 0);
    const ammo = equipment.reduce((sum, item) => sum + (item.ammo || 0), 0);
    const maxHp = Math.round(100 + hero.stats.sta * 12 + hero.level * 6 + armorHp);
    const physicalAttack = round(weaponPower + hero.stats.str * 1.75, 1);
    const magicAttack = round(focusPower + hero.stats.int * 1.9, 1);
    const defense = round(armorDefense + hero.stats.sta * 0.55, 1);
    const accuracy = clamp(round(70 + hero.stats.agi * 0.45 + accuracyBonus, 1), 35, 98);
    const evasion = clamp(round(hero.stats.agi * 0.22, 1), 0, 35);
    const crit = clamp(round(3 + hero.stats.agi * 0.08 + critBonus, 1), 3, 30);
    return { maxHp, physicalAttack, magicAttack, defense, accuracy, evasion, crit, block, ammo };
  }

  function heroPower(hero) {
    if (!hero || hero.state !== "ALIVE") return 0;
    const derived = derivedStats(hero);
    const attack = hero.role === "Mage" || hero.role === "Support" ? Math.max(derived.magicAttack, derived.physicalAttack * 0.75) : derived.physicalAttack;
    const morale = 0.8 + hero.morale / 500;
    const fatigue = 1 - Math.max(0, hero.fatigue - 50) * 0.0035;
    return Math.round((derived.maxHp * 0.22 + attack * 3 + derived.defense * 2) * morale * fatigue);
  }

  function teamReadiness(state) {
    const party = getPartyHeroes(state);
    const living = party.filter(Boolean);
    const warnings = [];
    if (living.length < 5) warnings.push(`Squadra incompleta: ${living.length}/5.`);
    const roles = living.map((hero) => hero.role);
    const front = roles.filter((role) => role === "Guardian" || role === "Vanguard").length;
    const ranged = roles.filter((role) => role === "Ranger" || role === "Mage").length;
    const support = roles.includes("Support");
    if (front < 2) warnings.push("Prima linea fragile: consigliati due frontliner.");
    if (!support) warnings.push("Nessun Support: recupero in missione limitato.");
    if (ranged < 1) warnings.push("Nessuna pressione a distanza.");
    living.forEach((hero) => {
      if (hero.fatigue >= 80) warnings.push(`${hero.name} è in Fatigue critica.`);
      else if (hero.fatigue >= 60) warnings.push(`${hero.name} è esausto.`);
      if (hero.morale < 30) warnings.push(`${hero.name} ha morale basso.`);
      if (hero.injuries.length) warnings.push(`${hero.name} ha ferite persistenti.`);
    });
    let totalBond = 0;
    let bondPairs = 0;
    for (let i = 0; i < living.length; i += 1) {
      for (let j = i + 1; j < living.length; j += 1) {
        totalBond += getBond(state, living[i].id, living[j].id);
        bondPairs += 1;
      }
    }
    const averageBond = bondPairs ? totalBond / bondPairs : 0;
    const bondBonus = clamp((averageBond - 40) * 0.12, 0, 7);
    const rawPower = living.reduce((sum, hero) => sum + heroPower(hero), 0);
    const coverage = clamp((front >= 2 ? 1 : 0.84) * (support ? 1.04 : 0.9) * (ranged ? 1.03 : 0.93), 0.7, 1.12);
    const score = Math.round(rawPower * coverage * (1 + bondBonus / 100));
    const grade = living.length < 5 ? "INCOMPLETA" : warnings.length === 0 ? "ECCELLENTE" : warnings.length <= 2 ? "STABILE" : "A RISCHIO";
    return { party, living, score, grade, warnings, averageBond: round(averageBond, 1), bondBonus: round(bondBonus, 1), roleCoverage: coverage };
  }

  function rollRarity(state, pool, rng) {
    const roll = rng() * 100;
    if (pool === "normal") {
      if (roll < 78) return 1;
      if (roll < 97) return 2;
      return 3;
    }
    if (pool === "high") {
      state.pity.highGrade += 1;
      if (state.pity.highGrade >= 100) {
        state.pity.highGrade = 0;
        return 5;
      }
      const pityBoost = state.pity.highGrade >= 70 ? (state.pity.highGrade - 69) * 0.25 : 0;
      const fiveRate = 1 + pityBoost;
      if (roll < fiveRate) {
        state.pity.highGrade = 0;
        return 5;
      }
      if (roll < fiveRate + 5.5) return 4;
      return 3;
    }
    throw new Error(`Pool non supportato: ${pool}`);
  }

  function summon(state, pool, count) {
    const pulls = Number(count) || 1;
    const price = pool === "normal" ? 10000 : 500;
    const currency = pool === "normal" ? "gold" : "gems";
    const total = price * pulls;
    if (pulls < 1 || pulls > 10) return { ok: false, message: "Numero di evocazioni non valido." };
    if (state.world[currency] < total) return { ok: false, message: `Risorse insufficienti: servono ${total.toLocaleString("it-IT")} ${currency === "gold" ? "Oro" : "Gemme"}.` };
    state.world[currency] -= total;
    addLedger(state, currency, -total, `${pulls} evocazion${pulls === 1 ? "e" : "i"} ${pool === "normal" ? "normali" : "high-grade"}`, "summoning");
    const heroes = [];
    for (let i = 0; i < pulls; i += 1) {
      const pullSeed = `${state.world.seed}:summon:${state.summonCounter}:${pool}`;
      const rng = rngFrom(pullSeed);
      const rarity = rollRarity(state, pool, rng);
      const hero = generateHero(pullSeed, rarity, null, state.summonCounter);
      state.summonCounter += 1;
      state.heroes.push(hero);
      initializeRelationships(state, hero);
      heroes.push(hero);
      if (rarity >= 4) addEvent(state, "SUMMON", "Risonanza rara", `${hero.name}, ${stars(rarity)}, ha risposto al richiamo. Nessun duplicato identico è stato creato.`, "good", { heroId: hero.id });
    }
    addEvent(state, "SUMMON", "Evocazione completata", `${pulls} HeroSeed unici aggiunti al roster.`, "info");
    return { ok: true, heroes, spent: total, currency };
  }

  function addHeroXp(hero, amount, source) {
    const changes = { levels: 0, statPoints: 0, capped: false };
    if (!hero || hero.state !== "ALIVE") return changes;
    hero.xp += Math.max(0, Math.round(amount));
    const cap = RARITY_CAPS[hero.currentRarity];
    while (hero.level < cap) {
      const required = xpToNext(hero.level, hero.currentRarity);
      if (hero.xp < required) break;
      hero.xp -= required;
      hero.level += 1;
      changes.levels += 1;
      const points = Math.max(3, Math.round(hero.growth + ((hashString(`${hero.seed}:${hero.level}`) % 100) / 100 - 0.5)));
      const keys = ["str", "int", "sta", "agi"];
      let allocated = 0;
      keys.forEach((key, index) => {
        const gain = index === keys.length - 1 ? points - allocated : Math.max(0, Math.round(points * hero.growthVector[index]));
        hero.stats[key] += gain;
        allocated += gain;
      });
      changes.statPoints += points;
      hero.skills[0].xp += 20 + hero.level * 2;
      const skillNeed = hero.skills[0].level * 90;
      if (hero.skills[0].xp >= skillNeed && hero.skills[0].level < 10) {
        hero.skills[0].xp -= skillNeed;
        hero.skills[0].level += 1;
      }
      hero.memories.unshift({ type: "LEVEL_UP", text: `Ha raggiunto il livello ${hero.level} tramite ${source || "esperienza"}.`, intensity: 24 });
    }
    changes.capped = hero.level >= cap;
    return changes;
  }

  function trainHero(state, heroId) {
    const hero = state.heroes.find((candidate) => candidate.id === heroId && candidate.state === "ALIVE");
    if (!hero) return { ok: false, message: "Eroe non disponibile." };
    if (hero.fatigue >= 80) return { ok: false, message: "Fatigue critica: l'eroe deve riposare." };
    if (hero.level >= RARITY_CAPS[hero.currentRarity]) return { ok: false, message: "Cap di livello raggiunto: serve una promozione." };
    const cost = 600 + hero.level * 120;
    if (state.world.gold < cost) return { ok: false, message: `Servono ${cost.toLocaleString("it-IT")} Oro.` };
    state.world.gold -= cost;
    addLedger(state, "gold", -cost, `Addestramento di ${hero.name}`, "training");
    const amount = Math.round(xpToNext(hero.level, hero.currentRarity) * (0.62 + state.facilities.training.level * 0.06));
    const changes = addHeroXp(hero, amount, "addestramento");
    hero.fatigue = clamp(hero.fatigue + 18, 0, 100);
    hero.morale = clamp(hero.morale - 2, 0, 100);
    addEvent(state, "TRAINING", "Sessione completata", `${hero.name} ottiene ${amount} XP${changes.levels ? ` e sale di ${changes.levels} livello/i` : ""}.`, "good", { heroId });
    return { ok: true, hero, amount, cost, changes };
  }

  function restRoster(state) {
    const foodCost = Math.min(state.world.materials.food, Math.ceil(getAliveHeroes(state).length / 3));
    if (foodCost <= 0) return { ok: false, message: "Nessuna razione disponibile negli alloggi." };
    state.world.materials.food -= foodCost;
    let recovered = 0;
    getAliveHeroes(state).forEach((hero) => {
      const before = hero.fatigue;
      hero.fatigue = clamp(hero.fatigue - (28 + state.facilities.lodging.level * 5), 0, 100);
      hero.morale = clamp(hero.morale + 8, 0, 100);
      recovered += before - hero.fatigue;
    });
    addEvent(state, "BASE", "Turno di riposo", `Il roster recupera ${recovered} Fatigue complessiva consumando ${foodCost} razioni.`, "good");
    return { ok: true, recovered, foodCost };
  }

  function promoteHero(state, heroId) {
    const hero = state.heroes.find((candidate) => candidate.id === heroId && candidate.state === "ALIVE");
    if (!hero) return { ok: false, message: "Eroe non disponibile." };
    if (hero.currentRarity >= 7) return { ok: false, message: "Rarità massima raggiunta." };
    const cap = RARITY_CAPS[hero.currentRarity];
    if (hero.level < cap) return { ok: false, message: `Serve il Lv.${cap}.` };
    const stoneCost = hero.currentRarity === 1 ? 1 : hero.currentRarity === 2 ? 3 : 5;
    if (state.world.promotionStones < stoneCost) return { ok: false, message: `Servono ${stoneCost} Pietre Promozione.` };
    state.world.promotionStones -= stoneCost;
    hero.currentRarity += 1;
    hero.morale = clamp(hero.morale + 15, 0, 100);
    hero.memories.unshift({ type: "PROMOTION", text: `Promozione a ${hero.currentRarity} stelle. Il potenziale nativo resta immutato.`, intensity: 72 });
    addEvent(state, "PROMOTION", "Promozione riuscita", `${hero.name} raggiunge ${stars(hero.currentRarity)}. Nuovo cap: Lv.${RARITY_CAPS[hero.currentRarity]}.`, "good", { heroId });
    return { ok: true, hero, stoneCost };
  }

  function createCraftedItem(state, slot) {
    const slotData = {
      main: ["Lama del Rift", "sword", "⚔"],
      sub: ["Scudo di servizio", "shield", "◇"],
      armor: ["Corazza della torre", "mail", "⬒"],
      accessory: ["Sigillo di quarzo", "charm", "◆"],
    }[slot];
    if (!slotData) return { ok: false, message: "Slot non valido." };
    const unlocked = state.facilities.smithy.unlocked;
    const cost = unlocked ? 4500 : 6500;
    if (state.world.gold < cost || state.world.materials.ore < 2 || state.world.materials.leather < 1) {
      return { ok: false, message: `Servono ${cost.toLocaleString("it-IT")} Oro, 2 Minerale e 1 Pelle.` };
    }
    state.world.gold -= cost;
    state.world.materials.ore -= 2;
    state.world.materials.leather -= 1;
    const seed = `${state.world.seed}:craft:${Date.now()}:${state.inventory.length}`;
    const rng = rngFrom(seed);
    const grades = unlocked ? ["D", "C", "C", "C", "B"] : ["D", "D", "D", "C"];
    const grade = pick(rng, grades);
    const mult = { D: 1, C: 1.25, B: 1.55 }[grade];
    const item = {
      id: uid("EQ", seed),
      name: slotData[0],
      slot,
      type: slotData[1],
      glyph: slotData[2],
      grade,
      quality: round(0.9 + rng() * 0.2, 2),
      reinforcement: 0,
      durability: 100,
      weaponPower: slot === "main" ? Math.round(17 * mult) : 0,
      armorDefense: slot === "armor" ? Math.round(17 * mult) : 0,
      block: slot === "sub" ? Math.round(11 * mult) : 0,
      hp: slot === "accessory" ? Math.round(28 * mult) : slot === "armor" ? Math.round(12 * mult) : 0,
      crit: slot === "accessory" ? round(2.5 * mult, 1) : 0,
      accuracy: slot === "main" ? round(4 * mult, 1) : 0,
    };
    state.inventory.push(item);
    addLedger(state, "gold", -cost, `Forgiatura: ${item.name} ${grade}`, unlocked ? "smithy" : "armory-commission");
    addEvent(state, "CRAFT", "Oggetto completato", `${item.name} [${grade}] è stato depositato nel Warehouse.`, grade === "B" ? "good" : "info");
    return { ok: true, item, cost };
  }

  function equipItem(state, heroId, itemId) {
    const hero = state.heroes.find((candidate) => candidate.id === heroId && candidate.state === "ALIVE");
    const itemIndex = state.inventory.findIndex((item) => item.id === itemId);
    if (!hero || itemIndex < 0) return { ok: false, message: "Eroe o oggetto non disponibile." };
    const item = state.inventory[itemIndex];
    const previous = hero.equipment[item.slot];
    hero.equipment[item.slot] = item;
    state.inventory.splice(itemIndex, 1);
    if (previous) state.inventory.push(previous);
    addEvent(state, "ARMORY", "Loadout aggiornato", `${hero.name} equipaggia ${item.name} [${item.grade}].`, "info", { heroId });
    return { ok: true, hero, item, previous };
  }

  function autoEquip(state) {
    const party = getPartyHeroes(state).filter(Boolean);
    let equipped = 0;
    const gradePower = { D: 1, C: 2, B: 3, A: 4, S: 5, SS: 6 };
    party.forEach((hero) => {
      ["main", "sub", "armor", "accessory"].forEach((slot) => {
        const candidates = state.inventory
          .filter((item) => item.slot === slot)
          .sort((a, b) => (gradePower[b.grade] || 0) - (gradePower[a.grade] || 0));
        if (!candidates.length) return;
        const current = hero.equipment[slot];
        const currentPower = current ? gradePower[current.grade] || 0 : -1;
        if ((gradePower[candidates[0].grade] || 0) > currentPower) {
          equipItem(state, hero.id, candidates[0].id);
          equipped += 1;
        }
      });
    });
    return { ok: true, equipped };
  }

  function beginMission(state, floor) {
    const stageRecord = getStage(state, floor);
    if (!stageRecord) return { ok: false, message: "Piano non disponibile." };
    const readiness = teamReadiness(state);
    if (readiness.living.length !== 5) return { ok: false, message: "Servono cinque eroi vivi per entrare nel Rift." };
    if (readiness.living.some((hero) => hero.fatigue >= 90)) return { ok: false, message: "Un eroe ha Fatigue critica (90+)." };
    stageRecord.attempts += 1;
    state.activeMission = {
      id: uid("RUN", `${state.world.seed}:${floor}:${stageRecord.attempts}:${Date.now()}`),
      stageId: stageRecord.descriptor.id,
      floor,
      attempt: stageRecord.attempts,
      party: state.party.slice(),
      startedAt: Date.now(),
      deaths: [],
    };
    addEvent(state, "MISSION", `Deployment Piano ${floor}`, `Party e loadout bloccati per il tentativo ${stageRecord.attempts}.`, "warn");
    return { ok: true, run: state.activeMission, stage: stageRecord.descriptor, readiness };
  }

  function recordHeroDeath(state, heroId, cause) {
    const hero = state.heroes.find((candidate) => candidate.id === heroId);
    if (!hero || hero.state !== "ALIVE") return { ok: false };
    const floor = state.activeMission ? state.activeMission.floor : state.world.currentFloor;
    hero.state = "DEAD";
    hero.death = { floor, cause: cause || "Caduto in missione", timestamp: Date.now(), runId: state.activeMission ? state.activeMission.id : null };
    hero.memories.unshift({ type: "DEATH", text: `Caduto al Piano ${floor}: ${hero.death.cause}.`, intensity: 100 });
    state.party = state.party.map((id) => (id === heroId ? null : id));
    if (state.activeMission) state.activeMission.deaths.push(heroId);
    state.memorial.unshift({
      heroId: hero.id,
      name: hero.name,
      rarity: hero.currentRarity,
      level: hero.level,
      role: hero.role,
      floor,
      cause: hero.death.cause,
      missions: hero.missions,
      victories: hero.victories,
      timestamp: hero.death.timestamp,
      quote: hero.quote,
    });
    addEvent(state, "DEATH", `${hero.name} è caduto`, `Morte permanente al Piano ${floor}. Il record resta nel Memoriale, l'eroe non è recuperabile.`, "danger", { heroId });
    return { ok: true, hero };
  }

  function missionReward(stage, attempts, victory) {
    if (!victory) return { gold: 0, xp: Math.round(10 * stage.floor), materials: {} };
    const retryCount = Math.max(0, attempts - 1);
    const retryMultiplier = Math.max(0.35, 1 - 0.2 * retryCount);
    const typeMod = { Subjugation: 1, Survival: 1.15, Exploration: 0.7, Defense: 1.08, Boss: 1.5 }[stage.type] || 1;
    const gold = Math.round(450 * stage.floor ** 1.12 * typeMod * retryMultiplier);
    const materialCount = 1 + Math.floor(stage.floor / 5) + (stage.type === "Boss" ? 2 : 0);
    const materials = stage.type === "Exploration"
      ? { ore: materialCount + 1, leather: materialCount, wood: materialCount + 1 }
      : stage.type === "Boss"
        ? { ore: materialCount, leather: materialCount, cores: 1, food: 2 }
        : { ore: materialCount, leather: Math.max(1, materialCount - 1), food: 1 };
    return { gold, xp: Math.round(34 * stage.floor ** 1.08), materials, retryMultiplier };
  }

  function updateRelationshipsAfterMission(state, survivorIds, deadIds, victory) {
    for (let i = 0; i < survivorIds.length; i += 1) {
      for (let j = i + 1; j < survivorIds.length; j += 1) {
        const key = relationshipKey(survivorIds[i], survivorIds[j]);
        state.relationships[key] = clamp((state.relationships[key] || 0) + (victory ? 3 : 1), -100, 100);
      }
      deadIds.forEach((deadId) => {
        const hero = state.heroes.find((candidate) => candidate.id === survivorIds[i]);
        const bond = getBond(state, survivorIds[i], deadId);
        if (hero && bond > 20) {
          hero.morale = clamp(hero.morale - Math.round(4 + bond / 12), 0, 100);
          hero.memories.unshift({ type: "FRIEND_DIED", text: "Ha visto un compagno morire durante la missione.", intensity: clamp(50 + bond / 2, 50, 100) });
        }
      });
    }
  }

  function unlockFacilities(state, clearedFloor) {
    const unlocked = [];
    Object.entries(state.facilities).forEach(([key, facility]) => {
      if (!facility.unlocked && facility.unlockFloor <= clearedFloor) {
        facility.unlocked = true;
        facility.level = 1;
        unlocked.push(key);
      }
    });
    if (unlocked.length) addEvent(state, "UNLOCK", "Nuove strutture disponibili", unlocked.map((key) => key.toUpperCase()).join(" · "), "good");
    return unlocked;
  }

  function finalizeMission(state, result) {
    if (!state.activeMission) return { ok: false, message: "Nessuna missione attiva." };
    const run = state.activeMission;
    const stageRecord = state.stages[run.floor];
    const stage = stageRecord.descriptor;
    const heroResults = result.heroResults || [];
    const deadIds = run.deaths.slice();
    const survivorIds = [];
    heroResults.forEach((entry) => {
      const hero = state.heroes.find((candidate) => candidate.id === entry.id);
      if (!hero || hero.state !== "ALIVE") return;
      survivorIds.push(hero.id);
      hero.missions += 1;
      hero.kills += entry.kills || 0;
      hero.fatigue = clamp(hero.fatigue + (entry.fatigue || 0), 0, 100);
      hero.morale = clamp(hero.morale + (result.victory ? 5 : -8), 0, 100);
      if (entry.hpRatio < 0.3) {
        const severity = entry.hpRatio < 0.1 ? "Serious" : "Moderate";
        hero.injuries.push({ type: severity, text: severity === "Serious" ? "Trauma grave da missione" : "Ferita da combattimento", timestamp: Date.now() });
      }
    });
    const reward = missionReward(stage, stageRecord.attempts, Boolean(result.victory));
    survivorIds.forEach((heroId) => {
      const hero = state.heroes.find((candidate) => candidate.id === heroId);
      if (result.victory) hero.victories += 1;
      addHeroXp(hero, reward.xp, result.victory ? `clear del Piano ${run.floor}` : `fallimento al Piano ${run.floor}`);
    });
    updateRelationshipsAfterMission(state, survivorIds, deadIds, Boolean(result.victory));

    if (result.victory) {
      const firstClear = !stageRecord.cleared;
      state.world.gold += reward.gold;
      addLedger(state, "gold", reward.gold, `Ricompensa Piano ${run.floor}${firstClear ? " (prima clear)" : ""}`, "mission");
      Object.entries(reward.materials).forEach(([key, amount]) => {
        state.world.materials[key] = (state.world.materials[key] || 0) + amount;
      });
      stageRecord.cleared = true;
      stageRecord.bestResult = {
        timestamp: Date.now(),
        duration: result.duration,
        deaths: deadIds.length,
        reward,
      };
      if (!state.world.completedFloors.includes(run.floor)) state.world.completedFloors.push(run.floor);
      if (run.floor < 5) {
        state.world.maxUnlockedFloor = Math.max(state.world.maxUnlockedFloor, run.floor + 1);
        state.world.currentFloor = run.floor + 1;
        getStage(state, run.floor + 1);
      } else {
        state.world.currentFloor = 5;
      }
      state.world.promotionStones += run.floor === 5 ? 1 : 0;
      unlockFacilities(state, run.floor);
      addEvent(state, "MISSION", `Piano ${run.floor} completato`, `${reward.gold.toLocaleString("it-IT")} Oro, ${reward.xp} XP per superstite. Moltiplicatore retry ×${round(reward.retryMultiplier, 2)}.`, "good");
      if (run.floor === 5) addEvent(state, "SYSTEM", "Vertical slice completata", "Il primo Stream è chiuso. La Torre segnala altri 95 piani e sistemi oltre il confine del prototipo.", "good");
    } else {
      addEvent(state, "MISSION", `Missione fallita al Piano ${run.floor}`, deadIds.length ? `${deadIds.length} mort${deadIds.length === 1 ? "e" : "i"} permanenti. Il descriptor non è cambiato.` : "I superstiti sono rientrati. Il descriptor non è cambiato.", "warn");
    }
    state.activeMission = null;
    return { ok: true, reward, deadIds, survivorIds, firstClear: result.victory && stageRecord.attempts === 1 };
  }

  function formatNumber(value) {
    return Math.round(value || 0).toLocaleString("it-IT");
  }

  function exportState(state) {
    const payload = JSON.parse(JSON.stringify(state));
    payload.world.lastSavedAt = Date.now();
    return JSON.stringify(payload, null, 2);
  }

  return {
    VERSION,
    SAVE_KEY,
    PARTY_POSITIONS,
    RARITY_CAPS,
    GROWTH_RANGES,
    ROLES,
    ENEMY_TEMPLATES,
    STAGE_BLUEPRINTS,
    hashString,
    rngFrom,
    clamp,
    round,
    stars,
    xpToNext,
    generateHero,
    generateStage,
    createInitialState,
    migrateState,
    applyOfflineProgress,
    addEvent,
    addLedger,
    getBond,
    getStage,
    getAliveHeroes,
    getPartyHeroes,
    assignPartySlot,
    removePartySlot,
    autoFormParty,
    derivedStats,
    heroPower,
    teamReadiness,
    summon,
    addHeroXp,
    trainHero,
    restRoster,
    promoteHero,
    createCraftedItem,
    equipItem,
    autoEquip,
    beginMission,
    recordHeroDeath,
    missionReward,
    finalizeMission,
    formatNumber,
    exportState,
  };
});
