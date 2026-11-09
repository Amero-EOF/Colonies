--!strict

local DictionaryUtil = {}

export type dict<T, U> = { [T]: U }

function DictionaryUtil.length<T, U>(array: dict<T, U>): number
	local count = 0
	for _, v in array do
		count += 1
	end
	return count
end

function DictionaryUtil.find<T, U>(array: dict<T, U>, needle: U): U?
	for _, v in array do
		if needle == v then
			return v
		end
	end
	return nil
end

function DictionaryUtil.toArray<T, U>(array: dict<T, U>): { { index: T, value: U } }
	local newArray = {}
	for i, v in array do
		table.insert(newArray, { index = i, value = v })
	end
	return newArray
end

function DictionaryUtil.isEmpty<T, U>(array: dict<T, U>): boolean
	return next(array) == nil
end

return DictionaryUtil
