--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const DayCycle = require(Shared.Time.DayCycle)

const create = vide.create
const source = vide.source
const cleanup = vide.cleanup

-- Clock minutes shown in steps of this many (a game hour lasts a few real seconds)
const MINUTE_STEP = 10

local function getText(now: number): string
	local hour = DayCycle.GetClockTime(now)
	local minutes = math.floor(hour % 1 * 60 / MINUTE_STEP) * MINUTE_STEP
	local phase = if DayCycle.IsNight(now) then "Night" else "Day"
	return string.format(
		"%s %d   %02d:%02d",
		phase,
		DayCycle.GetDay(now) + 1,
		math.floor(hour),
		minutes
	)
end

-- Day number and time of day, top right
local function Clock()
	local text = source(getText(workspace:GetServerTimeNow()))
	local connection = RunService.Heartbeat:Connect(function()
		local current = getText(workspace:GetServerTimeNow())
		if current ~= text() then
			text(current)
		end
	end)
	cleanup(function()
		connection:Disconnect()
	end)

	return create("TextLabel")({
		Name = "Clock",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 8),
		Size = UDim2.fromOffset(150, 30),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.3,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 16,
		Font = Enum.Font.GothamMedium,
		Text = text,

		create("UICorner")({}),
	})
end

return Clock
