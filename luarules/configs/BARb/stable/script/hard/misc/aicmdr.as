#include "../../define.as"
#include "../../task.as"
#include "base.as"


/*
 * Custom (denysfast/bar-game): external commander directives.
 * The gadget cmd_ai_commander.lua forwards text lines here (AiLuaMessage in main.as):
 *   detach <id,id,...>           the commander took these units: stop driving them (PlayerTask)
 *   attach <id,id,...>           hand them back
 *   posture <mult>|hold|normal   quota.attack multiplier; hold = never launch waves
 *   wave [minutes]               launch attack waves with whatever the army has, for N minutes (default 2)
 *   build <def> <count> <type> <x> <z> [prio] [shake]   x < 0 -> first base; type: factory|nano|energy|
 *                                defence|radar|sonar|convert|bunker|big_gun|store|geo|mex
 *   recruit <def> <count> [prio] factory production order
 *   limit <def> <n>              cap how many of this unit the AI keeps (maxThisUnit); -1 = back to default
 *   status                       report through CallRules("aicmd_status {...}")
 * prio: low|normal|high|now
 */
namespace AiCmdr {

float attackMul = 1.f;
bool hold = false;
int waveUntil = -1;
int detached = 0;
dictionary defaultLimits;  // def name -> original maxThisUnit

Task::Priority ParsePrio(const string& in s, Task::Priority dflt)
{
	if (s == "low") return Task::Priority::LOW;
	if (s == "normal") return Task::Priority::NORMAL;
	if (s == "high") return Task::Priority::HIGH;
	if (s == "now") return Task::Priority::NOW;
	return dflt;
}

Task::BuildType ParseBuildType(const string& in s)
{
	if (s == "factory") return Task::BuildType::FACTORY;
	if (s == "nano") return Task::BuildType::NANO;
	if (s == "energy") return Task::BuildType::ENERGY;
	if (s == "radar") return Task::BuildType::RADAR;
	if (s == "sonar") return Task::BuildType::SONAR;
	if (s == "convert") return Task::BuildType::CONVERT;
	if (s == "bunker") return Task::BuildType::BUNKER;
	if (s == "big_gun") return Task::BuildType::BIG_GUN;
	if (s == "store") return Task::BuildType::STORE;
	if (s == "geo") return Task::BuildType::GEO;
	if (s == "mex") return Task::BuildType::MEX;
	return Task::BuildType::DEFENCE;
}

AIFloat3 PosOrBase(float x, float z)
{
	if (x >= 0.f && z >= 0.f)
		return AIFloat3(x, 0.f, z);
	if (Base::positions.length() > 0)
		return Base::positions[0];
	return AIFloat3(-1.f, 0.f, -1.f);
}

CCircuitDef@ FactoryRepr(CCircuitDef@ fac)
{
	CCircuitDef@ r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::ASSAULT.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::RAIDER.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::SKIRM.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::BUILDER.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::SUPER.type);
	if (r is null) @r = aiFactoryMgr.GetRoleDef(fac, Unit::Role::HEAVY.type);
	return r;
}

// called from Military::UpdateArmySize after it computed its own threshold
float AdjustAttack(float attack)
{
	if (waveUntil > ai.frame)
		return 1.f;  // anything goes: every gathered group launches
	if (hold)
		return 1e9f;
	return attack * attackMul;
}

void Reply(const string& in what, bool ok, const string& in msg)
{
	ai.CallRules("aicmd_reply {\"team\":" + ai.teamId + ",\"what\":\"" + what + "\",\"ok\":" + (ok ? "true" : "false")
		+ ",\"msg\":\"" + msg + "\"}");
}

void Status()
{
	string s = "aicmd_status {\"team\":" + ai.teamId
		+ ",\"frame\":" + ai.frame
		+ ",\"side\":\"" + ai.GetSideName() + "\""
		+ ",\"quotaAttack\":" + int(aiMilitaryMgr.quota.attack)
		+ ",\"armyCost\":" + int(aiMilitaryMgr.armyCost)
		+ ",\"mIncome\":" + int(aiEconomyMgr.metal.income)
		+ ",\"eIncome\":" + int(aiEconomyMgr.energy.income)
		+ ",\"energyStalling\":" + (aiEconomyMgr.isEnergyStalling ? "true" : "false")
		+ ",\"metalStalling\":" + (aiEconomyMgr.isMetalEmpty ? "true" : "false")
		+ ",\"workers\":" + aiBuilderMgr.GetWorkerCount()
		+ ",\"factories\":" + aiFactoryMgr.GetFactoryCount()
		+ ",\"bases\":" + Base::positions.length()
		+ ",\"attackMul\":" + attackMul
		+ ",\"hold\":" + (hold ? "true" : "false")
		+ ",\"waveLeftSec\":" + ((waveUntil > ai.frame) ? (waveUntil - ai.frame) / SECOND : 0)
		+ ",\"detached\":" + detached
		+ "}";
	ai.CallRules(s);
}

