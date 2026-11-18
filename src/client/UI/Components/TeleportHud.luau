--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const UserInputService = game:GetService("UserInputService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const SpireData = require(Shared.Spire.SpireData)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const attributeSource = require(script.Parent.Parent.attributeSource)

const create = vide.create
const source = vide.source
const cleanup = vide.cleanup

const RETURN_KEY = Enum.KeyCode.H
const TEXT_COLOR = Color3.new(1, 1, 1)

-- Return home button (H) plus the teleport channel bar and cooldown
local function TeleportHud()
	local channelEnd = attributeSource("TeleportChannelEnd")
	-- Seconds before launch; differs between Spire travel and return home
	local channelTime = attributeSource("TeleportChannelTime")
	local readyAt = attributeSource("TeleportReadyAt")
	local now = source(workspace:GetServerTimeNow())
	local message = ColonyStore.Message

	local function returnHome()
		task.spawn(function()
			local ok, result = Net:Invoke("ReturnHome")
			if not ok then
				ColonyStore.Notify(tostring(result))
			end
		end)
	end

	local connections = {
		RunService.RenderStepped:Connect(function()
			now(workspace:GetServerTimeNow())
		end),

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and input.KeyCode == RETURN_KEY then
				returnHome()
			end
		end),
	}

	cleanup(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)

	local channelling = function(): boolean
		local ends = channelEnd()
		return ends ~= nil and ends > now()
	end

	local cooldownLeft = function(): number
		local ready = readyAt()
		return if ready then math.max(math.ceil(ready - now()), 0) else 0
	end

	return create("Frame")({
		Name = "TeleportHud",
		AnchorPoint = Vector2.new(0, 1),
		-- Sits above the Build button
		Position = UDim2.new(0, 16, 1, -64),
		Size = UDim2.fromOffset(220, 100),
		BackgroundTransparency = 1,

		create("TextLabel")({
			Name = "Message",
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			TextColor3 = TEXT_COLOR,
			TextStrokeTransparency = 0.4,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = message,
			Visible = function()
				return message() ~= ""
			end,
		}),

		create("Frame")({
			Name = "ChannelBar",
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BackgroundTransparency = 0.2,
			Visible = channelling,

			create("UICorner")({}),

			create("Frame")({
				Name = "Fill",
				BackgroundColor3 = Color3.fromRGB(150, 110, 230),
				Size = function()
					local remaining = (channelEnd() or 0) - now()
					local total = channelTime() or SpireData.CHANNEL_TIME
					return UDim2.fromScale(math.clamp(1 - remaining / total, 0, 1), 1)
				end,

				create("UICorner")({}),
			}),
		}),

		create("TextButton")({
			Name = "ReturnHome",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = Color3.fromRGB(70, 55, 120),
			TextColor3 = TEXT_COLOR,
			TextSize = 18,
			Text = function()
				local left = cooldownLeft()
				return if left > 0 then `Return home (H) {left}s` else "Return home (H)"
			end,

			Activated = returnHome,

			create("UICorner")({}),
		}),
	})
end

return TeleportHud
