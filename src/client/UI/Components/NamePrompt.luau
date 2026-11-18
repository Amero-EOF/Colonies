--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const ColonyData = require(Shared.Colony.ColonyData)

const create = vide.create
const source = vide.source
const changed = vide.changed

const TEXT_COLOR = Color3.new(1, 1, 1)

type Props = {
	Title: string,
	ButtonText: string,
	LayoutOrder: number?,
	-- Called after the server accepted the name
	OnSaved: (() -> ())?,
}

-- Text box plus button that asks the server to set the colony name
local function NameField(props: Props)
	local text = source("")
	local status = source("")
	local busy = false

	local function submit()
		if busy then
			return
		end
		busy = true
		status("...")

		task.spawn(function()
			local ok, message = Net:Invoke("SetColonyName", text())
			busy = false
			status(tostring(message))
			if ok and props.OnSaved then
				props.OnSaved()
			end
		end)
	end

	return create("Frame")({
		Name = "NameField",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,

		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),

		create("TextLabel")({
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			TextColor3 = TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 18,
			Text = props.Title,
		}),

		create("TextBox")({
			Name = "Input",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = Color3.fromRGB(55, 55, 55),
			TextColor3 = TEXT_COLOR,
			PlaceholderText = `{ColonyData.NAME_MIN}-{ColonyData.NAME_MAX} characters`,
			ClearTextOnFocus = false,
			TextSize = 16,
			Text = "",

			changed("Text", text),
			FocusLost = function(enterPressed: boolean)
				if enterPressed then
					submit()
				end
			end,

			create("UICorner")({}),
		}),

		create("TextLabel")({
			Name = "Status",
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 14,
			Text = status,
		}),

		create("TextButton")({
			Name = "Submit",
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = Color3.fromRGB(45, 90, 45),
			TextColor3 = TEXT_COLOR,
			TextSize = 16,
			Text = props.ButtonText,
			Activated = submit,

			create("UICorner")({}),
		}),
	})
end

-- Blocking popup shown until the colony has a name
local function NamePrompt()
	return create("Frame")({
		Name = "NamePrompt",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Active = true,
		ZIndex = 10,

		create("Frame")({
			Name = "Window",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(340, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),

			create("UICorner")({}),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
			}),

			NameField({ Title = "Name your colony", ButtonText = "Found colony" }),
		}),
	})
end

return {
	NamePrompt = NamePrompt,
	NameField = NameField,
}
