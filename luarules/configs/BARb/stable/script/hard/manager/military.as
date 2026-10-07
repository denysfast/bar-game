#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/base.as"
#include "../misc/aicmdr.as"


/*
 * Custom (denysfast/bar-game) military rules — see custom-ai.md in the repo:
 *  - ground raiders join the main army instead of roaming in small raid squads (no early harass);
 *  - the army threshold (quota.attack) grows with game time so attacks come as big waves;
 *  - anti-nuke coverage scales with the number of enemy nukes the team has seen (gadget
 *    game_ai_resource_bonus.lua publishes "ai_known_enemy_nukes"), shields come late game;
 *  - periodic mass air scouting.
 */
namespace Military {

// army size schedule: power = ATTACK_BASE + ATTACK_PER_MIN * minutes, capped.
// Rough scale: a T1 tank ~ 9 power, a T3 super ~ 250; power ~ 0.04 x metal cost of the army.
const float ATTACK_BASE    = 100.f;
const float ATTACK_PER_MIN = 35.f;
const float ATTACK_CAP     = 3000.f;  // v8: was 1200; 5000 kept split armies at home
// v8: the wave size also follows the economy, so a rich AI gathers a proportionally big army
const float ATTACK_PER_INCOME = 1.6f;  // power per m-income
const int   WAVE_FALLBACK_SINCE = 14 * MINUTE;  // no "launch what you have" before this
// if no wave went out for WAVE_MAX_GAP, lower the threshold to what the army already has
// (measured: a mixed T1-T3 army launches at ~0.013 power per metal); after 1.5x the gap, launch anything
const int   WAVE_MAX_GAP     = 8 * MINUTE;  // v8: was 6
const float POWER_PER_METAL  = 0.012f;

// anti-nuke: base coverage + per known enemy nuke launcher.
// Gated on economy: static defence of this size competes with expansion, so it only goes up
// once the team actually earns enough (and never while energy is stalling).
const int   ANTINUKE_BASE     = 2;
const int   ANTINUKE_PER_NUKE = 2;
const int   ANTINUKE_MAX      = 8;
const float ANTINUKE_MIN_INCOME = 35.f;  // m-income before the first (unprovoked) anti-nuke
const float ANTINUKE_SEEN_INCOME = 20.f; // once enemy nukes are seen, react at a lower income

// shields: late game only, and only on top of a real economy
const int   SHIELD_SINCE_MIN  = 25;
const int   SHIELD_STEP_MIN   = 8;
// v9: shields were ordered once per base (= per factory, up to 24 at a time, cap 12);
// now one per round, total cap 1 + income / SHIELD_INCOME_PER, at most SHIELD_MAX
const float SHIELD_INCOME_PER = 500.f;
const int   SHIELD_MAX        = 4;
const float SHIELD_MIN_INCOME = 70.f;
// above this m-income static projects are cheap relative to income: queue them at NORMAL, not LOW
const float RICH_INCOME = 150.f;

// economy expansion: the AI must keep scaling energy, converters and storage all game,
// not stop at the opening base. Checked every ECO_STEP.
const int   ECO_STEP            = 40 * SECOND;
const float ECO_CONVERT_E_RATIO = 12.f;  // e-income per m-income above which metal makers pay off
const float ECO_ENERGY_MARGIN   = 0.85f; // build more energy while income < margin x target
const int   ECO_CONVERT_BASE    = 2;     // converter cap: base + per minute
const float ECO_CONVERT_PER_MIN = 1.0f;
const int   ECO_CONVERT_MAX     = 60;
// v23 energy ladder: v8-v22 queued an advanced fusion (9.7k metal) at EVERY base (= factory) every 40 s from
// the first T2 constructor on - the AI started generators it could not pay for and built them for ages. Now
// the best rung the income pays for: adv solar -> fusion -> adv fusion (after ECO_AFUS_AFTER fusions) -> epic
// fusion (Scavengers Units Pack, after ECO_EPIC_AFTER adv fusions and from ECO_EPIC_INCOME m/s). A locked rung
// gets maxThisUnit = its count, so CircuitAI's own energy picks (economy.json) keep to the ladder too (its
// e-income gates alone do not: the AI bonus inflates energy, 5000 E at minute 5 with no fusion at all). A rung
// is ordered only when its metal cost is <= ECO_AFFORD_SEC of metal income, out of a budget of ECO_SHARE of it
const float ECO_AFFORD_SEC      = 75.f;
const float ECO_SHARE           = 0.25f;
const float ECO_FUS_E           = 500.f;
const int   ECO_AFUS_AFTER      = 4;
const int   ECO_EPIC_AFTER      = 8;
const float ECO_EPIC_INCOME     = 1200.f;
const int   ECO_EPIC_CONVERTERS = 4;     // epic converters (6000 E each) per epic fusion (30000 E)

// production expansion: CircuitAI adds factories far slower than income grows (measured: one T1
// factory at 12 min with 300 m/s income), so metal ends up in towers instead of an army.
// Target one factory per PROD_METAL_PER_FACTORY of income; nano turrets when metal floats.
const int   PROD_STEP              = 30 * SECOND;
const float PROD_METAL_PER_FACTORY = 25.f;
const int   PROD_MAX_FACTORIES     = 24;
// nano turrets assisting factories: 2 + income / PROD_METAL_PER_NANO (a T1 nano is 200 bp, ~10 m/s of army)
const float PROD_METAL_PER_NANO    = 8.f;
const int   PROD_NANO_MAX          = 90;

// air scouting pulse: every SCOUT_PERIOD minutes recruit SCOUT_BURST air scouts and widen the scout quota
const int  SCOUT_PERIOD_MIN = 6;
const uint SCOUT_QUOTA_IDLE = 2;
const uint SCOUT_QUOTA_MASS = 8;
const uint SCOUT_BURST      = 4;

// Raiders: false = default RAID squads sized by quota.raid (min 40 power ~ 20 Flashes, no lone harassers);
// true = raiders gather with the army. Measured: only raid squads reliably hunt a lone/passive enemy
// commander � ATTACK groups go for bases (targets with influence), so keep raids on.
const bool RAIDERS_JOIN_ARMY = false;

int lastAntiNukeFrame = 0;
int lastWaveFrame = 0;
int lastShieldFrame = 0;
int lastScoutPulseFrame = 0;
int lastEcoFrame = 0;
float ecoBudget = 0.f;  // v23: metal set aside for generators (not saved: starts again at 0 after a load)
uint ecoBaseIdx = 0;
int scavUnits = -1;     // modoption scavunitsforplayers (epic fusion / epic converters), read on first use
int afusMax = -1;       // the unlocked maxThisUnit of the adv fusion / epic fusion (read before the first lock)
int epicMax = -1;
int lastProdFrame = 0;
int lastAltarFrame = -10 * MINUTE;
int altarTries = -1;

// v19 heroes: the hero altar (T4 foundry) is ordered on its own once the economy is late-T2 / T3 - before, it
// came only as one of the many factory picks of UpdateProduction (behind a T3 gantry and 700 m/s income) and
// landed after minute 25, when one side was usually gone already.
const int   ALTAR_SINCE    = 10 * MINUTE;  // never before this
const float ALTAR_INCOME   = 250.f;        // m-income (AI bonus included) for the altar ...
const float ALTAR_INCOME_LATE = 120.f;     // ... or this from ALTAR_LATE on
const int   ALTAR_LATE     = 16 * MINUTE;
const int   ALTAR_STEP     = 90 * SECOND;  // re-order (a cancelled / destroyed frame) at most this often
int attackTasks = 0;  // ATTACK tasks added since the last status line (diagnostics)
int shieldsOrdered = 0;
int knownNukesHandled = -1;

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	const CCircuitDef@ cdef = unit.circuitDef;
	if (RAIDERS_JOIN_ARMY && cdef.GetMainRole() == Unit::Role::RAIDER.type
		&& !cdef.IsRoleAny(Unit::Role::AIR.mask | Unit::Role::SCOUT.mask | Unit::Role::SUB.mask))
	{
		// gather at base with everyone else; promoted to ATTACK when the group reaches quota.attack
		return aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK, aiMilitaryMgr.quota.attack));
	}
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
	IFighterTask@ ft = cast<IFighterTask>(task);
	if (ft !is null && ft.GetFightType() == Task::FightType::ATTACK) {
		++attackTasks;
		if (ai.frame - lastWaveFrame > MINUTE)  // groups promoting together within a minute are one wave
			AiLog("[custom] ATTACK wave launched at " + int(ai.frame / MINUTE) + "min, quota.attack=" + int(aiMilitaryMgr.quota.attack) + " armyCost=" + int(aiMilitaryMgr.armyCost));
		lastWaveFrame = ai.frame;
	}
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{

}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
}

