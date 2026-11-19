--!strict

const RunService = game:GetService("RunService")

-- Springy "pop" for a freshly built part: it grows from a fraction of its size about its centre and
-- overshoots a little before settling
const START_SCALE = 0.2
-- Spring constants (angular frequency ~15 rad/s, damping ratio ~0.35)
const STIFFNESS = 220
const DAMPING = 10
-- Settled once this close to rest
const EPSILON = 0.002
-- Longest a spring runs; also the step cap so a hitch can't blow it up
const MAX_TIME = 2
const MAX_STEP = 1 / 60

type Spring = {
	Size: Vector3,
	CFrame: CFrame,
	Scale: number,
	Velocity: number,
	Elapsed: number,
}

const PartSpring = {}

const active: { [BasePart]: Spring } = {}
local connection: RBXScriptConnection? = nil

local function apply(part: BasePart, spring: Spring)
	part.Size = spring.Size * math.max(spring.Scale, 0.01)
	part.CFrame = spring.CFrame
end

local function step(deltaTime: number)
	for part, spring in active do
		if not part.Parent then
			active[part] = nil
			continue
		end
		spring.Elapsed += deltaTime
		local remaining = deltaTime
		while remaining > 0 do
			local dt = math.min(remaining, MAX_STEP)
			remaining -= dt
			local acceleration = -STIFFNESS * (spring.Scale - 1) - DAMPING * spring.Velocity
			spring.Velocity += acceleration * dt
			spring.Scale += spring.Velocity * dt
		end
		local settled = math.abs(spring.Scale - 1) < EPSILON and math.abs(spring.Velocity) < EPSILON
		if settled or spring.Elapsed >= MAX_TIME then
			spring.Scale = 1
			active[part] = nil
		end
		apply(part, spring)
	end

	if next(active) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Pops `part` in from small; restarts the pop if it's already springing
function PartSpring.Play(part: BasePart)
	local current = active[part]
	local spring: Spring = {
		Size = if current then current.Size else part.Size,
		CFrame = if current then current.CFrame else part.CFrame,
		Scale = START_SCALE,
		Velocity = 0,
		Elapsed = 0,
	}
	active[part] = spring
	apply(part, spring)
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

return PartSpring
