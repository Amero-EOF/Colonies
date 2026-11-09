local Players = game:GetService("Players")
local player = Players.LocalPlayer
local CharacterUtil = {}

function CharacterUtil.Guard(userId: string?): Model?
	local checkPlayer = if userId then Players:GetPlayerByUserId(userId) else player
	local checkCharacter = checkPlayer.Character
	if
		not checkCharacter
		or not checkCharacter:FindFirstChild("HumanoidRootPart")
		or checkCharacter.Humanoid.Health <= 0
	then
		return nil
	end

	return checkCharacter
end

return CharacterUtil
