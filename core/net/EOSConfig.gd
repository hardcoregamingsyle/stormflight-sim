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

const PRODUCT_ID := ""       # e.g. "a1b2c3..."   (Product Settings)
const SANDBOX_ID := ""       # e.g. "d4e5f6..."   (Live sandbox)
const DEPLOYMENT_ID := ""    # e.g. "0f1e2d..."   (Live deployment)
const CLIENT_ID := ""        # (Product Settings -> Clients)
const CLIENT_SECRET := ""    # (Product Settings -> Clients)

# Matchmaking: everyone who Quick-Joins lands in a public lobby under this
# bucket. The first player creates it, everyone after joins it - "join and
# you're in a server", no friends or IPs needed.
const LOBBY_BUCKET := "stormflight_public"
const LOBBY_MAX_MEMBERS := 16

## True only when the mandatory IDs are present.
static func configured() -> bool:
	return PRODUCT_ID != "" and SANDBOX_ID != "" and DEPLOYMENT_ID != "" \
		and CLIENT_ID != "" and CLIENT_SECRET != ""
