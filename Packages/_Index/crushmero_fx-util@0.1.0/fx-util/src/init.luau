local BeamsFX = {}

local FXUtil = {
	Beams = BeamsFX,
}

function BeamsFX.BeamCurve(numOfBeams: number, radius: number)
	return 4 / 3 * radius * math.tan(math.pi / (2 * numOfBeams))
end

return FXUtil
