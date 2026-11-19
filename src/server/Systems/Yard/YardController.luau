--!strict

const Players = game:GetService("Players")

const Systems = script.Parent.Parent

const ColonyController = require(Systems.Colony.ColonyController)

-- Server-set player attribute (testing): every yard node becomes ready, then it's cleared
const DEBUG_READY_ATTRIBUTE = "DebugYardReady"

-- Resource yards (YardData): the trees around a Forester's Hut, the rocks around a Mine. Their
-- workers (AI/Jobs/Gatherer) change the saved nodes and ColonyController keeps them filled in and
-- sends them to the owner; regrowth is a pure function of server time (YardData.GetStage). The
-- player has nothing to set on a yard, so this only holds the testing hook.
const YardController = {}

local started = false

-- Testing: makes every node of the player's yards ready now. Returns how many were growing back.
function YardController.MakeReady(player: Player): number
	local data = ColonyController.GetData(player)
	if not data then
		return 0
	end
	local readied = 0
	for _, nodes in data.Yards do
		for _, node in nodes do
			if node.HarvestedAt then
				node.HarvestedAt = nil
				readied += 1
			end
		end
	end
	ColonyController.Sync(player)
	return readied
end

local function watchDebug(player: Player)
	local function check()
		if player:GetAttribute(DEBUG_READY_ATTRIBUTE) == true then
			YardController.MakeReady(player)
			player:SetAttribute(DEBUG_READY_ATTRIBUTE, nil)
		end
	end
	player:GetAttributeChangedSignal(DEBUG_READY_ATTRIBUTE):Connect(check)
	check()
end

function YardController.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(watchDebug)
	for _, player in Players:GetPlayers() do
		watchDebug(player)
	end
end

return YardController
