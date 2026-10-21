const CONFIG = {
  ticksPerDay: 24,
  gameDays: 30,
  cycleTicks: 12,
  runs: 5000,
  seed: 1,
  rankCap: 20,
  maxLevel: 3,
  baseCost: 1000,
  rankCostStep: 0.1,
  affinity: 1.5,
};

const SCHOOLS = {
  battleschool: ['valor', 'tactics', 'siegecraft'],
  university: ['muster', 'steward', 'scholar'],
  rangers: ['pace', 'scout', 'plunder'],
};

const ABILITIES = Object.values(SCHOOLS).flat();

const PROFILES = {
  frontline: { battleProb: 0.25, winProb: 0.75, fieldFrac: 0.4, valorXp: 300, tacticsXp: 200, siegeProb: 0.1, siegeXp: 150, garrisonXp: 0, marchXp: 80, scoutXp: 60, captureProb: 0.05, plunderXp: 400 },
  garrison: { battleProb: 0.04, winProb: 0.8, fieldFrac: 0, valorXp: 300, tacticsXp: 0, siegeProb: 0.05, siegeXp: 150, garrisonXp: 60, marchXp: 0, scoutXp: 20, captureProb: 0, plunderXp: 0 },
  raider: { battleProb: 0.12, winProb: 0.7, fieldFrac: 0.6, valorXp: 250, tacticsXp: 200, siegeProb: 0, siegeXp: 0, garrisonXp: 0, marchXp: 100, scoutXp: 100, captureProb: 0.08, plunderXp: 400 },
};

const cycles = Math.round((CONFIG.gameDays * CONFIG.ticksPerDay) / CONFIG.cycleTicks);

function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function levelCost(nextLevel, rank) {
  return CONFIG.baseCost * nextLevel * (1 + CONFIG.rankCostStep * rank);
}

function simulate(profile, school, rng) {
  const levels = {};
  const xp = {};
  ABILITIES.forEach((a) => {
    levels[a] = 0;
    xp[a] = 0;
  });
  levels[SCHOOLS[school][Math.floor(rng() * 3)]] = 1;
  let rank = 1;

  const earn = (ability, amount) => {
    if (amount <= 0) return;
    xp[ability] += SCHOOLS[school].includes(ability) ? amount * CONFIG.affinity : amount;
    while (rank < CONFIG.rankCap && levels[ability] < CONFIG.maxLevel && xp[ability] >= levelCost(levels[ability] + 1, rank)) {
      xp[ability] -= levelCost(levels[ability] + 1, rank);
      levels[ability] += 1;
      rank += 1;
    }
  };

  let alive = true;
  for (let c = 0; c < cycles && alive; c++) {
    if (rng() < profile.battleProb) {
      if (rng() < profile.winProb) {
        earn('valor', profile.valorXp);
        if (rng() < profile.fieldFrac) earn('tactics', profile.tacticsXp);
      } else {
        alive = false;
      }
    }
    if (rng() < profile.siegeProb) earn('siegecraft', profile.siegeXp);
    earn('muster', profile.garrisonXp);
    earn('steward', profile.garrisonXp);
    earn('scholar', profile.garrisonXp);
    earn('pace', profile.marchXp);
    earn('scout', profile.scoutXp);
    if (rng() < profile.captureProb) earn('plunder', profile.plunderXp);
  }

  const sum = (list) => list.reduce((s, a) => s + levels[a], 0);
  return {
    rank,
    alive,
    battle: sum(SCHOOLS.battleschool),
    garrison: sum(SCHOOLS.university),
    campaign: sum(SCHOOLS.rangers),
  };
}

function percentile(sorted, p) {
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
}

const rng = mulberry32(CONFIG.seed);
const rows = [];

for (const [profileName, profile] of Object.entries(PROFILES)) {
  for (const school of Object.keys(SCHOOLS)) {
    const results = Array.from({ length: CONFIG.runs }, () => simulate(profile, school, rng));
    const ranks = results.map((r) => r.rank).sort((a, b) => a - b);
    const mean = (key) => (results.reduce((s, r) => s + r[key], 0) / results.length).toFixed(1);
    const pct = (n) => ((ranks.filter((r) => r >= n).length / ranks.length) * 100).toFixed(1) + '%';
    rows.push({
      profile: profileName,
      school,
      survive: ((results.filter((r) => r.alive).length / results.length) * 100).toFixed(0) + '%',
      meanRank: mean('rank'),
      p50: percentile(ranks, 0.5),
      p95: percentile(ranks, 0.95),
      max: ranks[ranks.length - 1],
      'rank>=5': pct(5),
      'rank>=10': pct(10),
      'rank>=15': pct(15),
      'rank>=20': pct(20),
      battle: mean('battle'),
      garrison: mean('garrison'),
      campaign: mean('campaign'),
    });
  }
}

console.log(`${CONFIG.gameDays} days, ${cycles} cycles, ${CONFIG.runs} runs per row, affinity x${CONFIG.affinity}`);
console.table(rows);
