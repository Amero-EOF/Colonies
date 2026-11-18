--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages

const Net = require(Packages.Net)

-- What happened; the client picks an icon/colour per kind.
-- "ColonyEvent" is for raids, weather, disease outbreaks... (not implemented yet; see runDay in ColonistController)
export type Kind =
	"Death"
	| "Job"
	| "Join"
	| "Birth"
	| "Leave"
	| "ColonyEvent"
	| "Merchant"
	| "Mail"

const NotificationRemote = Net:RemoteEvent("Notification")

-- Shows a toast on the player's screen
local function send(player: Player, kind: Kind, text: string)
	NotificationRemote:FireClient(player, kind, text)
end

return {
	Send = send,
}
