--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const MailboxData = require(Shared.Colony.MailboxData)
const ItemsList = require(Shared.Inventory.ItemsList)
const PlotData = require(Shared.Plot.PlotData)
const RaidData = require(Shared.Raid.RaidData)
const ResourceData = require(Shared.Resources.ResourceData)
const DayCycle = require(Shared.Time.DayCycle)
const Agent = require(Systems.Colonist.AI.Agent)
const ColonistController = require(Systems.Colonist.ColonistController)
const Navigation = require(Systems.Colonist.Components.Navigation)
const ColonyController = require(Systems.Colony.ColonyController)
const Mailbox = require(Systems.Colony.Components.Mailbox)
const Notifications = require(Systems.Colony.Components.Notifications)
const Bag = require(Systems.Inventory.Components.Bag)
const Raiders = require(script.Parent.Components.Raiders)

type Agent = Agent.Agent
type ColonyData = ColonyTypes.ColonyData
type Context = Agent.Context
type MailItem = ColonyTypes.MailItem
type Raid = Raiders.Raid
type Raider = Raiders.Raider
type RaidSchedule = ColonyTypes.RaidSchedule

-- Per-player state for the colony currently loaded (not saved)
type Session = {
	Context: Context,
	-- DayCycle day the dusk warning was last shown for
	WarnedDay: number,
}

-- Studs between raiders rummaging at the Town Hall door
const DOOR_SPACING = 2
-- Studs up or down the player may be from a raider and still hit it
const MAX_HEIGHT_GAP = 12
const MAIL_FROM = "Town Guard"

-- Raids: every few in-game days raiders come at night, walk to the Town Hall, carry off stacks
-- from its storage and hurt colonists on the way. Guards (AI/Jobs/Guard) and the player fight
-- them. Raiders are server data replayed as Motions, like colonists; the owner's client draws
-- them (RaidView). Only the schedule and what the raiders carry are saved.
const RaidController = {}

local started = false

const sessions: { [Player]: Session } = {}
-- Server time of each player's last swing at a raider
const lastAttack: { [Player]: number } = {}

local function getSchedule(data: ColonyData): RaidSchedule
	local schedule = data.Raid
	if not schedule then
		local fresh: RaidSchedule = { NextDay = 0, SeenDay = -1, Carried = {} }
		data.Raid = fresh
		return fresh
	end
	-- Fill gaps only
	schedule.NextDay = schedule.NextDay or 0
	schedule.SeenDay = schedule.SeenDay or -1
	schedule.Carried = schedule.Carried or {}
	return schedule
end

