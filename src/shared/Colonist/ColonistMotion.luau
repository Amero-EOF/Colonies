--!strict

const ColonistTypes = require(script.Parent.ColonistTypes)

type Motion = ColonistTypes.Motion

-- Replays a Motion; shared so the server's idea of where a colonist is matches what the client draws
const ColonistMotion = {}

function ColonistMotion.GetLength(path: { Vector3 }): number
	local length = 0
	for i = 2, #path do
		length += (path[i] - path[i - 1]).Magnitude
	end
	return length
end

-- Position, facing direction (unit XZ, may be zero) and whether the path is finished at `now`
function ColonistMotion.Evaluate(motion: Motion, now: number): (Vector3, Vector3, boolean)
	local path = motion.Path
	local travelled = math.max(now - motion.StartTime, 0) * motion.Speed

	for i = 2, #path do
		local from, to = path[i - 1], path[i]
		local segment = (to - from).Magnitude
		if travelled <= segment and segment > 0 then
			local direction = (to - from) / segment
			return from + direction * travelled, direction, false
		end
		travelled -= segment
	end

	local last = path[#path]
	local facing = Vector3.zero
	if motion.LookAt then
		local offset = (motion.LookAt - last) * Vector3.new(1, 0, 1)
		if offset.Magnitude > 0.01 then
			facing = offset.Unit
		end
	elseif #path >= 2 then
		local offset = (last - path[#path - 1]) * Vector3.new(1, 0, 1)
		if offset.Magnitude > 0.01 then
			facing = offset.Unit
		end
	end
	return last, facing, true
end

-- Server time the motion reaches its last point
function ColonistMotion.GetEndTime(motion: Motion): number
	if motion.Speed <= 0 then
		return motion.StartTime
	end
	return motion.StartTime + ColonistMotion.GetLength(motion.Path) / motion.Speed
end

return ColonistMotion
