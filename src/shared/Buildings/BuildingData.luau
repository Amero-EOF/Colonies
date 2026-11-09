--!strict

const BuildingTypes = require(script.Parent.BuildingTypes)

type BuildingId = BuildingTypes.BuildingId
type BuildingInfo = BuildingTypes.BuildingInfo

-- Every building from the MineColonies wiki (https://minecolonies.com/wiki/), keyed by Id
const BuildingData: { [BuildingId]: BuildingInfo } = {
	AlchemistLaboratory = {
		Id = "AlchemistLaboratory",
		Name = "Alchemist Laboratory",
		Description = "Where the Alchemist brews potions.",
		Components = {
			Workplace = { Jobs = { "Alchemist" } },
		},
	},
	Apiary = {
		Id = "Apiary",
		Name = "Apiary",
		Description = "Where the Beekeeper breeds bees and harvests honey.",
		Components = {
			Workplace = { Jobs = { "Beekeeper" } },
		},
	},
	Archery = {
		Id = "Archery",
		Name = "Archery",
		Description = "Where archers in training become Archers.",
		Components = {
			Workplace = { Jobs = { "Archer in Training" } },
		},
	},
	Bakery = {
		Id = "Bakery",
		Name = "Bakery",
		Description = "Where the Baker bakes bread and pastries.",
		Components = {
			Workplace = { Jobs = { "Baker" } },
		},
	},
	Barracks = {
		Id = "Barracks",
		Name = "Barracks",
		Description = "Central defence hub that holds multiple Barracks Towers.",
		Components = {},
	},
	BarracksTower = {
		Id = "BarracksTower",
		Name = "Barracks Tower",
		Description = "Houses and employs one Guard per level.",
		Components = {
			Workplace = { Jobs = { "Guard" } },
		},
	},
	BlacksmithHut = {
		Id = "BlacksmithHut",
		Name = "Blacksmith's Hut",
		Description = "Where the Blacksmith crafts tools, armour and weapons.",
		Components = {
			Workplace = { Jobs = { "Blacksmith" } },
		},
	},
	BrickYard = {
		Id = "BrickYard",
		Name = "Brick Yard",
		Description = "Where the Brickmaker smelts stone and bricks.",
		Components = {
			Workplace = { Jobs = { "Brickmaker" } },
		},
	},
	BuilderHut = {
		Id = "BuilderHut",
		Name = "Builder's Hut",
		Description = "Where the Builder works; required before any other building.",
		Components = {
			Workplace = { Jobs = { "Builder" } },
		},
	},
	ChefKitchen = {
		Id = "ChefKitchen",
		Name = "Chef's Kitchen",
		Description = "Where the Chef cooks meals for the townspeople.",
		Components = {
			Workplace = { Jobs = { "Chef" } },
		},
	},
	ChickenFarmerHut = {
		Id = "ChickenFarmerHut",
		Name = "Chicken Farmer's Hut",
		Description = "Where the Chicken Farmer raises chickens and collects eggs.",
		Components = {
			Workplace = { Jobs = { "Chicken Farmer" } },
		},
	},
	CombatAcademy = {
		Id = "CombatAcademy",
		Name = "Combat Academy",
		Description = "Where knights in training become Knights.",
		Components = {
			Workplace = { Jobs = { "Knight in Training" } },
		},
	},
	ComposterHut = {
		Id = "ComposterHut",
		Name = "Composter's Hut",
		Description = "Where the Composter turns organic materials into compost.",
		Components = {
			Workplace = { Jobs = { "Composter" } },
		},
	},
	ConcreteMixerHut = {
		Id = "ConcreteMixerHut",
		Name = "Concrete Mixer's Hut",
		Description = "Where the Concrete Mixer makes concrete.",
		Components = {
			Workplace = { Jobs = { "Concrete Mixer" } },
		},
	},
	CourierHut = {
		Id = "CourierHut",
		Name = "Courier's Hut",
		Description = "Where Couriers run deliveries between the Warehouse and huts.",
		Components = {
			Workplace = { Jobs = { "Courier" } },
		},
	},
	CowhandHut = {
		Id = "CowhandHut",
		Name = "Cowhand's Hut",
		Description = "Where the Cowhand breeds, milks and butchers cows.",
		Components = {
			Workplace = { Jobs = { "Cowhand" } },
		},
	},
	CrusherHut = {
		Id = "CrusherHut",
		Name = "Crusher's Hut",
		Description = "Where the Crusher crushes blocks into other materials.",
		Components = {
			Workplace = { Jobs = { "Crusher" } },
		},
	},
	DiningHall = {
		Id = "DiningHall",
		Name = "Dining Hall",
		Description = "Where the Waiter cooks and serves food.",
		Components = {
			Workplace = { Jobs = { "Waiter" } },
		},
	},
	DyerHut = {
		Id = "DyerHut",
		Name = "Dyer's Hut",
		Description = "Where the Dyer crafts dyes and dyes items.",
		Components = {
			Workplace = { Jobs = { "Dyer" } },
		},
	},
	EnchanterTower = {
		Id = "EnchanterTower",
		Name = "Enchanter's Tower",
		Description = "Where the Enchanter creates enchantments.",
		Components = {
			Workplace = { Jobs = { "Enchanter" } },
		},
	},
	FarmerHut = {
		Id = "FarmerHut",
		Name = "Farmer's Hut",
		Description = "Where the Farmer grows crops.",
		Components = {
			Workplace = { Jobs = { "Farmer" } },
		},
	},
	FisherHut = {
		Id = "FisherHut",
		Name = "Fisher's Hut",
		Description = "Where the Fisher catches fish.",
		Components = {
			Workplace = { Jobs = { "Fisher" } },
		},
	},
	FletcherHut = {
		Id = "FletcherHut",
		Name = "Fletcher's Hut",
		Description = "Where the Fletcher crafts arrows and string/wool items.",
		Components = {
			Workplace = { Jobs = { "Fletcher" } },
		},
	},
	Flowershop = {
		Id = "Flowershop",
		Name = "Flowershop",
		Description = "Where the Florist grows flowers.",
		Components = {
			Workplace = { Jobs = { "Florist" } },
		},
	},
	ForesterHut = {
		Id = "ForesterHut",
		Name = "Forester's Hut",
		Description = "Where the Forester chops and replants trees.",
		Components = {
			Workplace = { Jobs = { "Forester" } },
		},
	},
	Gatehouse = {
		Id = "Gatehouse",
		Name = "Gatehouse",
		Description = "Stations guards at the colony's entrance.",
		Components = {
			Workplace = { Jobs = { "Guard" } },
		},
	},
	GlassblowerHut = {
		Id = "GlassblowerHut",
		Name = "Glassblower's Hut",
		Description = "Where the Glassblower smelts sand into glass.",
		Components = {
			Workplace = { Jobs = { "Glassblower" } },
		},
	},
	Graveyard = {
		Id = "Graveyard",
		Name = "Graveyard",
		Description = "Where the Undertaker buries deceased townspeople.",
		Components = {
			Workplace = { Jobs = { "Undertaker" } },
		},
	},
	GuardTower = {
		Id = "GuardTower",
		Name = "Guard Tower",
		Description = "Houses and employs one Guard to protect the colony.",
		Components = {
			Workplace = { Jobs = { "Guard" } },
		},
	},
	Hospital = {
		Id = "Hospital",
		Name = "Hospital",
		Description = "Where the Healer treats injured or sick townspeople.",
		Components = {
			Workplace = { Jobs = { "Healer" } },
		},
	},
	Library = {
		Id = "Library",
		Name = "Library",
		Description = "Where adult townspeople study to raise Intelligence.",
		Components = {
			Workplace = { Jobs = { "Student" } },
		},
	},
	MechanicHut = {
		Id = "MechanicHut",
		Name = "Mechanic's Hut",
		Description = "Where the Mechanic crafts mechanical items.",
		Components = {
			Workplace = { Jobs = { "Mechanic" } },
		},
	},
	Mine = {
		Id = "Mine",
		Name = "Mine",
		Description = "Where the Miner digs for ores.",
		Components = {
			Workplace = { Jobs = { "Miner" } },
		},
	},
	MysticalSite = {
		Id = "MysticalSite",
		Name = "Mystical Site",
		Description = "Raises the colony's happiness. Has no workers.",
		Components = {},
	},
	NetherMine = {
		Id = "NetherMine",
		Name = "Nether Mine",
		Description = "Where the Nether Miner works.",
		Components = {
			Workplace = { Jobs = { "Nether Miner" } },
		},
	},
	Plantation = {
		Id = "Plantation",
		Name = "Plantation",
		Description = "Where the Planter grows a variety of plants.",
		Components = {
			Workplace = { Jobs = { "Planter" } },
		},
	},
	Quarry = {
		Id = "Quarry",
		Name = "Quarry",
		Description = "Where the Quarrier digs out a quarry pit.",
		Components = {
			Workplace = { Jobs = { "Quarrier" } },
		},
	},
	RabbitHutch = {
		Id = "RabbitHutch",
		Name = "Rabbit Hutch",
		Description = "Where the Rabbit Herder raises rabbits.",
		Components = {
			Workplace = { Jobs = { "Rabbit Herder" } },
		},
	},
	Residence = {
		Id = "Residence",
		Name = "Residence",
		Description = "Where assigned townspeople sleep at night.",
		Components = {},
	},
	Sawmill = {
		Id = "Sawmill",
		Name = "Sawmill",
		Description = "Where the Carpenter crafts wooden items.",
		Components = {
			Workplace = { Jobs = { "Carpenter" } },
		},
	},
	School = {
		Id = "School",
		Name = "School",
		Description = "Where the Teacher raises children's Intelligence.",
		Components = {
			Workplace = { Jobs = { "Teacher", "Pupil" } },
		},
	},
	ShepherdHut = {
		Id = "ShepherdHut",
		Name = "Shepherd's Hut",
		Description = "Where the Shepherd breeds sheep for food and wool.",
		Components = {
			Workplace = { Jobs = { "Shepherd" } },
		},
	},
	SifterHut = {
		Id = "SifterHut",
		Name = "Sifter's Hut",
		Description = "Where the Sifter sifts dirt, gravel and sand for loot.",
		Components = {
			Workplace = { Jobs = { "Sifter" } },
		},
	},
	Smeltery = {
		Id = "Smeltery",
		Name = "Smeltery",
		Description = "Where the Smelter smelts ores into ingots.",
		Components = {
			Workplace = { Jobs = { "Smelter" } },
		},
	},
	Stable = {
		Id = "Stable",
		Name = "Stable",
		Description = "Where the Stablemaster trains cavalry horses.",
		Components = {
			Workplace = { Jobs = { "Stablemaster" } },
		},
	},
	StonemasonHut = {
		Id = "StonemasonHut",
		Name = "Stonemason's Hut",
		Description = "Where the Stonemason crafts stone items.",
		Components = {
			Workplace = { Jobs = { "Stonemason" } },
		},
	},
	SwineherdHut = {
		Id = "SwineherdHut",
		Name = "Swineherd's Hut",
		Description = "Where the Swineherd breeds pigs for food.",
		Components = {
			Workplace = { Jobs = { "Swineherd" } },
		},
	},
	Tavern = {
		Id = "Tavern",
		Name = "Tavern",
		Description = "Houses several townspeople, like a larger Residence.",
		Components = {},
	},
	TownHall = {
		Id = "TownHall",
		Name = "Town Hall",
		Description = "The central building of the colony.",
		Components = {},
	},
	University = {
		Id = "University",
		Name = "University",
		Description = "Where the Researcher researches colony upgrades.",
		Components = {
			Workplace = { Jobs = { "Researcher" } },
		},
	},
	Warehouse = {
		Id = "Warehouse",
		Name = "Warehouse",
		Description = "Central storage used by Couriers.",
		Components = {},
	},
}

return table.freeze(BuildingData)
