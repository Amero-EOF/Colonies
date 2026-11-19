--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent.Parent

const ColonistMotion = require(Shared.Colonist.ColonistMotion)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const RaidTypes = require(Shared.Raid.RaidTypes)
const Navigation = require(Systems.Colonist.Components.Navigation)

type Action = ColonistTypes.Action
type Motion = RaidTypes.Motion

-- What a raider is trying to do: reach the Town Hall storage, rummage through it, go after
-- colonists (when there was nothing to take), or run for the plot's edge
export type Goal = "Advance" | "Steal" | "Hunt" | "Flee"

-- Runtime state for one raider. Server data only: the owner's client draws it from its Motion.
export type Raider = {
	Id: number,
	Health: number,
	MaxHealth: number,
	Motion: Motion,
	Goal: Goal,
	-- Colonist it is fighting: a Guard that engaged it, or the colonist it hunts
	TargetId: number?,
	-- The target is a Guard that attacked it (takes priority over hunting)
	Engaged: boolean,
	-- Server time of its next swing
	NextAttack: number,
	-- Server time it may next re-path towards a moving target, and where that path led
	NextPath: number,
	ChaseTo: Vector3?,
	-- Server time it finishes a swing at a colonist it passed (it stands still until then)
	BusyUntil: number,
	-- Steal: when it's done rummaging. Hunt: when it gives up.
	Until: number,
	-- Where its current path leads ("Storage", "Steal", "Edge"); nil after fighting
	Heading: string?,
	-- Stacks it took from the Town Hall storage
	Loot: { ColonyTypes.MailItem },
	Dead: boolean,
	-- Reached the plot's edge and left
	Escaped: boolean,
}

-- Runtime state for one raid; lives in the colony's AI Context while it lasts
export type Raid = {
	Raiders: { [number]: Raider },
	NextRaiderId: number,
	-- Raiders it started with
	Total: number,
	-- Town Hall level when it started (raider strength)
	Level: number,
	-- Server time the raiders give up and retreat (dawn)
	RetreatAt: number,
	-- Server time anyone still on the plot is written off
	EndsAt: number,
	Retreating: boolean,
	-- The "they're stealing" toast was shown
	StealAnnounced: boolean,
	-- Navigation grid key the raiders' paths were made for
	GridKey: string,
	Killed: number,
	Escaped: number,
	ColonistsLost: number,
	-- Items carried off for good, by item id
	Stolen: { [number]: number },
	-- Motions changed since the last send, by raider id
	ChangedMotions: { [number]: Motion },
	-- Health or the raider list changed since the last send
	Dirty: boolean,
}

-- Raiders are plain data plus these functions. No controllers are required here, so the
-- colonists' AI (the Guard job) can use it too.
const Raiders = {}

function Raiders.New(level: number, retreatAt: number, endsAt: number, gridKey: string): Raid
	return {
		Raiders = {},
		NextRaiderId = 1,
		Total = 0,
		Level = level,
		RetreatAt = retreatAt,
		EndsAt = endsAt,
		Retreating = false,
		StealAnnounced = false,
		GridKey = gridKey,
		Killed = 0,
		Escaped = 0,
		ColonistsLost = 0,
		Stolen = {},
		ChangedMotions = {},
		Dirty = true,
	}
end

local function setMotion(raid: Raid, raider: Raider, motion: Motion)
	raider.Motion = motion
	raid.ChangedMotions[raider.Id] = motion
end

-- Adds a raider standing at a plot-local point
function Raiders.Add(raid: Raid, position: Vector3, health: number, now: number): Raider
	local id = raid.NextRaiderId
	raid.NextRaiderId += 1
	local raider: Raider = {
		Id = id,
		Health = health,
		MaxHealth = health,
		Motion = {
			Id = id,
			Path = { position },
			Speed = 0,
			StartTime = now,
			Action = "Idle",
		},
		Goal = "Advance",
		TargetId = nil,
		Engaged = false,
		NextAttack = 0,
		NextPath = 0,
		ChaseTo = nil,
		BusyUntil = 0,
		Until = 0,
		Heading = nil,
		Loot = {},
		Dead = false,
		Escaped = false,
	}
	raid.Raiders[id] = raider
	raid.Total += 1
	raid.ChangedMotions[id] = raider.Motion
	raid.Dirty = true
	return raider
end

-- Still on the plot and fighting fit
function Raiders.IsActive(raider: Raider): boolean
	return not raider.Dead and not raider.Escaped
