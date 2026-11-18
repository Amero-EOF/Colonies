--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages

const vide = require(Packages.vide)
const Net = require(Packages.Net)

const create = vide.create
const source = vide.source
const cleanup = vide.cleanup
const spring = vide.spring
const values = vide.values

-- Mirrors the server's Notifications.Kind
export type Kind =
	"Death"
	| "Job"
	| "Join"
	| "Birth"
	| "Leave"
	| "ColonyEvent"
	| "Merchant"
	| "Mail"

type Toast = {
	Id: number,
	Kind: string,
	Text: string,
}

type Style = {
	Icon: string,
	Title: string,
	Color: Color3,
}

const LIFETIME = 5
const MAX_VISIBLE = 5
const WIDTH = 300
const HEIGHT = 58
const GAP = 6
-- Leaves room for the Clock above (top right, 8 px down, 30 px tall)
const TOP_OFFSET = 46
const EXIT_TIME = 0.5
const SLIDE_DISTANCE = 60

const STYLES: { [string]: Style } = {
	Death = { Icon = "💀", Title = "Death", Color = Color3.fromRGB(220, 70, 70) },
	Job = { Icon = "🔨", Title = "New job", Color = Color3.fromRGB(240, 170, 60) },
	Join = { Icon = "👋", Title = "New colonist", Color = Color3.fromRGB(90, 190, 110) },
	Birth = { Icon = "👶", Title = "Birth", Color = Color3.fromRGB(240, 130, 190) },
	Leave = { Icon = "🚪", Title = "Departure", Color = Color3.fromRGB(150, 150, 165) },
	ColonyEvent = { Icon = "⚠", Title = "Colony event", Color = Color3.fromRGB(240, 210, 60) },
	Merchant = { Icon = "💰", Title = "Merchant", Color = Color3.fromRGB(80, 160, 230) },
	Mail = { Icon = "✉", Title = "Mail", Color = Color3.fromRGB(200, 120, 60) },
}
const DEFAULT_STYLE: Style =
	{ Icon = "•", Title = "Notice", Color = Color3.fromRGB(200, 200, 200) }

local function ToastCard(toast: Toast, present: () -> boolean): Instance
	local style = STYLES[toast.Kind] or DEFAULT_STYLE
	-- 0 hidden -> 1 shown; `present` turns false when the toast is dropped
	local shown = spring(function()
		return if present() then 1 else 0
	end, 0.35)

	return create("Frame")({
		Name = `Toast{toast.Id}`,
		-- Newest on top
		LayoutOrder = -toast.Id,
		BackgroundTransparency = 1,
		-- Collapses while leaving so the stack closes the gap smoothly
		Size = function()
			return UDim2.new(1, 0, 0, math.max(HEIGHT * shown(), 0))
		end,

		create("CanvasGroup")({
			Name = "Card",
			Size = UDim2.new(1, 0, 0, HEIGHT),
			Position = function()
				return UDim2.fromOffset((1 - shown()) * SLIDE_DISTANCE, 0)
			end,
			GroupTransparency = function()
				return math.clamp(1 - shown(), 0, 1)
			end,
			BackgroundColor3 = Color3.fromRGB(28, 28, 32),
			BackgroundTransparency = 0.1,

			create("UICorner")({ CornerRadius = UDim.new(0, 8) }),

			create("Frame")({
				Name = "Accent",
				Size = UDim2.new(0, 5, 1, 0),
				BorderSizePixel = 0,
				BackgroundColor3 = style.Color,
			}),

			create("TextLabel")({
				Name = "Icon",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(30, 30),
				BackgroundColor3 = style.Color,
				BackgroundTransparency = 0.75,
				TextColor3 = style.Color,
				TextSize = 18,
				Font = Enum.Font.GothamBold,
				Text = style.Icon,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			}),

			create("TextLabel")({
				Name = "Kind",
				Position = UDim2.fromOffset(54, 6),
				Size = UDim2.new(1, -62, 0, 14),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = style.Color,
				TextSize = 12,
				Font = Enum.Font.GothamBold,
				Text = string.upper(style.Title),
			}),

			create("TextLabel")({
				Name = "Message",
				Position = UDim2.fromOffset(54, 21),
				Size = UDim2.new(1, -62, 1, -25),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 14,
				Font = Enum.Font.GothamMedium,
				Text = toast.Text,
			}),
		}),
	})
end

-- Stack of toasts at the top right for colony news (deaths, births, jobs, merchants...)
local function Notifications()
	local toasts = source({} :: { Toast })
	local nextId = 1
	local alive = true

	local function remove(id: number)
		local list = {}
		for _, toast in toasts() do
			if toast.Id ~= id then
				table.insert(list, toast)
			end
		end
		toasts(list)
	end

	local function push(kind: unknown, text: unknown)
		if not alive or typeof(text) ~= "string" then
			return
		end
		local toast: Toast = {
			Id = nextId,
			Kind = if typeof(kind) == "string" then kind else "",
			Text = text,
		}
		nextId += 1

		local list = table.clone(toasts())
		table.insert(list, toast)
		-- Oldest drop off past the limit
		while #list > MAX_VISIBLE do
			table.remove(list, 1)
		end
		toasts(list)

		task.delay(LIFETIME, function()
			if alive then
				remove(toast.Id)
			end
		end)
	end

	-- The remote is looked up off-scope because Net waits for it on the client
	local connection: RBXScriptConnection? = nil
	task.spawn(function()
		local ok, result = pcall(function()
			return Net:Connect("Notification", push)
		end)
		if not ok then
			warn(`[Notifications] {result}`)
		elseif alive then
			connection = result
		else
			result:Disconnect()
		end
	end)
	cleanup(function()
		alive = false
		if connection then
			connection:Disconnect()
		end
	end)

	return create("Frame")({
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, TOP_OFFSET),
		Size = UDim2.fromOffset(WIDTH, (HEIGHT + GAP) * MAX_VISIBLE),
		BackgroundTransparency = 1,

		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, GAP),
		}),

		values(toasts, function(toast: Toast, _index: () -> number, present: () -> boolean)
			return ToastCard(toast, present), EXIT_TIME
		end),
	})
end

return Notifications
