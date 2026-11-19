--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BuildingBlueprint = require(Shared.Buildings.BuildingBlueprint)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingModels = require(Shared.Buildings.BuildingModels)
const BuildingPlacement = require(Shared.Buildings.BuildingPlacement)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const FarmData = require(Shared.Farm.FarmData)
const YardData = require(Shared.Yard.YardData)
const MailboxData = require(Shared.Colony.MailboxData)
const PlotData = require(Shared.Plot.PlotData)
const ColonyStore = require(script.Parent.ColonyStore)
const PartSpring = require(script.Parent.PartSpring)

const effect = vide.effect
const source = vide.source

type SavedBuilding = ColonyTypes.SavedBuilding
type BuildingId = BuildingTypes.BuildingId

const PLOT_COLOR = Color3.fromRGB(86, 150, 60)
-- Studs past a building's footprint its prompts reach
const PROMPT_REACH = 16
-- Prompts sit near the base so tall buildings keep them on screen
const PROMPT_HEIGHT = 4
-- Studs between the Town Hall's two prompts and its centre
const SIDE_OFFSET = 6
const HIDE_CHECK_INTERVAL = 0.25
-- Unbuilt parts (construction sites, and the pieces the next level adds) are untextured shadows
const SHADOW_COLOR = Color3.new(0, 0, 0)
const SHADOW_TRANSPARENCY = 0.7
-- Placeholder mailbox colours
const MAILBOX_POST_COLOR = Color3.fromRGB(110, 75, 45)
const MAILBOX_BOX_COLOR = Color3.fromRGB(60, 90, 140)
const MAILBOX_SLOT_COLOR = Color3.fromRGB(25, 25, 30)
const MAILBOX_FLAG_COLOR = Color3.fromRGB(200, 50, 50)
-- Flag on the placeholder's right side, relative to its base: raised while mail is unread
const MAILBOX_FLAG_UP = CFrame.new(0.88, 5.1, 0.6)
const MAILBOX_FLAG_DOWN = CFrame.new(0.88, 4.1, 0.6) * CFrame.Angles(math.pi / 2, 0, 0)

const player = Players.LocalPlayer

-- Draws the local player's plot and buildings; nobody else sees them
const ColonyView = {}

local started = false

-- Parts Builders place, in blueprint order, by building id: a construction site's whole model, or
-- the pieces the next level adds (drawn as shadows beside the building until built)
const sites: { [string]: { BasePart } } = {}
-- The next level's pieces, drawn as a separate model beside each building
const nextTiers: { [string]: Model } = {}
-- Parts of each building the next level replaces; hidden once its upgrade has started
const replaced: { [string]: { BasePart } } = {}
-- Level each building was last drawn at, to spot an upgrade finishing
const drawnLevels: { [string]: number } = {}
-- Upgrade target level per building whose model adds no pieces (no shadows to draw)
const noShadows: { [string]: number } = {}
-- Keys (BuildingBlueprint.GetPartKey) of the parts still shadows when the buildings were redrawn
const springKeys: { [string]: { [string]: boolean } } = {}

type Look = {
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
	CastShadow: boolean,
	CanCollide: boolean,
	CanQuery: boolean,
	CanTouch: boolean,
	TextureID: string?,
	-- SurfaceAppearances, Decals and Textures taken off while it's a shadow
	Details: { Instance },
}

-- A part's real look while it's drawn as a shadow
const looks: { [BasePart]: Look } = {}
-- Whether each site part is currently drawn built
const shownBuilt: { [BasePart]: boolean } = {}
-- Collision of replaced parts before they were hidden
const replacedCollide: { [BasePart]: boolean } = {}