void AiLoad(IStream& istream)
{
	istream >> lastAntiNukeFrame >> lastShieldFrame >> lastScoutPulseFrame >> shieldsOrdered >> knownNukesHandled >> lastWaveFrame >> lastEcoFrame >> lastProdFrame;
}

void AiSave(OStream& ostream)
{
	ostream << lastAntiNukeFrame << lastShieldFrame << lastScoutPulseFrame << shieldsOrdered << knownNukesHandled << lastWaveFrame << lastEcoFrame << lastProdFrame;
}

void AiMakeDefence(int cluster, const AIFloat3& in pos)
{
	// towers early and everywhere: no waiting for income / threat
	aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
}

/*
 * anti-air threat threshold;
 * air factories will stop production when AA threat exceeds
 */
// FIXME: Remove/replace, deprecated.
bool AiIsAirValid()
{
	return aiEnemyMgr.GetEnemyThreat(Unit::Role::AA.type) <= 80.f;
}

/* --- custom, called from Main::AiUpdate --- */

CCircuitDef@ SideDef(const string& in arm, const string& in cor, const string& in leg)
{
	const string side = ai.GetSideName();
	CCircuitDef@ cdef = null;
	if (side == "armada") @cdef = ai.GetCircuitDef(arm);
	else if (side == "cortex") @cdef = ai.GetCircuitDef(cor);
	else @cdef = ai.GetCircuitDef(leg);
	return cdef;
}

