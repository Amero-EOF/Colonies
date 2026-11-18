--!strict

-- Primary/secondary trait per job (MineColonies Traits table). Shown in the colonist menu
-- and used to pick the best unemployed colonist for a workplace.
export type JobInfo = {
	Primary: string,
	Secondary: string?,
}

const JOBS: { [string]: JobInfo } = {
	Alchemist = { Primary = "Dexterity", Secondary = "Mana" },
	["Archer in Training"] = { Primary = "Agility", Secondary = "Adaptability" },
	Baker = { Primary = "Knowledge", Secondary = "Dexterity" },
	Beekeeper = { Primary = "Dexterity", Secondary = "Adaptability" },
	Blacksmith = { Primary = "Strength", Secondary = "Focus" },
	Brickmaker = { Primary = "Athletics", Secondary = "Dexterity" },
	Builder = { Primary = "Adaptability", Secondary = "Athletics" },
	Carpenter = { Primary = "Knowledge", Secondary = "Dexterity" },
	Chef = { Primary = "Creativity", Secondary = "Knowledge" },
	["Chicken Farmer"] = { Primary = "Adaptability", Secondary = "Agility" },
	Composter = { Primary = "Stamina", Secondary = "Athletics" },
	["Concrete Mixer"] = { Primary = "Stamina", Secondary = "Dexterity" },
	Courier = { Primary = "Agility", Secondary = "Adaptability" },
	Cowhand = { Primary = "Athletics", Secondary = "Stamina" },
	Crusher = { Primary = "Stamina", Secondary = "Strength" },
	Dyer = { Primary = "Creativity", Secondary = "Dexterity" },
	Enchanter = { Primary = "Mana", Secondary = "Knowledge" },
	Farmer = { Primary = "Stamina", Secondary = "Athletics" },
	Fisher = { Primary = "Focus", Secondary = "Agility" },
	Fletcher = { Primary = "Dexterity", Secondary = "Creativity" },
	Florist = { Primary = "Dexterity", Secondary = "Agility" },
	Forester = { Primary = "Strength", Secondary = "Focus" },
	Glassblower = { Primary = "Creativity", Secondary = "Focus" },
	Guard = { Primary = "Adaptability", Secondary = "Stamina" },
	Healer = { Primary = "Mana", Secondary = "Knowledge" },
	["Knight in Training"] = { Primary = "Adaptability", Secondary = "Stamina" },
	Mechanic = { Primary = "Knowledge", Secondary = "Agility" },
	Miner = { Primary = "Strength", Secondary = "Stamina" },
	["Nether Miner"] = { Primary = "Adaptability", Secondary = "Strength" },
	Planter = { Primary = "Agility", Secondary = "Dexterity" },
	Pupil = { Primary = "Intelligence", Secondary = "Mana" },
	Quarrier = { Primary = "Strength", Secondary = "Stamina" },
	["Rabbit Herder"] = { Primary = "Agility", Secondary = "Athletics" },
	Researcher = { Primary = "Knowledge", Secondary = "Mana" },
	Shepherd = { Primary = "Focus", Secondary = "Strength" },
	Sifter = { Primary = "Focus", Secondary = "Strength" },
	Smelter = { Primary = "Athletics", Secondary = "Strength" },
	Stablemaster = { Primary = "Athletics", Secondary = "Stamina" },
	Stonemason = { Primary = "Creativity", Secondary = "Dexterity" },
	Student = { Primary = "Intelligence" },
	Swineherd = { Primary = "Strength", Secondary = "Athletics" },
	Teacher = { Primary = "Knowledge", Secondary = "Mana" },
	Undertaker = { Primary = "Strength", Secondary = "Mana" },
	Waiter = { Primary = "Adaptability", Secondary = "Knowledge" },
}

const JobData = {}

function JobData.Get(job: string): JobInfo?
	return JOBS[job]
end

-- Suitability for a job: primary trait counts double
function JobData.Score(job: string, skills: { [string]: number }): number
	local info = JOBS[job]
	if not info then
		return 0
	end
	local score = (skills[info.Primary] or 0) * 2
	if info.Secondary then
		score += skills[info.Secondary] or 0
	end
	return score
end

return JobData
