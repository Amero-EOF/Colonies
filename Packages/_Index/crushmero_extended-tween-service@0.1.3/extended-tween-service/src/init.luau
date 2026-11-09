local TweenService = game:GetService("TweenService")
local ExtendedRunService = require(script.Parent.ExtendedRunService)

type validProperties = "Color" | "Size" | "Squash" | "Transparency"

local validProperties = {
	"Color",
	"Size",
	"Squash",
	"Transparency",
}
local function propertyValidator(property: validProperties)
	for _, v in validProperties do
		if property == v then
			return true
		end
	end
	return false
end

type FiniteObject = ExtendedRunService.FiniteObject
local ExtendedTweenService = {}

function ExtendedTweenService.TweenSequence(
	object,
	property: validProperties,
	sequence: ColorSequence | NumberSequence,
	tweenInfo: TweenInfo
): FiniteObject?
	-- Validate object
	if not object then
		return nil
	end

	-- Validate property
	if not propertyValidator(property) then
		return nil
	end

	-- Validate sequence type
	local typeOfSequence = typeof(sequence)
	local sequenceType
	local sequencePointType
	if typeOfSequence == "ColorSequence" then
		sequenceType = ColorSequence
		sequencePointType = ColorSequenceKeypoint
	elseif typeOfSequence == "NumberSequence" then
		sequenceType = NumberSequence :: never
		sequencePointType = NumberSequenceKeypoint :: never
	else
		return nil
	end

	local endPoints = sequence.Keypoints
	local current = object[property]
	local currentPoints = current.Keypoints
	if #endPoints ~= #currentPoints then
		error("Invalid Sequence")
	end

	return ExtendedRunService.FiniteRenderStepped(
		if tweenInfo.Reverses then tweenInfo.Time * 2 else tweenInfo.Time,
		function(deltaStart, cancel)
			if not object then
				cancel(false)
				return
			end

			local newDelta = deltaStart
			if tweenInfo.Reverses then
				if deltaStart >= 0.5 then
					newDelta = 1 - math.map(newDelta, 0.5, 1, 0, 1)
				elseif deltaStart < 0.5 then
					newDelta = math.map(newDelta, 0, 0.5, 0, 1)
				end
			end

			local alpha =
				TweenService:GetValue(newDelta, tweenInfo.EasingStyle, tweenInfo.EasingDirection)

			local keypoints = {}
			for i: any, v: any in currentPoints do
				local value
				if typeOfSequence == "ColorSequence" then
					value = v.Value:Lerp(endPoints[i].Value, alpha)
				else
					value = math.lerp(currentPoints[i].Value, endPoints[i].Value :: never, alpha)
				end

				table.insert(keypoints, sequencePointType.new(endPoints[i].Time, value))
			end
			object[property] = sequenceType.new(keypoints)
		end
	)
end

function ExtendedTweenService.TweenPivot(
	object: PVInstance,
	endGoal: CFrame,
	tweenInfo: TweenInfo
): FiniteObject?
	if not object or not object:IsA("PVInstance") then
		return nil
	end

	if typeof(endGoal) ~= "CFrame" then
		return nil
	end
	local startGoal = object:GetPivot()
	return ExtendedRunService.FiniteRenderStepped(
		if tweenInfo.Reverses then tweenInfo.Time * 2 else tweenInfo.Time,
		function(deltaStart, cancel)
			if not object then
				cancel(false)
				return
			end

			local alpha =
				TweenService:GetValue(deltaStart, tweenInfo.EasingStyle, tweenInfo.EasingDirection)
			if tweenInfo.Reverses and deltaStart >= 0.5 then
				alpha = 1 - math.map(alpha, 0.5, 1, 0, 1)
			elseif tweenInfo.Reverses and deltaStart < 0.5 then
				alpha = math.map(alpha, 0, 0.5, 0, 1)
			end
			object:PivotTo(startGoal:Lerp(endGoal, alpha))
		end
	)
end

function ExtendedTweenService.TweenNumber(
	startGoal: number,
	endGoal: number,
	tweenInfo: TweenInfo,
	callback: (number, (forceCancel: boolean) -> ()) -> ()
): FiniteObject?
	return ExtendedRunService.FiniteRenderStepped(
		if tweenInfo.Reverses then tweenInfo.Time * 2 else tweenInfo.Time,
		function(deltaStart, cancel)
			local alpha =
				TweenService:GetValue(deltaStart, tweenInfo.EasingStyle, tweenInfo.EasingDirection)
			if tweenInfo.Reverses and deltaStart >= 0.5 then
				alpha = 1 - math.map(alpha, 0.5, 1, 0, 1)
			elseif tweenInfo.Reverses and deltaStart < 0.5 then
				alpha = math.map(alpha, 0, 0.5, 0, 1)
			end
			callback(math.lerp(startGoal, endGoal, alpha), cancel)
		end
	)
end

return ExtendedTweenService
