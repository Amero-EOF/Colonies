--!strict

const ColonistTypes = require(script.Parent.Parent.Colonist.ColonistTypes)

-- Raiders replay paths exactly like colonists do (ColonistMotion); Id is the raider's id
export type Motion = ColonistTypes.Motion

-- One raider as the owner's client needs it (where it is comes from its Motion)
export type RaiderInfo = {
	Id: number,
	Health: number,
	MaxHealth: number,
	-- Carrying stolen items back to the plot's edge
	Carrying: boolean,
}

-- Sent to the owner with the "RaidState" remote
export type RaidState = {
	Active: boolean,
	-- Raiders still on the plot
	Raiders: { RaiderInfo },
	-- Raiders the raid started with
	Total: number,
	-- workspace:GetServerTimeNow() the raiders give up and retreat (dawn)
	RetreatAt: number,
}

-- Returned by the "GetRaid" remote while a raid is on
export type RaidSnapshot = {
	State: RaidState,
	Motions: { Motion },
}

return 0
