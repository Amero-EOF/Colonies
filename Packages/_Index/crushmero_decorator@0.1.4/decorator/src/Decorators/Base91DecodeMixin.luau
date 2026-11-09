local Base91 = require(script.Parent.DecoratorLib.rbnsr)

-- Recommended to have
return function(serializedString: string)
	if typeof(serializedString) ~= "string" then
		error("[Decorator] - Base91 Decode failed passed parameter is not a string")
	end
	return Base91.Deserialize(serializedString)
end
