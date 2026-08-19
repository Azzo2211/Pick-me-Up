(function (root) {
  "use strict";

  const C = root.RiftwardCore;
  const TAU = Math.PI * 2;

  class CombatSimulation {
    constructor(options) {
      this.canvas = options.canvas;
      this.ctx = this.canvas.getContext("2d");
      this.stage = options.stage;
      this.heroesSource = options.heroes;
      this.worldSeed = options.worldSeed;
      this.attempt = options.attempt;
      this.onUpdate = options.onUpdate || (() => {});
      this.onLog = options.onLog || (() => {});
      this.onHeroDeath = options.onHeroDeath || (() => {});
      this.onComplete = options.onComplete || (() => {});
      this.random = C.rngFrom(`${this.stage.seed}:attempt:${this.attempt}:combat`);
      this.running = false;
      this.finished = false;
      this.elapsed = 0;
      this.accumulator = 0;
      this.lastFrame = 0;
      this.tick = 1 / 20;
      this.decisionInterval = 0.2;
      this.decisionTimer = 0;
      this.nextEntityId = 1;
      this.heroes = [];
      this.enemies = [];
      this.projectiles = [];
      this.effects = [];
      this.spawnedWaves = new Set();
      this.commands = {
        posture: "advance",
        focus: false,
        protect: false,
        alloutUntil: 0,
        extracting: false,
        extractionEnds: 0,
      };
      this.objective = {
        poi: 0,
        beaconIntegrity: 100,
        bossKilled: false,
      };
      this.boundFrame = this.frame.bind(this);
      this.handleResize = this.resize.bind(this);
      this.resizeObserver = typeof ResizeObserver !== "undefined" ? new ResizeObserver(this.handleResize) : null;
      this.resizeObserver?.observe(this.canvas);
      this.resize();
      this.initializeHeroes();
      this.createBackdrop();
    }

    resize() {
      const rect = this.canvas.getBoundingClientRect();
      const scale = Math.min(2, root.devicePixelRatio || 1);
      this.width = Math.max(320, rect.width || root.innerWidth);
      this.height = Math.max(320, rect.height || root.innerHeight);
      this.canvas.width = Math.floor(this.width * scale);
      this.canvas.height = Math.floor(this.height * scale);
      this.ctx.setTransform(scale, 0, 0, scale, 0, 0);
      this.playTop = Math.max(115, this.height * 0.16);
      this.playBottom = Math.max(this.playTop + 200, this.height - 115);
    }

    createBackdrop() {
      const rng = C.rngFrom(`${this.stage.seed}:backdrop`);
      this.backdrop = Array.from({ length: 28 }, (_, index) => ({
        x: rng() * this.width,
        y: this.playTop + rng() * Math.max(100, this.playBottom - this.playTop),
        r: 8 + rng() * 34,
        depth: rng(),
        kind: index % 4,
      }));
    }

    initializeHeroes() {
      const placements = [
        [0.27, 0.4],
        [0.25, 0.61],
        [0.18, 0.35],
        [0.17, 0.66],
        [0.11, 0.5],
      ];
      this.heroes = this.heroesSource.map((hero, index) => {
        const derived = C.derivedStats(hero);
        const role = C.ROLES[hero.role];
        const fatiguePenalty = Math.max(0, hero.fatigue - 50) * 0.0035;
        return {
          entityId: this.nextEntityId++,
          id: hero.id,
          source: hero,
          type: "hero",
          name: hero.name,
          role: hero.role,
          hue: hero.hue,
          x: this.width * placements[index][0],
          y: this.playTop + (this.playBottom - this.playTop) * placements[index][1],
          homeY: this.playTop + (this.playBottom - this.playTop) * placements[index][1],
          radius: hero.role === "Guardian" ? 15 : 13,
          hp: derived.maxHp,
          maxHp: derived.maxHp,
          attack: hero.role === "Mage" || hero.role === "Support" ? Math.max(derived.magicAttack, derived.physicalAttack * 0.72) : derived.physicalAttack,
          defense: derived.defense,
          accuracy: derived.accuracy,
          evasion: derived.evasion,
          crit: derived.crit,
          block: derived.block,
          range: role.attackRange,
          cadence: role.cadence,
          moveSpeed: role.moveSpeed * (1 - fatiguePenalty),
          attackTimer: 0.25 + this.random() * 0.8,
          skillTimer: 2 + this.random() * 3,
          decision: null,
          target: null,
          alive: true,
          ammo: derived.ammo,
          maxAmmo: derived.ammo,
          mana: 100,
          morale: hero.morale,
          fatigueStart: hero.fatigue,
          kills: 0,
          damage: 0,
          healing: 0,
          status: hero.morale < 40 ? "Low morale" : "Stable",
          fear: 0,
          flash: 0,
          shield: 0,
          lastAction: "Valuta minacce",
          skillName: role.skill[0],
          skillCooldown: role.skill[2],
        };
      });
    }

    start() {
      if (this.running) return;
      this.running = true;
      this.lastFrame = performance.now();
      this.log(`Missione iniziata. Il descriptor ${this.stage.seed.toUpperCase()} è bloccato.`, "good");
      this.log("Gli eroi assumono la formazione e iniziano a valutare l'ambiente.");
      root.requestAnimationFrame(this.boundFrame);
    }

    stop() {
      this.running = false;
      this.resizeObserver?.disconnect();
    }

    frame(now) {
      if (!this.running) return;
      const delta = Math.min(0.1, (now - this.lastFrame) / 1000);
      this.lastFrame = now;
      this.accumulator += delta;
      while (this.accumulator >= this.tick && !this.finished) {
        this.update(this.tick);
        this.accumulator -= this.tick;
      }
      this.draw();
      if (this.running && !this.finished) root.requestAnimationFrame(this.boundFrame);
    }

    update(dt) {
      this.elapsed += dt;
      this.decisionTimer -= dt;
      this.spawnWaves();
      this.updateCommands();
      if (this.decisionTimer <= 0) {
        this.decisionTimer = this.decisionInterval;
        this.heroes.filter((hero) => hero.alive).forEach((hero) => this.decideHero(hero));
        this.enemies.filter((enemy) => enemy.alive).forEach((enemy) => this.decideEnemy(enemy));
      }
      this.heroes.forEach((hero) => this.updateUnit(hero, dt));
      this.enemies.forEach((enemy) => this.updateUnit(enemy, dt));
      this.updateProjectiles(dt);
      this.updateEffects(dt);
      this.updateObjective(dt);
      this.checkEndConditions();
      this.onUpdate(this.snapshot());
    }

    spawnWaves() {
      this.stage.enemyWaves.forEach((wave, waveIndex) => {
        if (this.elapsed + 0.001 < wave.at || this.spawnedWaves.has(waveIndex)) return;
        this.spawnedWaves.add(waveIndex);
        wave.units.forEach((entry) => {
          for (let i = 0; i < entry.count; i += 1) this.spawnEnemy(entry.kind, waveIndex, i);
        });
        const count = wave.units.reduce((sum, entry) => sum + entry.count, 0);
        this.log(`${waveIndex === 0 ? "Contatto" : "Rinforzi"}: ${count} ostili rilevati.`, waveIndex ? "warn" : "");
      });
    }

    spawnEnemy(kind, waveIndex, index) {
      const template = C.ENEMY_TEMPLATES[kind];
      const scale = this.stage.enemyScale;
      const lane = (waveIndex * 3 + index * 2 + Math.floor(this.random() * 5)) % 7;
      const enemy = {
        entityId: this.nextEntityId++,
        id: `ENEMY-${this.nextEntityId}`,
        type: "enemy",
        kind,
        name: template.name,
        hue: template.hue,
        x: this.width + 45 + this.random() * 90,
        y: this.playTop + 45 + lane * Math.max(28, (this.playBottom - this.playTop - 90) / 7),
        homeY: 0,
        radius: kind === "boss" ? 28 : kind === "brute" ? 19 : 12,
        hp: Math.round(template.hp * scale),
        maxHp: Math.round(template.hp * scale),
        attack: template.attack * scale,
        defense: template.defense * scale,
        accuracy: kind === "archer" ? 82 : 76,
        evasion: kind === "skirmisher" ? 14 : 4,
        crit: kind === "boss" ? 12 : 5,
        block: 0,
        range: template.range,
        cadence: template.cadence,
        moveSpeed: template.speed * (0.95 + this.random() * 0.12),
        attackTimer: this.random() * 0.9,
        skillTimer: kind === "boss" ? 5 : 99,
        decision: null,
        target: null,
        alive: true,
        threat: template.threat,
        status: "Hostile",
        flash: 0,
        shield: 0,
        lastAction: "Advance",
        damage: 0,
      };
      this.enemies.push(enemy);
    }

    updateCommands() {
      if (this.commands.extracting && this.elapsed >= this.commands.extractionEnds) {
        this.finish(false, "extracted");
      }
    }

    decideHero(hero) {
      if (!hero.alive) return;
      if (hero.role === "Support") {
        const wounded = this.heroes
          .filter((ally) => ally.alive && ally.hp / ally.maxHp < 0.72)
          .sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0];
        const healUtility = wounded ? (1 - wounded.hp / wounded.maxHp) * (0.6 + hero.source.personality.altruism / 100) : 0;
        if (wounded && healUtility > 0.5 && hero.skillTimer <= 0 && hero.mana >= 18) {
          hero.decision = { action: "heal", target: wounded };
          hero.lastAction = `Protegge ${wounded.name}`;
          return;
        }
      }

      const targets = this.enemies.filter((enemy) => enemy.alive);
      if (!targets.length) {
        hero.decision = { action: "regroup" };
        hero.lastAction = "Mantiene la formazione";
        return;
      }

      let best = null;
      let bestScore = -Infinity;
      targets.forEach((enemy) => {
        const distance = this.distance(hero, enemy);
        const proximity = 1 / Math.max(1, distance / 100);
        const highThreat = this.commands.focus ? enemy.threat * 0.7 : enemy.threat * 0.13;
        const vulnerable = (1 - enemy.hp / enemy.maxHp) * (0.2 + hero.source.personality.aggression / 120);
        const rearThreat = this.commands.protect && enemy.x < this.width * 0.58 ? 0.7 : 0;
        const roleFit = hero.role === "Guardian" && enemy.x < this.width * 0.48 ? 0.4 : hero.role === "Ranger" && distance > 110 ? 0.25 : 0;
        const score = proximity + highThreat + vulnerable + rearThreat + roleFit + this.random() * 0.08;
        if (score > bestScore) {
          bestScore = score;
          best = enemy;
        }
      });
      hero.target = best;

      const hpRatio = hero.hp / hero.maxHp;
      const riskTolerance = (hero.source.personality.courage + hero.source.personality.loyalty) / 200;
      if (hpRatio < 0.18 + (1 - riskTolerance) * 0.12 && !this.commands.alloutUntil) {
        hero.decision = { action: "retreat", target: best };
        hero.lastAction = "Cerca spazio per sopravvivere";
        return;
      }

      const distance = this.distance(hero, best);
      if (distance <= hero.range) {
        if (hero.skillTimer <= 0 && this.skillUtility(hero, best) > 0.72) {
          hero.decision = { action: "skill", target: best };
          hero.lastAction = hero.skillName;
        } else {
          hero.decision = { action: "attack", target: best };
          hero.lastAction = `Attacca ${best.name}`;
        }
      } else {
        hero.decision = { action: "advance", target: best };
        hero.lastAction = `Si porta a distanza utile`;
      }
    }

    skillUtility(hero, target) {
      const targetThreat = target.threat / 8;
      const targetMissingHp = 1 - target.hp / target.maxHp;
      const pressure = this.enemies.filter((enemy) => enemy.alive && this.distance(hero, enemy) < 115).length / 4;
      const resource = hero.mana / 100;
      const allout = this.elapsed < this.commands.alloutUntil ? 0.7 : 0;
      const discipline = hero.source.personality.discipline / 100;
      return targetThreat * 0.6 + targetMissingHp * 0.2 + pressure * 0.36 + resource * 0.13 + allout + discipline * 0.08;
    }

    decideEnemy(enemy) {
      if (!enemy.alive) return;
      const targets = this.heroes.filter((hero) => hero.alive);
      if (!targets.length) return;
      let target;
      if (enemy.kind === "archer") {
        target = targets
          .slice()
          .sort((a, b) => (a.role === "Support" || a.role === "Ranger" ? -1 : 1) - (b.role === "Support" || b.role === "Ranger" ? -1 : 1) || this.distance(enemy, a) - this.distance(enemy, b))[0];
      } else if (enemy.kind === "brute" && this.stage.type === "Defense" && this.objective.beaconIntegrity > 0 && this.random() < 0.42) {
        target = null;
      } else {
        target = targets.slice().sort((a, b) => this.distance(enemy, a) - this.distance(enemy, b))[0];
      }
      enemy.target = target;
      if (!target) {
        enemy.decision = { action: "beacon" };
        return;
      }
      const distance = this.distance(enemy, target);
      if (enemy.kind === "boss" && enemy.skillTimer <= 0) {
        enemy.decision = { action: "bossSkill", target };
      } else if (distance <= enemy.range) {
        enemy.decision = { action: "attack", target };
      } else {
        enemy.decision = { action: "advance", target };
      }
    }

    updateUnit(unit, dt) {
      if (!unit.alive) return;
      unit.attackTimer -= dt;
      unit.skillTimer -= dt;
      unit.flash = Math.max(0, unit.flash - dt * 4);
      unit.shield = Math.max(0, unit.shield - dt);
      const decision = unit.decision;
      if (!decision) return;
      if (decision.action === "advance") this.moveToward(unit, decision.target, dt);
      if (decision.action === "retreat") this.moveAway(unit, decision.target, dt);
      if (decision.action === "regroup") this.regroup(unit, dt);
      if (decision.action === "attack") this.tryAttack(unit, decision.target);
      if (decision.action === "skill") this.trySkill(unit, decision.target);
      if (decision.action === "heal") this.tryHeal(unit, decision.target);
      if (decision.action === "bossSkill") this.tryBossSkill(unit);
      if (decision.action === "beacon") this.attackBeacon(unit, dt);
    }

    moveToward(unit, target, dt) {
      if (!target || !target.alive) return;
      const dx = target.x - unit.x;
      const dy = target.y - unit.y;
      const distance = Math.hypot(dx, dy) || 1;
      const preferred = unit.range * (unit.type === "hero" && unit.range > 100 ? 0.78 : 0.72);
      if (distance <= preferred) return;
      let speed = unit.moveSpeed;
      if (unit.type === "hero" && this.commands.posture === "hold") speed *= 0.58;
      if (unit.type === "hero" && this.commands.posture === "retreat") speed *= -0.34;
      unit.x += (dx / distance) * speed * dt;
      unit.y += (dy / distance) * speed * dt;
      this.constrain(unit);
    }

    moveAway(unit, target, dt) {
      if (!target) return;
      const dx = unit.x - target.x;
      const dy = unit.y - target.y;
      const distance = Math.hypot(dx, dy) || 1;
      unit.x += (dx / distance) * unit.moveSpeed * 0.65 * dt;
      unit.y += (dy / distance) * unit.moveSpeed * 0.65 * dt;
      this.constrain(unit);
    }

    regroup(unit, dt) {
      const homeX = unit.type === "hero" ? this.width * (unit.role === "Ranger" || unit.role === "Mage" ? 0.21 : 0.3) : this.width * 0.78;
      const dx = homeX - unit.x;
      const dy = unit.homeY - unit.y;
      const distance = Math.hypot(dx, dy) || 1;
      if (distance > 5) {
        unit.x += (dx / distance) * unit.moveSpeed * dt;
        unit.y += (dy / distance) * unit.moveSpeed * dt;
      }
    }

    constrain(unit) {
      unit.x = C.clamp(unit.x, 28, this.width - 28);
      unit.y = C.clamp(unit.y, this.playTop + 25, this.playBottom - 25);
    }

    tryAttack(attacker, target) {
      if (!target || !target.alive || attacker.attackTimer > 0) return;
      if (this.distance(attacker, target) > attacker.range + target.radius) return;
      if (attacker.type === "hero" && attacker.role === "Ranger") {
        if (attacker.ammo <= 0) {
          attacker.status = "No ammo";
          attacker.lastAction = "Conserva l'arco scarico";
          attacker.attackTimer = 1.4;
          return;
        }
        attacker.ammo -= 1;
        if (attacker.ammo === 4) this.log(`${attacker.name}: 4 frecce rimaste.`, "warn");
        if (attacker.ammo === 0) this.log(`${attacker.name} ha esaurito le munizioni.`, "danger");
      }
      const cadence = attacker.cadence * (this.elapsed < this.commands.alloutUntil && attacker.type === "hero" ? 0.76 : 1);
      attacker.attackTimer = cadence;
      if (attacker.range > 100) {
        this.launchProjectile(attacker, target, false);
      } else {
        this.resolveHit(attacker, target, 1, false);
        this.effects.push({ type: "slash", x: target.x, y: target.y, hue: attacker.hue, life: 0.24, maxLife: 0.24 });
      }
    }

    trySkill(hero, target) {
      if (!target || !target.alive || hero.skillTimer > 0) return;
      hero.skillTimer = hero.skillCooldown;
      hero.mana = Math.max(0, hero.mana - 24);
      if (hero.role === "Guardian") {
        hero.shield = 4;
        this.heroes.filter((ally) => ally.alive && this.distance(hero, ally) < 105).forEach((ally) => { ally.shield = Math.max(ally.shield, 2.8); });
        this.effects.push({ type: "ring", x: hero.x, y: hero.y, hue: 45, life: 0.7, maxLife: 0.7, radius: 80 });
        this.log(`${hero.name} usa Aegis Brace: la linea si compatta.`, "good");
      } else if (hero.role === "Mage") {
        this.enemies.filter((enemy) => enemy.alive && this.distance(enemy, target) < 92).forEach((enemy) => this.resolveHit(hero, enemy, 1.52, true));
        this.effects.push({ type: "burst", x: target.x, y: target.y, hue: 24, life: 0.7, maxLife: 0.7, radius: 92 });
        this.log(`${hero.name} intreccia Ember Lattice su un gruppo.`, "good");
      } else if (hero.role === "Ranger") {
        if (hero.ammo > 0) hero.ammo -= 1;
        this.launchProjectile(hero, target, true);
        this.log(`${hero.name} marca ${target.name}.`, "good");
      } else if (hero.role === "Lancer") {
        this.resolveHit(hero, target, 1.45, true);
        target.attackTimer += 1.15;
        this.effects.push({ type: "line", x: hero.x, y: hero.y, x2: target.x, y2: target.y, hue: 190, life: 0.32, maxLife: 0.32 });
      } else if (hero.role === "Vanguard") {
        this.resolveHit(hero, target, 1.7, true);
        target.defense *= 0.92;
        this.effects.push({ type: "slash", x: target.x, y: target.y, hue: 12, life: 0.42, maxLife: 0.42 });
      } else {
        this.resolveHit(hero, target, 1.28, true);
      }
    }

    tryHeal(hero, target) {
      if (!target || !target.alive || hero.skillTimer > 0 || hero.mana < 18) return;
      const amount = Math.round(28 + hero.source.stats.int * 2.1 + hero.source.skills[0].level * 4);
      target.hp = Math.min(target.maxHp, target.hp + amount);
      hero.healing += amount;
      hero.mana -= 18;
      hero.skillTimer = hero.skillCooldown;
      target.status = "Stabilized";
      this.effects.push({ type: "ring", x: target.x, y: target.y, hue: 155, life: 0.75, maxLife: 0.75, radius: 48 });
      this.log(`${hero.name} stabilizza ${target.name} (+${amount} HP).`, "good");
    }

    tryBossSkill(boss) {
      if (boss.skillTimer > 0) return;
      boss.skillTimer = 12;
      const targets = this.heroes.filter((hero) => hero.alive);
      targets.forEach((hero) => {
        const distance = this.distance(boss, hero);
        if (distance < 240) this.resolveHit(boss, hero, distance < 105 ? 1.45 : 0.72, true);
        if (hero.morale < 45 && hero.source.personality.courage < 65) {
          hero.fear = Math.max(hero.fear, 7);
          hero.status = "Fear";
          hero.accuracy *= 0.86;
        }
      });
      this.effects.push({ type: "ring", x: boss.x, y: boss.y, hue: 4, life: 1.1, maxLife: 1.1, radius: 250 });
      this.log("Il Custode ruggisce. La formazione vacilla.", "danger");
    }

    attackBeacon(enemy, dt) {
      const targetX = this.width * 0.18;
      const targetY = (this.playTop + this.playBottom) / 2;
      const distance = Math.hypot(targetX - enemy.x, targetY - enemy.y);
      if (distance > enemy.range) {
        const dx = targetX - enemy.x;
        const dy = targetY - enemy.y;
        enemy.x += (dx / distance) * enemy.moveSpeed * dt;
        enemy.y += (dy / distance) * enemy.moveSpeed * dt;
        return;
      }
      if (enemy.attackTimer <= 0) {
        enemy.attackTimer = enemy.cadence;
        const damage = enemy.attack * 0.12;
        this.objective.beaconIntegrity = Math.max(0, this.objective.beaconIntegrity - damage);
        this.effects.push({ type: "burst", x: targetX, y: targetY, hue: 42, life: 0.3, maxLife: 0.3, radius: 25 });
        if (this.objective.beaconIntegrity < 50 && !this.objective.beaconWarned) {
          this.objective.beaconWarned = true;
          this.log("Integrità del faro sotto il 50%.", "danger");
        }
      }
    }

    launchProjectile(attacker, target, skill) {
      const speed = attacker.role === "Mage" ? 330 : 460;
      this.projectiles.push({
        x: attacker.x,
        y: attacker.y,
        target,
        attacker,
        speed,
        hue: attacker.role === "Mage" ? 24 : attacker.hue,
        skill,
        alive: true,
      });
    }

    updateProjectiles(dt) {
      this.projectiles.forEach((projectile) => {
        if (!projectile.alive || !projectile.target.alive) {
          projectile.alive = false;
          return;
        }
        const dx = projectile.target.x - projectile.x;
        const dy = projectile.target.y - projectile.y;
        const distance = Math.hypot(dx, dy) || 1;
        if (distance < projectile.target.radius + 6) {
          this.resolveHit(projectile.attacker, projectile.target, projectile.skill ? 1.75 : 1, projectile.skill);
          this.effects.push({ type: "burst", x: projectile.target.x, y: projectile.target.y, hue: projectile.hue, life: 0.25, maxLife: 0.25, radius: 18 });
          projectile.alive = false;
          return;
        }
        projectile.x += (dx / distance) * projectile.speed * dt;
        projectile.y += (dy / distance) * projectile.speed * dt;
      });
      this.projectiles = this.projectiles.filter((projectile) => projectile.alive);
    }

    resolveHit(attacker, target, coefficient, isSkill) {
      if (!attacker.alive || !target.alive) return;
      const hitChance = C.clamp(attacker.accuracy - target.evasion, 35, 98) / 100;
      if (this.random() > hitChance) {
        target.status = "Evaded";
        this.effects.push({ type: "text", text: "EVADE", x: target.x, y: target.y - 20, hue: 190, life: 0.55, maxLife: 0.55 });
        return;
      }
      const crit = this.random() < attacker.crit / 100;
      const blockChance = target.block ? C.clamp(target.block, 0, 65) / 100 : 0;
      const blocked = this.random() < blockChance;
      const raw = attacker.attack * coefficient * (crit ? 1.5 : 1) * (0.95 + this.random() * 0.1);
      const mitigation = 100 / (100 + target.defense);
      let damage = raw * mitigation;
      if (blocked) damage *= 0.42;
      if (target.shield > 0) damage *= 0.66;
      if (target.type === "hero" && target.fear > 0) damage *= 1.04;
      damage = Math.max(1, Math.round(damage));
      target.hp = Math.max(0, target.hp - damage);
      target.flash = 1;
      attacker.damage = (attacker.damage || 0) + damage;
      this.effects.push({ type: "text", text: `${crit ? "CRIT " : ""}${blocked ? "BLOCK " : ""}-${damage}`, x: target.x, y: target.y - target.radius - 9, hue: crit ? 43 : target.type === "hero" ? 5 : 0, life: 0.65, maxLife: 0.65 });
      if (target.type === "hero" && target.hp / target.maxHp < 0.25 && !target.lowHpWarned) {
        target.lowHpWarned = true;
        this.log(`${target.name} è in condizioni critiche.`, "danger");
      }
      if (target.hp <= 0) this.killUnit(target, attacker, isSkill);
    }

    killUnit(target, attacker) {
      target.alive = false;
      target.status = "Dead";
      if (attacker.type === "hero") attacker.kills += 1;
      if (target.type === "hero") {
        this.log(`${target.name} è caduto. Evento irreversibile registrato.`, "danger");
        this.effects.push({ type: "death", x: target.x, y: target.y, hue: 0, life: 1.4, maxLife: 1.4, radius: 70 });
        this.onHeroDeath(target.id, `Ucciso da ${attacker.name}`);
        this.heroes.filter((hero) => hero.alive).forEach((hero) => {
          const bond = hero.source.id && target.source.id ? 0 : 0;
          hero.morale = Math.max(0, hero.morale - 7 - bond);
          if (hero.morale < 35 && hero.source.personality.composure < 55) {
            hero.status = "Fear";
            hero.fear = 8;
          }
        });
      } else {
        if (target.kind === "boss") this.objective.bossKilled = true;
        this.effects.push({ type: "death", x: target.x, y: target.y, hue: target.hue, life: 0.65, maxLife: 0.65, radius: target.radius * 2.5 });
      }
    }

    updateEffects(dt) {
      this.effects.forEach((effect) => { effect.life -= dt; });
      this.effects = this.effects.filter((effect) => effect.life > 0);
      this.heroes.forEach((hero) => {
        if (hero.fear > 0) {
          hero.fear = Math.max(0, hero.fear - dt);
          if (hero.fear === 0 && hero.status === "Fear") {
            hero.status = "Stable";
            hero.accuracy = C.derivedStats(hero.source).accuracy;
          }
        }
        hero.mana = Math.min(100, hero.mana + dt * 1.8);
      });
    }

    updateObjective() {
      if (this.stage.type === "Exploration") {
        const thresholds = [15, 31, 49];
        thresholds.forEach((threshold, index) => {
          if (this.elapsed >= threshold && this.objective.poi < index + 1) {
            this.objective.poi = index + 1;
            this.log(`Punto d'interesse ${index + 1}/3 messo in sicurezza.`, "good");
            this.effects.push({ type: "ring", x: this.width * (0.45 + index * 0.12), y: this.playTop + 90 + index * 65, hue: 190, life: 1.1, maxLife: 1.1, radius: 70 });
          }
        });
      }
    }

    checkEndConditions() {
      const livingHeroes = this.heroes.filter((hero) => hero.alive);
      const livingEnemies = this.enemies.filter((enemy) => enemy.alive);
      if (!livingHeroes.length) {
        this.finish(false, "party-wipe");
        return;
      }
      if (this.stage.type === "Defense" && this.objective.beaconIntegrity <= 0) {
        this.finish(false, "objective-destroyed");
        return;
      }
      const allWavesSpawned = this.spawnedWaves.size === this.stage.enemyWaves.length;
      if (this.stage.type === "Survival" && this.elapsed >= this.stage.duration) {
        this.finish(true, "timer-survived");
        return;
      }
      if (this.stage.type === "Exploration" && this.objective.poi >= 3 && allWavesSpawned && livingEnemies.length === 0) {
        this.finish(true, "intel-secured");
        return;
      }
      if ((this.stage.type === "Subjugation" || this.stage.type === "Defense") && allWavesSpawned && livingEnemies.length === 0) {
        this.finish(true, "objective-complete");
        return;
      }
      if (this.stage.type === "Boss" && this.objective.bossKilled && livingEnemies.length === 0) {
        this.finish(true, "boss-killed");
        return;
      }
      if (this.elapsed >= this.stage.duration && this.stage.type !== "Survival") {
        this.finish(false, "time-limit");
      }
    }

    finish(victory, reason) {
      if (this.finished) return;
      this.finished = true;
      this.running = false;
      const heroResults = this.heroes.map((hero) => ({
        id: hero.id,
        alive: hero.alive,
        hpRatio: hero.maxHp ? hero.hp / hero.maxHp : 0,
        kills: hero.kills,
        damage: Math.round(hero.damage),
        healing: Math.round(hero.healing),
        fatigue: Math.round(10 + this.elapsed * 0.28 + (hero.hp / hero.maxHp < 0.3 ? 7 : 0)),
      }));
      const result = { victory, reason, duration: this.elapsed, heroResults, snapshot: this.snapshot() };
      setTimeout(() => this.onComplete(result), 520);
    }

    command(type) {
      if (this.finished) return { ok: false };
      if (type === "posture") {
        const order = ["advance", "hold", "retreat"];
        this.commands.posture = order[(order.indexOf(this.commands.posture) + 1) % order.length];
        const label = { advance: "AVANZA", hold: "MANTIENI", retreat: "ARRETRA" }[this.commands.posture];
        this.log(`Ordine Master: postura ${label}.`, "warn");
        return { ok: true, label };
      }
      if (type === "focus") {
        this.commands.focus = !this.commands.focus;
        this.log(`Priorità alta minaccia ${this.commands.focus ? "attivata" : "disattivata"}.`, "warn");
        return { ok: true, active: this.commands.focus };
      }
      if (type === "protect") {
        this.commands.protect = !this.commands.protect;
        this.log(`Protezione retroguardia ${this.commands.protect ? "attivata" : "disattivata"}.`, "warn");
        return { ok: true, active: this.commands.protect };
      }
      if (type === "allout") {
        this.commands.alloutUntil = this.elapsed + 10;
        this.heroes.filter((hero) => hero.alive).forEach((hero) => { hero.morale = Math.max(hero.morale, 45); });
        this.log("Tutto per tutto autorizzato per 10 secondi.", "warn");
        return { ok: true, active: true };
      }
      if (type === "extract") {
        if (this.commands.extracting) return { ok: false };
        this.commands.extracting = true;
        this.commands.extractionEnds = this.elapsed + 6;
        this.commands.posture = "retreat";
        this.log("Estrazione d'emergenza autorizzata. 6 secondi al disimpegno.", "danger");
        return { ok: true, active: true };
      }
      return { ok: false };
    }

    snapshot() {
      const livingEnemies = this.enemies.filter((enemy) => enemy.alive);
      let progress;
      if (this.stage.type === "Survival") progress = `${Math.max(0, Math.ceil(this.stage.duration - this.elapsed))}s rimanenti`;
      else if (this.stage.type === "Exploration") progress = `${this.objective.poi}/3 punti · ${livingEnemies.length} ostili`;
      else if (this.stage.type === "Defense") progress = `Faro ${Math.round(this.objective.beaconIntegrity)}% · ${livingEnemies.length} ostili`;
      else if (this.stage.type === "Boss") {
        const boss = this.enemies.find((enemy) => enemy.kind === "boss" && enemy.alive);
        progress = boss ? `Custode ${Math.round((boss.hp / boss.maxHp) * 100)}% · ${livingEnemies.length} ostili` : `${livingEnemies.length} ostili`;
      } else progress = `${livingEnemies.length} ostili rimanenti`;
      return {
        elapsed: this.elapsed,
        progress,
        heroes: this.heroes.map((hero) => ({
          id: hero.id,
          name: hero.name,
          role: hero.role,
          hue: hero.hue,
          hp: hero.hp,
          maxHp: hero.maxHp,
          alive: hero.alive,
          ammo: hero.ammo,
          maxAmmo: hero.maxAmmo,
          status: hero.status,
          lastAction: hero.lastAction,
          kills: hero.kills,
        })),
        enemies: livingEnemies.length,
        threat: livingEnemies.reduce((sum, enemy) => sum + enemy.threat, 0),
        commands: { ...this.commands },
      };
    }

    log(message, tone) {
      this.onLog(message, tone || "");
    }

    distance(a, b) {
      return Math.hypot(a.x - b.x, a.y - b.y);
    }

    draw() {
      const ctx = this.ctx;
      ctx.clearRect(0, 0, this.width, this.height);
      this.drawGround(ctx);
      this.drawObjective(ctx);
      this.drawProjectiles(ctx);
      const units = [...this.enemies, ...this.heroes].filter((unit) => unit.alive).sort((a, b) => a.y - b.y);
      units.forEach((unit) => this.drawUnit(ctx, unit));
      this.drawEffects(ctx);
    }

    drawGround(ctx) {
      const gradient = ctx.createLinearGradient(0, 0, this.width, this.height);
      gradient.addColorStop(0, `hsl(${this.stage.hue} 22% 13%)`);
      gradient.addColorStop(0.5, `hsl(${this.stage.hue + 12} 18% 9%)`);
      gradient.addColorStop(1, "#070a0d");
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, this.width, this.height);

      const top = this.playTop;
      const bottom = this.playBottom;
      const ground = ctx.createLinearGradient(0, top, 0, bottom);
      ground.addColorStop(0, "rgba(78, 91, 89, 0.08)");
      ground.addColorStop(1, "rgba(4, 7, 8, 0.58)");
      ctx.fillStyle = ground;
      ctx.fillRect(0, top, this.width, bottom - top);

      ctx.strokeStyle = "rgba(146, 175, 178, 0.035)";
      ctx.lineWidth = 1;
      for (let x = -this.height; x < this.width + this.height; x += 54) {
        ctx.beginPath();
        ctx.moveTo(x, top);
        ctx.lineTo(x + (bottom - top) * 0.62, bottom);
        ctx.stroke();
      }
      for (let y = top + 36; y < bottom; y += 46) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(this.width, y);
        ctx.stroke();
      }

      this.backdrop.forEach((shape) => {
        const drift = Math.sin(this.elapsed * 0.12 + shape.x) * 2;
        ctx.globalAlpha = 0.08 + shape.depth * 0.07;
        ctx.fillStyle = shape.kind % 2 ? `hsl(${this.stage.hue} 25% 25%)` : "#1b2221";
        ctx.beginPath();
        ctx.ellipse(shape.x, shape.y + drift, shape.r * 1.7, shape.r * 0.65, -0.2, 0, TAU);
        ctx.fill();
      });
      ctx.globalAlpha = 1;

      const fog = ctx.createLinearGradient(0, top, this.width, bottom);
      fog.addColorStop(0, "rgba(90, 158, 164, 0.04)");
      fog.addColorStop(0.55, "rgba(170, 174, 143, 0.045)");
      fog.addColorStop(1, "transparent");
      ctx.fillStyle = fog;
      ctx.fillRect(0, top, this.width, bottom - top);
    }

    drawObjective(ctx) {
      if (this.stage.type === "Defense") {
        const x = this.width * 0.18;
        const y = (this.playTop + this.playBottom) / 2;
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(Math.PI / 4);
        ctx.fillStyle = "rgba(228, 183, 91, 0.14)";
        ctx.strokeStyle = "rgba(245, 204, 123, 0.7)";
        ctx.lineWidth = 2;
        ctx.fillRect(-20, -20, 40, 40);
        ctx.strokeRect(-20, -20, 40, 40);
        ctx.restore();
        ctx.fillStyle = "rgba(236, 190, 100, 0.18)";
        ctx.beginPath();
        ctx.arc(x, y, 60 + Math.sin(this.elapsed * 2) * 4, 0, TAU);
        ctx.fill();
      }
      if (this.stage.type === "Exploration") {
        [0, 1, 2].forEach((index) => {
          const x = this.width * (0.45 + index * 0.12);
          const y = this.playTop + 90 + index * 65;
          ctx.strokeStyle = index < this.objective.poi ? "rgba(86, 211, 215, 0.7)" : "rgba(120, 145, 150, 0.2)";
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.arc(x, y, 18 + Math.sin(this.elapsed + index) * 2, 0, TAU);
          ctx.stroke();
          ctx.beginPath();
          ctx.moveTo(x - 7, y);
          ctx.lineTo(x + 7, y);
          ctx.moveTo(x, y - 7);
          ctx.lineTo(x, y + 7);
          ctx.stroke();
        });
      }
    }

    drawUnit(ctx, unit) {
      ctx.save();
      ctx.translate(unit.x, unit.y);
      const facing = unit.type === "hero" ? 1 : -1;
      const hue = unit.hue;
      const shadow = ctx.createRadialGradient(0, unit.radius * 0.8, 1, 0, unit.radius * 0.8, unit.radius * 1.5);
      shadow.addColorStop(0, "rgba(0,0,0,0.5)");
      shadow.addColorStop(1, "transparent");
      ctx.fillStyle = shadow;
      ctx.beginPath();
      ctx.ellipse(0, unit.radius * 0.75, unit.radius * 1.6, unit.radius * 0.62, 0, 0, TAU);
      ctx.fill();

      if (unit.shield > 0) {
        ctx.strokeStyle = "rgba(91, 216, 224, 0.75)";
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(0, 0, unit.radius + 8 + Math.sin(this.elapsed * 5) * 2, 0, TAU);
        ctx.stroke();
      }

      ctx.fillStyle = unit.flash > 0 ? "#fff" : `hsl(${hue} 40% ${unit.type === "hero" ? 52 : 38}%)`;
      ctx.strokeStyle = unit.type === "hero" ? "rgba(218, 232, 235, 0.72)" : "rgba(240, 132, 117, 0.52)";
      ctx.lineWidth = unit.kind === "boss" ? 3 : 1;
      ctx.beginPath();
      if (unit.kind === "boss") {
        for (let i = 0; i < 8; i += 1) {
          const angle = (i / 8) * TAU;
          const radius = i % 2 ? unit.radius * 0.8 : unit.radius * 1.15;
          const px = Math.cos(angle) * radius;
          const py = Math.sin(angle) * radius;
          if (i === 0) ctx.moveTo(px, py);
          else ctx.lineTo(px, py);
        }
        ctx.closePath();
      } else if (unit.type === "hero") {
        ctx.moveTo(-unit.radius * 0.72, unit.radius * 0.72);
        ctx.lineTo(-unit.radius * 0.88, -unit.radius * 0.18);
        ctx.lineTo(-unit.radius * 0.4, -unit.radius * 0.84);
        ctx.lineTo(unit.radius * 0.4, -unit.radius * 0.84);
        ctx.lineTo(unit.radius * 0.88, -unit.radius * 0.18);
        ctx.lineTo(unit.radius * 0.72, unit.radius * 0.72);
        ctx.closePath();
      } else {
        ctx.moveTo(-unit.radius, 0);
        ctx.lineTo(-unit.radius * 0.4, -unit.radius);
        ctx.lineTo(unit.radius * 0.8, -unit.radius * 0.6);
        ctx.lineTo(unit.radius, unit.radius * 0.5);
        ctx.lineTo(-unit.radius * 0.3, unit.radius);
        ctx.closePath();
      }
      ctx.fill();
      ctx.stroke();

      ctx.strokeStyle = unit.type === "hero" ? "rgba(245, 219, 167, 0.65)" : "rgba(50, 23, 20, 0.85)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(facing * unit.radius * 0.35, -unit.radius * 0.2);
      ctx.lineTo(facing * unit.radius * 1.45, -unit.radius * 0.58);
      ctx.stroke();

      const hpWidth = unit.kind === "boss" ? 90 : unit.radius * 2.6;
      ctx.fillStyle = "rgba(2,4,6,0.82)";
      ctx.fillRect(-hpWidth / 2, -unit.radius - 13, hpWidth, 4);
      ctx.fillStyle = unit.type === "hero" ? "#6ec391" : unit.kind === "boss" ? "#e2af56" : "#d3605a";
      ctx.fillRect(-hpWidth / 2, -unit.radius - 13, hpWidth * (unit.hp / unit.maxHp), 4);

      if (unit.kind === "boss") {
        ctx.fillStyle = "rgba(236,225,205,0.85)";
        ctx.font = "9px Bahnschrift, sans-serif";
        ctx.textAlign = "center";
        ctx.fillText("CUSTODE", 0, -unit.radius - 20);
      }
      ctx.restore();
    }

    drawProjectiles(ctx) {
      this.projectiles.forEach((projectile) => {
        ctx.save();
        ctx.fillStyle = `hsl(${projectile.hue} 75% 66%)`;
        ctx.shadowColor = ctx.fillStyle;
        ctx.shadowBlur = projectile.skill ? 18 : 7;
        ctx.beginPath();
        ctx.arc(projectile.x, projectile.y, projectile.skill ? 5 : 2.5, 0, TAU);
        ctx.fill();
        ctx.restore();
      });
    }

    drawEffects(ctx) {
      this.effects.forEach((effect) => {
        const progress = 1 - effect.life / effect.maxLife;
        const alpha = Math.max(0, 1 - progress);
        ctx.save();
        ctx.globalAlpha = alpha;
        ctx.strokeStyle = `hsl(${effect.hue} 75% 62%)`;
        ctx.fillStyle = `hsl(${effect.hue} 75% 62%)`;
        if (effect.type === "text") {
          ctx.font = "600 11px Bahnschrift, sans-serif";
          ctx.textAlign = "center";
          ctx.fillText(effect.text, effect.x, effect.y - progress * 24);
        } else if (effect.type === "ring") {
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.arc(effect.x, effect.y, effect.radius * (0.45 + progress * 0.75), 0, TAU);
          ctx.stroke();
        } else if (effect.type === "burst" || effect.type === "death") {
          const rays = effect.type === "death" ? 10 : 6;
          ctx.lineWidth = effect.type === "death" ? 2 : 1;
          for (let i = 0; i < rays; i += 1) {
            const angle = (i / rays) * TAU;
            const start = progress * effect.radius * 0.25;
            const end = progress * effect.radius;
            ctx.beginPath();
            ctx.moveTo(effect.x + Math.cos(angle) * start, effect.y + Math.sin(angle) * start);
            ctx.lineTo(effect.x + Math.cos(angle) * end, effect.y + Math.sin(angle) * end);
            ctx.stroke();
          }
        } else if (effect.type === "slash") {
          ctx.lineWidth = 3;
          ctx.beginPath();
          ctx.arc(effect.x, effect.y, 12 + progress * 18, -1.3, 0.9);
          ctx.stroke();
        } else if (effect.type === "line") {
          ctx.lineWidth = 3;
          ctx.beginPath();
          ctx.moveTo(effect.x, effect.y);
          ctx.lineTo(effect.x2, effect.y2);
          ctx.stroke();
        }
        ctx.restore();
      });
    }
  }

  root.RiftwardCombat = { CombatSimulation };
})(typeof globalThis !== "undefined" ? globalThis : this);
