--!strict

-- Shared rules for the dev-only Creative menu (spawn any item into the backpack)
const Creative = {}

Creative.MIN_AMOUNT = 1
Creative.MAX_AMOUNT = 999

-- Server -> client: opens or closes the menu (fired by the `creative` Cmdr command)
Creative.TOGGLE_REMOTE = "CreativeToggle"
-- Client -> server: CreativeSpawn(itemId, amount) -> (spawned: number, message: string)
Creative.SPAWN_REMOTE = "CreativeSpawn"

-- A whole number from MIN_AMOUNT to MAX_AMOUNT
function Creative.IsValidAmount(amount: unknown): boolean
	if typeof(amount) ~= "number" then
		return false
	end
	local n = amount :: number
	return n == math.floor(n) and n >= Creative.MIN_AMOUNT and n <= Creative.MAX_AMOUNT
end

-- Rounds and clamps any number into the allowed range (NaN becomes MIN_AMOUNT)
function Creative.ClampAmount(amount: number): number
	if amount ~= amount then
		return Creative.MIN_AMOUNT
	end
	return math.clamp(math.round(amount), Creative.MIN_AMOUNT, Creative.MAX_AMOUNT)
end

return table.freeze(Creative)
