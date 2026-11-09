--!strict
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

export type Categories<T> = T

export type UIType<T> = {
	Name: string,
	Categories: { Categories<T> },
	UI: (target: any, ...any) -> () -> (),
}

local UITypes: { UIType<any> }? = nil
local Categories: { Categories<any> }? = nil
local UIController = {}

local ActiveUI = {}

function UIController:Init<T>(newUITypes: { UIType<T> }, newCategories: { Categories<T> })
	if not newUITypes then
		error("UITypes not found")
	end
	if not newCategories then
		error("Categories not found")
	end
	UITypes = newUITypes
	Categories = newCategories
end

local function isInitialized()
	return UITypes and Categories
end

function UIController:CreateUI(UIType: string, target: GuiBase?, ...: any)
	if not isInitialized() then
		error("UITypes not found")
	end
	if target and (typeof(target) ~= "Instance" or not target:IsA("GuiBase")) then
		error(`Target ({target}) is not a GuiBase {debug.traceback()}`)
	end

	if not UIType then
		error("UIType not found")
	end

	local UITypeData = nil
	for _, v in UITypes :: { UIType<any> } do
		if v.Name == UIType then
			UITypeData = v
			break
		end
	end

	if not UITypeData then
		error(`UITypeData not found, {UIType} {debug.traceback()}`)
	end

	if not target then
		local newtarget = Instance.new("ScreenGui")
		newtarget.Name = UIType
		newtarget.Parent = Players.LocalPlayer.PlayerGui
		target = newtarget
	end
	local id = HttpService:GenerateGUID(false)

	local UI = UITypeData.UI(target, ...)
	if not ActiveUI[UITypeData.Name] then
		ActiveUI[UITypeData.Name] = {}
	end

	ActiveUI[UITypeData.Name][id] = {
		UI = UI,
		target = target,
	}
	return id
end

local function toggleUI(UIType: string, Enabled: boolean, id: string?)
	if not ActiveUI[UIType] then
		return
	end
	if id then
		if not (ActiveUI[UIType] and ActiveUI[UIType][id]) then
			return
		end
		local target = ActiveUI[UIType][id].target
		if not target then
			error(`Target not found, {UIType} {id} {debug.traceback()}`)
		end
		if target:IsA("LayerCollector") then
			target.Enabled = Enabled
		elseif target:IsA("GuiObject") then
			target.Visible = Enabled
		end
		return
	end

	for _, v in ActiveUI[UIType] do
		if not v.target then
			error(`Target not found, {UIType} {debug.traceback()}`)
		end
		if v.target:IsA("LayerCollector") then
			v.target.Enabled = Enabled
		elseif v.target:IsA("GuiObject") then
			v.target.Visible = Enabled
		end
	end
end

function UIController:DisableUI(UIType: string, id: string?)
	toggleUI(UIType, false, id)
end

function UIController:EnableUI(UIType: string, id: string?)
	toggleUI(UIType, true, id)
end

local function toggleUICategory(UICategory: string, Enabled: boolean)
	if not isInitialized() then
		error("UITypes not found")
	end
	for _, uiData in UITypes :: { UIType<any> } do
		if not (ActiveUI[uiData.Name] and table.find(uiData.Categories, UICategory)) then
			continue
		end
		for id, _ in ActiveUI[uiData.Name] do
			toggleUI(uiData.Name, Enabled, id)
		end
	end
end

function UIController:EnableUICategory(UICategory: string)
	toggleUICategory(UICategory, true)
end

function UIController:DisableUICategory(UICategory: string)
	toggleUICategory(UICategory, false)
end

function UIController:DestroyUI(UIType: string, id: string?)
	if not ActiveUI[UIType] then
		return
	end

	if id then
		local uiData = ActiveUI[UIType][id]
		if not uiData then
			return
		end
		if uiData.UI then
			uiData.UI()
		end

		if uiData.target then
			uiData.target:Destroy()
		end
		ActiveUI[UIType][id] = nil
		if not next(ActiveUI[UIType]) then
			ActiveUI[UIType] = nil
		end
		return
	end

	for id, v in ActiveUI[UIType] do
		if v.UI then
			v.UI()
		end
		if v.target then
			v.target:Destroy()
		end
		ActiveUI[UIType][id] = nil
	end
end

return UIController