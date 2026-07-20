class_name EOSConfig
## Epic Online Services credentials + matchmaking settings.
##
## Fill these in from your Epic dev product (https://dev.epicgames.com/portal):
##   Product Settings -> your product -> the IDs are on the SDK / Clients pages.
## See docs/MULTIPLAYER_EOS_SETUP.md for the full walkthrough.
##
## NOTE: the client id/secret ship inside the game binary either way, but do
## NOT commit real values to a PUBLIC repo - keep this repo private, or paste
## the values only into your local build. Empty values just disable EOS and
## fall back to the LAN/direct transport, so the game still builds and runs.

const PRODUCT_NAME := "Stormfighter Flight Sim"
const PRODUCT_VERSION := "1.3.0"

const PRODUCT_ID := "88280df138444d61a9a5bcea4689df28"
const SANDBOX_ID := "32d0eba9f84f4a899ea248c1798cfa20"
const DEPLOYMENT_ID := "32d0eba9f84f4a899ea248c1798cfa20"
const CLIENT_ID := "xyza7891CfHh916sdI5hBWmKKyv3lAli"
const CLIENT_SECRET := "CGljUi2fiDcI/oCqocs+TogjaN5g9etDN9BKI/NbwlU"

# Matchmaking: everyone who Quick-Joins lands in a public lobby under this
# bucket. The first player creates it, everyone after joins it - "join and
# you're in a server", no friends or IPs needed.
const LOBBY_BUCKET := "stormflight_public"
const LOBBY_MAX_MEMBERS := 16

## True only when the mandatory IDs are present.
static func configured() -> bool:
	return PRODUCT_ID != "" and SANDBOX_ID != "" and DEPLOYMENT_ID != "" \
		and CLIENT_ID != "" and CLIENT_SECRET != ""
