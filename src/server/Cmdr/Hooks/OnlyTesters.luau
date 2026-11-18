--!strict

const RunService = game:GetService("RunService")

-- Testing commands run in Studio, or for the game's owner in live servers
return function(registry: any)
	registry:RegisterHook("BeforeRun", function(context: any): string?
		if RunService:IsStudio() then
			return nil
		end
		local executor: Player? = context.Executor
		if executor and (executor.UserId == game.CreatorId) then
			return nil
		end
		return "You don't have permission to run this command."
	end)
end
