--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const vide = require(ReplicatedStorage.Packages.vide)

const source = vide.source
const cleanup = vide.cleanup

const player = Players.LocalPlayer

-- Mirrors a server-set player attribute into a source; call inside a Vide scope
local function attributeSource(name: string): () -> any
	local value = source(player:GetAttribute(name))

	local connection = player:GetAttributeChangedSignal(name):Connect(function()
		value(player:GetAttribute(name))
	end)
	cleanup(function()
		connection:Disconnect()
	end)

	return value
end

return attributeSource
