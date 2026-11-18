--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const UserInputService = game:GetService("UserInputService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const ResourceData = require(Shared.Resources.ResourceData)

const create = vide.create
const source = vide.source
const cleanup = vide.cleanup

type Props = {
	-- False while something else owns mouse clicks (e.g. building placement)
	Enabled: () -> boolean,
}

const RAY_LENGTH = 500
const MESSAGE_TIME = 2
-- A little extra reach so the server, not the client, decides edge cases
const RANGE_TOLERANCE = 2

const player = Players.LocalPlayer

local function isGatherInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- The resource node under a screen position, if any
local function findNode(position: Vector3): Model?
	local wilds = workspace:FindFirstChild("Wilds")
	local nodes = wilds and wilds:FindFirstChild("Nodes")
	if not nodes then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { nodes }

	local ray = workspace.CurrentCamera:ScreenPointToRay(position.X, position.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)

	local hit: Instance? = result and result.Instance
	while hit and hit.Parent ~= nodes do
		hit = hit.Parent
	end

	return if hit and hit:IsA("Model") then hit else nil
end

local function isInRange(node: Model): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local offset = node:GetPivot().Position - root.Position
	return Vector2.new(offset.X, offset.Z).Magnitude <= ResourceData.GATHER_RANGE + RANGE_TOLERANCE
end

-- Hold the mouse (or a touch) on a tree, rock or bush to gather it
local function Gathering(props: Props)
	local progress = source(0)
	local gathering = source(false)
	local message = source("")

	local target: Model? = nil
	local holding = false
	local started = 0
	local duration = 0
	-- Bumped whenever a gather ends so late server replies are ignored
	local attempt = 0

	local function showMessage(text: string)
		message(text)
		task.delay(MESSAGE_TIME, function()
			if message() == text then
				message("")
			end
		end)
	end

	local function stop()
		attempt += 1
		target = nil
		gathering(false)
		progress(0)
	end

	local function cancel()
		if target then
			Net:RemoteEvent("CancelGather"):FireServer()
		end
		stop()
	end

	local function finish()
		stop()
		task.spawn(function()
			local _, result = Net:Invoke("FinishGather")
			showMessage(tostring(result))
		end)
	end

	local function begin(position: Vector3)
		local node = findNode(position)
		if not node then
			return
		end

		holding = true
		stop()
		local thisAttempt = attempt

		task.spawn(function()
			local ok, result = Net:Invoke("BeginGather", node)
			if thisAttempt ~= attempt or not holding then
				if ok then
					Net:RemoteEvent("CancelGather"):FireServer()
				end
				return
			end

			if not ok or typeof(result) ~= "number" then
				showMessage(tostring(result))
				return
			end

			target = node
			started = os.clock()
			duration = result
			gathering(true)
		end)
	end

	local connections = {
		RunService.RenderStepped:Connect(function()
			local node = target
			if not node then
				return
			end

			if not holding or not node.Parent or not isInRange(node) then
				cancel()
				return
			end

			local alpha = (os.clock() - started) / duration
			progress(math.min(alpha, 1))
			if alpha >= 1 then
				finish()
			end
		end),

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and props.Enabled() and isGatherInput(input) then
				begin(input.Position)
			end
		end),

		UserInputService.InputEnded:Connect(function(input)
			if isGatherInput(input) then
				holding = false
			end
		end),
	}

	cleanup(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)

	return create("Frame")({
		Name = "Gathering",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(320, 56),
		BackgroundTransparency = 1,

		create("TextLabel")({
			Name = "Message",
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.4,
			TextScaled = true,
			Text = message,
			Visible = function()
				return message() ~= ""
			end,
		}),

		create("Frame")({
			Name = "Bar",
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BackgroundTransparency = 0.2,
			Visible = gathering,

			create("UICorner")({}),

			create("Frame")({
				Name = "Fill",
				Size = function()
					return UDim2.fromScale(progress(), 1)
				end,
				BackgroundColor3 = Color3.fromRGB(110, 190, 90),

				create("UICorner")({}),
			}),
		}),
	})
end

return Gathering
