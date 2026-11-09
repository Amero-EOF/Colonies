local Signal = require(script.Parent.Signal)

local SheetService = {
	SheetInfo = {},
}
export type SheetInfo = {
	dimensions: Vector2,
	spriteCount: Vector2,
	offset: Vector2,
	-- Edge offsets for the sprite sheet so if the sprite sheet is 4x4 you can
	-- push the start by startEdge frames so that it's 1 frame in or you can
	-- trim the end by endEdge frames.
	edgeOffset: {
		startEdge: number,
		endEdge: number,
	}?,
	image: ImageLabel,
	frameRate: number,
	-- delay before the animation starts
	delayTime: number?,
	delayBeforeRepeat: number?,
	repeatCount: number?,
	reverses: boolean?,
	invert: boolean?,
}
function SheetService:Create(SheetInfo: SheetInfo)
	local dimensions = SheetInfo.dimensions
	local offset = SheetInfo.offset

	local edgeOffset = SheetInfo.edgeOffset
	local startOffset = 0
	local endOffset = 0
	if edgeOffset then
		startOffset = (edgeOffset.startEdge or 0) * dimensions.X
		endOffset = (edgeOffset.endEdge or 0) * dimensions.X
	end

	local spriteCount = SheetInfo.spriteCount
	local image = SheetInfo.image
	local frameRate = SheetInfo.frameRate
	local reverses = SheetInfo.reverses or false
	local invert = SheetInfo.invert or false
	local delayTime = SheetInfo.delayTime or 0
	local delayBeforeRepeat = SheetInfo.delayBeforeRepeat or 0

	if SheetInfo.repeatCount then
		if SheetInfo.repeatCount == 0 then
			SheetInfo.repeatCount = 0
		end
	else
		SheetInfo.repeatCount = -1
	end

	local width = dimensions.X
	local height = dimensions.Y

	local xOffset = offset.X
	local yOffset = offset.Y

	image.ImageRectOffset = offset
	image.ImageRectSize = dimensions

	if width > 1024 or dimensions.Y > 1024 then
		error(`[Utility.SpriteSheet] - Improper Width/Height out of range 0-1024 pixels  ( {width} x {height} )`)
	end

	if spriteCount.X <= 0 or spriteCount.Y <= 0 then
		error(`[Utility.SpriteSheet] - improper sprite count Vector2.new(x >= 1,y >= 1)`)
	end
	local endAnim = dimensions * (spriteCount - Vector2.one) + offset

	local x = if invert then endAnim.X - endOffset else xOffset + startOffset
	local y = if invert then endAnim.Y else yOffset
	local reversing = if invert then true else false

	local function forwards(imageEnd)
		image.ImageRectOffset = Vector2.new(x, y)

		local isEndOffset = (y == imageEnd.Y and x == imageEnd.X - endOffset)
		x += width

		if x > imageEnd.X or isEndOffset then
			x = xOffset
			y += height

			if y > imageEnd.Y then
				--reversing = not reversing
				y = yOffset
				return true
			end
		end
		return false
	end

	local function reverse(imageEnd)
		image.ImageRectOffset = Vector2.new(x, y)

		local isEndOffset = (y == offset.Y and x == offset.X + startOffset)
		x -= width

		if x < offset.X or isEndOffset then
			x = imageEnd.X
			y -= height

			if y < offset.Y then
				--reversing = not reversing
				y = imageEnd.Y
				return true
			end
		end
		return false
	end

	local SpriteSheetObject = {}
	local completedSignal = Signal.new()
	SpriteSheetObject.Completed = completedSignal
	local counter = 0
	local cancelled = false
	local function loop()
		task.wait(frameRate + (delayTime or 0))
		while not cancelled and image and image.Parent do
			local endingLoop = false
			if reversing then
				endingLoop = reverse(endAnim)
			else
				endingLoop = forwards(endAnim)
			end

			if reverses and endingLoop then
				if invert then
					if not reversing then
						x, y = endAnim.X - endOffset, endAnim.Y
					else
						x, y = offset.X + startOffset, offset.Y
					end
				else
					if not reversing then
						x, y = endAnim.X - endOffset, endAnim.Y
					else
						x, y = offset.X + startOffset, offset.Y
					end
				end

				reversing = not reversing
				image.ImageRectOffset = Vector2.new(x, y)
				continue
			end

			if endingLoop and counter >= SheetInfo.repeatCount and SheetInfo.repeatCount >= 0 then
				task.wait(frameRate)
				completedSignal:Fire()
				return
			end
			if endingLoop then
				counter += 1
				if invert then
					x = endAnim.X - endOffset
				else
					x = xOffset + startOffset
				end
				if delayBeforeRepeat then
					task.wait(frameRate)
					image.ImageRectOffset = Vector2.new(x, y)
					task.wait(delayBeforeRepeat - frameRate)

					continue
				end
			end
			task.wait(frameRate)
		end
	end

	local sheetThread = nil

	function SpriteSheetObject:Play()
		if invert then
			image.ImageRectOffset = endAnim - Vector2.new(endOffset, 0)
		else
			image.ImageRectOffset = offset + Vector2.new(startOffset, 0)
		end
		cancelled = false
		sheetThread = coroutine.create(loop)
		coroutine.resume(sheetThread)
	end

	function SpriteSheetObject:Cancel()
		if cancelled then
			return
		end

		local thread = sheetThread
		sheetThread = nil
		-- Only suspended threads can be closed. "running"/"normal" means Cancel was
		-- invoked from inside the sheet coroutine (e.g. a Completed listener).
		if thread and coroutine.status(thread) == "suspended" then
			coroutine.close(thread)
		end
		cancelled = true

		completedSignal:Fire()
		completedSignal:Destroy()
	end

	SpriteSheetObject.Destroy = SpriteSheetObject.Cancel

	return SpriteSheetObject
