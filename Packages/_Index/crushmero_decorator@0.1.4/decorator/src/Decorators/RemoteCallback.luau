local callbackDecorator
--[[
Used for handling remote events sent to the client.
Must be first priority in Decorator list
]]
callbackDecorator = function(decorators, callback)
	local returnfunc = function(...)
		local modifiedData = { ... }

		for _, v in decorators do
			if v == callbackDecorator then
				continue
			end
			modifiedData = v(modifiedData)
		end
		callback(table.unpack(modifiedData))
	end

	return returnfunc
end

return callbackDecorator
