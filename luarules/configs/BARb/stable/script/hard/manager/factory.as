#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/commander.as"
#include "../misc/base.as"


namespace Factory {

enum Attr {
	T1 = 0x0001, T2 = 0x0002, T3 = 0x0004, T4 = 0x0008
}

class SUserData {
	SUserData(int a) {
		attr = a;
	}
	SUserData() {}
	int attr = 0;
}

// Example of userData per UnitDef
array<SUserData> userData(ai.GetDefCount() + 1);

string armlab  ("armlab");
string armalab ("armalab");
string armvp   ("armvp");
string armavp  ("armavp");
string armsy   ("armsy");
string armasy  ("armasy");
string armap   ("armap");
string armaap  ("armaap");
string armshltx("armshltx");

string corlab  ("corlab");
string coralab ("coralab");
string corvp   ("corvp");
string coravp  ("coravp");
string corsy   ("corsy");
string corasy  ("corasy");
string corap   ("corap");
string coraap  ("coraap");
string corgant ("corgant");

string leglab  ("leglab");
string legalab ("legalab");
string legvp   ("legvp");
string legavp  ("legavp");
string legap   ("legap");
string legsy   ("legsy");
string legadvshipyard   ("legadvshipyard");
string legaap  ("legaap");
string leggant ("leggant");

float switchLimit = MakeSwitchLimit();

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	return aiFactoryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage != Unit::UseAs::FACTORY)
		return;

	const CCircuitDef@ facDef = unit.circuitDef;
	Base::Add(unit.GetPos(ai.frame));  // custom: remember base anchors for anti-nuke / shield placement
	if (userData[facDef.id].attr & Attr::T3 != 0) {
		// if (ai.teamId != ai.GetLeadTeamId()) then this change affects only target selection,
		// while threatmap still counts "ignored" here units.
		array<string> spam = {"armpw", "corak", "armflea", "armfav", "corfav", "leggob", "legscout"};
		for (uint i = 0; i < spam.length(); ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(spam[i]);
			if (cdef !is null)
				cdef.SetIgnore(true);
		}
	}

	const array<Opener::SO>@ opener = Opener::GetOpener(facDef);
	if (opener is null)
		return;

	const AIFloat3 pos = unit.GetPos(ai.frame);
	for (uint i = 0, icount = opener.length(); i < icount; ++i) {
		CCircuitDef@ buildDef = aiFactoryMgr.GetRoleDef(facDef, opener[i].role);
		if ((buildDef is null) || !buildDef.IsAvailable(ai.frame))
			continue;

		Task::Priority priority;
		Task::RecruitType recruit;
		if (opener[i].role == Unit::Role::BUILDER.type) {
			priority = Task::Priority::NORMAL;
			recruit  = Task::RecruitType::BUILDPOWER;
		} else {
			priority = Task::Priority::HIGH;
			recruit  = Task::RecruitType::FIREPOWER;
		}
		for (uint j = 0, jcount = opener[i].count; j < jcount; ++j)
			aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, buildDef, pos, 64.f));
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

/*
 * New factory switch condition; switch event is also based on eco + caretakers.
 */
bool AiIsSwitchTime(int lastSwitchFrame)
{
	const float value = pow((ai.frame - lastSwitchFrame), 0.9) * aiEconomyMgr.metal.income + (aiEconomyMgr.metal.current * 7);
	if (value > switchLimit) {
		switchLimit = MakeSwitchLimit();
		return true;
	}
	return false;
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
	return true;
}

/*
 * custom v9: tech follows the economy. Past TECH_T2_INCOME a new T1 factory is replaced by its T2
 * counterpart, past TECH_T3_INCOME a new T2 land factory by a T3 gantry (when buildable). Obsolete
 * factories that already exist are recycled by the gadget game_ai_unjam.lua (tech ladder part).
 */
const float TECH_T2_INCOME = 150.f;
const float TECH_T3_INCOME = 800.f;

CCircuitDef@ Upgrade(CCircuitDef@ d, const string& in from, const string& in to)
{
	if (d.GetName() != from)
		return null;
	CCircuitDef@ u = ai.GetCircuitDef(to);
	if (u is null || !u.IsAvailable(ai.frame) || u.count >= u.maxThisUnit)
		return null;
	return u;
}

CCircuitDef@ TechUp(CCircuitDef@ d)
{
	const float income = aiEconomyMgr.metal.income;
	CCircuitDef@ u = null;
	if (income >= TECH_T2_INCOME && (userData[d.id].attr & (Attr::T2 | Attr::T3)) == 0) {
		array<string> from = {armlab, armvp, armap, armsy, corlab, corvp, corap, corsy, leglab, legvp, legap, legsy};
		array<string> to   = {armalab, armavp, armaap, armasy, coralab, coravp, coraap, corasy, legalab, legavp, legaap, legadvshipyard};
		for (uint i = 0; i < from.length() && u is null; ++i)
			@u = Upgrade(d, from[i], to[i]);
		if (u !is null)
			@d = u;
	}
	if (income >= TECH_T3_INCOME && (userData[d.id].attr & Attr::T2) != 0) {
		array<string> from = {armalab, armavp, coralab, coravp, legalab, legavp};
		array<string> to   = {armshltx, armshltx, corgant, corgant, leggant, leggant};
		for (uint i = 0; i < from.length(); ++i) {
			CCircuitDef@ t3 = Upgrade(d, from[i], to[i]);
			if (t3 !is null)
				return t3;
		}
	}
	return d;
}

CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	CCircuitDef@ d = aiFactoryMgr.DefaultGetFactoryToBuild(pos, isStart, isReset);
	if (d is null || isStart)
		return d;
	return TechUp(d);
}

/* --- Utils --- */

float MakeSwitchLimit()
{
	return AiRandom(8000, 12000) * SECOND;
}

}  // namespace Factory