void EnqueueAtBasesAs(Task::BuildType type, CCircuitDef@ cdef, int perBase, Task::Priority prio, float shake)
{
	if (cdef is null || Base::positions.length() == 0)
		return;
	for (uint i = 0; i < Base::positions.length(); ++i) {
		for (int j = 0; j < perBase; ++j) {
			aiBuilderMgr.Enqueue(TaskB::Common(type, prio, cdef, Base::positions[i], shake));
		}
	}
}

void EnqueueAtBases(CCircuitDef@ cdef, int perBase, Task::Priority prio, float shake)
{
	EnqueueAtBasesAs(Task::BuildType::DEFENCE, cdef, perBase, prio, shake);
}

void UpdateArmySize()
{
	const float minutes = float(ai.frame) / float(MINUTE);
	float attack = AiMax(ATTACK_BASE + ATTACK_PER_MIN * minutes, ATTACK_PER_INCOME * aiEconomyMgr.metal.income);
	if (attack > ATTACK_CAP) attack = ATTACK_CAP;
	const int sinceWave = ai.frame - lastWaveFrame;
	if (sinceWave > WAVE_MAX_GAP && ai.frame > WAVE_FALLBACK_SINCE) {
		// army has been sitting at home too long: launch with whatever it has
		attack = AiMin(attack, AiMax(ATTACK_BASE, aiMilitaryMgr.armyCost * POWER_PER_METAL));
		if (sinceWave > WAVE_MAX_GAP * 3 / 2)
			attack = ATTACK_BASE;
	}
	attack = AiCmdr::AdjustAttack(attack);  // external commander: posture / forced waves
	aiMilitaryMgr.quota.attack = attack;
	// raid squads grow with time: ~10 Flashes at start, ~40 later (a Flash is ~2 power, a Stumpy ~9)
	float raidMin = 20.f + 2.f * minutes;
	if (raidMin > 80.f) raidMin = 80.f;
	aiMilitaryMgr.quota.raid.min = raidMin;
	aiMilitaryMgr.quota.raid.avg = raidMin * 3.f;
	if (ai.frame % (2 * MINUTE) < SECOND) {
		AiLog("[custom] t=" + int(minutes) + "min quota.attack=" + int(attack)
			+ " m-income=" + int(aiEconomyMgr.metal.income) + " e-income=" + int(aiEconomyMgr.energy.income)
			+ " armyCost=" + int(aiMilitaryMgr.armyCost) + " workers=" + aiBuilderMgr.GetWorkerCount()
			+ " factories=" + aiFactoryMgr.GetFactoryCount()
			+ " bonus=" + int(ai.GetTeamRulesParam("ai_bonus_pct", 0.f)) + "%"
			+ " attackTasks=" + attackTasks);
		attackTasks = 0;
	}
}

