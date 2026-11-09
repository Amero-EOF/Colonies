local Decorators = script.Decorators
local RemoteCallback = require(Decorators.RemoteCallback)

export type decoratorList = {
	Base91DecodeMixin: (...any) -> ...any,
	Base91EncodeMixin: (...any) -> ...any,
	RemoteCallback: (...any) -> ...any,
	TestDecorator: (...any) -> ...any,
	[string]: (...any) -> ...any,
}

local decoratorList = {}

-- populate built-in decorators
for _, v in Decorators:GetChildren() do
	if not v:IsA("ModuleScript") then
		continue
	end
	decoratorList[v.Name] = require(v)
end

local Decorator = {
	decoratorList = decoratorList :: decoratorList,
}

function Decorator.Injector<T>(someTable: T): T
	if typeof(someTable) ~= "table" then
		return someTable
	end
	assert(typeof(someTable) == "table", `Provided injection {someTable} is not a table.`)
	for i, v in someTable do
		assert(typeof(v) == "function", `Injection failed {i} is not a function`)
	end

	local proxyTable = setmetatable({}, {
		__index = function(_: { any }, key: string)
			local originalValue = someTable[key]
			return function(...)
				local args = { ... }
				local decorators = args[1]
				table.remove(args, 1)

				if typeof(decorators) ~= "table" then
					return originalValue(table.unpack(args))
				end

				local newData = args

				for _, decorator in decorators do
					-- Checks if this is a decorator table or a normal table
					if not table.find(decoratorList, decorator) then
						continue
					end
					if decorator == RemoteCallback then
						newData = { decorator(decorators, table.unpack(newData)) }
						break
					end
					-- unpack and repack after decorator call.
					newData = { decorator(table.unpack(newData)) }
				end
				args = newData
				return originalValue(table.unpack(args))
			end
		end,
	})
	return proxyTable
end

function Decorator.AddDecoratorsToList(DecoratorFolder: { ModuleScript })
	for _, v in Decorators do
		if not v:IsA("ModuleScript") then
			continue
		end
		decoratorList[v.Name] = require(v)
	end
end

return Decorator
