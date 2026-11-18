--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)

const source = vide.source

type Colonist = ColonistTypes.Colonist
type Motion = ColonistTypes.Motion

-- The conversation shown at the bottom of the screen
export type OpenDialogue = { Id: number, Dialogue: ColonistTypes.Dialogue }

-- The local player's colonists as last sent by the server
const ColonistStore = {
	Colonists = source({} :: { Colonist }),
	Departed = source({} :: { ColonistTypes.DepartedColonist }),
	Funeral = source(nil :: ColonistTypes.Funeral?),
	Disease = source(0),
	Status = source({} :: { [string]: string }),
	-- Latest motion per colonist id; ColonistView replays these every frame
	Motions = {} :: { [number]: Motion },
	-- Colonist whose menu is open
	SelectedId = source(nil :: number?),
	-- Colonist whose family tree is open
	FamilyTreeId = source(nil :: number?),
	-- Shows a toast (set by the UI, which owns the notifications)
	OnMessage = nil :: ((text: string) -> ())?,
	-- Conversation open in ColonistDialogue
	Dialogue = source(nil :: OpenDialogue?),
}

local started = false

local function applyState(state: ColonistTypes.ColonistsState?)
	if not state then
		return
	end
	ColonistStore.Colonists(state.Colonists)
	ColonistStore.Departed(state.Departed)
	ColonistStore.Funeral(state.Funeral)
	ColonistStore.Disease(state.Disease)
	ColonistStore.Status(state.Status)
end

local function applyMotions(motions: { Motion })
	for _, motion in motions do
		ColonistStore.Motions[motion.Id] = motion
	end
end

function ColonistStore.Get(id: number?): Colonist?
	if not id then
		return nil
	end
	for _, colonist in ColonistStore.Colonists() do
		if colonist.Id == id then
			return colonist
		end
	end
	return nil
end

function ColonistStore.GetDeparted(id: number): ColonistTypes.DepartedColonist?
	for _, departed in ColonistStore.Departed() do
		if departed.Id == id then
			return departed
		end
	end
	return nil
end

-- Opens a conversation with a colonist (their quest first, unless `chat` asks for the day's chat)
function ColonistStore.Talk(id: number, chat: boolean?)
	task.spawn(function()
		local dialogue, message = Net:Invoke("TalkColonist", id, chat == true)
		if dialogue then
			ColonistStore.Dialogue({ Id = id, Dialogue = dialogue })
		elseif ColonistStore.OnMessage then
			ColonistStore.OnMessage(tostring(message))
		end
	end)
end

-- Closes the conversation and lets the colonist move again
function ColonistStore.EndTalk()
	local open = ColonistStore.Dialogue()
	ColonistStore.Dialogue(nil)
	if open then
		Net:RemoteEvent("EndTalkColonist"):FireServer(open.Id)
	end
end

function ColonistStore.GetStatus(id: number): string
	return ColonistStore.Status()[tostring(id)] or ""
end

function ColonistStore.Start()
	if started then
		return
	end
	started = true

	Net:Connect("ColonistsState", applyState)
	Net:Connect("ColonistMotions", applyMotions)
	-- The colonist left the conversation (bedtime)
	Net:Connect("ColonistTalkEnded", function(id: number, message: string)
		local open = ColonistStore.Dialogue()
		if open and open.Id == id then
			ColonistStore.Dialogue(nil)
			if ColonistStore.OnMessage then
				ColonistStore.OnMessage(message)
			end
		end
	end)
	task.spawn(function()
		-- The colony may still be loading; retry until the server has it
		for _ = 1, 30 do
			local result = Net:Invoke("GetColonists")
			if result then
				applyMotions(result.Motions)
				applyState(result.State)
				return
			end
			task.wait(1)
		end
	end)
end

return ColonistStore
