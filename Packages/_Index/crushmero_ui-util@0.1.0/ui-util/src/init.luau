--!strict

local ExtendedTweenService = require(script.Parent.ExtendedTweenService)
local TweenService = game:GetService("TweenService")

local UIUtil = {}

type TransparencyCache = {
	Transparency: (number | NumberSequence)?,
	BackgroundTransparency: number?,
	ImageTransparency: number?,
	TextTransparency: number?,
	TextStrokeTransparency: number?,
	ScrollBarImageTransparency: number?,
	GroupTransparency: number?,
}

type UITransparencyCacheList = { [Instance]: TransparencyCache }

function UIUtil.cacheUITransparencies(ui: GuiBase2d): UITransparencyCacheList
	local cache = {}
	for _, v in ui:GetDescendants() do
		local cacheEntry = {}
		if v:IsA("UIStroke") or v:IsA("UIGradient") or v:IsA("UIShadow") then
			cacheEntry.Transparency = v.Transparency
		end
		if v:IsA("GuiObject") then
			cacheEntry.BackgroundTransparency = v.BackgroundTransparency
		end

		if v:IsA("ImageLabel") or v:IsA("ImageButton") or v:IsA("ViewportFrame") then
			cacheEntry.ImageTransparency = v.ImageTransparency
		end

		if v:IsA("TextLabel") or v:IsA("TextBox") or v:IsA("TextButton") then
			cacheEntry.TextTransparency = v.TextTransparency
			cacheEntry.TextStrokeTransparency = v.TextStrokeTransparency
		end

		if v:IsA("ScrollingFrame") then
			cacheEntry.ScrollBarImageTransparency = v.ScrollBarImageTransparency
		end

		if v:IsA("CanvasGroup") then
			cacheEntry.GroupTransparency = v.GroupTransparency
		end

		local isEmpty = next(cacheEntry) == nil
		if isEmpty then
			cache[v] = nil
			continue
		end
		cache[v] = cacheEntry
	end
	return cache
end

function UIUtil.restoreUITransparencies(
	ui: GuiBase2d,
	cache: UITransparencyCacheList,
	tweenInfo: TweenInfo?
)
	local hideTweenInfo = tweenInfo
		or TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)

	for instance, transparencyCache in cache do
		for property, value in transparencyCache do
			if typeof(value) == "NumberSequence" then
				ExtendedTweenService.TweenSequence(
					instance :: never,
					property,
					value,
					hideTweenInfo
				)
			else
				TweenService:Create(instance :: never, hideTweenInfo, { [property] = value }):Play()
			end
		end
	end
end

local function rebuildNumberInvisibleSequence(sequence: NumberSequence)
	local keypoints = sequence.Keypoints
	local newKeypoints = {}
	for _, v in keypoints do
		table.insert(newKeypoints, NumberSequenceKeypoint.new(v.Time, 1))
	end
	return NumberSequence.new(newKeypoints)
end

function UIUtil.hideUITransparencies(
	ui: GuiBase2d,
	cache: UITransparencyCacheList,
	tweenInfo: TweenInfo?
)
	local hideTweenInfo = tweenInfo
		or TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)

	for instance, transparencyCache in cache do
		for property, value in transparencyCache do
			-- type to remove attempting dynamic property access
			if typeof(value) == "NumberSequence" then
				local goalValue = rebuildNumberInvisibleSequence(value)
				ExtendedTweenService.TweenSequence(
					instance :: never,
					property,
					goalValue,
					hideTweenInfo
				)
			else
				TweenService:Create(instance :: never, hideTweenInfo, { [property] = 1 }):Play()
			end
		end
	end
end

return UIUtil
