--!strict
local valueLUT = {
	Object = "ObjectValue",
	number = "NumberValue",
	string = "StringValue",
	Color3 = "Color3Value",
	BrickColor = "BrickColorValue",
	Ray = "RayValue",
	Vector3 = "Vector3Value",
	boolean = "BoolValue",
	CFrame = "CFrameValue",
	BinaryString = "BinaryStringValue",
}

local function ValueToInstance(value: any): ValueBase?
	local valueType = typeof(value)
	if not valueLUT[valueType] then
		error(`Not a valid ValueBase {valueType}`)
		return nil
	end

	return Instance.new(valueLUT[valueType]) :: ValueBase
end

return ValueToInstance