void UpdateAntiNukes()
{
	const int known = int(ai.GetTeamRulesParam("ai_known_enemy_nukes", 0.f));
	CCircuitDef@ anti = SideDef("armamd", "corfmd", "legabm");
	if (anti is null)
		return;
	int want = ANTINUKE_BASE + ANTINUKE_PER_NUKE * known;
	if (want > ANTINUKE_MAX) want = ANTINUKE_MAX;
	anti.maxThisUnit = want;
	const bool moreNukes = known > knownNukesHandled;
	const bool periodic = ai.frame - lastAntiNukeFrame > 5 * MINUTE;
	// economy gate: an anti-nuke costs a small base, so never trade expansion for it
	const float income = aiEconomyMgr.metal.income;
	const float needIncome = (known > 0) ? ANTINUKE_SEEN_INCOME : ANTINUKE_MIN_INCOME;
	if (income < needIncome || aiEconomyMgr.isEnergyStalling) {
		knownNukesHandled = known;  // don't let a missed window queue a burst later
		return;
	}
	if ((moreNukes || periodic) && ai.frame > 12 * MINUTE && anti.count < want) {
		// unprovoked coverage is background work; a seen enemy nuke is worth jumping the queue
		// v9: order only what is missing (was one per base = per factory), spread over the bases
		const Task::Priority prio = moreNukes ? Task::Priority::HIGH
			: (income >= RICH_INCOME ? Task::Priority::NORMAL : Task::Priority::LOW);
		const uint nb = Base::positions.length();
		for (int k = 0; k < want - anti.count && nb > 0; ++k)
			aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, prio, anti, Base::positions[(anti.count + k) % nb], SQUARE_SIZE * 24));
		lastAntiNukeFrame = ai.frame;
		knownNukesHandled = known;
		AiLog("[custom] anti-nuke: known enemy nukes=" + known + " want=" + want + " have=" + anti.count
			+ " m-income=" + int(income));
	}
}

void UpdateShields()
{
	if (ai.frame < SHIELD_SINCE_MIN * MINUTE)
		return;
	if (ai.frame - lastShieldFrame < SHIELD_STEP_MIN * MINUTE)
		return;
	CCircuitDef@ gate = SideDef("armgate", "corgate", "leggatet3");
	if (gate is null)
		return;
	// economy gate: shields are pure upkeep, they only make sense on a fat economy
	if (aiEconomyMgr.metal.income < SHIELD_MIN_INCOME || aiEconomyMgr.isEnergyStalling)
		return;
	int cap = 1 + int(aiEconomyMgr.metal.income / SHIELD_INCOME_PER);
	if (cap > SHIELD_MAX) cap = SHIELD_MAX;
	gate.maxThisUnit = cap;
	if (gate.count >= cap || Base::positions.length() == 0)
		return;
	const AIFloat3 pos = Base::positions[shieldsOrdered % Base::positions.length()];
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
		aiEconomyMgr.metal.income >= RICH_INCOME ? Task::Priority::NORMAL : Task::Priority::LOW, gate, pos, SQUARE_SIZE * 40));
	lastShieldFrame = ai.frame;
	++shieldsOrdered;
	AiLog("[custom] shields: ordered round " + shieldsOrdered + " (have " + gate.count
		+ ") m-income=" + int(aiEconomyMgr.metal.income));
}

