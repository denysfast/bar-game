#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/economy.as"
#include "../common.as"


namespace Main {

void AiMain()  // Initialize config params
{
	for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
		CCircuitDef@ cdef = ai.GetCircuitDef(defId);
		if (cdef.costM >= 200.f && !cdef.IsMobile() && aiEconomyMgr.GetEnergyMake(cdef) > 1.f)
			cdef.AddAttribute(Unit::Attr::BASE.type);  // Build heavy energy at base
	}

	// Example of user-assigned custom attributes
	array<string> names = {Factory::armalab, Factory::coralab, Factory::armavp, Factory::coravp,
		Factory::armaap, Factory::coraap, Factory::armasy, Factory::corasy, Factory::legadvshipyard,
		Factory::legalab, Factory::legavp, Factory::legaap}; 
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ cdef = ai.GetCircuitDef(names[i]);
		if (cdef !is null)
			Factory::userData[cdef.id].attr |= Factory::Attr::T2;
	}
	names = {Factory::armshltx, Factory::corgant, Factory::leggant};
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ cdef = ai.GetCircuitDef(names[i]);
		if (cdef !is null)
			Factory::userData[cdef.id].attr |= Factory::Attr::T3;
	}
	names = {Factory::armt4gant, Factory::cort4gant, Factory::legt4gant};  // custom T4 foundries
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ cdef = ai.GetCircuitDef(names[i]);
		if (cdef !is null)
			Factory::userData[cdef.id].attr |= Factory::Attr::T4;
	}

	Init::EnableWallTargets();
}

void AiUpdate()  // SlowUpdate, every 30 frames with initial offset of skirmishAIId
{
	Military::AiCustomUpdate();  // custom: army size schedule, anti-nukes, shields, air scouting
	Factory::UpdateHall();  // custom v15: the T2 hero hall
}

}  // namespace Main

// external commander directives (gadget cmd_ai_commander.lua -> Spring.SendSkirmishAIMessage)
void AiLuaMessage(const string& in data)
{
	AiCmdr::OnMessage(data);
}
