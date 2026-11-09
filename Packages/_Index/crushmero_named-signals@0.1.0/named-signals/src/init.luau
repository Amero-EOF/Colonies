-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local Shared = ReplicatedStorage.Shared

local Signal = require(script.Parent.Signal)
local Trove = require(script.Parent.Trove)

local NamedSignals = {}
local SignalList = {}
local trove = Trove.new()
function NamedSignals:Bind<T...>(Name: string): Signal.Signal<T...>
	if not SignalList then
		SignalList = {}
	end
	local SignalPresent = SignalList[Name]
	if SignalPresent then
		return SignalPresent
	end

	local newBind = Signal.new()
	newBind.Name = Name

	SignalList[Name] = newBind

	trove:Add(newBind)
	return newBind
end

function NamedSignals:Unbind(Name: string)
	if not SignalList[Name] then
		return
	end
	trove:Remove(SignalList[Name])
	SignalList[Name] = nil
end

function NamedSignals:UnbindAll()
	trove:Destroy()
end

function NamedSignals:Fire(Name: string, ...)
	if not SignalList[Name] then
		error(debug.traceback(`Attempt to index invalid Signal {Name}`, 200))
		return
	end

	SignalList[Name]:Fire(...)
end

function NamedSignals:Connect(Name: string, bindFunc: (...any) -> ())
	if not SignalList[Name] then
		error(debug.traceback(`Attempt to index invalid Signal {Name}`, 200))
		return
	end

	return SignalList[Name]:Connect(bindFunc)
end

function NamedSignals:Once(Name: string, bindFunc: (...any) -> ())
	if not SignalList[Name] then
		error(debug.traceback(`Attempt to index invalid Signal {Name}`, 200))
		return
	end

	return SignalList[Name]:Once(bindFunc)
end

return NamedSignals
