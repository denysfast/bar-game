if Spring.GetModOptions().allowpausegameplay or BAR.Utilities.Gametype.IsSinglePlayer() then
	return
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Paused is paused",
		desc = "Prevent commands being queued while paused",
		author = "Floris",
		date = "May 2023",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

local paused = false

function gadget:GamePaused(playerID, isPaused)
	paused = isPaused
end

-- a multiplayer save is written while paused and loads unpaused without a GamePaused call;
-- frames only advance unpaused, so a frame clears a stale flag
function gadget:GameFrame()
	paused = false
end

function gadget:AllowCommand(
	unitID,
	unitDefID,
	teamID,
	cmdID,
	cmdParams,
	cmdOptions,
	cmdTag,
	playerID,
	fromSynced,
	fromLua
)
	if paused and not Spring.IsCheatingEnabled() then
		return false
	else
		return true
	end
end

function gadget:Initialize()
	gadgetHandler:RegisterAllowCommand(CMD.ANY)
end
