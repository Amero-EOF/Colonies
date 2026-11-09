local Base91 = require(script.Parent.DecoratorLib.rbnsr)

return function(...)
	return Base91.Serialize({ ... })
end