void UpdateAirScouting()
{
	const int period = SCOUT_PERIOD_MIN * MINUTE;
	const int sincePulse = ai.frame - lastScoutPulseFrame;
	if (sincePulse >= period) {
		lastScoutPulseFrame = ai.frame;
		aiMilitaryMgr.quota.scout = SCOUT_QUOTA_MASS;
		CCircuitDef@ scout = SideDef("armpeep", "corfink", "");
		if (scout !is null && Base::positions.length() > 0 && scout.IsAvailable(ai.frame)) {
			for (uint i = 0; i < SCOUT_BURST; ++i) {
				aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::FIREPOWER, Task::Priority::HIGH, scout, Base::positions[0], 64.f));
			}
			AiLog("[custom] air scouting pulse: +" + SCOUT_BURST + " scouts");
		}
	} else if (sincePulse > MINUTE) {
		aiMilitaryMgr.quota.scout = SCOUT_QUOTA_IDLE;
	}
}

// Energy income the AI should be aiming for right now, mirroring economy.json "factor"
// ([[6,1],[15,240],[22,420],[30,3000]]): e-income >= m-income * factor(time).
float EnergyTargetFactor()
{
	const float t = float(ai.frame) / float(SECOND);
	if (t <= 1.f)    return 6.f;
	if (t <= 240.f)  return 6.f  + (15.f - 6.f)  * (t - 1.f)   / 239.f;
	if (t <= 420.f)  return 15.f + (22.f - 15.f) * (t - 240.f) / 180.f;
	if (t <= 3000.f) return 22.f + (30.f - 22.f) * (t - 420.f) / 2580.f;
	return 30.f;
}

// true once the team owns a T2 constructor: T2 eco (advanced fusion, T2 converters) is only
// worth queueing when someone can build it, otherwise the task idles until its timeout
bool HasT2Builder()
{
	CCircuitDef@ a = SideDef("armack", "corack", "legack");
	CCircuitDef@ v = SideDef("armacv", "coracv", "legacv");
	CCircuitDef@ p = SideDef("armaca", "coraca", "legaca");  // v23: T2 air constructors build fusions too
	return (a !is null && a.count > 0) || (v !is null && v.count > 0) || (p !is null && p.count > 0);
}

CCircuitDef@ FirstAvailable(const string& in arm, const string& in cor, const string& in leg)
{
	CCircuitDef@ cdef = SideDef(arm, cor, leg);
	if (cdef is null || !cdef.IsAvailable(ai.frame))
		return null;
	return cdef;
}

bool ScavUnits()
{
	if (scavUnits < 0)
		scavUnits = (string(aiSetupMgr.GetModOptions()["scavunitsforplayers"]) == "1") ? 1 : 0;
	return scavUnits == 1;
}

// v23: lock the upper rungs of the energy ladder until the rung below is built up
void LadderLocks(float mInc)
{
	CCircuitDef@ fus = SideDef("armfus", "corfus", "legfus");
	CCircuitDef@ afus = SideDef("armafus", "corafus", "legafus");
	if (fus !is null && afus !is null) {
		if (afusMax < 0)
			afusMax = afus.maxThisUnit;
		afus.maxThisUnit = (fus.count >= ECO_AFUS_AFTER) ? afusMax : afus.count;
	}
	CCircuitDef@ epic = ScavUnits() ? SideDef("armafust3", "corafust3", "legafust3") : null;
	if (epic !is null && afus !is null) {
		if (epicMax < 0)
			epicMax = epic.maxThisUnit;
		epic.maxThisUnit = (afus.count >= ECO_EPIC_AFTER && mInc >= ECO_EPIC_INCOME) ? epicMax : epic.count;
	}
}

// v23: the highest rung of the energy ladder the economy has grown into and can pay for (locks: LadderLocks)
CCircuitDef@ PickGenerator(float mInc, float eInc, bool t2)
{
	array<CCircuitDef@> rungs;
	if (t2 && ScavUnits())
		rungs.insertLast(FirstAvailable("armafust3", "corafust3", "legafust3"));
	if (t2)
		rungs.insertLast(FirstAvailable("armafus", "corafus", "legafus"));
	if (t2 && eInc >= ECO_FUS_E)
		rungs.insertLast(FirstAvailable("armfus", "corfus", "legfus"));
	rungs.insertLast(FirstAvailable("armadvsol", "coradvsol", "legadvsol"));
	for (uint i = 0; i < rungs.length(); ++i) {
		if (rungs[i] !is null && rungs[i].costM <= mInc * ECO_AFFORD_SEC)
			return rungs[i];
	}
	return null;  // not even an adv solar pays off yet: CircuitAI's own wind/solar picks (economy.json)
}

