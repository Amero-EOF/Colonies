--!strict

const Lighting = game:GetService("Lighting")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Shared = ReplicatedStorage.Shared

const DayCycle = require(Shared.Time.DayCycle)

-- Hours the sky takes to fade between day and night around NIGHT_START / NIGHT_END
const FADE_HOURS = 1.5
const DAY_BRIGHTNESS = 2
const NIGHT_BRIGHTNESS = 0.4
const DAY_AMBIENT = Color3.fromRGB(128, 128, 128)
const NIGHT_AMBIENT = Color3.fromRGB(45, 55, 95)
const NIGHT_TINT = Color3.fromRGB(170, 185, 255)

-- Drives Lighting from the shared day cycle, so every client sees the same time of day
const DayNight = {}

local started = false

-- 1 in full day, 0 in full night, smooth around dusk and dawn
function DayNight.GetDaylight(hour: number): number
	local dawn = math.clamp((hour - (DayCycle.NIGHT_END - FADE_HOURS / 2)) / FADE_HOURS, 0, 1)
	local dusk = math.clamp(((DayCycle.NIGHT_START + FADE_HOURS / 2) - hour) / FADE_HOURS, 0, 1)
	return math.min(dawn, dusk)
end

function DayNight.Start()
	if started then
		return
	end
	started = true

	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "NightTint"
	tint.Parent = Lighting

	RunService.RenderStepped:Connect(function()
		local hour = DayCycle.GetClockTime(workspace:GetServerTimeNow())
		local daylight = DayNight.GetDaylight(hour)
		Lighting.ClockTime = hour
		Lighting.Brightness = NIGHT_BRIGHTNESS + (DAY_BRIGHTNESS - NIGHT_BRIGHTNESS) * daylight
		Lighting.OutdoorAmbient = NIGHT_AMBIENT:Lerp(DAY_AMBIENT, daylight)
		tint.TintColor = NIGHT_TINT:Lerp(Color3.new(1, 1, 1), daylight)
		tint.Saturation = -0.3 * (1 - daylight)
	end)
end

return DayNight
