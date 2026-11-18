--!strict

-- "giveTarget": where `give` puts items
return function(registry: any)
	registry:RegisterType(
		"giveTarget",
		registry.Cmdr.Util.MakeEnumType("GiveTarget", { "backpack", "storage" })
	)
end
