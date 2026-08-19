(function () {
  "use strict";

  const C = window.RiftwardCore;
  const main = document.getElementById("mainContent");
  const modalRoot = document.getElementById("modalRoot");
  const toastRegion = document.getElementById("toastRegion");
  const missionLayer = document.getElementById("missionLayer");
  const battleCanvas = document.getElementById("battleCanvas");

  const UI = {
    view: "hub",
    selectedHeroId: null,
    selectedFloor: 1,
    heroFilter: "all",
    archiveTab: "reports",
    lastSummon: [],
    combat: null,
    combatCooldowns: {},
    combatLog: [],
    cooldownTimer: null,
  };

  function safe(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function loadState() {
    try {
      const raw = localStorage.getItem(C.SAVE_KEY);
      const parsed = raw ? C.migrateState(JSON.parse(raw)) : null;
      return parsed || C.createInitialState();
    } catch (error) {
      console.warn("Salvataggio illeggibile; viene creato un nuovo world.", error);
      return C.createInitialState();
    }
  }

  let state = loadState();
  C.applyOfflineProgress(state);

  function save() {
    state.world.lastSavedAt = Date.now();
    localStorage.setItem(C.SAVE_KEY, JSON.stringify(state));
    updateChrome();
  }

  function formatTime(timestamp) {
    const date = new Date(timestamp);
    const now = Date.now();
    const delta = Math.max(0, now - timestamp);
    if (delta < 60000) return "ora";
    if (delta < 3600000) return `${Math.floor(delta / 60000)}m`;
    if (delta < 86400000) return `${Math.floor(delta / 3600000)}h`;
    return new Intl.DateTimeFormat("it-IT", { day: "2-digit", month: "short" }).format(date);
  }

  function formatDuration(seconds) {
    const total = Math.max(0, Math.floor(seconds || 0));
    return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
  }

  function materialName(key) {
    return { ore: "Minerale", leather: "Pelle", wood: "Legno", cores: "Nuclei", medicine: "Medicine", food: "Razioni" }[key] || key;
  }

  function roleGlyph(role) {
    return C.ROLES[role]?.icon || "◈";
  }

  function updateChrome() {
    document.getElementById("goldValue").textContent = C.formatNumber(state.world.gold);
    document.getElementById("gemsValue").textContent = C.formatNumber(state.world.gems);
    document.getElementById("stonesValue").textContent = C.formatNumber(state.world.promotionStones);
    document.getElementById("floorBadge").textContent = String(state.world.currentFloor).padStart(2, "0");
    document.getElementById("rosterBadge").textContent = C.getAliveHeroes(state).length;
    document.getElementById("partyBadge").textContent = `${C.getPartyHeroes(state).filter(Boolean).length}/5`;
    document.getElementById("masterName").textContent = state.world.masterName;
    document.getElementById("masterRank").textContent = `Rank ${state.world.completedFloors.length >= 5 ? "D" : "E"}`;
    document.getElementById("worldLabel").textContent = `NEXUS ${state.world.id.slice(-5)} // ONLINE`;
    document.querySelectorAll("[data-view]").forEach((button) => {
      button.classList.toggle("active", button.dataset.view === UI.view);
    });
  }

  function toast(title, message, tone, glyph) {
    const node = document.createElement("div");
    node.className = `toast ${tone || ""}`;
    node.innerHTML = `<span class="report-glyph">${safe(glyph || "◇")}</span><div><strong>${safe(title)}</strong><span>${safe(message)}</span></div>`;
    toastRegion.appendChild(node);
    setTimeout(() => {
      node.style.opacity = "0";
      node.style.transform = "translateX(12px)";
      setTimeout(() => node.remove(), 220);
    }, 3600);
  }

  function showModal({ eyebrow, title, body, actions, wide }) {
    modalRoot.hidden = false;
    modalRoot.innerHTML = `
      <div class="modal${wide ? " modal-wide" : ""}" role="dialog" aria-modal="true" aria-labelledby="modalTitle">
        <header class="modal-header">
          ${eyebrow ? `<span class="eyebrow">${safe(eyebrow)}</span>` : ""}
          <h2 id="modalTitle">${safe(title)}</h2>
        </header>
        <div class="modal-body">${body}</div>
        <footer class="modal-actions">
          ${(actions || [{ label: "Chiudi", className: "secondary-button", action: "close-modal" }])
            .map((action) => `<button class="${safe(action.className || "secondary-button")}" data-action="${safe(action.action)}" ${action.data ? Object.entries(action.data).map(([key, value]) => `data-${safe(key)}="${safe(value)}"`).join(" ") : ""}>${safe(action.label)}</button>`)
            .join("")}
        </footer>
      </div>`;
    requestAnimationFrame(() => modalRoot.querySelector("button")?.focus());
  }

  function closeModal() {
    modalRoot.hidden = true;
    modalRoot.innerHTML = "";
  }

  function header(eyebrow, title, description, actions) {
    return `
      <header class="view-header">
        <div>
          <span class="eyebrow">${safe(eyebrow)}</span>
          <h1>${safe(title)}</h1>
          ${description ? `<p>${safe(description)}</p>` : ""}
        </div>
        ${actions ? `<div class="header-actions">${actions}</div>` : ""}
      </header>`;
  }

  function resourceStats() {
    const alive = C.getAliveHeroes(state);
    const averageFatigue = alive.length ? Math.round(alive.reduce((sum, hero) => sum + hero.fatigue, 0) / alive.length) : 0;
    const unread = state.events.filter((event) => !event.read).length;
    return `
      <div class="stats-row">
        <article class="stat-tile"><small>Avanzamento torre</small><strong>${state.world.completedFloors.length}<span style="font-size:.45em;color:var(--faint)"> / 100</span></strong><span>Piano attivo ${String(state.world.currentFloor).padStart(2, "0")}</span></article>
        <article class="stat-tile"><small>Roster operativo</small><strong>${alive.length}</strong><span>${state.memorial.length} nel Memoriale</span></article>
        <article class="stat-tile"><small>Fatigue media</small><strong>${averageFatigue}%</strong><span>${averageFatigue < 30 ? "Squadra riposata" : averageFatigue < 60 ? "Carico sostenibile" : "Riposo consigliato"}</span></article>
        <article class="stat-tile"><small>Rapporti non letti</small><strong>${unread}</strong><span>${state.events[0] ? safe(state.events[0].category) : "Nessun evento"}</span></article>
      </div>`;
  }

  function reportList(limit) {
    const events = state.events.slice(0, limit || 6);
    if (!events.length) return `<div class="empty-state"><div><span>≡</span>Nessun rapporto registrato.</div></div>`;
    return `<div class="report-list">${events.map((event) => `
      <article class="report-item">
        <span class="report-glyph">${event.severity === "danger" ? "!" : event.severity === "good" ? "✓" : "◇"}</span>
        <div><strong>${safe(event.title)}</strong><span>${safe(event.text)}</span></div>
        <time>${formatTime(event.timestamp)}</time>
      </article>`).join("")}</div>`;
  }

  function renderHub() {
    const stageRecord = C.getStage(state, state.world.currentFloor);
    const stage = stageRecord?.descriptor;
    const readiness = C.teamReadiness(state);
    main.innerHTML = `<section class="view hub-view">
      ${header("Waiting Room // Master Layer", "Il Nexus attende le tue decisioni", "Costruisci condizioni di successo. Nel Rift, gli eroi combatteranno e sceglieranno autonomamente.", `<button class="secondary-button" data-action="rest-roster">Riposo roster</button>`)}
      ${resourceStats()}
      <div class="hub-grid">
        <article class="rift-card">
          <div class="rift-content">
            <span class="threat-chip">${safe(stage?.type || "Nessuna missione")}</span>
            <h2>Piano ${String(state.world.currentFloor).padStart(2, "0")} · ${safe(stage?.name || "Rift silente")}</h2>
            <p>${safe(stage?.description || "La Torre non ha ancora materializzato una nuova missione.")}</p>
            <div class="button-row">
              <button class="primary-button" data-action="open-stage" data-floor="${state.world.currentFloor}">Apri briefing</button>
              <button class="secondary-button" data-view="squad">Squadra · ${readiness.grade}</button>
            </div>
          </div>
        </article>
        <article class="panel">
          <header class="panel-head"><h2>Rapporti recenti</h2><button class="text-button" data-view="archive">Apri archivio</button></header>
          ${reportList(5)}
        </article>
      </div>
      <div class="quick-grid">
        <button class="quick-action" data-view="heroes"><span>◈</span><span><strong>Valuta eroi</strong><small>Stat, skill, tratti e potenziale qualitativo</small></span></button>
        <button class="quick-action" data-view="squad"><span>⋈</span><span><strong>Prepara formazione</strong><small>${readiness.warnings.length ? `${readiness.warnings.length} avvisi tattici` : "Copertura ruoli stabile"}</small></span></button>
        <button class="quick-action" data-view="base"><span>▦</span><span><strong>Gestisci base</strong><small>Training, armory, crafting e recupero</small></span></button>
      </div>
    </section>`;
  }

  function heroCard(hero, selectable) {
    const xpRequired = C.xpToNext(hero.level, hero.currentRarity);
    const xpPercent = hero.level >= C.RARITY_CAPS[hero.currentRarity] ? 100 : Math.min(100, (hero.xp / xpRequired) * 100);
    const stateLabel = hero.state === "DEAD" ? "Caduto" : hero.fatigue >= 80 ? "Fatigue critica" : hero.injuries.length ? "Ferito" : "Operativo";
    const dotClass = hero.state === "DEAD" || hero.fatigue >= 80 ? "danger" : hero.fatigue >= 60 || hero.injuries.length ? "warn" : "";
    return `<article class="hero-card ${hero.state === "DEAD" ? "dead" : ""} ${UI.selectedHeroId === hero.id ? "selected" : ""}" ${hero.state === "ALIVE" ? `data-action="select-hero" data-hero-id="${hero.id}" tabindex="0"` : ""}>
      <div class="hero-card-top">
        <div class="hero-portrait" style="--hue:${hero.hue};--skin:${hero.skinHue}"><span class="portrait-role" title="${safe(hero.role)}">${roleGlyph(hero.role)}</span></div>
        <div class="hero-card-info">
          <div class="star-row">${C.stars(hero.currentRarity)}</div>
          <h3>${safe(hero.name)}</h3>
          <span class="hero-card-sub">Lv.${hero.level} · ${safe(hero.className)}</span>
          <div class="hero-card-state"><span class="status-dot ${dotClass}"></span><span class="hero-card-sub">${stateLabel}</span></div>
        </div>
      </div>
      <div class="hero-bars">
        <div class="mini-bar"><label><span>XP</span><span>${Math.round(xpPercent)}%</span></label><div class="bar-track"><div class="bar-fill xp" style="--value:${xpPercent}%"></div></div></div>
        <div class="mini-bar"><label><span>Morale</span><span>${hero.morale}</span></label><div class="bar-track"><div class="bar-fill morale" style="--value:${hero.morale}%"></div></div></div>
      </div>
    </article>`;
  }

  function renderHeroes() {
    const heroes = state.heroes.filter((hero) => {
      if (UI.heroFilter === "alive") return hero.state === "ALIVE";
      if (UI.heroFilter === "dead") return hero.state === "DEAD";
      if (C.ROLES[UI.heroFilter]) return hero.role === UI.heroFilter && hero.state === "ALIVE";
      return true;
    });
    const filters = ["all", "alive", "Guardian", "Vanguard", "Lancer", "Ranger", "Mage", "Support", "dead"];
    main.innerHTML = `<section class="view">
      ${header("Roster // Persistent Agents", "Eroi", "Ogni eroe ha seed, crescita, personalità, memoria e una storia propria. Il potenziale nascosto è mostrato solo attraverso osservazioni qualitative.", `<button class="primary-button" data-view="summon">Evoca nuovi eroi</button>`)}
      <div class="section-bar">
        <h2 class="section-title">Roster · ${heroes.length}</h2>
        <div class="filters">${filters.map((filter) => `<button class="filter-button ${UI.heroFilter === filter ? "active" : ""}" data-action="hero-filter" data-filter="${filter}">${filter === "all" ? "Tutti" : filter === "alive" ? "Vivi" : filter === "dead" ? "Memoriale" : filter}</button>`).join("")}</div>
      </div>
      <div class="hero-grid">${heroes.length ? heroes.map((hero) => heroCard(hero)).join("") : `<div class="empty-state"><div><span>◈</span>Nessun eroe corrisponde al filtro.</div></div>`}</div>
    </section>`;
  }

  function equipmentRows(hero) {
    const labels = { main: "Main weapon", sub: "Off-hand", armor: "Armor", accessory: "Accessory" };
    return Object.entries(labels).map(([slot, label]) => {
      const item = hero.equipment[slot];
      return `<div class="equipment-row">
        <span class="list-glyph">${slot === "main" ? "⚔" : slot === "sub" ? "◇" : slot === "armor" ? "⬒" : "◆"}</span>
        <div><strong>${item ? safe(item.name) : "Slot vuoto"}</strong><small>${label}${item ? ` · Qualità ${Math.round(item.quality * 100)}% · +${item.reinforcement}` : ""}</small></div>
        <button class="text-button" data-action="choose-equipment" data-hero-id="${hero.id}" data-slot="${slot}">${item ? item.grade : "Equip"}</button>
      </div>`;
    }).join("");
  }

  function renderHeroDetail(heroId) {
    const hero = state.heroes.find((candidate) => candidate.id === heroId);
    if (!hero) return navigate("heroes");
    const derived = C.derivedStats(hero);
    const partySlot = state.party.indexOf(hero.id);
    const cap = C.RARITY_CAPS[hero.currentRarity];
    const canPromote = hero.level >= cap && hero.currentRarity < 7;
    main.innerHTML = `<section class="view">
      ${header("Hero Record // " + hero.id, hero.name, `${hero.origin} · ${hero.background}. I numeri di potenziale restano nascosti al Master.`, `<button class="secondary-button" data-view="heroes">← Roster</button><button class="${partySlot >= 0 ? "danger-button" : "primary-button"}" data-action="toggle-party-hero" data-hero-id="${hero.id}">${partySlot >= 0 ? "Rimuovi dal party" : "Aggiungi al party"}</button>`)}
      <div class="hero-detail">
        <article class="hero-profile">
          <div class="hero-portrait" style="--hue:${hero.hue};--skin:${hero.skinHue}"><span class="portrait-role">${roleGlyph(hero.role)}</span></div>
          <div class="profile-meta">
            <div class="star-row">${C.stars(hero.currentRarity)} <span style="color:var(--faint)">· nativa ${C.stars(hero.nativeRarity)}</span></div>
            <h2 class="hero-title">${safe(hero.name)}</h2>
            <span class="hero-card-sub">Lv.${hero.level}/${cap} · ${safe(hero.className)} · ${safe(hero.profession)}</span>
            <p class="hero-quote">“${safe(hero.quote)}”</p>
            <div class="button-row" style="margin-top:20px">
              <button class="primary-button" data-action="train-hero" data-hero-id="${hero.id}" ${hero.state !== "ALIVE" ? "disabled" : ""}>Addestra</button>
              <button class="secondary-button" data-action="promote-hero" data-hero-id="${hero.id}" ${!canPromote || hero.state !== "ALIVE" ? "disabled" : ""}>Promuovi</button>
            </div>
          </div>
        </article>
        <div class="detail-stack">
          <div class="attribute-grid">
            <div class="attribute"><small>STR</small><strong>${hero.stats.str}</strong></div>
            <div class="attribute"><small>INT</small><strong>${hero.stats.int}</strong></div>
            <div class="attribute"><small>STA</small><strong>${hero.stats.sta}</strong></div>
            <div class="attribute"><small>AGI</small><strong>${hero.stats.agi}</strong></div>
          </div>
          <div class="info-grid">
            <div class="info-cell"><small>HP max</small><strong>${derived.maxHp}</strong></div>
            <div class="info-cell"><small>Attacco / Magia</small><strong>${derived.physicalAttack} / ${derived.magicAttack}</strong></div>
            <div class="info-cell"><small>Defense</small><strong>${derived.defense}</strong></div>
            <div class="info-cell"><small>Accuracy / Crit</small><strong>${derived.accuracy}% / ${derived.crit}%</strong></div>
            <div class="info-cell"><small>Morale</small><strong>${hero.morale} · ${hero.morale >= 70 ? "High" : hero.morale >= 40 ? "Stable" : "Low"}</strong></div>
            <div class="info-cell"><small>Fatigue</small><strong>${hero.fatigue} · ${hero.fatigue < 30 ? "Fresh" : hero.fatigue < 60 ? "Tired" : "Exhausted"}</strong></div>
          </div>
          <article class="panel">
            <header class="panel-head"><h3>Assessment qualitativo</h3><span class="chip">Potential hidden</span></header>
            <div class="memory-list">${hero.assessment.map((text) => `<div class="memory-row"><span class="list-glyph">?</span><span>${safe(text)}</span></div>`).join("")}</div>
          </article>
          <article class="panel">
            <header class="panel-head"><h3>Skill</h3><span class="chip">Uso → crescita</span></header>
            <div class="skill-list">${hero.skills.map((skill) => `<div class="skill-row"><span class="list-glyph">✦</span><div><strong>${safe(skill.name)}</strong><small>${safe(skill.tier)} · ${safe(skill.description)}</small></div><span class="skill-level">Lv.${skill.level}</span></div>`).join("")}</div>
          </article>
          <article class="panel">
            <header class="panel-head"><h3>Equipaggiamento</h3><button class="text-button" data-view="base">Armory</button></header>
            <div class="equipment-list">${equipmentRows(hero)}</div>
          </article>
          <article class="panel">
            <header class="panel-head"><h3>Memoria persistente</h3><span class="chip">${hero.memories.length} eventi</span></header>
            <div class="memory-list">${hero.memories.slice(0, 6).map((memory) => `<div class="memory-row"><span class="list-glyph">≡</span><span>${safe(memory.text)}</span></div>`).join("")}</div>
          </article>
        </div>
      </div>
    </section>`;
  }

  function floorCard(floor) {
    const record = state.stages[floor];
    const unlocked = floor <= state.world.maxUnlockedFloor;
    const blueprint = C.STAGE_BLUEPRINTS[floor];
    const attempts = record?.attempts || 0;
    const cleared = record?.cleared;
    return `<button class="floor-card ${UI.selectedFloor === floor ? "active" : ""} ${!unlocked ? "locked" : ""}" data-action="select-floor" data-floor="${floor}" ${!unlocked ? "disabled" : ""}>
      <span class="floor-number">${String(floor).padStart(2, "0")}</span>
      <span class="floor-info"><small>${safe(blueprint.stream)}</small><strong>${safe(blueprint.name)}</strong><span>${safe(blueprint.type)} · ${safe(blueprint.biome)} · ${attempts} tentativ${attempts === 1 ? "o" : "i"}</span></span>
      <span class="floor-state ${cleared ? "cleared" : ""}">${!unlocked ? "Bloccato" : cleared ? "Clear ✓" : "Disponibile"}</span>
    </button>`;
  }

  function stageBrief(floor) {
    const record = C.getStage(state, floor);
    if (!record) return "";
    const stage = record.descriptor;
    const readiness = C.teamReadiness(state);
    const rewardMult = Math.max(0.35, 1 - 0.2 * Math.max(0, record.attempts));
    return `<article class="stage-brief" style="--stage-hue:${stage.hue}">
      <div class="stage-visual"><div class="stage-visual-label"><span class="eyebrow">${safe(stage.stream)}</span><h2>${safe(stage.name)}</h2></div></div>
      <div class="stage-body">
        <span class="threat-chip">${safe(stage.type)} · Threat ${stage.threatBudget}</span>
        <p>${safe(stage.description)}</p>
        <div class="brief-grid">
          <div class="brief-item"><small>Obiettivo</small><strong>${safe(stage.objective)}</strong></div>
          <div class="brief-item"><small>Bioma</small><strong>${safe(stage.biome)}</strong></div>
          <div class="brief-item"><small>Ricompensa prossimo tentativo</small><strong>×${rewardMult.toFixed(2)}</strong></div>
          <div class="brief-item"><small>World seed derivato</small><strong>${safe(stage.seed.toUpperCase())}</strong></div>
        </div>
        <span class="label">Intel disponibile</span>
        <ul class="intel-list">${stage.clues.map((clue) => `<li>${safe(clue)}</li>`).join("")}</ul>
        <div class="warning-box" style="margin:17px 0">Il retry mantiene questo descriptor. 0 HP significa morte permanente, salvo skill eccezionali pre-trigger.</div>
        <div class="button-row">
          <button class="primary-button" data-action="deploy" data-floor="${floor}" ${readiness.living.length !== 5 ? "disabled" : ""}>Entra nel Rift</button>
          <button class="secondary-button" data-view="squad">Squadra · ${safe(readiness.grade)}</button>
        </div>
      </div>
    </article>`;
  }

  function renderTower() {
    UI.selectedFloor = C.clamp(UI.selectedFloor || state.world.currentFloor, 1, state.world.maxUnlockedFloor);
    main.innerHTML = `<section class="view">
      ${header("Campaign // 100 Floors", "La Torre", "I primi cinque piani formano uno Stream persistente. Oltre il limite del vertical slice, la campagna continua fino al Floor 100.", `<button class="secondary-button" data-view="squad">Configura party</button>`)}
      <div class="tower-layout">
        <div class="floor-list">${[1, 2, 3, 4, 5].map(floorCard).join("")}
          <div class="empty-state"><div><span>△</span><strong>PIANI 06—100</strong><br />Architettura prevista nella specifica completa; contenuto oltre il vertical slice.</div></div>
        </div>
        ${stageBrief(UI.selectedFloor)}
      </div>
    </section>`;
  }

  function rosterDragCard(hero) {
    return `<div class="roster-drag" draggable="true" data-hero-id="${hero.id}" data-action="quick-assign-hero">
      <span class="slot-avatar" style="--hue:${hero.hue}">${safe(hero.name.slice(0, 2).toUpperCase())}</span>
      <span><strong>${safe(hero.name)}</strong><small>${C.stars(hero.currentRarity)} · ${safe(hero.role)} · Fatigue ${hero.fatigue}</small></span>
    </div>`;
  }

  function formationSlot(hero, index) {
    if (!hero) return `<div class="formation-slot" data-slot="${index}"><div class="slot-empty"><span>＋</span>${safe(C.PARTY_POSITIONS[index])}</div></div>`;
    return `<div class="formation-slot" data-slot="${index}">
      <div class="slot-hero"><span class="slot-avatar" style="--hue:${hero.hue}">${safe(hero.name.slice(0, 2).toUpperCase())}</span><span><strong>${safe(hero.name)}</strong><small>${safe(hero.role)} · Lv.${hero.level} · ${C.stars(hero.currentRarity)}</small></span><button class="slot-remove" data-action="remove-slot" data-slot="${index}" aria-label="Rimuovi ${safe(hero.name)}">×</button></div>
    </div>`;
  }

  function renderSquad() {
    const readiness = C.teamReadiness(state);
    const available = C.getAliveHeroes(state).filter((hero) => !state.party.includes(hero.id));
    main.innerHTML = `<section class="view">
      ${header("Party Formation // 2 Front · 2 Mid · 1 Rear", "Prepara la squadra", "Trascina gli eroi negli slot oppure selezionali dalla riserva. Formazione, morale e ruoli modificano il risultato più della sola somma delle statistiche.", `<button class="secondary-button" data-action="auto-form">Auto forma</button><button class="secondary-button" data-action="auto-equip">Auto equip</button><button class="primary-button" data-action="open-stage" data-floor="${state.world.currentFloor}">Briefing Piano ${state.world.currentFloor}</button>`)}
      <div class="squad-layout">
        <div>
          <div class="formation-board">
            <div class="formation-labels"><span>Front</span><span>Mid</span><span>Rear</span></div>
            <div class="formation-slots">${readiness.party.map(formationSlot).join("")}</div>
          </div>
          <div class="section-bar"><h2 class="section-title">Riserva disponibile</h2><span class="chip">Drag & drop</span></div>
          <div class="roster-strip">${available.length ? available.map(rosterDragCard).join("") : `<div class="empty-state"><div>Tutti gli eroi operativi sono già assegnati.</div></div>`}</div>
        </div>
        <aside class="panel squad-analysis">
          <header class="panel-head"><h2>Analisi formazione</h2><span class="chip">Utility model</span></header>
          <div class="analysis-score"><strong>${C.formatNumber(readiness.score)}</strong><span>Potenza stimata · ${safe(readiness.grade)}</span></div>
          <div class="analysis-row"><span>Copertura ruoli</span><strong>${Math.round(readiness.roleCoverage * 100)}%</strong></div>
          <div class="analysis-row"><span>Bond medio</span><strong>${readiness.averageBond}</strong></div>
          <div class="analysis-row"><span>Bonus cooperazione</span><strong>+${readiness.bondBonus}%</strong></div>
          <div class="analysis-row"><span>Party</span><strong>${readiness.living.length}/5</strong></div>
          <div class="memory-list">${readiness.warnings.length ? readiness.warnings.map((warning) => `<div class="memory-row"><span class="list-glyph" style="color:var(--amber)">!</span><span>${safe(warning)}</span></div>`).join("") : `<div class="memory-row"><span class="list-glyph" style="color:var(--green)">✓</span><span>Nessun avviso tattico rilevante.</span></div>`}</div>
        </aside>
      </div>
    </section>`;
    bindDragAndDrop();
  }

  function banner(pool) {
    const high = pool === "high";
    const cost = high ? 500 : 10000;
    const currency = high ? "Gemme" : "Oro";
    const rates = high ? [["3★", "93,5%"], ["4★", "5,5%"], ["5★", "1,0%"]] : [["1★", "78%"], ["2★", "19%"], ["3★", "3%"]];
    return `<article class="banner" style="--banner-hue:${high ? 270 : 42}">
      <div class="banner-art">
        <span class="eyebrow">${high ? "High-grade resonance" : "Common resonance"}</span>
        <h2>${high ? "Giuramento astrale" : "Richiamo del Nexus"}</h2>
      </div>
      <div class="banner-body">
        <table class="rate-table" aria-label="Probabilità ${high ? "high-grade" : "normal"}"><tbody>${rates.map(([rarity, rate]) => `<tr><th>${rarity}</th><td>${rate}</td></tr>`).join("")}</tbody></table>
        ${high ? `<div class="banner-note"><span>Pity 5★</span><strong>${state.pity.highGrade} / 100</strong></div><div class="pity-track" style="--pity:${state.pity.highGrade}%"><span></span></div>` : `<div class="banner-note"><span>Eroi 1★—3★</span><strong>HeroSeed unico</strong></div>`}
        <div class="button-row">
          <button class="primary-button" data-action="summon-confirm" data-pool="${pool}" data-count="1">1 · ${C.formatNumber(cost)} ${currency}</button>
          <button class="secondary-button" data-action="summon-confirm" data-pool="${pool}" data-count="10">10 · ${C.formatNumber(cost * 10)} ${currency}</button>
        </div>
      </div>
    </article>`;
  }

  function renderSummon() {
    main.innerHTML = `<section class="view">
      ${header("Summoning Hall // Odds disclosed", "Evocazione procedurale", "Ogni pull genera una persona nuova: identità, crescita, tratti e potenziale non producono cloni perfetti. Le probabilità sono mostrate prima di ogni spesa; questa demo non usa denaro reale.")}
      <div class="info-box" style="margin-bottom:18px">6★ e 7★ sono rarità reali ma non appartengono ai pool standard del prototipo: entrano tramite endgame, promozioni eccezionali e Transcendent pool.</div>
      <div class="summon-layout">${banner("normal")}${banner("high")}</div>
      ${UI.lastSummon.length ? `<div class="section-bar"><h2 class="section-title">Ultima risonanza</h2><span class="chip">${UI.lastSummon.length} nuovi eroi</span></div><div class="summon-results">${UI.lastSummon.map((hero, index) => `<article class="summon-result" style="--i:${index}" data-action="select-hero" data-hero-id="${hero.id}"><div class="hero-portrait" style="--hue:${hero.hue};--skin:${hero.skinHue}"><span class="portrait-role">${roleGlyph(hero.role)}</span></div><h3>${safe(hero.name)}</h3><p>${C.stars(hero.currentRarity)} · ${safe(hero.role)}</p></article>`).join("")}</div>` : ""}
    </section>`;
  }

  const FACILITIES = {
    summoning: ["Summoning Hall", "Evoca HeroSeed unici con Oro o Gemme.", "✦"],
    training: ["Training Center", "Converte tempo, Oro e Fatigue in XP e crescita skill.", "†"],
    armory: ["Armory", "Gestisce loadout, preset ed equipaggiamento.", "⚔"],
    warehouse: ["Warehouse", "Conserva materiali e oggetti non assegnati.", "▤"],
    lodging: ["Lodging", "Recupera Fatigue e morale attraverso riposo e razioni.", "⌂"],
    smithy: ["Smithy", "Forgiatura, rinforzo e riparazione degli oggetti.", "⚒"],
    workshop: ["Workshop", "Consumabili, strumenti, munizioni e ricette.", "⌘"],
    research: ["Archive", "Intel, codex nemici e previsione delle minacce.", "≡"],
    infirmary: ["Infirmary", "Cura ferite gravi e contaminazione persistente.", "+"],
    synthesis: ["Synthesis Chamber", "Trasferisce crescita distruggendo il donor in modo permanente.", "◌"],
    magic: ["Magic Hall", "Training arcano e ricerca di nuove skill.", "✧"],
    dimensionGate: ["Dimension Gate", "Accesso a Raid, Ruins e servizi cross-world.", "◇"],
  };

  function facilityCard(key, facility) {
    const meta = FACILITIES[key];
    const upgradeCost = 12000 * Math.max(1, facility.level) ** 2;
    return `<article class="facility-card ${facility.unlocked ? "" : "locked"}" data-glyph="${safe(meta[2])}">
      <span class="eyebrow">${facility.unlocked ? `Facility // Level ${facility.level}` : `Unlock // Floor ${facility.unlockFloor}`}</span>
      <h2>${safe(meta[0])}</h2>
      <p>${safe(meta[1])}</p>
      <div class="facility-level">${[1, 2, 3, 4, 5].map((level) => `<span class="${level <= facility.level ? "on" : ""}"></span>`).join("")}</div>
      ${facility.unlocked ? `<div class="button-row" style="margin-top:18px"><button class="secondary-button" data-action="use-facility" data-facility="${key}">Usa</button><button class="text-button" data-action="upgrade-facility" data-facility="${key}" ${facility.level >= 5 ? "disabled" : ""}>Upgrade · ${C.formatNumber(upgradeCost)} G</button></div>` : ""}
    </article>`;
  }

  function inventoryPanel() {
    const materials = Object.entries(state.world.materials).map(([key, value]) => `<article class="item-card"><span class="item-icon">${key === "ore" ? "⬡" : key === "leather" ? "▱" : key === "wood" ? "╫" : key === "cores" ? "◆" : key === "medicine" ? "+" : "◉"}</span><span><strong>${safe(materialName(key))}</strong><small>Quantità ${C.formatNumber(value)}</small></span></article>`).join("");
    const items = state.inventory.map((item) => `<article class="item-card"><span class="item-icon">${safe(item.glyph || (item.slot === "main" ? "⚔" : item.slot === "armor" ? "⬒" : "◇"))}</span><span><strong>${safe(item.name)} [${safe(item.grade)}]</strong><small>${safe(item.slot)} · Qualità ${Math.round(item.quality * 100)}%</small></span></article>`).join("");
    return `<article class="panel" style="margin-top:18px"><header class="panel-head"><h2>Warehouse</h2><span class="chip">${state.inventory.length} equip · 6 risorse</span></header><div class="inventory-grid">${materials}${items || ""}</div></article>`;
  }

  function renderBase() {
    main.innerHTML = `<section class="view">
      ${header("Waiting Room // Facilities", "Base persistente", "Il Nexus è un simulation layer: gli eroi riposano, si allenano, lavorano e costruiscono relazioni fra una missione e l'altra.", `<button class="secondary-button" data-action="rest-roster">Riposo roster</button><button class="primary-button" data-action="craft-open">Commissiona equip</button>`)}
      <div class="facility-grid">${Object.entries(state.facilities).map(([key, facility]) => facilityCard(key, facility)).join("")}</div>
      ${inventoryPanel()}
    </section>`;
  }

  function renderArchive() {
    const tabs = [["reports", "Rapporti"], ["ledger", "Ledger"], ["memorial", "Memoriale"], ["system", "Sistema"]];
    let content = "";
    if (UI.archiveTab === "reports") content = `<article class="panel">${reportList(120)}</article>`;
    if (UI.archiveTab === "ledger") content = `<div class="ledger">${state.ledger.length ? state.ledger.map((entry) => `<div class="ledger-row"><time>${new Intl.DateTimeFormat("it-IT", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }).format(new Date(entry.timestamp))}</time><small>${safe(entry.source)}</small><span>${safe(entry.reason)}</span><strong class="${entry.delta >= 0 ? "positive" : "negative"}">${entry.delta >= 0 ? "+" : ""}${C.formatNumber(entry.delta)} ${entry.currency === "gold" ? "G" : entry.currency === "gems" ? "◆" : safe(entry.currency)}</strong></div>`).join("") : `<div class="empty-state"><div>Nessuna transazione.</div></div>`}</div>`;
    if (UI.archiveTab === "memorial") content = state.memorial.length ? `<div class="memorial-grid">${state.memorial.map((record) => `<article class="memorial-card"><span class="eyebrow">Floor ${record.floor} // ${safe(record.role)}</span><h3>${safe(record.name)}</h3><span class="hero-card-sub">Lv.${record.level} · ${C.stars(record.rarity)} · ${record.missions} missioni</span><p>${safe(record.cause)}. “${safe(record.quote)}”</p><button class="text-button" data-action="select-hero" data-hero-id="${record.heroId}">Apri tombstone</button></article>`).join("")}</div>` : `<div class="empty-state"><div><span>†</span>Il Memoriale è vuoto.<br />Che resti così il più a lungo possibile.</div></div>`;
    if (UI.archiveTab === "system") content = `<article class="panel"><div class="memory-list">
      <div class="memory-row"><span class="list-glyph">#</span><span>World ID: ${safe(state.world.id)} · Seed: ${safe(state.world.seed)}</span></div>
      <div class="memory-row"><span class="list-glyph">△</span><span>Stage persistenti: ${Object.keys(state.stages).length}. Retry senza reroll attivo.</span></div>
      <div class="memory-row"><span class="list-glyph">20</span><span>Combat simulation: 20 tick/s. Utility AI: 5 Hz. Rendering: requestAnimationFrame.</span></div>
      <div class="memory-row"><span class="list-glyph">∞</span><span>Salvataggio locale immediato per summon, spese, missioni e morti permanenti.</span></div>
      <div class="memory-row"><span class="list-glyph">$</span><span>Nessun acquisto reale, paid resurrection o popup dopo una sconfitta.</span></div>
    </div></article>`;
    main.innerHTML = `<section class="view">
      ${header("Event Store // Append-only", "Archivio del Nexus", "Rapporti, transazioni e tombstone rendono leggibili le conseguenze. Gli eroi morti non vengono cancellati dai dati, ma non possono tornare nel roster.", `<button class="secondary-button" data-action="mark-read">Segna rapporti letti</button>`)}
      <div class="archive-tabs">${tabs.map(([key, label]) => `<button class="archive-tab ${UI.archiveTab === key ? "active" : ""}" data-action="archive-tab" data-tab="${key}">${label}</button>`).join("")}</div>
      ${content}
    </section>`;
  }

  function render() {
    updateChrome();
    if (UI.view === "hub") renderHub();
    else if (UI.view === "heroes") renderHeroes();
    else if (UI.view === "hero") renderHeroDetail(UI.selectedHeroId);
    else if (UI.view === "tower") renderTower();
    else if (UI.view === "squad") renderSquad();
    else if (UI.view === "summon") renderSummon();
    else if (UI.view === "base") renderBase();
    else if (UI.view === "archive") renderArchive();
    else renderHub();
  }

  function navigate(view) {
    if (missionLayer.hidden === false) return;
    UI.view = view;
    if (view === "tower") UI.selectedFloor = C.clamp(state.world.currentFloor, 1, state.world.maxUnlockedFloor);
    render();
    main.scrollTop = 0;
    main.focus({ preventScroll: true });
  }

  function showOnboarding() {
    showModal({
      eyebrow: "Master onboarding // 01",
      title: "Preparare. Osservare. Convivere con le conseguenze.",
      body: `<p>Riftward è un autonomous squad management roguelite. Non controllerai direttamente gli attacchi: scegli chi inviare, come equipaggiarlo, dove schierarlo e quali priorità macro comunicare.</p>
        <div class="onboarding-steps">
          <article class="onboarding-step"><span>1</span><strong>Prepara</strong><p>Valuta tratti, skill, Fatigue, morale, formazione e intel.</p></article>
          <article class="onboarding-step"><span>2</span><strong>Osserva</strong><p>L'IA decide bersagli, movimento, protezione e uso delle skill.</p></article>
          <article class="onboarding-step"><span>3</span><strong>Ricorda</strong><p>Stage e memorie persistono. La morte a 0 HP è permanente.</p></article>
        </div>
        <div class="warning-box"><strong>Vertical slice completa:</strong> 5 piani collegati, tre+ tipi missione, base, summon, equip, training, relazioni, XP, permadeath, retry persistente e boss.</div>`,
      actions: [{ label: "Assumo il comando", className: "primary-button", action: "finish-onboarding" }],
    });
  }

  function summonConfirm(pool, count) {
    const high = pool === "high";
    const total = (high ? 500 : 10000) * count;
    const rates = high ? "3★ 93,5% · 4★ 5,5% · 5★ 1,0%" : "1★ 78% · 2★ 19% · 3★ 3%";
    showModal({
      eyebrow: "Probabilità dichiarate // Prima della spesa",
      title: `${count} evocazion${count === 1 ? "e" : "i"} ${high ? "high-grade" : "normal"}`,
      body: `<p>Verranno consumati <strong>${C.formatNumber(total)} ${high ? "Gemme" : "Oro"}</strong>. Questa è valuta esclusivamente simulata: non esistono acquisti con denaro reale.</p>
        <div class="info-box"><strong>Probabilità:</strong> ${rates}<br /><strong>Generazione:</strong> ogni risultato usa un HeroSeed nuovo; nessun clone perfetto.</div>
        ${high ? `<p>Pity attuale: ${state.pity.highGrade}/100. Soft pity dal pull 70; 5★ garantita al pull 100.</p>` : ""}`,
      actions: [
        { label: "Annulla", className: "secondary-button", action: "close-modal" },
        { label: `Conferma · ${C.formatNumber(total)}`, className: "primary-button", action: "summon-execute", data: { pool, count } },
      ],
    });
  }

  function deploymentConfirm(floor) {
    const readiness = C.teamReadiness(state);
    const stage = C.getStage(state, floor)?.descriptor;
    if (!stage) return;
    showModal({
      eyebrow: `Deployment // Floor ${String(floor).padStart(2, "0")}`,
      title: "Bloccare party e loadout?",
      body: `<p><strong>${safe(stage.name)}</strong> · ${safe(stage.objective)}. Il Master potrà usare solo ordini macro con cooldown; l'IA gestirà ogni decisione individuale.</p>
        <div class="result-hero-list">${readiness.living.map((hero, index) => `<div class="result-hero"><span>${safe(C.PARTY_POSITIONS[index])} · ${safe(hero.name)}</span><strong>${safe(hero.role)}</strong><span>Fatigue ${hero.fatigue}</span></div>`).join("")}</div>
        <div class="warning-box" style="margin-top:16px"><strong>PERMADEATH ATTIVO:</strong> 0 HP registra immediatamente un tombstone. Chiudere o ricaricare la pagina non annulla una morte già avvenuta.</div>`,
      actions: [
        { label: "Torna alla preparazione", className: "secondary-button", action: "close-modal" },
        { label: "Entra nel Rift", className: "danger-button", action: "deploy-confirmed", data: { floor } },
      ],
    });
  }

  function startMission(floor) {
    closeModal();
    const started = C.beginMission(state, floor);
    if (!started.ok) {
      toast("Deployment bloccato", started.message, "danger", "!");
      return;
    }
    save();
    UI.combatLog = [];
    UI.combatCooldowns = {};
    missionLayer.hidden = false;
    document.getElementById("missionStream").textContent = started.stage.stream;
    document.getElementById("missionTitle").textContent = `PIANO ${String(floor).padStart(2, "0")} // ${started.stage.type.toUpperCase()}`;
    document.getElementById("missionObjective").textContent = started.stage.objective;
    document.getElementById("missionProgress").textContent = "Stabilizzazione del Rift...";
    document.getElementById("missionClock").textContent = "00:00";
    document.getElementById("combatLog").innerHTML = "";
    resetMacroButtons();
    const heroes = started.readiness.living;
    UI.combat = new window.RiftwardCombat.CombatSimulation({
      canvas: battleCanvas,
      stage: started.stage,
      heroes,
      worldSeed: state.world.seed,
      attempt: started.run.attempt,
      onLog: combatLog,
      onUpdate: updateCombatHud,
      onHeroDeath: (heroId, cause) => {
        C.recordHeroDeath(state, heroId, cause);
        save();
      },
      onComplete: completeMission,
    });
    UI.combat.start();
    UI.cooldownTimer = setInterval(updateCooldownButtons, 200);
  }

  function combatLog(message, tone) {
    UI.combatLog.unshift({ message, tone, timestamp: Date.now() });
    UI.combatLog = UI.combatLog.slice(0, 8);
    document.getElementById("combatLog").innerHTML = UI.combatLog.map((line) => `<div class="log-line ${safe(line.tone)}"><span style="color:var(--faint)">${formatDuration(UI.combat?.elapsed || 0)}</span> · ${safe(line.message)}</div>`).join("");
  }

  function updateCombatHud(snapshot) {
    document.getElementById("missionClock").textContent = formatDuration(snapshot.elapsed);
    document.getElementById("missionProgress").textContent = snapshot.progress;
    const threatLabel = document.getElementById("threatLabel");
    threatLabel.textContent = `THREAT // ${snapshot.threat >= 8 ? "CRITICAL" : snapshot.threat >= 4 ? "HIGH" : snapshot.threat ? "NOMINAL" : "CLEAR"}`;
    document.getElementById("missionParty").innerHTML = snapshot.heroes.map((hero) => {
      const hp = Math.max(0, Math.round((hero.hp / hero.maxHp) * 100));
      const resource = hero.maxAmmo ? `${hero.ammo}/${hero.maxAmmo} ammo` : hero.lastAction;
      return `<article class="combat-hero ${hero.alive ? "" : "dead"}" style="--hue:${hero.hue}"><span class="combat-avatar">${safe(hero.name.slice(0, 2).toUpperCase())}</span><span><strong>${safe(hero.name)}</strong><small>${safe(resource)}</small></span><span class="combat-status">${safe(hero.alive ? hero.status : "DEAD")}</span><div class="combat-hp"><span style="--hp:${hp}%"></span></div></article>`;
    }).join("");
  }

  function resetMacroButtons() {
    document.querySelectorAll("#macroCommands button").forEach((button) => {
      button.disabled = false;
      button.classList.remove("cooling", "active");
      button.removeAttribute("data-remaining");
      if (button.dataset.command === "posture") button.querySelector("strong").textContent = "AVANZA";
    });
  }

  function useMacro(button) {
    const command = button.dataset.command;
    if (!UI.combat || button.disabled) return;
    const result = UI.combat.command(command);
    if (!result.ok) return;
    if (command === "posture") {
      button.querySelector("strong").textContent = result.label;
      button.classList.add("active");
    } else if (command === "focus" || command === "protect") {
      button.classList.toggle("active", result.active);
    } else {
      button.classList.add("active");
    }
    const duration = Number(button.dataset.cooldown);
    UI.combatCooldowns[command] = performance.now() + duration * 1000;
    button.disabled = true;
    button.classList.add("cooling");
    if (command === "extract") button.dataset.cooldown = "999";
    updateCooldownButtons();
  }

  function updateCooldownButtons() {
    const now = performance.now();
    document.querySelectorAll("#macroCommands button").forEach((button) => {
      const command = button.dataset.command;
      const end = UI.combatCooldowns[command];
      if (!end) return;
      const remaining = Math.max(0, Math.ceil((end - now) / 1000));
      button.dataset.remaining = remaining;
      if (remaining <= 0 && command !== "extract") {
        button.disabled = false;
        button.classList.remove("cooling");
        button.removeAttribute("data-remaining");
        delete UI.combatCooldowns[command];
        if (command === "allout") button.classList.remove("active");
      }
    });
  }

  function completeMission(combatResult) {
    clearInterval(UI.cooldownTimer);
    UI.cooldownTimer = null;
    const outcome = C.finalizeMission(state, combatResult);
    save();
    const stage = C.getStage(state, state.activeMission?.floor || UI.selectedFloor)?.descriptor || C.STAGE_BLUEPRINTS[UI.selectedFloor];
    const heroRows = combatResult.heroResults.map((entry) => {
      const hero = state.heroes.find((candidate) => candidate.id === entry.id);
      return `<div class="result-hero ${entry.alive ? "" : "dead"}"><span>${safe(hero?.name || entry.id)}</span><strong>${entry.alive ? `${entry.kills} kill` : "CADUTO"}</strong><span>${entry.alive ? `${Math.round(entry.hpRatio * 100)}% HP` : "PERMANENTE"}</span></div>`;
    }).join("");
    const rewardText = combatResult.victory ? `${C.formatNumber(outcome.reward.gold)} Oro · ${outcome.reward.xp} XP per superstite` : "Nessun avanzamento · XP minima ai superstiti";
    showModal({
      eyebrow: `Mission result // ${formatDuration(combatResult.duration)}`,
      title: combatResult.victory ? "Missione completata" : combatResult.reason === "extracted" ? "Estrazione riuscita" : "Missione fallita",
      body: `<p>${combatResult.victory ? "L'obiettivo è stato raggiunto. Il Nexus sta risolvendo ricompense, XP, fatigue e relazioni." : "Il piano resta identico per il prossimo tentativo. Ferite, fatigue e morti già registrate persistono."}</p>
        <div class="result-hero-list">${heroRows}</div>
        <div class="${outcome.deadIds.length ? "warning-box" : "info-box"}" style="margin-top:16px"><strong>${rewardText}</strong>${outcome.deadIds.length ? `<br />${outcome.deadIds.length} eroe/i trasferiti nel Memoriale. Non esiste resurrezione.` : ""}</div>`,
      actions: [{ label: "Torna al Nexus", className: "primary-button", action: "leave-mission" }],
    });
  }

  function leaveMission() {
    closeModal();
    UI.combat?.stop();
    UI.combat = null;
    missionLayer.hidden = true;
    UI.view = "hub";
    render();
  }

  function chooseEquipment(heroId, slot) {
    const hero = state.heroes.find((candidate) => candidate.id === heroId);
    const items = state.inventory.filter((item) => item.slot === slot);
    showModal({
      eyebrow: `Armory // ${safe(slot)}`,
      title: `Equipaggia ${hero?.name || "eroe"}`,
      body: items.length ? `<div class="result-hero-list">${items.map((item) => `<div class="result-hero"><span>${safe(item.name)} [${safe(item.grade)}]</span><strong>Q ${Math.round(item.quality * 100)}%</strong><button class="text-button" data-action="equip-item" data-hero-id="${heroId}" data-item-id="${item.id}">Equipaggia</button></div>`).join("")}</div>` : `<div class="empty-state"><div><span>▤</span>Nessun oggetto compatibile nel Warehouse.<br />Commissionane uno dalla Base.</div></div>`,
      actions: [{ label: "Chiudi", className: "secondary-button", action: "close-modal" }],
    });
  }

  function craftingModal() {
    showModal({
      eyebrow: "Armory commission // Raw → process → item",
      title: "Commissiona equipaggiamento",
      body: `<p>La Smithy migliora le chance di grado. Prima del Floor 5, l'Armory può affidare il lavoro a un artigiano esterno con sovrapprezzo.</p>
        <div class="info-box">Costo base attuale: <strong>${state.facilities.smithy.unlocked ? "4.500" : "6.500"} Oro + 2 Minerale + 1 Pelle</strong>.</div>
        <div class="onboarding-steps">
          ${[["main", "⚔", "Main weapon"], ["sub", "◇", "Off-hand"], ["armor", "⬒", "Armor"]].map(([slot, glyph, label]) => `<button class="onboarding-step" data-action="craft-item" data-slot="${slot}" style="color:inherit;text-align:left;border:0;cursor:pointer"><span>${glyph}</span><strong>${label}</strong><p>Risultato individuale D—B, nessuna distruzione su fallimento.</p></button>`).join("")}
        </div>`,
      actions: [{ label: "Annulla", className: "secondary-button", action: "close-modal" }],
    });
  }

  function useFacility(key) {
    if (key === "summoning") return navigateAfterClose("summon");
    if (key === "training") return navigateAfterClose("heroes");
    if (key === "armory" || key === "smithy") return craftingModal();
    if (key === "warehouse") {
      toast("Warehouse", `${state.inventory.length} oggetti e materiali registrati.`, "", "▤");
      return;
    }
    if (key === "lodging") {
      const result = C.restRoster(state);
      if (result.ok) { save(); render(); toast("Riposo completato", `${result.recovered} Fatigue recuperata.`, "", "⌂"); }
      else toast("Riposo non disponibile", result.message, "warn", "!");
      return;
    }
    if (["research", "workshop", "infirmary", "synthesis", "magic", "dimensionGate"].includes(key)) {
      toast("Struttura pronta", "Il layer completo di questa facility è previsto oltre il vertical slice giocabile.", "warn", FACILITIES[key][2]);
    }
  }

  function navigateAfterClose(view) {
    closeModal();
    navigate(view);
  }

  function upgradeFacility(key) {
    const facility = state.facilities[key];
    if (!facility?.unlocked || facility.level >= 5) return;
    const cost = 12000 * Math.max(1, facility.level) ** 2;
    if (state.world.gold < cost) return toast("Upgrade bloccato", `Servono ${C.formatNumber(cost)} Oro.`, "warn", "!");
    state.world.gold -= cost;
    facility.level += 1;
    C.addLedger(state, "gold", -cost, `Upgrade ${FACILITIES[key][0]} al Lv.${facility.level}`, "facility");
    C.addEvent(state, "BASE", `${FACILITIES[key][0]} potenziata`, `La struttura raggiunge il livello ${facility.level}.`, "good");
    save();
    render();
    toast("Facility potenziata", `${FACILITIES[key][0]} è ora Lv.${facility.level}.`, "", "▦");
  }

  function bindDragAndDrop() {
    main.querySelectorAll(".roster-drag").forEach((card) => {
      card.addEventListener("dragstart", (event) => {
        event.dataTransfer.setData("text/plain", card.dataset.heroId);
        event.dataTransfer.effectAllowed = "move";
      });
    });
    main.querySelectorAll(".formation-slot").forEach((slot) => {
      slot.addEventListener("dragover", (event) => { event.preventDefault(); slot.classList.add("drag-over"); });
      slot.addEventListener("dragleave", () => slot.classList.remove("drag-over"));
      slot.addEventListener("drop", (event) => {
        event.preventDefault();
        slot.classList.remove("drag-over");
        const heroId = event.dataTransfer.getData("text/plain");
        const result = C.assignPartySlot(state, Number(slot.dataset.slot), heroId);
        if (result.ok) { save(); renderSquad(); }
      });
    });
  }

  function quickAssign(heroId) {
    const firstEmpty = state.party.findIndex((id) => !id);
    if (firstEmpty < 0) return toast("Party completo", "Rimuovi un eroe o trascinalo sopra uno slot esistente.", "warn", "!");
    C.assignPartySlot(state, firstEmpty, heroId);
    save();
    renderSquad();
  }

  function settingsModal() {
    showModal({
      eyebrow: "Local world // Save controls",
      title: "Impostazioni e salvataggio",
      body: `<div class="memory-list">
        <div class="memory-row"><span class="list-glyph">↓</span><span>Esporta un backup JSON del world corrente.</span><button class="text-button" data-action="export-save">Esporta</button></div>
        <div class="memory-row"><span class="list-glyph">↑</span><span>Importa un backup locale compatibile.</span><button class="text-button" data-action="import-save">Importa</button></div>
        <div class="memory-row"><span class="list-glyph">?</span><span>Mostra di nuovo l'onboarding.</span><button class="text-button" data-action="show-tutorial">Mostra</button></div>
        <div class="memory-row"><span class="list-glyph">×</span><span>Cancella il world locale e genera un nuovo seed.</span><button class="text-button" style="color:var(--red)" data-action="reset-confirm">Reset</button></div>
      </div>
      <input type="file" id="importFile" accept="application/json,.json" hidden />
      <div class="info-box" style="margin-top:16px">Il salvataggio è locale al browser. Non vengono inviati dati o richieste di rete.</div>`,
      actions: [{ label: "Chiudi", className: "secondary-button", action: "close-modal" }],
    });
  }

  function exportSave() {
    const blob = new Blob([C.exportState(state)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `riftward-${state.world.id.toLowerCase()}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
    toast("Backup esportato", "Il file JSON contiene l'intero world, inclusi tombstone e ledger.", "", "↓");
  }

  function importSaveFile(file) {
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const imported = C.migrateState(JSON.parse(reader.result));
        if (!imported) throw new Error("Formato non compatibile");
        state = imported;
        save();
        closeModal();
        navigate("hub");
        toast("Backup importato", `World ${state.world.id} caricato.`, "", "↑");
      } catch (error) {
        toast("Importazione fallita", error.message, "danger", "!");
      }
    };
    reader.readAsText(file);
  }

  function resetConfirm() {
    showModal({
      eyebrow: "Destructive action // Local world",
      title: "Cancellare questo world?",
      body: `<p>Roster, base, progressione, eventi e Memoriale verranno rimossi dal browser. I backup esportati non saranno modificati.</p><div class="warning-box">Questa azione non può essere annullata senza un backup JSON.</div>`,
      actions: [{ label: "Annulla", className: "secondary-button", action: "close-modal" }, { label: "Cancella e ricomincia", className: "danger-button", action: "reset-world" }],
    });
  }

  document.addEventListener("click", (event) => {
    const target = event.target.closest("button, [data-action]");
    if (!target) return;
    if (target.dataset.view) {
      navigate(target.dataset.view);
      return;
    }
    const action = target.dataset.action;
    if (!action) return;
    if (action === "close-modal") closeModal();
    else if (action === "finish-onboarding") { state.settings.tutorialSeen = true; save(); closeModal(); toast("Comando accettato", "Il Piano 1 attende il tuo party.", "", "△"); }
    else if (action === "hero-filter") { UI.heroFilter = target.dataset.filter; renderHeroes(); }
    else if (action === "select-hero") { UI.selectedHeroId = target.dataset.heroId; UI.view = "hero"; closeModal(); render(); }
    else if (action === "select-floor") { UI.selectedFloor = Number(target.dataset.floor); renderTower(); }
    else if (action === "open-stage") { UI.selectedFloor = Number(target.dataset.floor); UI.view = "tower"; render(); }
    else if (action === "deploy") deploymentConfirm(Number(target.dataset.floor));
    else if (action === "deploy-confirmed") startMission(Number(target.dataset.floor));
    else if (action === "leave-mission") leaveMission();
    else if (action === "summon-confirm") summonConfirm(target.dataset.pool, Number(target.dataset.count));
    else if (action === "summon-execute") {
      const result = C.summon(state, target.dataset.pool, Number(target.dataset.count));
      if (!result.ok) return toast("Evocazione bloccata", result.message, "danger", "!");
      UI.lastSummon = result.heroes;
      save(); closeModal(); renderSummon();
      toast("Risonanza completata", `${result.heroes.length} HeroSeed unici aggiunti al roster.`, "", "✦");
    }
    else if (action === "remove-slot") { C.removePartySlot(state, Number(target.dataset.slot)); save(); renderSquad(); }
    else if (action === "quick-assign-hero") quickAssign(target.dataset.heroId);
    else if (action === "auto-form") { C.autoFormParty(state); save(); renderSquad(); toast("Formazione aggiornata", "Il Nexus ha privilegiato copertura ruoli e potenza.", "", "⋈"); }
    else if (action === "auto-equip") { const result = C.autoEquip(state); save(); renderSquad(); toast("Auto equip", `${result.equipped} upgrade assegnati.`, "", "⚔"); }
    else if (action === "toggle-party-hero") {
      const heroId = target.dataset.heroId;
      const slot = state.party.indexOf(heroId);
      if (slot >= 0) C.removePartySlot(state, slot); else {
        const empty = state.party.findIndex((id) => !id);
        if (empty < 0) return toast("Party completo", "Libera uno slot nella schermata Squadra.", "warn", "!");
        C.assignPartySlot(state, empty, heroId);
      }
      save(); renderHeroDetail(heroId);
    }
    else if (action === "train-hero") {
      const result = C.trainHero(state, target.dataset.heroId);
      if (!result.ok) return toast("Training bloccato", result.message, "warn", "!");
      save(); renderHeroDetail(target.dataset.heroId); toast("Training completato", `${result.amount} XP assegnati.`, "", "†");
    }
    else if (action === "promote-hero") {
      const result = C.promoteHero(state, target.dataset.heroId);
      if (!result.ok) return toast("Promozione bloccata", result.message, "warn", "!");
      save(); renderHeroDetail(target.dataset.heroId); toast("Promozione", `${result.hero.name} è ora ${C.stars(result.hero.currentRarity)}.`, "", "★");
    }
    else if (action === "choose-equipment") chooseEquipment(target.dataset.heroId, target.dataset.slot);
    else if (action === "equip-item") {
      const result = C.equipItem(state, target.dataset.heroId, target.dataset.itemId);
      if (!result.ok) return toast("Equip bloccato", result.message, "warn", "!");
      save(); closeModal(); renderHeroDetail(target.dataset.heroId); toast("Loadout aggiornato", result.item.name, "", "⚔");
    }
    else if (action === "rest-roster") {
      const result = C.restRoster(state);
      if (!result.ok) return toast("Riposo bloccato", result.message, "warn", "!");
      save(); render(); toast("Roster riposato", `${result.recovered} Fatigue recuperata.`, "", "⌂");
    }
    else if (action === "craft-open") craftingModal();
    else if (action === "craft-item") {
      const result = C.createCraftedItem(state, target.dataset.slot);
      if (!result.ok) return toast("Forgiatura bloccata", result.message, "warn", "!");
      save(); closeModal(); renderBase(); toast("Oggetto creato", `${result.item.name} [${result.item.grade}]`, "", "⚒");
    }
    else if (action === "use-facility") useFacility(target.dataset.facility);
    else if (action === "upgrade-facility") upgradeFacility(target.dataset.facility);
    else if (action === "archive-tab") { UI.archiveTab = target.dataset.tab; renderArchive(); }
    else if (action === "mark-read") { state.events.forEach((item) => { item.read = true; }); save(); renderArchive(); }
    else if (action === "export-save") exportSave();
    else if (action === "import-save") document.getElementById("importFile")?.click();
    else if (action === "show-tutorial") { closeModal(); showOnboarding(); }
    else if (action === "reset-confirm") resetConfirm();
    else if (action === "reset-world") { localStorage.removeItem(C.SAVE_KEY); state = C.createInitialState(); save(); closeModal(); UI.view = "hub"; render(); showOnboarding(); }
  });

  document.addEventListener("change", (event) => {
    if (event.target.id === "importFile" && event.target.files[0]) importSaveFile(event.target.files[0]);
  });

  document.getElementById("macroCommands").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-command]");
    if (button) useMacro(button);
  });

  document.getElementById("settingsButton").addEventListener("click", settingsModal);

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !modalRoot.hidden && !UI.combat) closeModal();
    if (UI.combat) {
      const map = { "1": "posture", "2": "focus", "3": "protect", "4": "allout", x: "extract", X: "extract" };
      const command = map[event.key];
      if (command) {
        event.preventDefault();
        const button = document.querySelector(`#macroCommands button[data-command="${command}"]`);
        if (button) useMacro(button);
      }
    }
    if ((event.key === "Enter" || event.key === " ") && event.target.classList.contains("hero-card")) {
      event.preventDefault();
      UI.selectedHeroId = event.target.dataset.heroId;
      UI.view = "hero";
      render();
    }
  });

  window.addEventListener("beforeunload", save);
  render();
  save();
  if (!state.settings.tutorialSeen) setTimeout(showOnboarding, 240);
})();