end

-- Plot-local position at `now`
function Raiders.GetPosition(raider: Raider, now: number): Vector3
	local position = ColonistMotion.Evaluate(raider.Motion, now)
	return position
end

function Raiders.HasArrived(raider: Raider, now: number): boolean
	return now >= ColonistMotion.GetEndTime(raider.Motion)
end

-- Walks to a plot-local point around buildings; `action` plays once it arrives
function Raiders.WalkTo(
	raid: Raid,
	grid: Navigation.Grid,
	raider: Raider,
	target: Vector3,
	speed: number,
	action: Action,
	lookAt: Vector3?,
	now: number
)
	setMotion(raid, raider, {
		Id = raider.Id,
		Path = Navigation.FindPath(grid, Raiders.GetPosition(raider, now), target),
		Speed = speed,
		StartTime = now,
		Action = action,
		LookAt = lookAt,
	})
end

-- Stops where it is and plays `action`
function Raiders.Stop(raid: Raid, raider: Raider, action: Action, lookAt: Vector3?, now: number)
	local motion = raider.Motion
	if motion.Speed == 0 and motion.Action == action and motion.LookAt == lookAt then
		return
	end
	setMotion(raid, raider, {
		Id = raider.Id,
		Path = { Raiders.GetPosition(raider, now) },
		Speed = 0,
		StartTime = now,
		Action = action,
		LookAt = lookAt,
	})
end

-- Hurts a raider; returns true when that killed it. The raid's controller clears away the
-- dead on its next step (and returns what they carried).
function Raiders.Damage(raid: Raid, raider: Raider, amount: number): boolean
	if not Raiders.IsActive(raider) or amount <= 0 then
		return false
	end
	raider.Health = math.max(raider.Health - amount, 0)
	raid.Dirty = true
	if raider.Health <= 0 then
		raider.Dead = true
		return true
	end
	return false
end

-- A Guard attacks this raider: it turns to fight him, unless it's running away or already
-- fighting another Guard
function Raiders.Engage(raider: Raider, colonistId: number)
	if raider.Goal == "Flee" or raider.Engaged then
		return
	end
	raider.TargetId = colonistId
	raider.Engaged = true
end

-- Stops fighting (the target died, left or got away)
function Raiders.ClearTarget(raider: Raider)
	raider.TargetId = nil
	raider.Engaged = false
	raider.Heading = nil
	raider.ChaseTo = nil
end

-- A Guard breaks off (too hurt to fight): the raiders fighting him go back to what they were doing
function Raiders.Release(raid: Raid, colonistId: number)
	for _, raider in raid.Raiders do
		if raider.Engaged and raider.TargetId == colonistId then
			Raiders.ClearTarget(raider)
		end
	end
end

-- The active raider closest to a plot-local point, and how far it is (flat studs)
function Raiders.GetNearest(raid: Raid, position: Vector3, now: number): (Raider?, number)
	local nearest: Raider? = nil
	local nearestDistance = math.huge
	for _, raider in raid.Raiders do
		if Raiders.IsActive(raider) then
			local offset = Raiders.GetPosition(raider, now) - position
			local distance = Vector2.new(offset.X, offset.Z).Magnitude
			if distance < nearestDistance then
				nearest = raider
				nearestDistance = distance
			end
		end
	end
	return nearest, nearestDistance
end

function Raiders.CountActive(raid: Raid): number
	local count = 0
	for _, raider in raid.Raiders do
		if Raiders.IsActive(raider) then
			count += 1
		end
	end
	return count
end

-- What the owner's client draws
function Raiders.GetState(raid: Raid, active: boolean): RaidTypes.RaidState
	local list: { RaidTypes.RaiderInfo } = {}
	if active then
		for _, raider in raid.Raiders do
			if Raiders.IsActive(raider) then
				table.insert(list, {
					Id = raider.Id,
					Health = raider.Health,
					MaxHealth = raider.MaxHealth,
					Carrying = #raider.Loot > 0,
				})
			end
		end
	end
	return {
		Active = active,
		Raiders = list,
		Total = raid.Total,
		RetreatAt = raid.RetreatAt,
	}
end

function Raiders.GetMotions(raid: Raid): { Motion }
	local motions = {}
	for _, raider in raid.Raiders do
		if Raiders.IsActive(raider) then
			table.insert(motions, raider.Motion)
		end
	end
	return motions
end

return Raiders