/*
 * Keep scaling the economy for the whole game instead of stopping at the opening base:
 *  - more energy while income lags the target factor, up the ladder the income pays for (v23, PickGenerator);
 *  - metal makers whenever energy outruns metal (that is what "secondary economy" means here);
 * All of it goes in at NORMAL/LOW priority next to the bases, so it competes with defence
 * spending rather than with the factory queue.
 */
void UpdateEcoExpansion()
{
	if (ai.frame - lastEcoFrame < ECO_STEP)
		return;
	lastEcoFrame = ai.frame;
	if (Base::positions.length() == 0)
		return;

	const float minutes = float(ai.frame) / float(MINUTE);
	const SResourceInfo@ metal = aiEconomyMgr.metal;
	const SResourceInfo@ energy = aiEconomyMgr.energy;

	// 1. energy: chase the target factor up the ladder (v23), paid out of the generator budget
	LadderLocks(metal.income);
	const float target = metal.income * EnergyTargetFactor();
	if (energy.income < target * ECO_ENERGY_MARGIN) {
		CCircuitDef@ gen = PickGenerator(metal.income, energy.income, HasT2Builder());
		if (gen !is null) {
			ecoBudget += metal.income * ECO_SHARE * float(ECO_STEP) / float(SECOND);
			if (ecoBudget > gen.costM * 2.f)
				ecoBudget = gen.costM * 2.f;  // no burst of saved-up orders
			const uint nb = Base::positions.length();
			int n = 0;
			while (ecoBudget >= gen.costM && uint(n) < nb) {
				ecoBudget -= gen.costM;
				aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY, Task::Priority::NORMAL, gen,
					Base::positions[ecoBaseIdx % nb], SQUARE_SIZE * 48));
				++ecoBaseIdx;
				++n;
			}
			AiLog("[custom] eco: energy " + gen.GetName() + " x" + n + " have=" + gen.count
				+ " e-income=" + int(energy.income) + "/" + int(target) + " m-income=" + int(metal.income)
				+ " budget=" + int(ecoBudget));
		}
	} else {
		ecoBudget = 0.f;
	}

	// 2. converters: surplus energy turned into metal, capped by game time
	if (energy.income > metal.income * ECO_CONVERT_E_RATIO || aiEconomyMgr.isEnergyFull) {
		// v23: next to epic fusions, epic converters (9k metal, 6000 E each), ECO_EPIC_CONVERTERS per reactor
		CCircuitDef@ epic = ScavUnits() ? SideDef("armafust3", "corafust3", "legafust3") : null;
		CCircuitDef@ conv = null;
		int cap = ECO_CONVERT_BASE + int(ECO_CONVERT_PER_MIN * minutes);
		if (cap > ECO_CONVERT_MAX) cap = ECO_CONVERT_MAX;
		if (epic !is null && epic.count > 0) {
			@conv = FirstAvailable("armmmkrt3", "cormmkrt3", "legadveconvt3");
			if (conv !is null)
				cap = ECO_EPIC_CONVERTERS * epic.count;
		}
		if (conv is null && HasT2Builder()) @conv = FirstAvailable("armmmkr", "cormmkr", "legadveconv");
		if (conv is null) @conv = FirstAvailable("armmakr", "cormakr", "legeconv");
		if (conv !is null) {
			conv.maxThisUnit = cap;
			if (conv.count < cap) {
				EnqueueAtBasesAs(Task::BuildType::CONVERT, conv, 1, Task::Priority::NORMAL, SQUARE_SIZE * 32);
				AiLog("[custom] eco: +converter " + conv.GetName() + " have=" + conv.count + "/" + cap
					+ " e-income=" + int(energy.income) + " m-income=" + int(metal.income));
			}
		}
	}
	// (v10: no storage - the AI never builds energy/metal storage)
}

CCircuitDef@ ReprDef(CCircuitDef@ fac)
{
	CCircuitDef@ r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::ASSAULT.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::RAIDER.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::SKIRM.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::BUILDER.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::SUPER.type);  // T4 foundries: titans only
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::HEAVY.type);
	return r;
}