-- The Town Hall mailbox drawn last (its prompt's text and flag follow unread mail)
local mailboxPrompt: ProximityPrompt? = nil
local mailboxFlag: BasePart? = nil
local mailboxPivot = CFrame.new()

local function openStorage(target: string?): (boolean) -> ()
	return function(open: boolean)
		if open then
			ColonyStore.StorageTarget(target)
			ColonyStore.StorageOpen(true)
		elseif ColonyStore.StorageTarget() == target then
			ColonyStore.StorageOpen(false)
		end
	end
end

local function setTexture(part: BasePart, textureId: string)
	if part:IsA("MeshPart") then
		pcall(function()
			part.TextureID = textureId
		end)
	end
end

local function makeShadow(part: BasePart)
	local look = looks[part]
	if not look then
		local details: { Instance } = {}
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") or child:IsA("Decal") then
				table.insert(details, child)
			end
		end
		look = {
			Color = part.Color,
			Material = part.Material,
			Transparency = part.Transparency,
			CastShadow = part.CastShadow,
			CanCollide = part.CanCollide,
			CanQuery = part.CanQuery,
			CanTouch = part.CanTouch,
			TextureID = if part:IsA("MeshPart") then part.TextureID else nil,
			Details = details,
		}
		looks[part] = look
	end
	for _, detail in look.Details do
		detail.Parent = nil
	end
	setTexture(part, "")
	part.Color = SHADOW_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = SHADOW_TRANSPARENCY
	part.CastShadow = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function restoreLook(part: BasePart)
	local look = looks[part]
	if not look then
		return
	end
	looks[part] = nil
	for _, detail in look.Details do
		detail.Parent = part
	end
	local textureId = look.TextureID
	if textureId then
		setTexture(part, textureId)
	end
	part.Color = look.Color
	part.Material = look.Material
	part.Transparency = look.Transparency
	part.CastShadow = look.CastShadow
	part.CanCollide = look.CanCollide
	part.CanQuery = look.CanQuery
	part.CanTouch = look.CanTouch
end

-- Draws a site part built or as a shadow; `animate` springs it in when it gets built
local function setBuilt(part: BasePart, built: boolean, animate: boolean)
	local was = shownBuilt[part]
	if was == built then
		return
	end
	shownBuilt[part] = built
	if built then
		restoreLook(part)
		-- The first draw of a model isn't a part being placed
		if animate and was ~= nil then
			PartSpring.Play(part)
		end
	else
		makeShadow(part)
	end
end

-- Shows the parts a Builder has placed; the rest stay shadows. Parts the next level replaces
-- disappear once its upgrade has started.
local function updateSites(animate: boolean)
	local progress: { [string]: number } = {}
	for _, order in ColonyStore.WorkOrders() do
		progress[order.BuildingId] = order.Progress
	end
	for id, parts in sites do
		local placed = progress[id] or 0
		for index, part in parts do
			setBuilt(part, index <= placed, animate)
		end
	end
	for id, parts in replaced do
		local hidden = (progress[id] or 0) > 0
		for _, part in parts do
			part.LocalTransparencyModifier = if hidden then 1 else 0
			part.CanCollide = not hidden and replacedCollide[part]
		end
	end
end

-- Remembers which of a building's site parts are still shadows, so the redraw after its upgrade
-- finishes can spring them in (the last piece placed)
local function rememberUnbuilt(id: string)
	local parts = sites[id]
	local model = nextTiers[id] or ColonyStore.Models[id]
	if not parts or not model then
		return
	end
	local pivot = BuildingModels.GetLayoutFrame(model)
	local keys = {}
	for _, part in parts do
		if shownBuilt[part] == false then
			keys[BuildingBlueprint.GetPartKey(pivot, part)] = true
		end
	end
	springKeys[id] = keys
end

-- Removes an upgrade's shadow pieces and shows the parts it would have replaced again
local function removeNextTier(id: string)
	local nextModel = nextTiers[id]
	if not nextModel then
		return
	end
	rememberUnbuilt(id)
	nextModel:Destroy()
	nextTiers[id] = nil
	sites[id] = nil
	local gone = replaced[id]
	if gone then
		for _, part in gone do
			part.LocalTransparencyModifier = 0
			part.CanCollide = replacedCollide[part]
			replacedCollide[part] = nil
		end
	end
	replaced[id] = nil
end

-- Draws the pieces an upgrade to `targetLevel` adds as shadows beside the building (only when that
-- level has its own model and adds pieces to the current one)
local function addNextTier(id: BuildingId, targetLevel: number)
	local model = ColonyStore.Models[id]
	local folder = model and model.Parent
	if not model or not folder or not BuildingModels.HasModel(id, targetLevel) then
		return
	end
	local nextModel = BuildingModels.Create(id, targetLevel)
	local parts, incremental = BuildingBlueprint.GetBuildParts(nextModel, id, targetLevel)
	if not incremental then
		-- The level looks like this one (e.g. copied models): nothing to show as shadows
		nextModel:Destroy()
		noShadows[id] = targetLevel
		return
	end

	local keep: { [BasePart]: boolean } = {}
	for _, part in parts do
		keep[part] = true
	end
	for _, descendant in nextModel:GetDescendants() do
		if
			descendant:IsA("BasePart") and not keep[descendant] or descendant:IsA("BillboardGui")
		then
			descendant:Destroy()
		end
	end
	nextModel.Name = `{id}NextLevel`
	-- Line the levels' layout frames up: a level that grows to one side has its base centre elsewhere
	nextModel:PivotTo(
		BuildingModels.GetLayoutFrame(model)
			* CFrame.new(-BuildingModels.GetLayoutOrigin(nextModel))
	)
	nextModel.Parent = folder
	nextTiers[id] = nextModel
	sites[id] = parts

	-- Parts of this level the next one doesn't have (a roof under a new storey)
	local nextKeys = BuildingBlueprint.GetPartKeys(id, targetLevel)
	local pivot = BuildingModels.GetLayoutFrame(model)
	local gone = {}
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and not descendant:FindFirstAncestor("Mailbox")
			and not nextKeys[BuildingBlueprint.GetPartKey(pivot, descendant)]
		then
			table.insert(gone, descendant)
			replacedCollide[descendant] = descendant.CanCollide
		end
	end
	replaced[id] = gone
end

-- Shadow pieces only while an upgrade is ordered: adds them for new upgrade orders and removes
-- them when the order is gone
local function syncUpgrades()
	local upgrading: { [string]: boolean } = {}
	for _, order in ColonyStore.WorkOrders() do
		if order.Kind ~= "Upgrade" then
			continue
		end
		local id = order.BuildingId
		upgrading[id] = true
		if not nextTiers[id] and noShadows[id] ~= order.TargetLevel then
			addNextTier(id, order.TargetLevel)
		end
	end
	for id in nextTiers do
		if not upgrading[id] then
			removeNextTier(id)
		end
	end
end

-- Prompt that opens a menu, which closes again when the player walks away. Sits on the model's
-- `{actionText}Prompt` attachment (BuildingSpots) when it has one; otherwise `side` shifts the
-- prompt along the building's X so two prompts don't overlap.
local function addPrompt(
	model: Model,
	saved: SavedBuilding,
	actionText: string,
	menuOpen: (boolean) -> (),
	key: Enum.KeyCode,
	side: number
)
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end

	local authored: Attachment? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == `{actionText}Prompt` then
			authored = descendant
			break
		end
	end
	local attachment: Attachment
	if authored then
		attachment = authored
	else
		attachment = Instance.new("Attachment")
		attachment.Name = `{actionText}PromptAttachment`
		attachment.Parent = part
		attachment.WorldPosition = (model:GetPivot() * CFrame.new(side, PROMPT_HEIGHT, 0)).Position
	end

	-- A crop field's prompts reach from its hut, not from the field's edge
	local footprint = if BuildingData[saved.Id].Components.Field
		then Vector2.new(FarmData.HUT_FOOTPRINT, FarmData.HUT_FOOTPRINT)
		else BuildingModels.GetFootprint(saved.Id, saved.Level)
	-- Same for a resource yard
	if BuildingData[saved.Id].Components.Yard then
		footprint = Vector2.new(YardData.HUT_FOOTPRINT, YardData.HUT_FOOTPRINT)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = `{actionText}Prompt`
	prompt.ActionText = actionText
	prompt.ObjectText = BuildingData[saved.Id].Name
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = key
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(footprint.X, footprint.Y) / 2 + PROMPT_REACH
	prompt.Parent = attachment

	prompt.Triggered:Connect(function()
		menuOpen(true)
	end)
	prompt.PromptHidden:Connect(function()
		-- Rebuilding the model (e.g. after an upgrade) also hides the prompt; only close when walking away
		task.defer(function()
			if prompt.Parent then
				menuOpen(false)
			end
		end)
	end)
end

local function makeMailboxPart(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	cframe: CFrame,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CFrame = cframe
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	return part
end

-- Placeholder mailbox: a post, a box with a rounded lid, a slot on the front and a flag.
-- Built around its base at the origin with the slot facing -Z. Returns the model and its flag.
local function createPlaceholderMailbox(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Mailbox"
	makeMailboxPart(
		model,
		"Post",
		Vector3.new(0.6, 3.4, 0.6),
		MAILBOX_POST_COLOR,
		CFrame.new(0, 1.7, 0)
	)
	makeMailboxPart(
		model,
		"Box",
		Vector3.new(1.6, 1.4, 2.4),
		MAILBOX_BOX_COLOR,
		CFrame.new(0, 4.1, 0)
	)
	makeMailboxPart(
		model,
		"Lid",
		Vector3.new(2.4, 1.6, 1.6),
		MAILBOX_BOX_COLOR,
		CFrame.new(0, 4.8, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Enum.PartType.Cylinder
	)
	makeMailboxPart(
		model,
		"Slot",
		Vector3.new(1.1, 0.9, 0.1),
		MAILBOX_SLOT_COLOR,
		CFrame.new(0, 4.2, -1.22)
	)
	local flag = makeMailboxPart(
		model,
		"Flag",
		Vector3.new(0.12, 1, 0.4),
		MAILBOX_FLAG_COLOR,
		MAILBOX_FLAG_DOWN
	)
	model.WorldPivot = CFrame.new()
	return model, flag
end

-- Unread count on the prompt, and the placeholder's flag raised while there's unread mail
local function updateMailbox()
	local unread = 0
	for _, mail in ColonyStore.Mail() do
		if not mail.Read then
			unread += 1
		end
	end
	if mailboxPrompt then
		mailboxPrompt.ObjectText = if unread > 0 then `Mailbox ({unread} new)` else "Mailbox"
	end
	if mailboxFlag then
		mailboxFlag.CFrame = mailboxPivot
			* (if unread > 0 then MAILBOX_FLAG_UP else MAILBOX_FLAG_DOWN)
	end
end

-- The Town Hall mailbox, to the right of its entrance (MailboxData.GetCFrame, shared with the
-- server's reach check). Everything hangs off "MailboxAttachment" on the Town Hall: to swap in
-- a real model, add a Model named "MailboxModel" to ReplicatedStorage (pivot at its base, front
-- facing -Z) and it's placed at the attachment instead of the placeholder. A Town Hall model
-- that already has a "MailboxAttachment" keeps its authored spot (keep MailboxData's offsets
-- close to it: the server checks reach against them). Lives inside the Town Hall model, so it
-- follows it when it's moved or rebuilt.
local function createMailbox(model: Model, saved: SavedBuilding)
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end

	local found = model:FindFirstChild("MailboxAttachment", true)
	local attachment: Attachment
	if found and found:IsA("Attachment") then
		attachment = found
	else
		attachment = Instance.new("Attachment")
		attachment.Name = "MailboxAttachment"
		attachment.Parent = part
		attachment.WorldCFrame = MailboxData.GetCFrame(
			model:GetPivot(),
			BuildingModels.GetFootprint(saved.Id, saved.Level)
		)
	end
	mailboxPivot = attachment.WorldCFrame

	local template = ReplicatedStorage:FindFirstChild("MailboxModel")
	local mailbox: Model
	if template and template:IsA("Model") then
		mailbox = template:Clone()
		mailbox.Name = "Mailbox"
		mailboxFlag = nil
	else
		local flag
		mailbox, flag = createPlaceholderMailbox()
		mailboxFlag = flag
	end
	mailbox:PivotTo(mailboxPivot)
	mailbox.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MailboxPrompt"
	prompt.ActionText = "Check mail"
	prompt.ObjectText = "Mailbox"
	prompt.HoldDuration = 0
	-- G: E/F are the Town Hall's prompts and T the merchant's
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = MailboxData.REACH
	prompt.Parent = attachment
	mailboxPrompt = prompt

	prompt.Triggered:Connect(function()
		ColonyStore.MailboxOpen(true)
	end)
	prompt.PromptHidden:Connect(function()
		-- Rebuilding the Town Hall also hides the prompt; only close when walking away
		task.defer(function()
			if prompt.Parent then
				ColonyStore.MailboxOpen(false)
			end
		end)
	end)

	-- Called while the buildings effect runs; don't subscribe it to mail
	vide.untrack(updateMailbox)
end

local function createBuilding(saved: SavedBuilding, folder: Folder, townHallBuilt: boolean)
	local placement = saved.Placement
	if not placement then
		return
	end

	-- A construction site draws level 1 and reveals parts as they're built
	local isSite = not BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
	local model = BuildingModels.Create(saved.Id, math.max(saved.Level, 1))
	-- The model is drawn at level 1 or more, but the label shows the real level (the Town Hall starts at 0)
	local billboard = model:FindFirstChild("Label", true)
	local text = billboard and billboard:FindFirstChildWhichIsA("TextLabel")
	if text then
		local name = BuildingData[saved.Id].Name
		text.Text = if isSite then `{name} (construction site)` else `{name} (Lv {saved.Level})`
	end
	if isSite then
		sites[saved.Id] = BuildingBlueprint.GetBuildParts(model, saved.Id, 1)
	end
	model:SetAttribute("BuildingId", saved.Id)
	model:SetAttribute("Level", saved.Level)
	model:PivotTo(BuildingPlacement.ToCFrame(placement))
	model.Parent = folder
	ColonyStore.Models[saved.Id] = model

	-- An upgrade just finished: spring in the pieces that were still shadows (the last one placed)
	local previous = drawnLevels[saved.Id]
	drawnLevels[saved.Id] = saved.Level
	local pending = springKeys[saved.Id]
	if pending and previous and saved.Level > previous then
		local pivot = BuildingModels.GetLayoutFrame(model)
		for _, descendant in model:GetDescendants() do
			if
				descendant:IsA("BasePart")
				and pending[BuildingBlueprint.GetPartKey(pivot, descendant)]
			then
				PartSpring.Play(descendant)
			end
		end
	end

	local components = BuildingData[saved.Id].Components
	local isTownHall = saved.Id == "TownHall"
	-- Until the Town Hall is built, the Spire stands in for it: colony storage, the Manage
	-- menu and the mailbox are there (BuildingUnlocks.GetHubId)
	local isSpireHub = components.Teleporter ~= nil and not townHallBuilt
	if isSite then
		return
	end
	if components.WorkerStorage then
		addPrompt(model, saved, "Storage", openStorage(saved.Id), Enum.KeyCode.F, -SIDE_OFFSET)
	end
	if components.Storage then
		addPrompt(
			model,
			saved,
			"Storage",
			openStorage(nil),
			Enum.KeyCode.E,
			if components.Teleporter then 0 else -SIDE_OFFSET
		)
	end
	if isSpireHub then
		-- E stays the Spire's Teleport prompt
		addPrompt(model, saved, "Storage", openStorage(nil), Enum.KeyCode.F, -SIDE_OFFSET)
		addPrompt(model, saved, "Manage", ColonyStore.ManageOpen, Enum.KeyCode.R, SIDE_OFFSET)
		createMailbox(model, saved)
	end
	if isTownHall then
		addPrompt(model, saved, "Manage", ColonyStore.ManageOpen, Enum.KeyCode.F, SIDE_OFFSET)
		createMailbox(model, saved)
	elseif not components.Teleporter then
		-- Upgrade and move panel; shares the building with a Storage prompt on F
		local panelOpen = function(open: boolean)
			if open then
				ColonyStore.BuildingPanelId(saved.Id)
			elseif ColonyStore.BuildingPanelId() == saved.Id then
				ColonyStore.BuildingPanelId(nil)
			end
		end
		local hasStorage = components.Storage ~= nil or components.WorkerStorage ~= nil
		addPrompt(
			model,
			saved,
			"Manage",
			panelOpen,
			if hasStorage then Enum.KeyCode.F else Enum.KeyCode.E,
			if hasStorage then SIDE_OFFSET else 0
		)
	end
	if components.Teleporter then
		addPrompt(model, saved, "Teleport", ColonyStore.SpireMenuOpen, Enum.KeyCode.E, 0)
	end
end

local function setHidden(character: Model, hidden: boolean)
	local modifier = if hidden then 1 else 0
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = modifier
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if hidden
			then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
	end
end

-- Other players standing on the shared plot spot are in their own colony, so hide them
local function hideOthers()
	local hidden: { [Model]: boolean } = {}
	local elapsed = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < HIDE_CHECK_INTERVAL then
			return
		end
		elapsed = 0

		for _, other in Players:GetPlayers() do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if other == player or not character or not root or not root:IsA("BasePart") then
				continue
			end

			local inside = PlotData.IsInside(root.Position, BuildingUnlocks.MAX_LEVEL)
			if (hidden[character] or false) ~= inside then
				hidden[character] = inside
				setHidden(character, inside)
			end
		end

		for character in hidden do
			if not character.Parent then
				hidden[character] = nil
			end
		end
	end)
end

function ColonyView.Start()
	if started then
		return
	end
	started = true

	local folder = Instance.new("Folder")
	folder.Name = "MyColony"
	folder.Parent = workspace

	local plot = Instance.new("Part")
	plot.Name = "Plot"
	plot.Anchored = true
	plot.Material = Enum.Material.Grass
	plot.Color = PLOT_COLOR
	plot.TopSurface = Enum.SurfaceType.Smooth
	plot.Parent = folder

	local townHallLevel = source(player:GetAttribute("TownHallLevel") :: number?)
	player:GetAttributeChangedSignal("TownHallLevel"):Connect(function()
		townHallLevel(player:GetAttribute("TownHallLevel") :: number?)
	end)

	vide.root(function()
		effect(function()
			local size = PlotData.GetSize(townHallLevel() or 0)
			plot.Size = Vector3.new(size, PlotData.THICKNESS, size)
			plot.CFrame = PlotData.SURFACE * CFrame.new(0, -PlotData.THICKNESS / 2, 0)
		end)

		effect(function()
			local buildings = ColonyStore.Buildings()
			for id in sites do
				rememberUnbuilt(id)
			end
			for id, model in ColonyStore.Models do
				model:Destroy()
				ColonyStore.Models[id] = nil
			end
			for _, model in nextTiers do
				model:Destroy()
			end
			table.clear(nextTiers)
			table.clear(sites)
			table.clear(replaced)
			table.clear(replacedCollide)
			table.clear(looks)
			table.clear(shownBuilt)
			table.clear(noShadows)
			local townHallBuilt = BuildingUnlocks.IsTownHallBuilt(buildings)
			for _, saved in buildings do
				createBuilding(saved, folder, townHallBuilt)
			end
			table.clear(springKeys)
			vide.untrack(function()
				syncUpgrades()
				updateSites(false)
			end)
		end)

		effect(function()
			ColonyStore.WorkOrders()
			syncUpgrades()
			updateSites(true)
		end)

		effect(updateMailbox)
	end)

	hideOthers()
end

return ColonyView
