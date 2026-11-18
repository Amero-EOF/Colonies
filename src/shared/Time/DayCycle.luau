--!strict

-- The day/night cycle is a pure function of server time, so the server and every client agree
-- without replicating it. Clock hours: 0-24.
-- Seconds per full day and night
const DAY_LENGTH = 180
-- Clock hour at server time 0
const START_HOUR = 8
const NIGHT_START = 20
const NIGHT_END = 6

const DayCycle = {}

DayCycle.DAY_LENGTH = DAY_LENGTH
-- Seconds per in-game hour
DayCycle.HOUR_LENGTH = DAY_LENGTH / 24
DayCycle.NIGHT_START = NIGHT_START
DayCycle.NIGHT_END = NIGHT_END

-- Seconds for a number of in-game hours; tune anything tied to the day in hours so it scales with DAY_LENGTH
function DayCycle.Hours(hours: number): number
	return hours * DAY_LENGTH / 24
end

function DayCycle.GetClockTime(serverTime: number): number
	return (START_HOUR + (serverTime % DAY_LENGTH) / DAY_LENGTH * 24) % 24
end

function DayCycle.IsNight(serverTime: number): boolean
	local hour = DayCycle.GetClockTime(serverTime)
	return hour >= NIGHT_START or hour < NIGHT_END
end

-- Increases by one every morning (at NIGHT_END)
function DayCycle.GetDay(serverTime: number): number
	local hoursSinceMorning = serverTime / DAY_LENGTH * 24 + START_HOUR - NIGHT_END
	return math.floor(hoursSinceMorning / 24)
end

-- Server time of the next morning
function DayCycle.GetNextMorning(serverTime: number): number
	local nextDay = DayCycle.GetDay(serverTime) + 1
	return (nextDay * 24 - START_HOUR + NIGHT_END) / 24 * DAY_LENGTH
end

return DayCycle
