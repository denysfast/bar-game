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
string armt4gant("armt4gant");  // custom T4 foundries
string cort4gant("cort4gant");
string legt4gant("legt4gant");

float switchLimit = MakeSwitchLimit();

/*
 * custom T4 heroes: a T4 foundry (hero altar) builds each of its four heroes once. A hero is unique
 * (maxThisUnit 1), so a dead one has count 0 again and the altar rebuilds it - that is the revive
 * (the hero gadget charges the revive price and restores the level minus 5). Order: by weight.
 */
array<string> t4Titans = {
	"armt4atlas", "armt4olympus", "armt4aegis", "armt4zeus",
	"cort4colossus", "cort4bastion", "cort4armageddon", "cort4hellwalker",
	"legt4helios", "legt4starfall", "legt4longinus", "legt4tempest"};
array<float> t4Weights = {
	3.f, 2.f, 1.5f, 2.f,
	3.f, 2.f, 2.f, 2.f,
	2.5f, 2.f, 2.f, 2.5f};

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	if ((userData[unit.circuitDef.id].attr & Attr::T4) != 0) {
		const string side = unit.circuitDef.GetName().substr(0, 3);
		CCircuitDef@ pick = null;
		float best = 1e9f;
		for (uint i = 0; i < t4Titans.length(); ++i) {
			if (t4Titans[i].substr(0, 3) != side)
				continue;
			CCircuitDef@ d = ai.GetCircuitDef(t4Titans[i]);
			if (d is null || !d.IsAvailable(ai.frame) || d.count >= d.maxThisUnit)
				continue;
			const float score = (d.count + 1) / t4Weights[i];
			if (score < best) {
				best = score;
				@pick = d;
			}
		}
		if (pick !is null) {
			AiLog("[custom] hero: " + unit.circuitDef.GetName() + " builds " + pick.GetName());
			return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::FIREPOWER, Task::Priority::HIGH, pick, unit.GetPos(ai.frame), 64.f));
		}
		return null;  // every hero is alive: the altar idles instead of the stock pick
	}
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
const float TECH_T4_INCOME = 700.f;  // custom T4 heroes: a gantry pick becomes the hero altar

CCircuitDef@ Upgrade(CCircuitDef@ d, const string& in from, const string& in to)
{
	if (d.GetName() != from)
		return null;
	CCircuitDef@ u = ai.GetCircuitDef(to);
	if (u is null || !u.IsAvailable(ai.frame) || u.count >= u.maxThisUnit) {
		if (u !is null && ai.frame % 9000 < 900)
			AiLog("[custom] techup: " + to + " unavailable (avail=" + u.IsAvailable(ai.frame) + " count=" + u.count + " max=" + u.maxThisUnit + ")");
		return null;
	}
	return u;
}

// the hero altar of our side, once the income is there and a T3 gantry stands (the gantry count
// is per team, so only our own side's gantries have one)
CCircuitDef@ T4Foundry()
{
	if (aiEconomyMgr.metal.income < TECH_T4_INCOME)
		return null;
	array<string> g = {armshltx, corgant, leggant};
	array<string> f = {armt4gant, cort4gant, legt4gant};
	for (uint i = 0; i < g.length(); ++i) {
		CCircuitDef@ gantry = ai.GetCircuitDef(g[i]);
		if (gantry is null || gantry.count < 1)
			continue;
		CCircuitDef@ t4 = ai.GetCircuitDef(f[i]);
		if (ai.frame % 9000 < 900 && t4 !is null)
			AiLog("[custom] t4: " + f[i] + " gantries=" + gantry.count + " avail=" + t4.IsAvailable(ai.frame) + " count=" + t4.count + "/" + t4.maxThisUnit);
		if (t4 !is null && t4.IsAvailable(ai.frame) && t4.count < t4.maxThisUnit)
			return t4;
	}
	if (ai.frame % 9000 < 900)
		AiLog("[custom] t4: no side with a gantry");
	return null;
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
	// T4: past TECH_T4_INCOME any T2/T3 land pick becomes the T4 foundry (the gantries alone sit at
	// their limit and stop the production growth)
	if ((userData[d.id].attr & (Attr::T2 | Attr::T3)) != 0) {
		CCircuitDef@ t4 = T4Foundry();
		if (t4 !is null)
			return t4;
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
	if (isStart)
		return d;
	// the hero altar comes only through T4Foundry (income gate), never as a stock pick
	if (d !is null && (userData[d.id].attr & Attr::T4) != 0)
		@d = null;
	if (d is null)  // every usual factory at its limit: the T4 foundry still grows the production
		return T4Foundry();
	return TechUp(d);
}

/* --- Utils --- */

float MakeSwitchLimit()
{
	return AiRandom(8000, 12000) * SECOND;
}

}  // namespace Factory
