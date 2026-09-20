#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/base.as"


/*
 * Custom (denysfast/bar-game) military rules — see custom-ai.md in the repo:
 *  - ground raiders join the main army instead of roaming in small raid squads (no early harass);
 *  - the army threshold (quota.attack) grows with game time so attacks come as big waves;
 *  - anti-nuke coverage scales with the number of enemy nukes the team has seen (gadget
 *    game_ai_resource_bonus.lua publishes "ai_known_enemy_nukes"), shields come late game;
 *  - periodic mass air scouting.
 */
namespace Military {

// army size schedule: power = ATTACK_BASE + ATTACK_PER_MIN * minutes, capped
const float ATTACK_BASE    = 100.f;
const float ATTACK_PER_MIN = 35.f;
const float ATTACK_CAP     = 1200.f;

// anti-nuke: base coverage + per known enemy nuke launcher
const int ANTINUKE_BASE     = 2;
const int ANTINUKE_PER_NUKE = 2;
const int ANTINUKE_MAX      = 8;

// shields: from this minute, one per base anchor, then more
const int SHIELD_SINCE_MIN  = 25;
const int SHIELD_STEP_MIN   = 8;

// air scouting pulse: every SCOUT_PERIOD minutes recruit SCOUT_BURST air scouts and widen the scout quota
const int  SCOUT_PERIOD_MIN = 6;
const uint SCOUT_QUOTA_IDLE = 2;
const uint SCOUT_QUOTA_MASS = 8;
const uint SCOUT_BURST      = 4;

int lastAntiNukeFrame = 0;
int lastShieldFrame = 0;
int lastScoutPulseFrame = 0;
int shieldsOrdered = 0;
int knownNukesHandled = -1;

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	const CCircuitDef@ cdef = unit.circuitDef;
	if (cdef.GetMainRole() == Unit::Role::RAIDER.type
		&& !cdef.IsRoleAny(Unit::Role::AIR.mask | Unit::Role::SCOUT.mask | Unit::Role::SUB.mask))
	{
		// gather at base with everyone else; promoted to ATTACK when the group reaches quota.attack
		return aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK, aiMilitaryMgr.quota.attack));
	}
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
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
	istream >> lastAntiNukeFrame >> lastShieldFrame >> lastScoutPulseFrame >> shieldsOrdered >> knownNukesHandled;
}

void AiSave(OStream& ostream)
{
	ostream << lastAntiNukeFrame << lastShieldFrame << lastScoutPulseFrame << shieldsOrdered << knownNukesHandled;
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

void EnqueueAtBases(CCircuitDef@ cdef, int perBase, Task::Priority prio, float shake)
{
	if (cdef is null || Base::positions.length() == 0)
		return;
	for (uint i = 0; i < Base::positions.length(); ++i) {
		for (int j = 0; j < perBase; ++j) {
			aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, prio, cdef, Base::positions[i], shake));
		}
	}
}

void UpdateArmySize()
{
	const float minutes = float(ai.frame) / float(MINUTE);
	float attack = ATTACK_BASE + ATTACK_PER_MIN * minutes;
	if (attack > ATTACK_CAP) attack = ATTACK_CAP;
	aiMilitaryMgr.quota.attack = attack;
	// raid quota only matters for air raiders now; keep them in bigger packs too
	aiMilitaryMgr.quota.raid.min = 40.f;
	aiMilitaryMgr.quota.raid.avg = 200.f;
	if (ai.frame % (2 * MINUTE) < SECOND) {
		AiLog("[custom] t=" + int(minutes) + "min quota.attack=" + int(attack)
			+ " m-income=" + int(aiEconomyMgr.metal.income) + " e-income=" + int(aiEconomyMgr.energy.income)
			+ " armyCost=" + int(aiMilitaryMgr.armyCost) + " workers=" + aiBuilderMgr.GetWorkerCount()
			+ " factories=" + aiFactoryMgr.GetFactoryCount()
			+ " bonus=" + int(ai.GetTeamRulesParam("ai_bonus_pct", 0.f)) + "%");
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
	if ((moreNukes || periodic) && ai.frame > 12 * MINUTE && anti.count < want) {
		EnqueueAtBases(anti, 1, moreNukes ? Task::Priority::HIGH : Task::Priority::NORMAL, SQUARE_SIZE * 24);
		lastAntiNukeFrame = ai.frame;
		knownNukesHandled = known;
		AiLog("[custom] anti-nuke: known enemy nukes=" + known + " want=" + want + " have=" + anti.count);
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
	gate.maxThisUnit = 12;
	EnqueueAtBases(gate, 1, Task::Priority::NORMAL, SQUARE_SIZE * 40);
	lastShieldFrame = ai.frame;
	++shieldsOrdered;
	AiLog("[custom] shields: ordered round " + shieldsOrdered + " (have " + gate.count + ")");
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

void AiCustomUpdate()
{
	UpdateArmySize();
	UpdateAntiNukes();
	UpdateShields();
	UpdateAirScouting();
}

}  // namespace Military
