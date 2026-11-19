--!strict

const ServerScriptService = game:GetService("ServerScriptService")

const CreativeController = require(ServerScriptService.Server.Systems.Creative.CreativeController)

return function(context: any): string
	local executor: Player? = context.Executor
	if not executor then
		return "Run this from a player's console."
	end
	if not CreativeController.Toggle(executor) then
		return "You don't have permission to use the Creative menu."
	end
	return "Toggled the Creative menu."
end