end

type imageType = ImageLabel | ImageButton

local function getMaxSize(dimensions: Vector2, spriteCount: Vector2, offset: Vector2, gutter: Vector2?)
	local width = dimensions.X
	local height = dimensions.Y
	local max = Vector2.new(width * spriteCount.X + offset.X, height * spriteCount.Y + offset.Y)
	if gutter then
		max += spriteCount * gutter
	end

	return max
end

function SheetService:CreateSynced(
	dimensions: Vector2,
	spriteCount: Vector2,
	offsets: { Vector2 },
	images: { imageType },
	frameRate: number,
	gutter: Vector2?
)
	local width = dimensions.X
	local height = dimensions.Y

	if width > 1024 or height > 1024 then
		error(`[Utility.SpriteSheet] - Improper Width/Height out of range 0-1024 pixels  ( {width} x {height} )`)
	end

	local xy = table.create(#images, Vector2.zero)

	for i, v in xy do
		xy[i] += offsets[i]
	end

	return task.delay(frameRate, function()
		while true do
			for i, image in images do
				if image:IsA("ImageButton") and not image.Active then
					continue
				end

				local x, y = xy[i].X, xy[i].Y
				local offsetX, offsetY = offsets[i].X, offsets[i].Y
				local max = getMaxSize(dimensions, spriteCount, offsets[i], gutter)

				-- get gutter first
				if gutter then -- and x ~= offsetX then
					if x == offsetX and y == offsetY then
						y += gutter.Y
					end
					x += gutter.X
				end

				if image:IsA("ImageLabel") then
					image.ImageRectOffset = Vector2.new(x, y)
				elseif image:IsA("ImageButton") then
					image.ImageRectOffset = Vector2.new(x, y)
				end

				x += width
				if x >= max.X then
					x = offsetX
					y += height
					if y >= max.Y then
						y = offsetY
					end
					if gutter then
						y += gutter.Y
					end
				end

				xy[i] = Vector2.new(x, y)
			end
			task.wait(frameRate)
		end
	end)
end

return SheetService
