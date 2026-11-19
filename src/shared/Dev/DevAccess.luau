--!strict

const RunService = game:GetService("RunService")

-- Who may use developer tools (Cmdr testing commands, the Creative menu):
-- anyone in Studio, or the game's owner in live servers
const DevAccess = {}

function DevAccess.IsTester(player: Player?): boolean
	if RunService:IsStudio() then
		return true
	end
	return player ~= nil and player.UserId == game.CreatorId
end

return DevAccess
