--!strict

const ServerScriptService = game:GetService("ServerScriptService")

const Builder = require(ServerScriptService.Server.Systems.Colonist.AI.Jobs.Builder)

return function(_context: any, multiplier: number?): string
	if multiplier == nil then
		return `Build speed is x{Builder.GetSpeedMultiplier()}`
	end
	if multiplier <= 0 or multiplier ~= multiplier then
		return "Multiplier must be greater than 0"
	end
	Builder.SetSpeedMultiplier(multiplier)
	return `Build speed set to x{multiplier} (applies from the next part)`
end
