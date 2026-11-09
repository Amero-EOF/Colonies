local RunService = game:GetService("RunService")
local Signal = require(script.Parent.Signal)

export type FiniteObject = {
	Completed: Signal.Signal<boolean>, -- true if completed false if cancelled
	Cancel: () -> (),
}

export type FiniteCallback = (deltaStart: number, cancel: (forceCancel: boolean) -> ()) -> ()

type TimeManagementEventType =
	"PostSimulation"
	| "PreAnimation"
	| "PreRender"
	| "PreSimulation"
	| "RenderStepped"
	| "Stepped"

const TIME_MANAGEMENT_EVENT_TYPES: { [TimeManagementEventType]: boolean } = table.freeze({
	PostSimulation = true,
	PreAnimation = true,
	PreRender = true,
	PreSimulation = true,
	RenderStepped = true,
	Stepped = true,
})

function TimeManagementWrapper(
	timeLength: number,
	callback: FiniteCallback,
	eventType: TimeManagementEventType
): FiniteObject
	if not TIME_MANAGEMENT_EVENT_TYPES[eventType] then
		error("Invalid event type: " .. eventType)
	end
	local startTime = os.clock()
	local endSignal = Signal.new()
	local finiteConn

	local cancelFunction = function()
		if not finiteConn then
			return
		end
		finiteConn:Disconnect()
		endSignal:Fire(true)
	end

	finiteConn = RunService[eventType]:Connect(function()
		callback(math.clamp((os.clock() - startTime) / timeLength, 0, 1), cancelFunction)

		if os.clock() - startTime >= timeLength then
			finiteConn:Disconnect()
			endSignal:Fire(false)
		end
	end)
	return {
		Completed = endSignal,
		Cancel = cancelFunction,
		Destroy = cancelFunction,
	}
end

local ExtendedRunService = {}

function ExtendedRunService.FinitePreRender(
	timeLength: number,
	callback: FiniteCallback
): FiniteObject
	return TimeManagementWrapper(timeLength, callback, "PreRender")
end
ExtendedRunService.FiniteRenderStepped = ExtendedRunService.FinitePreRender

function ExtendedRunService.FinitePreSimulation(
	timeLength: number,
	callback: FiniteCallback,
	delayTime: number?
): FiniteObject
	return TimeManagementWrapper(timeLength, callback, "PreSimulation")
end
ExtendedRunService.FiniteStepped = ExtendedRunService.FinitePreSimulation

function ExtendedRunService.FinitePostSimulation(
	timeLength: number,
	callback: FiniteCallback,
	delayTime: number?
): FiniteObject
	return TimeManagementWrapper(timeLength, callback, "PostSimulation")
end
ExtendedRunService.FiniteHeartbeat = ExtendedRunService.FinitePostSimulation

function ExtendedRunService.FinitePreAnimation(
	timeLength: number,
	callback: FiniteCallback,
	delayTime: number?
): FiniteObject
	return TimeManagementWrapper(timeLength, callback, "PreAnimation")
end

return ExtendedRunService
