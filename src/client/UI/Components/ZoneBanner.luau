--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const TweenService = game:GetService("TweenService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const WildAreaData = require(Shared.Wilds.WildAreaData)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const ZoneStore = require(script.Parent.Parent.Parent.Colony.ZoneStore)
const attributeSource = require(script.Parent.Parent.attributeSource)

const create = vide.create
const source = vide.source
const effect = vide.effect
const cleanup = vide.cleanup

type ZoneId = ZoneStore.ZoneId

const FADE_IN = 0.6
const HOLD = 2.5
const FADE_OUT = 0.8
-- Below the placement hint at the top centre
const TOP_OFFSET = 64
const COLONY_COLOR = Color3.fromRGB(255, 236, 190)
const WILDS_COLOR = Color3.fromRGB(205, 240, 200)
const SUBTITLE_COLOR = Color3.fromRGB(225, 225, 215)

-- Large title + subtitle that fade in at the top of the screen when entering a zone
local function ZoneBanner()
	ZoneStore.Start()

	local townHallLevel = attributeSource("TownHallLevel")
	-- Zone the banner is (or was last) showing; kept while fading out
	local shown = source(nil :: ZoneId?)
	local transparency = source(1)

	local title = function(): string
		local zone = shown()
		if zone == "Colony" then
			return ColonyStore.Name() or "Your colony"
		end
		local area = WildAreaData.Get(zone)
		return if area then area.Name else ""
	end

	local subtitle = function(): string
		local zone = shown()
		if zone == "Colony" then
			if not BuildingUnlocks.IsTownHallBuilt(ColonyStore.Buildings()) then
				local builderHut = ColonyStore.GetBuilding("BuilderHut")
				return if builderHut and builderHut.Level >= 1
					then "Build your Town Hall to settle"
					else "Build a Builder's Hut to get started"
			end
			return `Town Hall level {townHallLevel() or 0}`
		end
		local area = WildAreaData.Get(zone)
		return if area then `The Wilds · {area.Description}` else ""
	end

	-- One NumberValue drives every transparency so text, stroke and divider fade together
	local fade = Instance.new("NumberValue")
	fade.Value = 1
	local tween: Tween? = nil
	local holdThread: thread? = nil

	local function fadeTo(target: number, time: number)
		if tween then
			tween:Cancel()
		end
		local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local nextTween = TweenService:Create(fade, info, { Value = target })
		tween = nextTween
		nextTween:Play()
	end

	local connection = fade:GetPropertyChangedSignal("Value"):Connect(function()
		transparency(fade.Value)
	end)
	cleanup(function()
		connection:Disconnect()
		if holdThread then
			task.cancel(holdThread)
		end
		if tween then
			tween:Cancel()
		end
		fade:Destroy()
	end)

	-- Show on every zone change; leaving to no zone lets the current banner finish
	effect(function()
		local zone = ZoneStore.Zone()
		if not zone then
			return
		end
		shown(zone)
		if holdThread then
			task.cancel(holdThread)
		end
		fadeTo(0, FADE_IN)
		holdThread = task.delay(FADE_IN + HOLD, function()
			holdThread = nil
			fadeTo(1, FADE_OUT)
		end)
	end)

	-- Partly transparent elements fade from their own resting transparency
	local function faded(resting: number): () -> number
		return function()
			return resting + (1 - resting) * transparency()
		end
	end

	return create("Frame")({
		Name = "ZoneBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP_OFFSET),
		Size = UDim2.fromOffset(720, 92),
		BackgroundTransparency = 1,
		Visible = function()
			return transparency() < 1
		end,

		create("TextLabel")({
			Name = "Title",
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 42,
			TextColor3 = function()
				return if shown() == "Colony" then COLONY_COLOR else WILDS_COLOR
			end,
			TextTransparency = transparency,
			Text = title,

			create("UIStroke")({
				Thickness = 2,
				Color = Color3.new(0, 0, 0),
				Transparency = faded(0.4),
			}),
		}),

		create("Frame")({
			Name = "Divider",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 56),
			Size = UDim2.fromOffset(320, 2),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = faded(0.2),

			-- Soft ends
			create("UIGradient")({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),

		create("TextLabel")({
			Name = "Subtitle",
			Position = UDim2.fromOffset(0, 62),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = 20,
			TextColor3 = SUBTITLE_COLOR,
			TextTransparency = transparency,
			Text = subtitle,

			create("UIStroke")({
				Thickness = 1.5,
				Color = Color3.new(0, 0, 0),
				Transparency = faded(0.5),
			}),
		}),
	})
end

return ZoneBanner
