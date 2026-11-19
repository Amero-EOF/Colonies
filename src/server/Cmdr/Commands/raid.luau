--!strict

return {
	Name = "raid",
	Aliases = { "raiders" },
	Description = "Starts or ends a raid on a player's colony, or schedules one for tonight, for testing.",
	Group = "Testing",
	Args = {
		{
			Type = "raidAction",
			Name = "Action",
			Description = "start (now, any time of day), end, tonight (schedule it) or status.",
		},
		{
			Type = "players",
			Name = "Players",
			Description = "Whose colony (defaults to you).",
			Optional = true,
		},
	},
}
