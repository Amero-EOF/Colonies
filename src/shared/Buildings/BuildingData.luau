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
		UnlockLevel = 5,
		Components = {
			Workplace = { Jobs = { "Alchemist" } },
		},
	},
	Apiary = {
		Id = "Apiary",
		Name = "Apiary",
		Description = "Where the Beekeeper breeds bees and harvests honey.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Beekeeper" } },
		},
	},
	Archery = {
		Id = "Archery",
		Name = "Archery",
		Description = "Where archers in training become Archers.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Archer in Training" } },
		},
	},
	Bakery = {
		Id = "Bakery",
		Name = "Bakery",
		Description = "Where the Baker bakes bread and pastries.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Baker" } },
		},
	},
	Barracks = {
		Id = "Barracks",
		Name = "Barracks",
		Description = "Central defence hub that holds multiple Barracks Towers.",
		UnlockLevel = 3,
		Components = {},
	},
	BarracksTower = {
		Id = "BarracksTower",
		Name = "Barracks Tower",
		Description = "Houses and employs one Guard per level.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Guard" } },
		},
	},
	BlacksmithHut = {
		Id = "BlacksmithHut",
		Name = "Blacksmith's Hut",
		Description = "Where the Blacksmith crafts tools, armour and weapons.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Blacksmith" } },
		},
	},
	BrickYard = {
		Id = "BrickYard",
		Name = "Brick Yard",
		Description = "Where the Brickmaker smelts stone and bricks.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Brickmaker" } },
		},
	},
	BuilderHut = {
		Id = "BuilderHut",
		Name = "Builder's Hut",
		Description = "Where the Builder works; required before any other building.",
		UnlockLevel = 0,
		Components = {
			Workplace = { Jobs = { "Builder" } },
			WorkerStorage = { BagItem = "BuilderHutStorage" },
		},
	},
	ChefKitchen = {
		Id = "ChefKitchen",
		Name = "Chef's Kitchen",
		Description = "Where the Chef cooks meals for the townspeople.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Chef" } },
		},
	},
	ChickenFarmerHut = {
		Id = "ChickenFarmerHut",
		Name = "Chicken Farmer's Hut",
		Description = "Where the Chicken Farmer raises chickens and collects eggs.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Chicken Farmer" } },
		},
	},
	CombatAcademy = {
		Id = "CombatAcademy",
		Name = "Combat Academy",
		Description = "Where knights in training become Knights.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Knight in Training" } },
		},
	},
	ComposterHut = {
		Id = "ComposterHut",
		Name = "Composter's Hut",
		Description = "Where the Composter turns organic materials into compost.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Composter" } },
		},
	},
	ConcreteMixerHut = {
		Id = "ConcreteMixerHut",
		Name = "Concrete Mixer's Hut",
		Description = "Where the Concrete Mixer makes concrete.",
		UnlockLevel = 5,
		Components = {
			Workplace = { Jobs = { "Concrete Mixer" } },
		},
	},
	CourierHut = {
		Id = "CourierHut",
		Name = "Courier's Hut",
		Description = "Where Couriers run deliveries between the Warehouse and huts.",
		UnlockLevel = 1,
		Components = {
			Workplace = { Jobs = { "Courier" } },
		},
	},
	CowhandHut = {
		Id = "CowhandHut",
		Name = "Cowhand's Hut",
		Description = "Where the Cowhand breeds, milks and butchers cows.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Cowhand" } },
		},
	},
	CrusherHut = {
		Id = "CrusherHut",
		Name = "Crusher's Hut",
		Description = "Where the Crusher crushes blocks into other materials.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Crusher" } },
		},
	},
	DiningHall = {
		Id = "DiningHall",
		Name = "Dining Hall",
		Description = "Where the Waiter cooks and serves food.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Waiter" } },
		},
	},
	DyerHut = {
		Id = "DyerHut",
		Name = "Dyer's Hut",
		Description = "Where the Dyer crafts dyes and dyes items.",
		UnlockLevel = 5,
		Components = {
			Workplace = { Jobs = { "Dyer" } },
		},
	},
	EnchanterTower = {
		Id = "EnchanterTower",
		Name = "Enchanter's Tower",
		Description = "Where the Enchanter creates enchantments.",
		UnlockLevel = 5,
		Components = {
			Workplace = { Jobs = { "Enchanter" } },
		},
	},
	FarmerHut = {
		Id = "FarmerHut",
		Name = "Farmer's Hut",
		Description = "Where the Farmer grows crops.",
		UnlockLevel = 1,
		Components = {
			Workplace = { Jobs = { "Farmer" } },
			WorkerStorage = { BagItem = "FarmerHutStorage" },
			Field = {},
		},
	},
	FisherHut = {
		Id = "FisherHut",
		Name = "Fisher's Hut",
		Description = "Where the Fisher catches fish.",
		UnlockLevel = 1,
		Components = {
			Workplace = { Jobs = { "Fisher" } },
		},
	},
	FletcherHut = {
		Id = "FletcherHut",
		Name = "Fletcher's Hut",
		Description = "Where the Fletcher crafts arrows and string/wool items.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Fletcher" } },
		},
	},
	Flowershop = {
		Id = "Flowershop",
		Name = "Flowershop",
		Description = "Where the Florist grows flowers.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Florist" } },
		},
	},
	ForesterHut = {
		Id = "ForesterHut",
		Name = "Forester's Hut",
		Description = "Where the Forester chops and replants trees.",
		UnlockLevel = 1,
		Components = {
			Workplace = { Jobs = { "Forester" } },
		},
	},
	Gatehouse = {
		Id = "Gatehouse",
		Name = "Gatehouse",
		Description = "Stations guards at the colony's entrance.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Guard" } },
		},
	},
	GlassblowerHut = {
		Id = "GlassblowerHut",
		Name = "Glassblower's Hut",
		Description = "Where the Glassblower smelts sand into glass.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Glassblower" } },
		},
	},
	Graveyard = {
		Id = "Graveyard",
		Name = "Graveyard",
		Description = "Where the Undertaker buries deceased townspeople.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Undertaker" } },
		},
	},
	GuardTower = {
		Id = "GuardTower",
		Name = "Guard Tower",
		Description = "Houses and employs one Guard to protect the colony.",
		UnlockLevel = 1,
		Components = {
			Workplace = { Jobs = { "Guard" } },
		},
	},
	Hospital = {
		Id = "Hospital",
		Name = "Hospital",
		Description = "Where the Healer treats injured or sick townspeople.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Healer" } },
		},
	},
	Library = {
		Id = "Library",
		Name = "Library",
		Description = "Where adult townspeople study to raise Intelligence.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Student" } },
		},
	},
	MechanicHut = {
		Id = "MechanicHut",
		Name = "Mechanic's Hut",
		Description = "Where the Mechanic crafts mechanical items.",
		UnlockLevel = 5,
		Components = {
			Workplace = { Jobs = { "Mechanic" } },
		},
	},
	Mine = {
		Id = "Mine",
		Name = "Mine",
		Description = "Where the Miner digs for ores.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Miner" } },
		},
	},
	MysticalSite = {
		Id = "MysticalSite",
		Name = "Mystical Site",
		Description = "Raises the colony's happiness. Has no workers.",
		UnlockLevel = 5,
		Components = {},
	},
	NetherMine = {
		Id = "NetherMine",
		Name = "Nether Mine",
		Description = "Where the Nether Miner works.",
		UnlockLevel = 5,
		Components = {
			Workplace = { Jobs = { "Nether Miner" } },
		},
	},
	Plantation = {
		Id = "Plantation",
		Name = "Plantation",
		Description = "Where the Planter grows a variety of plants.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Planter" } },
		},
	},
	Quarry = {
		Id = "Quarry",
		Name = "Quarry",
		Description = "Where the Quarrier digs out a quarry pit.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Quarrier" } },
		},
	},
	RabbitHutch = {
		Id = "RabbitHutch",
		Name = "Rabbit Hutch",
		Description = "Where the Rabbit Herder raises rabbits.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Rabbit Herder" } },
		},
	},
	Residence = {
		Id = "Residence",
		Name = "Residence",
		Description = "Where assigned townspeople sleep at night.",
		UnlockLevel = 1,
		Components = {
			Housing = { Capacity = 0, CapacityPerLevel = 1 },
		},
	},
	Sawmill = {
		Id = "Sawmill",
		Name = "Sawmill",
		Description = "Where the Carpenter crafts wooden items.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Carpenter" } },
		},
	},
	School = {
		Id = "School",
		Name = "School",
		Description = "Where the Teacher raises children's Intelligence.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Teacher", "Pupil" } },
		},
	},
	ShepherdHut = {
		Id = "ShepherdHut",
		Name = "Shepherd's Hut",
		Description = "Where the Shepherd breeds sheep for food and wool.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Shepherd" } },
		},
	},
	SifterHut = {
		Id = "SifterHut",
		Name = "Sifter's Hut",
		Description = "Where the Sifter sifts dirt, gravel and sand for loot.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Sifter" } },
		},
	},
	Smeltery = {
		Id = "Smeltery",
		Name = "Smeltery",
		Description = "Where the Smelter smelts ores into ingots.",
		UnlockLevel = 3,
		Components = {
			Workplace = { Jobs = { "Smelter" } },
		},
	},
	Spire = {
		Id = "Spire",
		Name = "Spire",
		Description = "Teleports you to the border of the wilds.",
		UnlockLevel = 1,
		Components = { Teleporter = {} },
	},
	Stable = {
		Id = "Stable",
		Name = "Stable",
		Description = "Where the Stablemaster trains cavalry horses.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Stablemaster" } },
		},
	},
	StonemasonHut = {
		Id = "StonemasonHut",
		Name = "Stonemason's Hut",
		Description = "Where the Stonemason crafts stone items.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Stonemason" } },
		},
	},
	SwineherdHut = {
		Id = "SwineherdHut",
		Name = "Swineherd's Hut",
		Description = "Where the Swineherd breeds pigs for food.",
		UnlockLevel = 2,
		Components = {
			Workplace = { Jobs = { "Swineherd" } },
		},
	},
	Tavern = {
		Id = "Tavern",
		Name = "Tavern",
		Description = "Houses several townspeople, like a larger Residence.",
		UnlockLevel = 3,
		Components = {
			Housing = { Capacity = 4 },
		},
	},
	TownHall = {
		Id = "TownHall",
		Name = "Town Hall",
		Description = "The central building of the colony.",
		UnlockLevel = 0,
		Components = { Storage = {}, Housing = { Capacity = 3 } },
	},
	University = {
		Id = "University",
		Name = "University",
		Description = "Where the Researcher researches colony upgrades.",
		UnlockLevel = 4,
		Components = {
			Workplace = { Jobs = { "Researcher" } },
		},
	},
	Warehouse = {
		Id = "Warehouse",
		Name = "Warehouse",
		Description = "Central storage used by Couriers.",
		UnlockLevel = 1,
		Components = { Storage = {} },
	},
}

return table.freeze(BuildingData)