-- The built Town Hall; raids wait for it (a construction site doesn't count)
local function getTownHall(data: ColonyData): ColonyTypes.SavedBuilding?
	for _, saved in data.Buildings do
		if saved.Id == "TownHall" and saved.Placement and saved.Level >= 1 then
			return saved
		end
	end
	return nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function announce(context: Context, text: string)
	Notifications.Send(context.Player, "ColonyEvent", text)
	context.Log(text)
end

local function sendState(player: Player, raid: Raid, active: boolean)
	Net:RemoteEvent("RaidState"):FireClient(player, Raiders.GetState(raid, active))
end

local function setAttribute(player: Player, active: boolean)
	if player:GetAttribute(RaidData.ATTRIBUTE) ~= active then
		player:SetAttribute(RaidData.ATTRIBUTE, active)
	end
end

-- Puts items back in the Town Hall storage; what doesn't fit is mailed
local function giveBack(context: Context, items: { MailItem })
	local data = context.Data
	local leftovers: { MailItem } = {}
	for _, item in items do
		local left = Bag.AddItem(data.Storage, item.UniqueID, item.Quantity)
		if left > 0 then
			table.insert(leftovers, { UniqueID = item.UniqueID, Quantity = left })
		end
	end
	if #leftovers > 0 then
		local mail = Mailbox.Send(data, {
			From = MAIL_FROM,
			Title = "Recovered from raiders",
			Body = "The Town Hall storage was full, so what we took back from the raiders is here.",
			Items = leftovers,
		})
		Mailbox.Notify(context.Player, mail)
	end
	context.SyncColony()
end

-- Saves what the raiders still on the plot carry, so it can be given back if the raid is cut short
local function saveCarried(schedule: RaidSchedule, raid: Raid?)
	local carried: { MailItem } = {}
	if raid then
		for _, raider in raid.Raiders do
			if Raiders.IsActive(raider) then
				for _, item in raider.Loot do
					table.insert(carried, { UniqueID = item.UniqueID, Quantity = item.Quantity })
				end
			end
		end
	end
	schedule.Carried = carried
end

-- A colony was (re)loaded: a raid that was going on when the player left is over. Its raiders
-- dropped what they carried, and days spent away don't bring the next raid closer.
local function openSession(player: Player, context: Context, now: number): Session
	local schedule = getSchedule(context.Data)
	local today = DayCycle.GetDay(now)

	if #schedule.Carried > 0 then
		local carried = schedule.Carried
		schedule.Carried = {}
		giveBack(context, carried)
		context.Log("The raiders fled and dropped what they had taken from the storage")
	end
	if schedule.NextDay > 0 and schedule.SeenDay >= 0 and today > schedule.SeenDay then
		schedule.NextDay += today - schedule.SeenDay
	end
	schedule.SeenDay = today

	context.Raid = nil
	setAttribute(player, false)
	Net:RemoteEvent("RaidState"):FireClient(player, {
		Active = false,
		Raiders = {},
		Total = 0,
		RetreatAt = 0,
	})
	return { Context = context, WarnedDay = -1 }
end

-------- Starting and ending --------

-- Raiders appear in a row on one side of the plot, level with the Town Hall
local function getSpawnPoints(context: Context, townHall: ColonyTypes.SavedBuilding, count: number)
	local grid = context.Grid
	local random = context.Random
	local edge = grid.Half - grid.CellSize / 2
	local centre = Navigation.GetCentre(townHall) or Vector3.zero
	local side = random:NextInteger(1, 4)
	local points: { Vector3 } = {}
	for i = 1, count do
		local along = (i - (count + 1) / 2) * RaidData.SPAWN_SPACING
		local point: Vector3
		if side == 1 then
			point = Vector3.new(edge, 0, math.clamp(centre.Z + along, -edge, edge))
		elseif side == 2 then
			point = Vector3.new(-edge, 0, math.clamp(centre.Z + along, -edge, edge))
		elseif side == 3 then
			point = Vector3.new(math.clamp(centre.X + along, -edge, edge), 0, edge)
		else
			point = Vector3.new(math.clamp(centre.X + along, -edge, edge), 0, -edge)
		end
		table.insert(points, Navigation.Snap(grid, point))
	end
	return points
end

local function startRaid(player: Player, session: Session, now: number): Raid?
	local context = session.Context
	local data = context.Data
	local townHall = getTownHall(data)
	if not townHall or context.Raid then
		return nil
	end

	-- They leave at dawn; a raid forced in the daytime gets a fixed time instead
	local morning = DayCycle.GetNextMorning(now)
	local retreatAt = if DayCycle.IsNight(now) and morning - now >= RaidData.MIN_NIGHT_LEFT
		then morning
		else now + RaidData.FORCED_RAID_TIME

	local level = townHall.Level
	local raid = Raiders.New(level, retreatAt, retreatAt + RaidData.RETREAT_TIME, context.Grid.Key)
	local size = RaidData.GetRaidSize(level, #data.Colonists)
	local health = RaidData.GetRaiderHealth(level)
	for _, point in getSpawnPoints(context, townHall, size) do
		Raiders.Add(raid, point, health, now)
	end
	context.Raid = raid

	-- The next raid is scheduled now, so one cut short by leaving doesn't come straight back
	local schedule = getSchedule(data)
	schedule.NextDay = DayCycle.GetDay(now)
		+ context.Random:NextInteger(RaidData.MIN_DAYS_BETWEEN, RaidData.MAX_DAYS_BETWEEN)
	saveCarried(schedule, raid)

	setAttribute(player, true)
	announce(context, `{size} raiders are attacking! They're after the Town Hall storage.`)
	return raid
end

local function endRaid(player: Player, session: Session, raid: Raid)
	local context = session.Context
	context.Raid = nil
	saveCarried(getSchedule(context.Data), nil)
	setAttribute(player, false)

	local stolen: { MailItem } = {}
	for id, quantity in raid.Stolen do
		table.insert(stolen, { UniqueID = id, Quantity = quantity })
	end
	table.sort(stolen, function(a, b)
		return a.UniqueID < b.UniqueID
	end)
	local lost = raid.ColonistsLost
	local parts = {
		`{raid.Killed} of {raid.Total} raiders struck down`,
		if lost == 1 then "1 colonist lost" else `{lost} colonists lost`,
		if #stolen > 0 then `stolen: {MailboxData.DescribeItems(stolen)}` else "nothing was stolen",
	}
	announce(context, `The raid is over: {table.concat(parts, ", ")}.`)
	sendState(player, raid, false)
end

-------- Raiders --------

-- A raider died: what it carried goes back to the storage
local function onKilled(context: Context, raid: Raid, raider: Raider)
	raid.Killed += 1
	raid.Dirty = true
	if #raider.Loot > 0 then
		local loot = raider.Loot
		raider.Loot = {}
		giveBack(context, loot)
		announce(
			context,
			`A raider was struck down and dropped {MailboxData.DescribeItems(loot)}. It's back in storage.`
		)
	end
end

-- A raider got away: what it carried is gone
local function onEscaped(raid: Raid, raider: Raider)
	raid.Escaped += 1
	raid.Dirty = true
	for _, item in raider.Loot do
		raid.Stolen[item.UniqueID] = (raid.Stolen[item.UniqueID] or 0) + item.Quantity
	end
	raider.Loot = {}
end

-- Takes stacks out of the Town Hall storage; false when there was nothing to take
local function steal(context: Context, raid: Raid, raider: Raider): boolean
	local storage = context.Data.Storage
	for _ = 1, RaidData.STACKS_PER_RAIDER do
		-- Bags kept in the storage aren't worth carrying
		local candidates: { number } = {}
		for index, stack in storage.Items do
			if not ItemsList.GetMetadata(stack.UniqueID).isBag then
				table.insert(candidates, index)
			end
		end
		if #candidates == 0 then
			break
		end
		local index = candidates[context.Random:NextInteger(1, #candidates)]
		local stack = table.remove(storage.Items, index)
		if stack then
			table.insert(raider.Loot, { UniqueID = stack.UniqueID, Quantity = stack.Quantity })
		end
	end
	if #raider.Loot == 0 then
		return false
	end
	raid.Dirty = true
	context.Log(`A raider took {MailboxData.DescribeItems(raider.Loot)} from the storage`)
	context.SyncColony()
	return true
end

-- A raider's swing lands on a colonist; Guards shrug part of it off. Returns true when it killed.
local function hit(player: Player, context: Context, raid: Raid, agent: Agent): boolean
	local colonist = agent.Colonist
	local damage = RaidData.GetRaiderDamage(raid.Level)
	if colonist.Job == RaidData.GUARD_JOB then
		damage *= 1 - RaidData.GetGuardBlock(colonist.Skills)
	end
	colonist.Health -= damage
	if colonist.Health > 0 then
		return false
	end
	context.Log(`{colonist.Name} was killed by raiders`)
	if ColonistController.Kill(player, colonist.Id) then
		raid.ColonistsLost += 1
	end
	return true
end

-- Raiders leave children alone, and those already walking out of the colony
local function canAttack(agent: Agent): boolean
	local colonist = agent.Colonist
	return colonist.Health > 0 and colonist.Age == "Adult" and not colonist.Leaving
end

-- The colonist it's fighting, if that still makes sense
local function getTarget(raider: Raider, agents: { [number]: Agent }): Agent?
	local id = raider.TargetId
	if not id then
		return nil
	end
	local agent = agents[id]
	-- A Guard that stopped defending (wounded, raid mode over) is let go
	if
		not agent
		or not canAttack(agent)
		or (raider.Engaged and agent.Blackboard.Mode ~= "Defend")
	then
		Raiders.ClearTarget(raider)
		return nil
	end
	return agent
end

-- The closest colonist a raider may attack within `radius` studs
local function findColonist(
	agents: { [number]: Agent },
	position: Vector3,
	radius: number,
	now: number
): Agent?
	local nearest: Agent? = nil
	local nearestDistance = radius
	for _, agent in agents do
		if canAttack(agent) then
			local distance = flatDistance(Agent.GetPosition(agent, now), position)
			if distance <= nearestDistance then
				nearest = agent
				nearestDistance = distance
			end
		end
	end
	return nearest
end

local function flee(raider: Raider)
	Raiders.ClearTarget(raider)
	raider.Goal = "Flee"
	raider.BusyUntil = 0
end

-- Stands and swings at its target, or runs after it
local function fight(
	player: Player,
	context: Context,
	raid: Raid,
	raider: Raider,
	target: Agent,
	position: Vector3,
	now: number
)
	local targetPosition = Agent.GetPosition(target, now)
	local distance = flatDistance(targetPosition, position)

	if distance <= RaidData.RAIDER_REACH then
		raider.Heading = nil
		raider.ChaseTo = nil
		Raiders.Stop(raid, raider, "Attack", targetPosition, now)
		if now >= raider.NextAttack then
			raider.NextAttack = now + RaidData.RAIDER_ATTACK_INTERVAL
			if hit(player, context, raid, target) then
				Raiders.ClearTarget(raider)
			end
		end
		return
	end

	-- It lets go of a Guard that got too far away, and of prey once it gives up the hunt
	local limit = if raider.Engaged then RaidData.LEASH else RaidData.HUNT_RADIUS
	if distance > limit or (not raider.Engaged and now >= raider.Until) then
		Raiders.ClearTarget(raider)
		return
	end

	local chaseTo = raider.ChaseTo
	local stale = not chaseTo
		or Raiders.HasArrived(raider, now)
		or (chaseTo - targetPosition).Magnitude > RaidData.REPATH_DISTANCE
	if raider.Heading ~= "Chase" or (stale and now >= raider.NextPath) then
		raider.Heading = "Chase"
		raider.ChaseTo = targetPosition
		raider.NextPath = now + RaidData.REPATH_INTERVAL
		Raiders.WalkTo(
			raid,
			context.Grid,
			raider,
			targetPosition,
			RaidData.RAIDER_SPEED,
			"Idle",
			targetPosition,
			now
		)
	end
end

-- One step of a raider's behaviour
local function stepRaider(
	player: Player,
	context: Context,
	raid: Raid,
	raider: Raider,
	agents: { [number]: Agent },
	now: number
)
	local grid = context.Grid
	local position = Raiders.GetPosition(raider, now)

	if raider.Goal == "Flee" then
		if raider.Heading ~= "Edge" then
			raider.Heading = "Edge"
			Raiders.WalkTo(
				raid,
				grid,
				raider,
				Navigation.GetEdge(grid, position),
				RaidData.FLEE_SPEED,
				"Idle",
				nil,
				now
			)
		elseif Raiders.HasArrived(raider, now) then
			raider.Escaped = true
		end
		return
	end

	-- Mid-swing at a colonist it passed
	if now < raider.BusyUntil then
		return
	end

	local target = getTarget(raider, agents)
	if target then
		fight(player, context, raid, raider, target, position, now)
		return
	end

	if raider.Goal == "Advance" then
		-- A colonist within reach on the way gets one swing; a Guard on duty gets a fight
		-- (unless he's wounded and falling back)
		if now >= raider.NextAttack then
			local victim = findColonist(agents, position, RaidData.RAIDER_REACH, now)
			local board = victim and victim.Blackboard
			if victim and board and board.Mode == "Defend" and board.GuardState ~= "Retreat" then
				Raiders.Engage(raider, victim.Colonist.Id)
				return
			elseif victim then
				raider.NextAttack = now + RaidData.RAIDER_ATTACK_INTERVAL
				raider.BusyUntil = now + RaidData.SWING_PAUSE
				raider.Heading = nil
				Raiders.Stop(raid, raider, "Attack", Agent.GetPosition(victim, now), now)
				hit(player, context, raid, victim)
				return
			end
		end

		local townHall = getTownHall(context.Data)
		local door = townHall and Navigation.GetDoor(townHall)
		if not townHall or not door then
			flee(raider)
			return
		end
		if raider.Heading ~= "Storage" then
			raider.Heading = "Storage"
			local offset = ((raider.Id % 5) - 2) * DOOR_SPACING
			Raiders.WalkTo(
				raid,
				grid,
				raider,
				Navigation.Snap(grid, door + Vector3.new(offset, 0, 0)),
				RaidData.RAIDER_SPEED,
				"Idle",
				Navigation.GetCentre(townHall),
				now
			)
		elseif Raiders.HasArrived(raider, now) then
			raider.Goal = "Steal"
			raider.Heading = "Steal"
			raider.Until = now + RaidData.STEAL_TIME
			Raiders.Stop(raid, raider, "Work", Navigation.GetCentre(townHall), now)
			if not raid.StealAnnounced then
				raid.StealAnnounced = true
				announce(context, "Raiders are breaking into the Town Hall storage!")
			end
		end
	elseif raider.Goal == "Steal" then
		-- A fight pulled it away from the door: walk back and start over
		if raider.Heading ~= "Steal" then
			raider.Goal = "Advance"
			return
		end
		if now < raider.Until then
			return
		end
		if steal(context, raid, raider) then
			flee(raider)
		else
			-- Nothing to take: they go after the colonists for a while instead
			raider.Goal = "Hunt"
			raider.Heading = nil
			raider.Until = now + RaidData.HUNT_TIME
		end
	elseif raider.Goal == "Hunt" then
		local prey = if now < raider.Until
			then findColonist(agents, position, RaidData.HUNT_RADIUS, now)
			else nil
		if not prey then
			flee(raider)
			return
		end
		raider.TargetId = prey.Colonist.Id
		raider.Engaged = false
	end
end

-- Advances a raid; returns false once it's over
local function stepRaid(
	player: Player,
	session: Session,
	raid: Raid,
	agents: { [number]: Agent },
	now: number
): boolean
	local context = session.Context

	-- Buildings changed: paths made for the old layout may cross the new one
	if raid.GridKey ~= context.Grid.Key then
		raid.GridKey = context.Grid.Key
		for _, raider in raid.Raiders do
			raider.Heading = nil
			raider.ChaseTo = nil
		end
	end

	if not raid.Retreating and now >= raid.RetreatAt then
		raid.Retreating = true
		for _, raider in raid.Raiders do
			if Raiders.IsActive(raider) and raider.Goal ~= "Flee" then
				flee(raider)
			end
		end
		if Raiders.CountActive(raid) > 0 then
			announce(context, "Dawn is breaking. The raiders are retreating!")
		end
	end

	local lootChanged = false
	for id, raider in raid.Raiders do
		local carrying = #raider.Loot > 0
		if not raider.Dead then
			stepRaider(player, context, raid, raider, agents, now)
			-- Anyone still on the plot when time runs out slips away
			if now >= raid.EndsAt then
				raider.Escaped = true
			end
		end
		if raider.Dead then
			onKilled(context, raid, raider)
			raid.Raiders[id] = nil
		elseif raider.Escaped then
			onEscaped(raid, raider)
			raid.Raiders[id] = nil
		end
		if carrying ~= (raid.Raiders[id] ~= nil and #raider.Loot > 0) then
			lootChanged = true
		end
	end
	if lootChanged then
		saveCarried(getSchedule(context.Data), raid)
	end

	if next(raid.Raiders) == nil then
		endRaid(player, session, raid)
		return false
	end

	if next(raid.ChangedMotions) then
		local motions = {}
		for raiderId, motion in raid.ChangedMotions do
			if raid.Raiders[raiderId] then
				table.insert(motions, motion)
			end
		end
		table.clear(raid.ChangedMotions)
		if #motions > 0 then
			Net:RemoteEvent("RaidMotions"):FireClient(player, motions)
		end
	end
	if raid.Dirty then
		raid.Dirty = false
		sendState(player, raid, true)
	end
	return true
end

-- Runs with the colonists' tick (ColonistController.OnStep)
local function step(
	player: Player,
	context: Context,
	agents: { [number]: Agent },
	_deltaTime: number,
	now: number
)
	local existing = sessions[player]
	local session: Session = if existing and existing.Context == context
		then existing
		else openSession(player, context, now)
	sessions[player] = session

	local data = context.Data
	local schedule = getSchedule(data)
	local today = DayCycle.GetDay(now)
	schedule.SeenDay = today

	local raid = context.Raid
	if raid then
		stepRaid(player, session, raid, agents, now)
		return
	end

	-- Raids only come to a colony worth raiding
	if not getTownHall(data) or #data.Colonists < RaidData.MIN_COLONISTS then
		return
	end
	if schedule.NextDay <= 0 then
		schedule.NextDay = today + RaidData.FIRST_RAID_DAYS
		return
	end
	if today < schedule.NextDay then
		return
	end

	if DayCycle.IsNight(now) then
		-- Too close to dawn (the player just arrived): they come the next night instead
		if DayCycle.GetNextMorning(now) - now >= RaidData.MIN_NIGHT_LEFT then
			startRaid(player, session, now)
		end
	elseif DayCycle.GetClockTime(now) >= RaidData.WARN_HOUR and session.WarnedDay ~= today then
		session.WarnedDay = today
		announce(context, "Raiders have been spotted nearby. They will attack tonight!")
	end
end

-------- The player --------

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return if root and root:IsA("BasePart") then root else nil
end

-- Damage of the player's swing: the held weapon's, a gathering tool's, or bare hands
local function getPlayerDamage(player: Player): number
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return RaidData.BARE_HANDS_DAMAGE
	end
	local itemType = tool:GetAttribute("ItemType")
	local itemId = if typeof(itemType) == "string" then ItemsList.GetItemId(itemType) else nil
	local damage = if itemId then ItemsList.GetMetadata(itemId).Damage else nil
	if damage then
		return damage
	end
	local toolId = tool:GetAttribute("ToolId")
	local info = if typeof(toolId) == "string" then ResourceData.TOOLS[toolId] else nil
	return (info and RaidData.TOOL_DAMAGE[info.Type]) or RaidData.BARE_HANDS_DAMAGE
end

-- "AttackRaider": the player swings at a raider next to their character
local function onAttack(player: Player, raiderId: unknown): (boolean, string)
	if typeof(raiderId) ~= "number" or raiderId ~= raiderId then
		return false, "Raider not found"
	end
	local session = sessions[player]
	local raid = session and session.Context.Raid
	local raider = raid and raid.Raiders[raiderId]
	if not raid or not raider or not Raiders.IsActive(raider) then
		return false, "Raider not found"
	end

	local now = workspace:GetServerTimeNow()
	local last = lastAttack[player]
	if last and now - last < RaidData.PLAYER_ATTACK_COOLDOWN then
		return false, "Not ready yet"
	end

	local root = getRoot(player)
	if not root then
		return false, "Too far away"
	end
	local position = PlotData.SURFACE * Raiders.GetPosition(raider, now)
	if
		flatDistance(root.Position, position) > RaidData.PLAYER_REACH + RaidData.REACH_TOLERANCE
		or math.abs(root.Position.Y - position.Y) > MAX_HEIGHT_GAP
	then
		return false, "Too far away"
	end

	lastAttack[player] = now
	Raiders.Damage(raid, raider, getPlayerDamage(player))
	return true, ""
end

-------- Testing --------

-- Testing: raiders attack now, whatever the time of day. Needs a placed Town Hall.
function RaidController.ForceRaid(player: Player): (boolean, string)
	local session = sessions[player]
	if not session then
		return false, "Colony not loaded"
	end
	if session.Context.Raid then
		return false, "A raid is already going on"
	end
	local raid = startRaid(player, session, workspace:GetServerTimeNow())
	if not raid then
		return false, "Place the Town Hall first"
	end
	return true, `Raid started with {raid.Total} raiders`
end

-- Testing: calls the raid off now. Raiders still on the plot vanish and what they carry goes
-- back to the storage.
function RaidController.EndRaid(player: Player): (boolean, string)
	local session = sessions[player]
	local raid = session and session.Context.Raid
	if not session or not raid then
		return false, "No raid is going on"
	end
	local carried: { MailItem } = {}
	for _, raider in raid.Raiders do
		for _, item in raider.Loot do
			table.insert(carried, item)
		end
	end
	raid.Raiders = {}
	if #carried > 0 then
		giveBack(session.Context, carried)
	end
	endRaid(player, session, raid)
	return true, "Raid ended"
end

-- Testing: schedules the next raid for the coming night (the dusk warning shows as usual)
function RaidController.ScheduleTonight(player: Player): (boolean, string)
	local data = ColonyController.GetData(player)
	if not data then
		return false, "Colony not loaded"
	end
	local now = workspace:GetServerTimeNow()
	getSchedule(data).NextDay = DayCycle.GetDay(now)
	return true, "Raiders will come tonight (with a Town Hall and enough colonists)"
end

-- Where the player's raid schedule stands, for the testing command
function RaidController.Describe(player: Player): string
	local data = ColonyController.GetData(player)
	if not data then
		return "Colony not loaded"
	end
	local session = sessions[player]
	local raid = session and session.Context.Raid
	if raid then
		return `Raid in progress: {Raiders.CountActive(raid)} of {raid.Total} raiders left`
	end
	local schedule = getSchedule(data)
	local today = DayCycle.GetDay(workspace:GetServerTimeNow())
	if schedule.NextDay <= 0 then
		return "No raid scheduled yet"
	end
	return `Next raid on the night of day {schedule.NextDay + 1} (today is day {today + 1})`
end

-- True while raiders are on the player's plot
function RaidController.IsActive(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Context.Raid ~= nil
end

function RaidController.Start()
	if started then
		return
	end
	started = true

	Net:RemoteEvent("RaidState")
	Net:RemoteEvent("RaidMotions")
	Net:Handle("GetRaid", function(player: Player): any
		local session = sessions[player]
		local raid = session and session.Context.Raid
		if not raid then
			return nil
		end
		return { State = Raiders.GetState(raid, true), Motions = Raiders.GetMotions(raid) }
	end)
	Net:Handle("AttackRaider", onAttack)

	ColonistController.OnStep(step)

	-- Testing hook: setting the player attribute "DebugRaid" to "Start", "End" or "Tonight" on
	-- the server (e.g. from the Studio command bar) forces a raid
	local function watchDebug(player: Player)
		player:GetAttributeChangedSignal("DebugRaid"):Connect(function()
			local command = player:GetAttribute("DebugRaid")
			if command == nil then
				return
			end
			player:SetAttribute("DebugRaid", nil)
			if command == "Start" then
				RaidController.ForceRaid(player)
			elseif command == "End" then
				RaidController.EndRaid(player)
			elseif command == "Tonight" then
				RaidController.ScheduleTonight(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchDebug)
	for _, player in Players:GetPlayers() do
		watchDebug(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		lastAttack[player] = nil
	end)
end

return RaidController
