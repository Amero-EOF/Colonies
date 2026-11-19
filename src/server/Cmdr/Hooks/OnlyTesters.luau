--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const DevAccess = require(ReplicatedStorage.Shared.Dev.DevAccess)

-- Testing commands run in Studio, or for the game's owner in live servers (DevAccess)
return function(registry: any)
	registry:RegisterHook("BeforeRun", function(context: any): string?
		if DevAccess.IsTester(context.Executor) then
			return nil
		end
		return "You don't have permission to run this command."
	end)
end
