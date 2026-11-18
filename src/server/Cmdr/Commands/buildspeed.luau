--!strict

return {
	Name = "buildspeed",
	Aliases = { "buildspeedmultiplier" },
	Description = "Sets the server-wide Builder speed multiplier (2 = twice as fast). Omit to show it.",
	Group = "Testing",
	Args = {
		{
			Type = "number",
			Name = "Multiplier",
			Description = "Build speed multiplier (> 0, default 1).",
			Optional = true,
		},
	},
}
