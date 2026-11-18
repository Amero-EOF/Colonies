--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const UserInputService = game:GetService("UserInputService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BagMoves = require(Shared.Inventory.BagMoves)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const ColonistStore = require(script.Parent.Parent.Colony.ColonistStore)
const ColonyStore = require(script.Parent.Parent.Colony.ColonyStore)

const create = vide.create
const source = vide.source

type Bag = InventoryTypes.Bag
type ItemStack = InventoryTypes.ItemStack
type Move = BagMoves.Move

-- The stack on the mouse. It never leaves its origin slot on the server: the origin just
-- shows `Count` fewer until a placement sends a move, so dropping it loses nothing.
export type Held = {
	Ref: string,
	Slot: number,
	UniqueID: number,
	Count: number,
}

export type Button = "Left" | "Right"

type SlotKey = { Ref: string, Slot: number }
type Batch = { Id: number, Moves: { Move } }

const CURSOR_OFFSET = Vector2.new(14, 14)
const CURSOR_SIZE = 56
const TEXT_COLOR = Color3.new(1, 1, 1)
-- Seconds after a MoveItems answer before the held stack is checked against the bags again
const ANSWER_GRACE = 0.5
-- Seconds between the clicks of a double click
const DOUBLE_CLICK_TIME = 0.35
-- The server takes at most this many moves per MoveItems call
const MAX_MOVES = 40

const held = source(nil :: Held?)
-- Slots picked for a drag-distribute, in the order they were visited
const selection = source({} :: { SlotKey })
-- Moves sent but not answered yet; the grids draw them straight away
const pending = source({} :: { Batch })

-- Every mounted bag grid and the ref it currently shows
const grids: { [GuiObject]: () -> string? } = {}

local nextBatchId = 0
local lastAnswer = 0
local mouseDown = false
-- The slot a left drag started on
local pressed: SlotKey? = nil
-- Where and when the last stack was picked up with a left click, to spot a double click
local lastPickup: { Ref: string, Slot: number, Time: number }? = nil
-- Fills the held stack from matching stacks in every open bag (defined below)
local collectSame: (current: Held) -> ()
-- Shift-click: moves a stack to the other open bag (defined below)
local quickMove: (ref: string, slot: number) -> ()
local cursorLabel: TextLabel? = nil
local started = false

-- Drag-and-drop for every bag grid: left click picks up / places a stack, right click
-- splits / places one, and dragging with the left button while holding spreads the stack
-- evenly over the slots dragged across
const ItemCursor = {
	Held = held,
}

local function keyOf(ref: string, slot: number): string
	return `{ref}#{slot}`
end

-- A bag as the server last sent it
local function getServerBag(ref: string): Bag?
	local kind, id = BagMoves.ParseRef(ref)
	if kind == BagMoves.BACKPACK then
		return ColonyStore.Inventory().Bags[1]
	elseif kind == BagMoves.STORAGE then
		return ColonyStore.Storage()
	elseif kind == "Hut" and id then
		return ColonyStore.HutStorage()[id]
	elseif kind == "Colonist" and id then
		local colonist = ColonistStore.Get(tonumber(id))
		return colonist and colonist.Carried
	end
	return nil
end

-- The bag with the unanswered moves applied (`bag` overrides the store's copy)
function ItemCursor.View(ref: string?, bag: Bag?): Bag?
	local batches = pending()
	if not ref or not bag or #batches == 0 then
		return bag
	end

	local bags: { [string]: Bag } = { [ref] = BagMoves.Clone(bag) }
	local function get(other: string): Bag?
		if not bags[other] then
			local serverBag = getServerBag(other)
			if serverBag then
				bags[other] = BagMoves.Clone(serverBag)
			end
		end
		return bags[other]
	end

	for _, batch in batches do
		for _, move in batch.Moves do
			local from, to = get(move.From), get(move.To)
			if from and to then
				BagMoves.Move(from, move.FromSlot, to, move.ToSlot, move.Count)
			end
		end
	end
	return bags[ref]
end

local function viewStack(ref: string, slot: number): ItemStack?
	local bag = ItemCursor.View(ref, getServerBag(ref))
	return if bag then BagMoves.GetStack(bag, slot) else nil
end

-- Room for the held item in a slot, or nil if another item is there. The origin slot
-- counts as holding only what's left once the held stack is lifted off it.
local function getSpace(current: Held, ref: string, slot: number): number?
	local stack = viewStack(ref, slot)
	local quantity = if stack then stack.Quantity else 0
	if ref == current.Ref and slot == current.Slot then
		quantity -= current.Count
	end
	if quantity > 0 and stack and stack.UniqueID ~= current.UniqueID then
		return nil
	end
	return ItemsList.GetMaxStack(current.UniqueID) - math.max(quantity, 0)
end

local function setCount(current: Held, count: number)
	if count <= 0 then
		held(nil)
	else
		held({ Ref = current.Ref, Slot = current.Slot, UniqueID = current.UniqueID, Count = count })
	end
end

local function isShiftDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- Lets go of the held stack. It never left its origin slot on the server, so the items
-- are simply back where they were.
local function drop()
	held(nil)
	selection({})
	mouseDown = false
	pressed = nil
end

-- Sends moves to the server and shows them until it answers; on rejection the server resyncs
local function send(moves: { Move })
	nextBatchId += 1
	local id = nextBatchId
	local batches = table.clone(pending())
	table.insert(batches, { Id = id, Moves = moves })
	pending(batches)

	task.spawn(function()
		local ok, success, message = pcall(function()
			return Net:Invoke("MoveItems", moves)
		end)

		local remaining = {}
		for _, batch in pending() do
			if batch.Id ~= id then
				table.insert(remaining, batch)
			end
		end
		pending(remaining)
		lastAnswer = os.clock()

		if not ok or not success then
			ColonyStore.Notify(if ok then tostring(message) else "Couldn't move that")
		end
	end)
end

-- Where a drag-distribute would put the held items: amount per slot key, and the total
local function getPlan(): ({ [string]: number }, number)
	local current = held()
	local chosen = selection()
	if not current or #chosen == 0 then
		return {}, 0
	end

	local targets: { { Key: string, Space: number } } = {}
	for _, slotKey in chosen do
		local space = getSpace(current, slotKey.Ref, slotKey.Slot) or 0
		if space > 0 then
			table.insert(targets, { Key = keyOf(slotKey.Ref, slotKey.Slot), Space = space })
		end
	end
	if #targets == 0 then
		return {}, 0
	end

	local each = math.max(math.floor(current.Count / #targets), 1)
	local amounts: { [string]: number } = {}
	local total = 0
	for _, target in targets do
		local give = math.min(each, target.Space, current.Count - total)
		if give > 0 then
			amounts[target.Key] = give
			total += give
		end
	end
	return amounts, total
end

local function commitSelection()
	local current = held()
	local chosen = selection()
	local amounts, total = getPlan()
	selection({})
	if not current or total == 0 then
		return
	end

	local moves: { Move } = {}
	for _, slotKey in chosen do
		local count = amounts[keyOf(slotKey.Ref, slotKey.Slot)]
		local isOrigin = slotKey.Ref == current.Ref and slotKey.Slot == current.Slot
		-- Items planned for the origin never left it, so they need no move
		if count and not isOrigin then
			table.insert(moves, {
				From = current.Ref,
				FromSlot = current.Slot,
				To = slotKey.Ref,
				ToSlot = slotKey.Slot,
				Count = count,
			})
		end
	end
	if #moves > 0 then
		send(moves)
	end
	setCount(current, current.Count - total)
end

-- Adds a slot to the drag-distribute if the held item can go there
local function select(ref: string, slot: number)
	local current = held()
	if not current then
		return
	end

	local chosen = selection()
	if #chosen >= current.Count then
		return
	end
	for _, slotKey in chosen do
		if slotKey.Ref == ref and slotKey.Slot == slot then
			return
		end
	end

	local space = getSpace(current, ref, slot)
	if not space or space <= 0 then
		return
	end

	local updated = table.clone(chosen)
	table.insert(updated, { Ref = ref, Slot = slot })
	selection(updated)
end

-- Places held items on a slot: left puts as many as fit (or swaps), right puts one
local function place(current: Held, ref: string, slot: number, button: Button)
	if ref == current.Ref and slot == current.Slot then
		-- Back where it came from
		setCount(current, if button == "Left" then 0 else current.Count - 1)
		return
	end

	local stack = viewStack(ref, slot)
	local maxStack = ItemsList.GetMaxStack(current.UniqueID)
	local function moveTo(count: number)
		send({
			{ From = current.Ref, FromSlot = current.Slot, To = ref, ToSlot = slot, Count = count },
		})
	end

	if stack and stack.UniqueID ~= current.UniqueID then
		if button == "Right" then
			return
		end
		-- Swap: only the whole origin stack can trade places, then the other item is held
		local origin = viewStack(current.Ref, current.Slot)
		if not origin or origin.Quantity ~= current.Count then
			ColonyStore.Notify("Pick up the whole stack to swap")
			return
		end
		moveTo(current.Count)
		held({
			Ref = current.Ref,
			Slot = current.Slot,
			UniqueID = stack.UniqueID,
			Count = stack.Quantity,
		})
		return
	end

	local space = if stack then maxStack - stack.Quantity else maxStack
	local count = math.min(if button == "Left" then current.Count else 1, space)
	if count <= 0 then
		return
	end
	moveTo(count)
	setCount(current, current.Count - count)
end

-- Mouse button pressed on a slot of a grid showing `ref`
function ItemCursor.Press(ref: string, slot: number, button: Button)
	local current = held()
	if not current and button == "Left" and isShiftDown() then
		quickMove(ref, slot)
		return
	end
	if not current then
		local stack = viewStack(ref, slot)
		if stack then
			local count = if button == "Left" then stack.Quantity else math.ceil(stack.Quantity / 2)
			held({ Ref = ref, Slot = slot, UniqueID = stack.UniqueID, Count = count })
			lastPickup = if button == "Left"
				then { Ref = ref, Slot = slot, Time = os.clock() }
				else nil
		end
		return
	end

	-- Second click of a double click on the slot just picked up: gather matching items
	local pickup = lastPickup
	lastPickup = nil
	if
		button == "Left"
		and pickup
		and pickup.Ref == ref
		and pickup.Slot == slot
		and current.Ref == ref
		and current.Slot == slot
		and os.clock() - pickup.Time <= DOUBLE_CLICK_TIME
	then
		collectSame(current)
		return
	end

	-- Left press starts a drag: released on the same slot it's a normal place,
	-- dragged over more slots it spreads the stack. Swaps happen straight away.
	if button == "Left" and getSpace(current, ref, slot) then
		mouseDown = true
		pressed = { Ref = ref, Slot = slot }
		selection({})
		select(ref, slot)
		return
	end
	place(current, ref, slot, button)
end

-- Mouse moved onto a slot; dragging with the left button adds it to the distribute
function ItemCursor.Hover(ref: string, slot: number)
	if mouseDown and held() then
		select(ref, slot)
	end
end

-- Left button released: one slot is a plain place, several spread the stack
local function release()
	mouseDown = false
	local current = held()
	local start = pressed
	pressed = nil
	if not current or not start then
		selection({})
		return
	end

	if #selection() > 1 then
		commitSelection()
	else
		selection({})
		place(current, start.Ref, start.Slot, "Left")
	end
end

-- What a slot shows: its item and count after the held stack and the distribute preview
function ItemCursor.GetShown(ref: string?, bag: Bag?, slot: number): (number?, number, boolean)
	local stack = if bag then BagMoves.GetStack(bag, slot) else nil
	local uniqueID = stack and stack.UniqueID
	local quantity = if stack then stack.Quantity else 0
	if not ref then
		return uniqueID, quantity, false
	end

	local current = held()
	if current and current.Ref == ref and current.Slot == slot then
		quantity -= current.Count
	end

	local planned = (getPlan())[keyOf(ref, slot)]
	if current and planned then
		uniqueID = current.UniqueID
		quantity += planned
	end

	local selected = false
	for _, slotKey in selection() do
		if slotKey.Ref == ref and slotKey.Slot == slot then
			selected = true
		end
	end
	return if quantity > 0 then uniqueID else nil, math.max(quantity, 0), selected
end

-- How many are on the mouse once the distribute preview is taken off
local function getCursorCount(): number
	local current = held()
	if not current then
		return 0
	end
	local _, planned = getPlan()
	return current.Count - planned
end

local function isShown(gui: GuiObject): boolean
	local current: Instance? = gui
	while current do
		if current:IsA("GuiObject") then
			if not current.Visible then
				return false
			end
		elseif current:IsA("LayerCollector") then
			return current.Enabled and current:IsDescendantOf(Players.LocalPlayer)
		end
		current = current.Parent
	end
	return false
end

-- The panel a grid sits in: its top-most GuiObject ancestor
local function getPanel(gui: GuiObject): GuiObject
	local panel = gui
	local parent = gui.Parent
	while parent and parent:IsA("GuiObject") do
		panel = parent
		parent = parent.Parent
	end
	return panel
end

local function isOverPanel(position: Vector2): boolean
	for grid in grids do
		if isShown(grid) then
			local panel = getPanel(grid)
			local topLeft = panel.AbsolutePosition
			local bottomRight = topLeft + panel.AbsoluteSize
			if
				position.X >= topLeft.X
				and position.Y >= topLeft.Y
				and position.X <= bottomRight.X
				and position.Y <= bottomRight.Y
			then
				return true
			end
		end
	end
	return false
end

local function isOriginShown(ref: string): boolean
	for grid, getRef in grids do
		if getRef() == ref and isShown(grid) then
			return true
		end
	end
	return false
end

-- Refs of every bag grid currently on screen, in no particular order
local function getShownRefs(): { string }
	local refs: { string } = {}
	for grid, getRef in grids do
		local ref = getRef()
		if ref and isShown(grid) and not table.find(refs, ref) then
			table.insert(refs, ref)
		end
	end
	return refs
end

-- Pulls matching items into the held stack's origin slot until it's a full stack:
-- the origin's bag first, then the other open bags, smallest stacks first
function collectSame(current: Held)
	local origin = viewStack(current.Ref, current.Slot)
	if not origin then
		return
	end
	local room = ItemsList.GetMaxStack(current.UniqueID) - origin.Quantity
	if room <= 0 then
		return
	end

	local sources: { { Ref: string, Slot: number, Quantity: number, Order: number } } = {}
	for _, ref in getShownRefs() do
		local bag = ItemCursor.View(ref, getServerBag(ref))
		if bag then
			for slot = 1, BagMoves.GetSlotsCount(bag) do
				local stack = BagMoves.GetStack(bag, slot)
				local isOrigin = ref == current.Ref and slot == current.Slot
				if stack and stack.UniqueID == current.UniqueID and not isOrigin then
					table.insert(sources, {
						Ref = ref,
						Slot = slot,
						Quantity = stack.Quantity,
						Order = if ref == current.Ref then 0 else 1,
					})
				end
			end
		end
	end
	table.sort(sources, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		if a.Quantity ~= b.Quantity then
			return a.Quantity < b.Quantity
		end
		return a.Slot < b.Slot
	end)

	local moves: { Move } = {}
	local total = 0
	for _, source in sources do
		if room - total <= 0 or #moves >= MAX_MOVES then
			break
		end
		local count = math.min(source.Quantity, room - total)
		table.insert(moves, {
			From = source.Ref,
			FromSlot = source.Slot,
			To = current.Ref,
			ToSlot = current.Slot,
			Count = count,
		})
		total += count
	end
	if total == 0 then
		return
	end

	send(moves)
	setCount(current, current.Count + total)
end

-- Shift-click target: the backpack for a stack in another bag, otherwise the first other
-- open bag (by name, so it's always the same one)
local function getQuickTarget(ref: string): string?
	local others = {}
	for _, other in getShownRefs() do
		if other ~= ref then
			table.insert(others, other)
		end
	end
	if ref ~= BagMoves.BACKPACK and table.find(others, BagMoves.BACKPACK) then
		return BagMoves.BACKPACK
	end
	table.sort(others)
	return others[1]
end

-- Shift-click: sends the whole stack to the first slots with room in the other open bag
function quickMove(ref: string, slot: number)
	local stack = viewStack(ref, slot)
	local target = getQuickTarget(ref)
	local bag = target and ItemCursor.View(target, getServerBag(target))
	if not stack or not target or not bag then
		return
	end
	local maxStack = ItemsList.GetMaxStack(stack.UniqueID)
	local left = stack.Quantity
	local moves: { Move } = {}
	for toSlot = 1, BagMoves.GetSlotsCount(bag) do
		if left <= 0 or #moves >= MAX_MOVES then
			break
		end
		local other = BagMoves.GetStack(bag, toSlot)
		local space = if not other
			then maxStack
			elseif other.UniqueID == stack.UniqueID then maxStack - other.Quantity
			else 0
		if space > 0 then
			local count = math.min(space, left)
			table.insert(
				moves,
				{ From = ref, FromSlot = slot, To = target, ToSlot = toSlot, Count = count }
			)
			left -= count
		end
	end
	if #moves == 0 then
		ColonyStore.Notify("No room in the other inventory")
		return
	end
	send(moves)
end

-- Drops the held stack when its origin closed, emptied or changed item, and clamps its count
local function checkHeld()
	local current = held()
	if not current then
		return
	end
	if not isOriginShown(current.Ref) then
		drop()
		return
	end
	-- Right after an answer the matching state may still be on its way
	if #pending() > 0 or os.clock() - lastAnswer < ANSWER_GRACE then
		return
	end
	local origin = viewStack(current.Ref, current.Slot)
	if not origin or origin.UniqueID ~= current.UniqueID then
		drop()
	elseif origin.Quantity < current.Count then
		setCount(current, origin.Quantity)
	end
end

local function CursorGui()
	local label = create("TextLabel")({
		Name = "HeldStack",
		Size = UDim2.fromOffset(CURSOR_SIZE, CURSOR_SIZE),
		BackgroundColor3 = Color3.fromRGB(80, 80, 80),
		BackgroundTransparency = 0.15,
		TextColor3 = TEXT_COLOR,
		TextStrokeTransparency = 0.5,
		TextSize = 13,
		TextWrapped = true,
		Active = false,
		Visible = function()
			return held() ~= nil
		end,
		Text = function()
			local current = held()
			if not current then
				return ""
			end
			local name = ItemsList.GetDisplayName(current.UniqueID) or "?"
			return `{name}\n{getCursorCount()}`
		end,

		create("UICorner")({}),
		create("UIStroke")({ Color = Color3.fromRGB(255, 210, 110), Thickness = 1.5 }),
	})
	cursorLabel = label

	return create("ScreenGui")({
		Name = "ItemCursor",
		DisplayOrder = 100,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		label,
	})
end

-- A grid shows `getRef()`'s bag; the held stack drops when no shown grid has its origin
function ItemCursor.Register(grid: GuiObject, getRef: () -> string?)
	grids[grid] = getRef
end

function ItemCursor.Unregister(grid: GuiObject)
	grids[grid] = nil
end

-- Mounts the cursor and listens for input; safe to call from every grid
function ItemCursor.Start()
	if started then
		return
	end
	started = true

	task.defer(function()
		vide.mount(CursorGui, Players.LocalPlayer:WaitForChild("PlayerGui"))
	end)

	UserInputService.InputBegan:Connect(function(input)
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
		-- Clicking away from every bag panel puts the stack back
		if isClick and held() then
			local position = Vector2.new(input.Position.X, input.Position.Y)
			if not isOverPanel(position) then
				drop()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and mouseDown then
			release()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not held() then
			return
		end
		checkHeld()
		if cursorLabel then
			local mouse = UserInputService:GetMouseLocation() + CURSOR_OFFSET
			cursorLabel.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		end
	end)
end

return ItemCursor
