const assert = require("assert");
const core = require("../core.js");

function test(name, fn) {
  try {
    fn();
    console.log(`✓ ${name}`);
  } catch (error) {
    console.error(`✗ ${name}`);
    throw error;
  }
}

test("la creazione iniziale è deterministica per lo stesso world seed", () => {
  const a = core.createInitialState("00112233445566778899aabbccddeeff");
  const b = core.createInitialState("00112233445566778899aabbccddeeff");
  assert.deepStrictEqual(
    a.heroes.map((hero) => [hero.id, hero.name, hero.role, hero.stats]),
    b.heroes.map((hero) => [hero.id, hero.name, hero.role, hero.stats]),
  );
  assert.strictEqual(a.stages[1].descriptor.seed, b.stages[1].descriptor.seed);
});

test("il roster iniziale include sei eroi e un party valido da cinque", () => {
  const state = core.createInitialState("party-seed");
  assert.strictEqual(state.heroes.length, 6);
  assert.strictEqual(core.getPartyHeroes(state).filter(Boolean).length, 5);
  assert.strictEqual(new Set(state.heroes.map((hero) => hero.id)).size, 6);
});

test("le evocazioni applicano costi, rarità di pool e HeroSeed unici", () => {
  const state = core.createInitialState("summon-seed");
  state.world.gold = 1000000;
  state.world.gems = 50000;
  const normal = core.summon(state, "normal", 10);
  const high = core.summon(state, "high", 10);
  assert.ok(normal.ok && high.ok);
  assert.ok(normal.heroes.every((hero) => hero.nativeRarity >= 1 && hero.nativeRarity <= 3));
  assert.ok(high.heroes.every((hero) => hero.nativeRarity >= 3 && hero.nativeRarity <= 5));
  assert.strictEqual(state.world.gold, 900000);
  assert.strictEqual(state.world.gems, 45000);
  assert.strictEqual(new Set(state.heroes.map((hero) => hero.id)).size, state.heroes.length);
});

test("l'hard pity high-grade garantisce un 5 stelle al pull 100", () => {
  const state = core.createInitialState("pity-seed");
  state.world.gems = 5000;
  state.pity.highGrade = 99;
  const result = core.summon(state, "high", 1);
  assert.ok(result.ok);
  assert.strictEqual(result.heroes[0].nativeRarity, 5);
  assert.strictEqual(state.pity.highGrade, 0);
});

test("il descriptor del piano persiste fra i retry", () => {
  const state = core.createInitialState("stage-seed");
  const first = core.getStage(state, 1).descriptor;
  core.autoFormParty(state);
  assert.ok(core.beginMission(state, 1).ok);
  core.finalizeMission(state, { victory: false, duration: 9, heroResults: core.getPartyHeroes(state).filter(Boolean).map((hero) => ({ id: hero.id, hpRatio: 1, fatigue: 8 })) });
  const second = core.getStage(state, 1).descriptor;
  assert.strictEqual(first.id, second.id);
  assert.strictEqual(first.seed, second.seed);
  assert.strictEqual(state.stages[1].attempts, 1);
});

test("la morte è permanente, crea un tombstone e rimuove l'eroe dal party", () => {
  const state = core.createInitialState("death-seed");
  const victim = core.getPartyHeroes(state)[0];
  core.beginMission(state, 1);
  const death = core.recordHeroDeath(state, victim.id, "Test controllato");
  assert.ok(death.ok);
  assert.strictEqual(victim.state, "DEAD");
  assert.ok(!state.party.includes(victim.id));
  assert.strictEqual(state.memorial[0].heroId, victim.id);
  assert.ok(!core.assignPartySlot(state, 0, victim.id).ok);
});

test("una clear sblocca il piano successivo e assegna ricompense", () => {
  const state = core.createInitialState("clear-seed");
  const goldBefore = state.world.gold;
  const begin = core.beginMission(state, 1);
  assert.ok(begin.ok);
  const party = core.getPartyHeroes(state).filter(Boolean);
  const result = core.finalizeMission(state, {
    victory: true,
    duration: 24,
    heroResults: party.map((hero) => ({ id: hero.id, hpRatio: 0.8, fatigue: 12, kills: 1 })),
  });
  assert.ok(result.ok);
  assert.strictEqual(state.world.maxUnlockedFloor, 2);
  assert.strictEqual(state.world.currentFloor, 2);
  assert.ok(state.world.gold > goldBefore);
  assert.ok(state.stages[1].cleared);
  assert.ok(state.stages[2].descriptor);
});

test("il moltiplicatore retry non scende sotto 0,35", () => {
  const stage = core.generateStage("reward-seed", 5);
  assert.strictEqual(core.missionReward(stage, 50, true).retryMultiplier, 0.35);
});

console.log("\nTutti i test core sono passati.");
