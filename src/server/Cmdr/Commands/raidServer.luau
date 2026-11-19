--!strict

const ServerScriptService = game:GetService("ServerScriptService")

const RaidController = require(ServerScriptService.Server.Systems.Raid.RaidController)

return function(context: any, action: string, players: { Player }?): string
	local lines = {}
	local targets: { Player } = players or { context.Executor }
	for _, player in targets do
		local message: string
		if action == "start" then
			local _, text = RaidController.ForceRaid(player)
			message = text
		elseif action == "end" then
			local _, text = RaidController.EndRaid(player)
			message = text
		elseif action == "tonight" then
			local _, text = RaidController.ScheduleTonight(player)
			message = text
		else
			message = RaidController.Describe(player)
		end
		table.insert(lines, `{player.Name}: {message}`)
	end
	return table.concat(lines, "\n")
end
