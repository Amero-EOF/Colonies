--!strict

const HttpService = game:GetService("HttpService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonistStore = require(script.Parent.Parent.Parent.Colony.ColonistStore)

const create = vide.create
const show = vide.show
const derive = vide.derive
const untrack = vide.untrack

type Family = ColonistTypes.Family

-- A colonist or a departed one, as the tree draws it
type Member = {
	Id: number,
	Name: string,
	Gender: ColonistTypes.Gender,
	Family: Family,
	-- Second line on the card: job, "Child", "Died"...
	Subtitle: string,
	Gone: boolean,
}

type Card = { Member: Member, X: number, Y: number }
type Link = { Kind: "Marriage" | "Child", From: Vector2, To: Vector2 }
type Layout = { Cards: { Card }, Links: { Link }, Size: Vector2, FocusCentre: Vector2 }

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(170, 170, 170)
const FOCUS_COLOR = Color3.fromRGB(70, 90, 140)
const MALE_COLOR = Color3.fromRGB(52, 62, 78)
const FEMALE_COLOR = Color3.fromRGB(78, 52, 66)
const GONE_COLOR = Color3.fromRGB(40, 40, 40)
const CHILD_LINE_COLOR = Color3.fromRGB(150, 150, 150)
const MARRIAGE_LINE_COLOR = Color3.fromRGB(230, 190, 90)

const PANEL_SIZE = Vector2.new(660, 440)
const TITLE_HEIGHT = 30
const PANEL_PADDING = 12
-- Visible area of the tree inside the panel
const VIEW_SIZE =
	Vector2.new(PANEL_SIZE.X - PANEL_PADDING * 2, PANEL_SIZE.Y - PANEL_PADDING * 2 - TITLE_HEIGHT)

const CARD_W = 120
const CARD_H = 44
-- Space between spouses (the marriage line spans it)
const COUPLE_GAP = 28
-- Space between neighbouring family units
const H_GAP = 18
const ROW_GAP = 56
const PAD = 16
-- Rows: 0 grandparents, 1 parents, 2 the colonist and siblings, 3 children, 4 grandchildren
const FOCUS_ROW = 2
const LAST_ROW = 4

-------- Data --------

local function getMember(id: number?): Member?
	if not id then
		return nil
	end
	local colonist = ColonistStore.Get(id)
	if colonist then
		return {
			Id = colonist.Id,
			Name = colonist.Name,
			Gender = colonist.Gender,
			Family = colonist.Family,
			Subtitle = colonist.Job or (if colonist.Age == "Child" then "Child" else "Unemployed"),
			Gone = false,
		}
	end
	local departed = ColonistStore.GetDeparted(id)
	if departed then
		return {
			Id = departed.Id,
			Name = departed.Name,
			Gender = departed.Gender,
			Family = departed.Family,
			Subtitle = if departed.Fate == "Died" then "Died" else "Left the colony",
			Gone = true,
		}
	end
	return nil
end

-- Oldest first (ids grow with arrival/birth)
local function getMembers(ids: { number }): { Member }
	local members = {}
	for _, id in ids do
		local member = getMember(id)
		if member then
			table.insert(members, member)
		end
	end
	table.sort(members, function(a, b)
		return a.Id < b.Id
	end)
	return members
end

-- Father before mother
local function getParents(member: Member): { Member }
	local parents = getMembers(member.Family.Parents)
	table.sort(parents, function(a, b)
		if a.Gender ~= b.Gender then
			return a.Gender == "Male"
		end
		return a.Id < b.Id
	end)
	return parents
end

-------- Layout --------

local function rowY(row: number): number
	return row * (CARD_H + ROW_GAP)
end

local function coupleWidth(count: number): number
	return if count >= 2 then CARD_W * 2 + COUPLE_GAP elseif count == 1 then CARD_W else 0
end

-- Card positions and connecting lines: grandparents and parents above the colonist,
-- the colonist and siblings in the middle, each with spouse, children and grandchildren below
local function layout(focus: Member): Layout
	local cards: { Card } = {}
	local links: { Link } = {}
	local placed: { [number]: boolean } = {}

	local function addCard(member: Member, centreX: number, row: number)
		placed[member.Id] = true
		table.insert(cards, { Member = member, X = centreX - CARD_W / 2, Y = rowY(row) })
	end

	local function addMarriage(leftX: number, rightX: number, row: number)
		local y = rowY(row) + CARD_H / 2
		table.insert(
			links,
			{ Kind = "Marriage", From = Vector2.new(leftX, y), To = Vector2.new(rightX, y) }
		)
	end

	local function addChildLink(from: Vector2, childCentreX: number, childRow: number)
		table.insert(
			links,
			{ Kind = "Child", From = from, To = Vector2.new(childCentreX, rowY(childRow)) }
		)
	end

	-- Draws one or two people centred on x (husband left). Returns where lines to their
	-- children start (middle of the marriage line, or under a single parent) and the
	-- centre of `member`'s own card.
	local function addCouple(
		member: Member,
		spouse: Member?,
		centreX: number,
		row: number
	): (Vector2, number)
		if not spouse then
			addCard(member, centreX, row)
			return Vector2.new(centreX, rowY(row) + CARD_H), centreX
		end
		local offset = (CARD_W + COUPLE_GAP) / 2
		local memberOnLeft = not (member.Gender == "Female" and spouse.Gender == "Male")
		local memberX = if memberOnLeft then centreX - offset else centreX + offset
		local spouseX = if memberOnLeft then centreX + offset else centreX - offset
		addCard(member, memberX, row)
		addCard(spouse, spouseX, row)
		addMarriage(centreX - COUPLE_GAP / 2, centreX + COUPLE_GAP / 2, row)
		return Vector2.new(centreX, rowY(row) + CARD_H / 2), memberX
	end

	-- Width of a person's unit: them and their spouse above all their descendants down to LAST_ROW
	local measuring: { [number]: boolean } = {}
	local function measure(member: Member, row: number): number
		if measuring[member.Id] then
			return CARD_W
		end
		measuring[member.Id] = true
		local width = coupleWidth(if getMember(member.Family.Spouse) then 2 else 1)
		if row < LAST_ROW then
			local children = getMembers(member.Family.Children)
			local total = H_GAP * math.max(#children - 1, 0)
			for _, child in children do
				total += measure(child, row + 1)
			end
			width = math.max(width, total)
		end
		measuring[member.Id] = nil
		return width
	end

	-- Places a person's unit in [left, left + width]; returns the centre of their card
	local function placeUnit(member: Member, row: number, left: number): number
		local centreX = left + measure(member, row) / 2
		local spouse = getMember(member.Family.Spouse)
		if spouse and placed[spouse.Id] then
			spouse = nil
		end
		local anchor, memberX = addCouple(member, spouse, centreX, row)
		if row >= LAST_ROW then
			return memberX
		end

		local children = {}
		for _, child in getMembers(member.Family.Children) do
			if not placed[child.Id] then
				table.insert(children, child)
			end
		end
		local total = H_GAP * math.max(#children - 1, 0)
		for _, child in children do
			total += measure(child, row + 1)
		end
		local childLeft = centreX - total / 2
		for _, child in children do
			local childWidth = measure(child, row + 1)
			addChildLink(anchor, placeUnit(child, row + 1, childLeft), row + 1)
			childLeft += childWidth + H_GAP
		end
		return memberX
	end

	-- Middle row: the colonist and every sibling (children of either parent), oldest first
	local parents = getParents(focus)
	for _, parent in parents do
		placed[parent.Id] = true
	end
	local siblings: { Member } = { focus }
	local seen: { [number]: boolean } = { [focus.Id] = true }
	for _, parent in parents do
		for _, sibling in getMembers(parent.Family.Children) do
			if not seen[sibling.Id] then
				seen[sibling.Id] = true
				table.insert(siblings, sibling)
			end
		end
	end
	table.sort(siblings, function(a, b)
		return a.Id < b.Id
	end)

	local siblingCentres: { number } = {}
	local x = 0
	for _, sibling in siblings do
		local width = measure(sibling, FOCUS_ROW)
		table.insert(siblingCentres, placeUnit(sibling, FOCUS_ROW, x))
		x += width + H_GAP
	end
	local spanCentre = (x - H_GAP) / 2

	-- Parents above, spread apart far enough for both sets of grandparents
	if #parents > 0 then
		local grandparents: { { Member } } = {}
		for i, parent in parents do
			grandparents[i] = getParents(parent)
		end

		local parentRow = FOCUS_ROW - 1
		local parentCentres: { number } = {}
		local anchor: Vector2
		if #parents == 1 then
			parentCentres[1] = spanCentre
			addCard(parents[1], spanCentre, parentRow)
			anchor = Vector2.new(spanCentre, rowY(parentRow) + CARD_H)
		else
			local apart = math.max(
				CARD_W + COUPLE_GAP,
				(coupleWidth(#grandparents[1]) + coupleWidth(#grandparents[2])) / 2 + H_GAP
			)
			parentCentres[1] = spanCentre - apart / 2
			parentCentres[2] = spanCentre + apart / 2
			addCard(parents[1], parentCentres[1], parentRow)
			addCard(parents[2], parentCentres[2], parentRow)
			addMarriage(parentCentres[1] + CARD_W / 2, parentCentres[2] - CARD_W / 2, parentRow)
			anchor = Vector2.new(spanCentre, rowY(parentRow) + CARD_H / 2)
		end
		for _, centre in siblingCentres do
			addChildLink(anchor, centre, FOCUS_ROW)
		end

		for i, list in grandparents do
			if #list > 0 then
				local grandAnchor = addCouple(list[1], list[2], parentCentres[i], parentRow - 1)
				addChildLink(grandAnchor, parentCentres[i], parentRow)
			end
		end
	end

	-- Move everything so the top-left card sits at PAD
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, card in cards do
		minX, minY = math.min(minX, card.X), math.min(minY, card.Y)
		maxX, maxY = math.max(maxX, card.X + CARD_W), math.max(maxY, card.Y + CARD_H)
	end
	local shift = Vector2.new(PAD - minX, PAD - minY)
	local focusCentre = Vector2.zero
	for _, card in cards do
		card.X += shift.X
		card.Y += shift.Y
		if card.Member.Id == focus.Id then
			focusCentre = Vector2.new(card.X + CARD_W / 2, card.Y + CARD_H / 2)
		end
	end
	for _, link in links do
		link.From += shift
		link.To += shift
	end

	return {
		Cards = cards,
		Links = links,
		Size = Vector2.new(maxX - minX + PAD * 2, maxY - minY + PAD * 2),
		FocusCentre = focusCentre,
	}
end

-------- Drawing --------

local function controlPoint(position: Vector2, left: Vector2?, right: Vector2?): Path2DControlPoint
	local zero = UDim2.new()
	return Path2DControlPoint.new(
		UDim2.fromOffset(position.X, position.Y),
		if left then UDim2.fromOffset(left.X, left.Y) else zero,
		if right then UDim2.fromOffset(right.X, right.Y) else zero
	)
end

-- A Path2D line: straight between spouses, an S-curve from the parents down to a child
local function drawLink(link: Link, offset: Vector2): Path2D
	local from, to = link.From + offset, link.To + offset
	local path = create("Path2D")({
		Color3 = if link.Kind == "Marriage" then MARRIAGE_LINE_COLOR else CHILD_LINE_COLOR,
		Thickness = if link.Kind == "Marriage" then 3 else 2,
		ZIndex = 1,
	}) :: Path2D

	if link.Kind == "Marriage" then
		path:SetControlPoints({ controlPoint(from), controlPoint(to) })
	else
		-- Tangents are relative to their point: leave straight down, arrive straight down
		local bend = Vector2.new(0, (to.Y - from.Y) * 0.6)
		path:SetControlPoints({ controlPoint(from, nil, bend), controlPoint(to, -bend, nil) })
	end
	return path
end

local function drawCard(card: Card, focusId: number, offset: Vector2)
	local member = card.Member
	local isFocus = member.Id == focusId
	local color = if isFocus
		then FOCUS_COLOR
		elseif member.Gone then GONE_COLOR
		elseif member.Gender == "Male" then MALE_COLOR
		else FEMALE_COLOR

	return create("TextButton")({
		Position = UDim2.fromOffset(card.X + offset.X, card.Y + offset.Y),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = color,
		AutoButtonColor = not isFocus,
		Text = "",
		ZIndex = 2,
		Activated = function()
			-- Walk the tree by clicking relatives
			ColonistStore.FamilyTreeId(member.Id)
		end,

		create("UICorner")({}),
		create("UIStroke")({
			Color = if isFocus then Color3.fromRGB(150, 180, 255) else Color3.fromRGB(90, 90, 90),
			Thickness = if isFocus then 2 else 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 18),
			BackgroundTransparency = 1,
			TextColor3 = if member.Gone then MUTED_COLOR else TEXT_COLOR,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Enum.Font.GothamMedium,
			Text = member.Name,
			ZIndex = 3,
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(6, 22),
			Size = UDim2.new(1, -12, 0, 16),
			BackgroundTransparency = 1,
			TextColor3 = MUTED_COLOR,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = member.Subtitle,
			ZIndex = 3,
		}),
	})
end

-- Changes only when something the tree shows changes (the store is resent every second)
local function getSignature(): string
	local rows = {}
	for _, colonist in ColonistStore.Colonists() do
		table.insert(
			rows,
			{ colonist.Id, colonist.Name, colonist.Age, colonist.Job or "", colonist.Family }
		)
	end
	for _, departed in ColonistStore.Departed() do
		table.insert(rows, { departed.Id, departed.Fate })
	end
	return `{ColonistStore.FamilyTreeId()}:{HttpService:JSONEncode(rows)}`
end

-- Genealogy chart from grandparents to grandchildren, joined by Path2D lines. Click a card to recentre.
local function FamilyTree()
	return show(function()
		return getMember(ColonistStore.FamilyTreeId()) ~= nil
	end, function()
		local signature = derive(getSignature)
		local scroller: ScrollingFrame

		-- Rebuilds the chart; centred in the view when small, scrolled to the colonist when large
		local function chart()
			signature()
			return untrack(function()
				local focus = getMember(ColonistStore.FamilyTreeId())
				if not focus then
					return {}
				end
				local tree = layout(focus)
				local canvas = Vector2.new(
					math.max(tree.Size.X, VIEW_SIZE.X),
					math.max(tree.Size.Y, VIEW_SIZE.Y)
				)
				local offset = (canvas - tree.Size) / 2

				local children: { Instance } = {}
				for _, link in tree.Links do
					table.insert(children, drawLink(link, offset))
				end
				for _, card in tree.Cards do
					table.insert(children, drawCard(card, focus.Id, offset))
				end

				local centre = tree.FocusCentre + offset
				task.defer(function()
					scroller.CanvasSize = UDim2.fromOffset(canvas.X, canvas.Y)
					scroller.CanvasPosition = Vector2.new(
						math.clamp(centre.X - VIEW_SIZE.X / 2, 0, canvas.X - VIEW_SIZE.X),
						math.clamp(centre.Y - VIEW_SIZE.Y / 2, 0, canvas.Y - VIEW_SIZE.Y)
					)
				end)

				-- Path2D points are relative to this holder
				return create("Frame")({
					Size = UDim2.fromOffset(canvas.X, canvas.Y),
					BackgroundTransparency = 1,
					children,
				})
			end)
		end

		scroller = create("ScrollingFrame")({
			Position = UDim2.fromOffset(0, TITLE_HEIGHT),
			Size = UDim2.new(1, 0, 1, -TITLE_HEIGHT),
			BackgroundColor3 = Color3.fromRGB(22, 22, 22),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollingDirection = Enum.ScrollingDirection.XY,
			CanvasSize = UDim2.new(),

			chart,
		}) :: ScrollingFrame

		return create("Frame")({
			Name = "FamilyTree",
			AnchorPoint = Vector2.new(0.5, 0.5),
			-- Left of centre so the colonist menu on the right stays visible
			Position = UDim2.new(0.5, -170, 0.5, 0),
			Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BackgroundTransparency = 0.05,

			create("UICorner")({}),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, PANEL_PADDING),
				PaddingRight = UDim.new(0, PANEL_PADDING),
				PaddingTop = UDim.new(0, PANEL_PADDING),
				PaddingBottom = UDim.new(0, PANEL_PADDING),
			}),

			create("TextLabel")({
				Size = UDim2.new(1, -36, 0, 22),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 18,
				Text = function()
					signature()
					local focus = untrack(function()
						return getMember(ColonistStore.FamilyTreeId())
					end)
					return if focus then `{focus.Name}'s family` else ""
				end,
			}),

			create("TextButton")({
				Name = "Close",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(30, 26),
				BackgroundColor3 = Color3.fromRGB(110, 50, 50),
				TextColor3 = TEXT_COLOR,
				TextSize = 16,
				Text = "X",
				ZIndex = 4,
				Activated = function()
					ColonistStore.FamilyTreeId(nil)
				end,
				create("UICorner")({}),
			}),

			scroller,
		})
	end)
end

return FamilyTree
