--!strict

-- "raidAction": what the `raid` command does
return function(registry: any)
	registry:RegisterType(
		"raidAction",
		registry.Cmdr.Util.MakeEnumType("RaidAction", { "start", "end", "tonight", "status" })
	)
end
