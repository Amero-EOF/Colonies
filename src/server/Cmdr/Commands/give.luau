--!strict

return {
	Name = "give",
	Aliases = { "giveitem" },
	Description = "Gives items to a player's backpack (or colony storage) for testing.",
	Group = "Testing",
	Args = {
		{ Type = "item", Name = "Item", Description = "The item to give." },
		{
			Type = "integer",
			Name = "Quantity",
			Description = "How many.",
			Optional = true,
			Default = 1,
		},
		{
			Type = "players",
			Name = "Players",
			Description = "Who gets them (defaults to you).",
			Optional = true,
		},
		{
			Type = "giveTarget",
			Name = "Target",
			Description = "backpack (default) or storage (the Town Hall's).",
			Optional = true,
		},
	},
}
