--!strict

-- "Spire": from the player's Spire to a wild area. "Home": back beside the Spire.
export type TravelKind = "Spire" | "Home"

-- Server -> owner client "SpireTravel" payload; the client plays the sequence then fires "SpireTravelDone"(Token)
export type TravelInfo = {
	Token: number,
	Kind: TravelKind,
	-- Where the HumanoidRootPart ends up (server-picked, already streaming)
	Destination: CFrame,
}

const MAX_LEVEL = 3

-- The Spire's level follows the Town Hall's
local function getLevel(townHallLevel: number): number
	return math.clamp(townHallLevel, 1, MAX_LEVEL)
end

-- Cinematic travel: seconds (_TIME) and studs. Spire: light up -> float to the top -> launch -> drop.
-- Return home skips the Spire: charge in place -> launch -> drop beside the Spire.
const TRAVEL = {
	-- Spire glows and its beam shoots up while the player lifts off the ground
	LIGHT_UP_TIME = 1,
	LIFT_HEIGHT = 3,
	-- Glide to just above the top middle of the Spire
	FLOAT_TIME = 1.5,
	FLOAT_CLEARANCE = 4,
	-- Return home: beam at the player instead of the Spire
	HOME_CHARGE_TIME = 0.8,
	-- Straight up, very fast
	LAUNCH_TIME = 0.6,
	LAUNCH_HEIGHT = 350,
	-- Screen flash that covers the jump across the map
	HANG_TIME = 0.15,
	-- Arrive this high above the landing spot, drop fast, then brake to a stop
	SKY_HEIGHT = 150,
	DROP_TIME = 0.45,
	BRAKE_HEIGHT = 8,
	BRAKE_TIME = 0.3,
	-- Max seconds to hover while the landing ground streams in
	GROUND_WAIT = 3,
	BEAM_HEIGHT = 1200,
	BEAM_WIDTH = 6,
	FOV_KICK = 25,
	-- Server: horizontal studs from the destination that count as arrived
	ARRIVAL_TOLERANCE = 40,
	-- Server: extra seconds past the sequence before it moves the player itself
	TIMEOUT_GRACE = 5,
}

const AFTER_LAUNCH_TIME = TRAVEL.LAUNCH_TIME
	+ TRAVEL.HANG_TIME
	+ TRAVEL.DROP_TIME
	+ TRAVEL.BRAKE_TIME

-- Seconds before launch (the HUD's channel bar), by travel kind
local function getChannelTime(kind: TravelKind): number
	return if kind == "Home"
		then TRAVEL.HOME_CHARGE_TIME
		else TRAVEL.LIGHT_UP_TIME + TRAVEL.FLOAT_TIME
end

-- Seconds the whole sequence takes, not counting a wait for the ground to stream in
local function getTravelTime(kind: TravelKind): number
	return getChannelTime(kind) + AFTER_LAUNCH_TIME
end

return {
	MAX_LEVEL = MAX_LEVEL,
	-- Seconds before launch from the Spire (HUD fallback when TeleportChannelTime isn't set)
	CHANNEL_TIME = getChannelTime("Spire"),
	-- Seconds between teleports (Spire and return home share it)
	COOLDOWN = 10,
	-- Horizontal studs from the Spire's base to use it
	USE_RANGE = 30,
	TRAVEL = TRAVEL,
	GetLevel = getLevel,
	GetChannelTime = getChannelTime,
	GetTravelTime = getTravelTime,
}
