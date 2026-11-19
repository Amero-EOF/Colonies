--!strict

-- The day/night cycle is a pure function of server time, so the server and every client agree
-- without replicating it. Clock hours: 0-24. Daytime (NIGHT_END -> NIGHT_START) and night tick at
-- different rates, so an in-game hour lasts longer by day than by night.

-- Speeds up time: shortens the day and night and speeds up colonists to match (1 = normal).
-- A constant, since changing it at runtime would jump the clock.
const TIME_SCALE = 5
-- Seconds of daytime and night at TIME_SCALE 1
const BASE_DAYTIME_LENGTH = 600
const BASE_NIGHT_LENGTH = BASE_DAYTIME_LENGTH * 0.25
-- Clock hour at server time 0 (must be daytime)
const START_HOUR = 8
const NIGHT_START = 20
const NIGHT_END = 6

const DAYTIME_LENGTH = BASE_DAYTIME_LENGTH / TIME_SCALE
const NIGHT_LENGTH = BASE_NIGHT_LENGTH / TIME_SCALE
const DAY_LENGTH = DAYTIME_LENGTH + NIGHT_LENGTH
const DAYTIME_HOURS = NIGHT_START - NIGHT_END
const NIGHT_HOURS = 24 - DAYTIME_HOURS
-- Seconds from the first morning to server time 0
const START_OFFSET = (START_HOUR - NIGHT_END) / DAYTIME_HOURS * DAYTIME_LENGTH

const DayCycle = {}

DayCycle.TIME_SCALE = TIME_SCALE
-- Seconds per full day and night
DayCycle.DAY_LENGTH = DAY_LENGTH
DayCycle.DAYTIME_LENGTH = DAYTIME_LENGTH
DayCycle.NIGHT_LENGTH = NIGHT_LENGTH
DayCycle.NIGHT_START = NIGHT_START
DayCycle.NIGHT_END = NIGHT_END

-- Seconds for a number of in-game hours, averaged over the whole day; for long spans (days,
-- regrowth). Use DaytimeHours/NightHours for spans that fall within the day or the night.
function DayCycle.Hours(hours: number): number
	return hours * DAY_LENGTH / 24
end

-- Seconds for a number of daytime hours
function DayCycle.DaytimeHours(hours: number): number
	return hours * DAYTIME_LENGTH / DAYTIME_HOURS
end

-- Seconds for a number of night hours
function DayCycle.NightHours(hours: number): number
	return hours * NIGHT_LENGTH / NIGHT_HOURS
end

-- A speed (studs/second at TIME_SCALE 1) scaled with time, so walks take the same in-game time
function DayCycle.Speed(baseSpeed: number): number
	return baseSpeed * TIME_SCALE
end

-- In-game hours since the first morning (NIGHT_END of day 0)
function DayCycle.GetTotalHours(serverTime: number): number
	local seconds = serverTime + START_OFFSET
	local day = math.floor(seconds / DAY_LENGTH)
	local into = seconds - day * DAY_LENGTH
	local hours = if into < DAYTIME_LENGTH
		then into / DAYTIME_LENGTH * DAYTIME_HOURS
		else DAYTIME_HOURS + (into - DAYTIME_LENGTH) / NIGHT_LENGTH * NIGHT_HOURS
	return day * 24 + hours
end

-- Server time at a number of in-game hours since the first morning (inverse of GetTotalHours)
function DayCycle.GetTimeAtHours(totalHours: number): number
	local day = math.floor(totalHours / 24)
	local hours = totalHours - day * 24
	local into = if hours < DAYTIME_HOURS
		then hours / DAYTIME_HOURS * DAYTIME_LENGTH
		else DAYTIME_LENGTH + (hours - DAYTIME_HOURS) / NIGHT_HOURS * NIGHT_LENGTH
	return day * DAY_LENGTH + into - START_OFFSET
end

-- In-game hours that pass between two server times
function DayCycle.HoursBetween(from: number, to: number): number
	return DayCycle.GetTotalHours(to) - DayCycle.GetTotalHours(from)
end

function DayCycle.GetClockTime(serverTime: number): number
	return (NIGHT_END + DayCycle.GetTotalHours(serverTime) % 24) % 24
end

function DayCycle.IsNight(serverTime: number): boolean
	return DayCycle.GetTotalHours(serverTime) % 24 >= DAYTIME_HOURS
end

-- Increases by one every morning (at NIGHT_END)
function DayCycle.GetDay(serverTime: number): number
	return math.floor(DayCycle.GetTotalHours(serverTime) / 24)
end

-- Server time of the next morning
function DayCycle.GetNextMorning(serverTime: number): number
	return DayCycle.GetTimeAtHours((DayCycle.GetDay(serverTime) + 1) * 24)
end

return DayCycle
