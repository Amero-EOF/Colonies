--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const RaidData = require(Shared.Raid.RaidData)
const RaidTypes = require(Shared.Raid.RaidTypes)

const source = vide.source

type Motion = RaidTypes.Motion
type RaiderInfo = RaidTypes.RaiderInfo

-- A little longer than the server's cooldown, so swings sent back to back aren't refused
const ATTACK_INTERVAL = RaidData.PLAYER_ATTACK_COOLDOWN + 0.1

-- The raid on the local player's colony as last sent by the server
const RaidStore = {
	Active = source(false),
	-- Raiders still on the plot
	Raiders = source({} :: { RaiderInfo }),
	-- Raiders the raid started with
	Total = source(0),
	-- workspace:GetServerTimeNow() the raiders retreat (dawn)
	RetreatAt = source(0),
	-- Latest motion per raider id; RaidView replays these every frame
	Motions = {} :: { [number]: Motion },
	-- os.clock() of the local player's last hit on each raider (RaidView flashes it)
	Hits = {} :: { [number]: number },
	-- Shows a toast (set by the UI, which owns the notifications)
	OnMessage = nil :: ((text: string) -> ())?,
}

local started = false
local lastAttack = 0

local function applyState(state: RaidTypes.RaidState?)
	if not state then
		return
	end
	if not state.Active then
		table.clear(RaidStore.Motions)
		table.clear(RaidStore.Hits)
	end
	RaidStore.Total(state.Total)
	RaidStore.RetreatAt(state.RetreatAt)
	RaidStore.Raiders(state.Raiders)
	RaidStore.Active(state.Active)
end

local function applyMotions(motions: { Motion })
	for _, motion in motions do
		RaidStore.Motions[motion.Id] = motion
	end
end

function RaidStore.Get(id: number): RaiderInfo?
	for _, raider in RaidStore.Raiders() do
		if raider.Id == id then
			return raider
		end
	end
	return nil
end

-- Swings at a raider; the server checks reach and decides the damage
function RaidStore.Attack(id: number)
	local now = os.clock()
	if now - lastAttack < ATTACK_INTERVAL then
		return
	end
	lastAttack = now
	task.spawn(function()
		local ok, message = Net:Invoke("AttackRaider", id)
		if ok then
			RaidStore.Hits[id] = os.clock()
		elseif message == "Too far away" and RaidStore.OnMessage then
			RaidStore.OnMessage("Get closer to strike the raider")
		end
	end)
end

function RaidStore.Start()
	if started then
		return
	end
	started = true

	Net:Connect("RaidState", applyState)
	Net:Connect("RaidMotions", applyMotions)
	task.spawn(function()
		-- A raid may already be going on (respawned client); nil when there is none
		local result = Net:Invoke("GetRaid")
		if result then
			applyMotions(result.Motions)
			applyState(result.State)
		end
	end)
end

return RaidStore