void UpdateProduction()
{
	if (ai.frame - lastProdFrame < PROD_STEP)
		return;
	lastProdFrame = ai.frame;
	if (Base::positions.length() == 0 || ai.frame < 4 * MINUTE)
		return;

	const SResourceInfo@ metal = aiEconomyMgr.metal;
	const int facs = aiFactoryMgr.GetFactoryCount();
	int want = 1 + int(metal.income / PROD_METAL_PER_FACTORY);
	if (want > PROD_MAX_FACTORIES) want = PROD_MAX_FACTORIES;
	const bool floating = metal.current > metal.storage * 0.5f;

	if (facs < want || (floating && facs < PROD_MAX_FACTORIES)) {
		// catch up faster when far behind the income (2 per step at a deficit of 3+)
		const int orders = (want - facs >= 3) ? 2 : 1;
		for (int k = 0; k < orders; ++k) {
			const AIFloat3 pos = Base::positions[(ai.frame / PROD_STEP + k) % Base::positions.length()];
			CCircuitDef@ fac = Factory::AiGetFactoryToBuild(pos, false, false);  // v9: includes the income tech-up
			if (fac is null || !fac.IsAvailable(ai.frame)) {
				if (fac is null && ai.frame % 9000 < 900)
					AiLog("[custom] prod: no factory pick");
				else if (fac !is null)
					AiLog("[custom] prod: skip " + fac.GetName() + " (unavailable, count=" + fac.count + " max=" + fac.maxThisUnit + ")");
				continue;
			}
			CCircuitDef@ repr = ReprDef(fac);
			if (repr is null)
				continue;
			aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH, fac, pos, repr, SQUARE_SIZE * 64));
			AiLog("[custom] prod: +factory " + fac.GetName() + " have=" + facs + " want=" + want
				+ " m-income=" + int(metal.income) + (floating ? " (metal floating)" : ""));
		}
	}
	// assist: factories alone cannot spend a big income — nanos at the factories turn it into units
	CCircuitDef@ nano = FirstAvailable("armnanotc", "cornanotc", "legnanotc");
	if (nano !is null) {
		int wantNano = 2 + int(metal.income / PROD_METAL_PER_NANO);
		if (wantNano > PROD_NANO_MAX) wantNano = PROD_NANO_MAX;
		nano.maxThisUnit = wantNano;
		if (nano.count < wantNano) {
			EnqueueAtBasesAs(Task::BuildType::NANO, nano, floating ? 3 : 2, Task::Priority::NORMAL, SQUARE_SIZE * 16);
			AiLog("[custom] prod: +nano have=" + nano.count + " want=" + wantNano);
		}
	}
}

void UpdateAltar()
{
	if (ai.frame < ALTAR_SINCE || ai.frame - lastAltarFrame < ALTAR_STEP || Base::positions.length() == 0)
		return;
	CCircuitDef@ altar = SideDef(Factory::armt4gant, Factory::cort4gant, Factory::legt4gant);
	if (altar is null || !altar.IsAvailable(ai.frame) || altar.count >= altar.maxThisUnit)
		return;
	const float income = aiEconomyMgr.metal.income;
	const float need = ai.frame >= ALTAR_LATE ? ALTAR_INCOME_LATE : ALTAR_INCOME;
	if (income < need || !HasT2Builder())
		return;
	CCircuitDef@ repr = ReprDef(altar);
	if (repr is null)
		return;
	lastAltarFrame = ai.frame;
	// a different base anchor each try, wide shake: the foundry is 18x18 and needs open ground
	++altarTries;
	const AIFloat3 pos = Base::positions[uint(altarTries) % Base::positions.length()];
	aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH, altar, pos, repr, SQUARE_SIZE * 96));
	AiLog("[custom] altar: +" + altar.GetName() + " m-income=" + int(income) + " t=" + int(ai.frame / MINUTE) + "min");
}

void AiCustomUpdate()
{
	UpdateAltar();
	UpdateProduction();
	UpdateArmySize();
	UpdateEcoExpansion();
	UpdateAntiNukes();
	UpdateShields();
	UpdateAirScouting();
}

}  // namespace Military