void OnMessage(const string& in line)
{
	array<string>@ a = line.split(" ");
	if (a.length() == 0)
		return;
	const string verb = a[0];

	if (verb == "detach" || verb == "attach") {
		if (a.length() < 2)
			return;
		array<string>@ ids = a[1].split(",");
		const bool enable = (verb == "attach");
		int n = 0;
		for (uint i = 0; i < ids.length(); ++i) {
			if (ids[i].isEmpty())
				continue;
			if (ai.UnitControl(int(parseInt(ids[i])), enable))
				++n;
		}
		detached += enable ? -n : n;
		if (detached < 0) detached = 0;
		return;
	}

	if (verb == "posture" && a.length() >= 2) {
		if (a[1] == "hold") {
			hold = true;
		} else if (a[1] == "normal") {
			hold = false; attackMul = 1.f;
		} else {
			hold = false;
			attackMul = parseFloat(a[1]);
			if (attackMul < 0.05f) attackMul = 0.05f;
		}
		Reply("posture", true, a[1]);
		return;
	}

	if (verb == "wave") {
		float minutes = (a.length() >= 2) ? parseFloat(a[1]) : 2.f;
		if (minutes <= 0.f) minutes = 2.f;
		waveUntil = ai.frame + int(minutes * MINUTE);
		hold = false;
		aiMilitaryMgr.quota.attack = 1.f;
		Reply("wave", true, "" + minutes + "min");
		return;
	}

	if (verb == "build" && a.length() >= 6) {
		CCircuitDef@ cdef = ai.GetCircuitDef(a[1]);
		if (cdef is null) { Reply("build", false, "unknown def " + a[1]); return; }
		int count = parseInt(a[2]);
		const Task::BuildType type = ParseBuildType(a[3]);
		const AIFloat3 pos = PosOrBase(parseFloat(a[4]), parseFloat(a[5]));
		if (pos.x < 0.f) { Reply("build", false, "no base yet and no position"); return; }
		const Task::Priority prio = ParsePrio((a.length() >= 7) ? a[6] : "", Task::Priority::HIGH);
		const float shake = (a.length() >= 8) ? parseFloat(a[7]) : SQUARE_SIZE * 16;
		if (count < 1) count = 1;
		if (count > 40) count = 40;
		if (cdef.maxThisUnit < cdef.count + count)
			cdef.maxThisUnit = cdef.count + count;
		for (int i = 0; i < count; ++i) {
			if (type == Task::BuildType::FACTORY) {
				CCircuitDef@ repr = FactoryRepr(cdef);
				if (repr is null) { Reply("build", false, "factory has no known product " + a[1]); return; }
				aiBuilderMgr.Enqueue(TaskB::Factory(prio, cdef, pos, repr, shake));
			} else {
				aiBuilderMgr.Enqueue(TaskB::Common(type, prio, cdef, pos, shake));
			}
		}
		Reply("build", true, a[1] + " x" + count);
		return;
	}

	if (verb == "recruit" && a.length() >= 3) {
		CCircuitDef@ cdef = ai.GetCircuitDef(a[1]);
		if (cdef is null) { Reply("recruit", false, "unknown def " + a[1]); return; }
		int count = parseInt(a[2]);
		if (count < 1) count = 1;
		if (count > 60) count = 60;
		const Task::Priority prio = ParsePrio((a.length() >= 4) ? a[3] : "", Task::Priority::HIGH);
		const AIFloat3 pos = PosOrBase(-1.f, -1.f);
		if (pos.x < 0.f) { Reply("recruit", false, "no factory yet"); return; }
		if (cdef.maxThisUnit < cdef.count + count)
			cdef.maxThisUnit = cdef.count + count;
		for (int i = 0; i < count; ++i)
			aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::FIREPOWER, prio, cdef, pos, 64.f));
		Reply("recruit", true, a[1] + " x" + count);
		return;
	}

	if (verb == "limit" && a.length() >= 3) {
		CCircuitDef@ cdef = ai.GetCircuitDef(a[1]);
		if (cdef is null) { Reply("limit", false, "unknown def " + a[1]); return; }
		if (!defaultLimits.exists(a[1]))
			defaultLimits.set(a[1], int(cdef.maxThisUnit));
		int n = parseInt(a[2]);
		if (n < 0) {
			int orig = 0;
			defaultLimits.get(a[1], orig);
			n = orig;
		}
		cdef.maxThisUnit = n;
		Reply("limit", true, a[1] + "=" + n);
		return;
	}

	if (verb == "status") {
		Status();
		return;
	}

	Reply(verb, false, "unknown directive");
}

}  // namespace AiCmdr
