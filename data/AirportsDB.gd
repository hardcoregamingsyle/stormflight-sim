class_name AirportsDB
## The Meridian Isles region: 10 airports across ~400 km, real-world-scale
## separations (50-230 km legs) so cruise times are proportional to reality.
## Positions in km (world absolute, converted to meters at load). Headings in
## degrees true. Runway offsets are meters from the airport origin.

const KM := 1000.0

static func ids() -> Array:
	return DATA.keys()

static func get_airport(id: String) -> Dictionary:
	return DATA.get(id, DATA["sfi"])

static func position_m(id: String) -> Vector3:
	var a: Dictionary = get_airport(id)
	return Vector3(a.pos_km[0] * KM, a.elevation_m, a.pos_km[1] * KM)

static func distance_km(a: String, b: String) -> float:
	var pa := position_m(a)
	var pb := position_m(b)
	return Vector2(pa.x - pb.x, pa.z - pb.z).length() / KM

const DATA := {
	"sfi": {
		"icao": "SFMI", "name": "Meridian International", "size": "mega",
		"pos_km": [0.0, 0.0], "elevation_m": 9.0,
		"runways": [
			{"id": "09L/27R", "heading": 92.0, "length": 4000.0, "width": 60.0, "offset": [0.0, -450.0]},
			{"id": "09R/27L", "heading": 92.0, "length": 3400.0, "width": 60.0, "offset": [200.0, 450.0]},
		],
		"gates": 12, "tower_height": 62.0, "hangars": 3,
		"desc": "The region's mega-hub. Twin parallel runways, heavy traffic, home base of Stormfighter Airways.",
	},
	"skh": {
		"icao": "SKHC", "name": "Skyharbor City", "size": "international",
		"pos_km": [145.0, 38.0], "elevation_m": 24.0,
		"runways": [
			{"id": "04/22", "heading": 44.0, "length": 3400.0, "width": 45.0, "offset": [0.0, 0.0]},
			{"id": "13/31", "heading": 128.0, "length": 2600.0, "width": 45.0, "offset": [500.0, 700.0]},
		],
		"gates": 8, "tower_height": 48.0, "hangars": 2,
		"desc": "Coastal metropolis with crossing runways and tricky sea breezes.",
	},
	"npt": {
		"icao": "SNPT", "name": "Northpoint Regional", "size": "regional",
		"pos_km": [-52.0, -117.0], "elevation_m": 57.0,
		"runways": [
			{"id": "17/35", "heading": 174.0, "length": 2400.0, "width": 45.0, "offset": [0.0, 0.0]},
		],
		"gates": 5, "tower_height": 32.0, "hangars": 2,
		"desc": "A quiet regional field serving the northern forests.",
	},
	"cve": {
		"icao": "SCVE", "name": "Cove Field", "size": "small",
		"pos_km": [28.0, 42.0], "elevation_m": 12.0,
		"runways": [
			{"id": "07/25", "heading": 68.0, "length": 1200.0, "width": 23.0, "offset": [0.0, 0.0]},
		],
		"gates": 3, "tower_height": 15.0, "hangars": 2,
		"desc": "A charming island GA strip. Short, breezy, and unforgiving of sloppy approaches.",
	},
	"msa": {
		"icao": "SMSA", "name": "Mesa Alta Highlands", "size": "regional",
		"pos_km": [-138.0, 72.0], "elevation_m": 1650.0,
		"runways": [
			{"id": "10/28", "heading": 96.0, "length": 2200.0, "width": 45.0, "offset": [0.0, 0.0]},
		],
		"gates": 4, "tower_height": 28.0, "hangars": 1,
		"desc": "High-altitude plateau strip at 5,400 ft. Thin air means long takeoff rolls - plan accordingly.",
	},
	"brk": {
		"icao": "SBRK", "name": "Breakwater Bay", "size": "regional",
		"pos_km": [83.0, -64.0], "elevation_m": 15.0,
		"runways": [
			{"id": "01/19", "heading": 8.0, "length": 1900.0, "width": 30.0, "offset": [0.0, 0.0]},
		],
		"gates": 4, "tower_height": 24.0, "hangars": 1,
		"desc": "Island regional field wedged between the harbor and the hills.",
	},
	"vlc": {
		"icao": "SVLC", "name": "Vulcan Air Force Base", "size": "international",
		"pos_km": [-95.0, -20.0], "elevation_m": 210.0,
		"runways": [
			{"id": "06/24", "heading": 62.0, "length": 3000.0, "width": 60.0, "offset": [0.0, 0.0]},
			{"id": "12/30", "heading": 118.0, "length": 2450.0, "width": 45.0, "offset": [-400.0, 600.0]},
		],
		"gates": 6, "tower_height": 40.0, "hangars": 5,
		"desc": "Military airbase in the western foothills. Fast jets live here; expect afterburners.",
	},
	"gld": {
		"icao": "SGLD", "name": "Goldshore Municipal", "size": "small",
		"pos_km": [58.0, 121.0], "elevation_m": 18.0,
		"runways": [
			{"id": "15/33", "heading": 152.0, "length": 1600.0, "width": 30.0, "offset": [0.0, 0.0]},
		],
		"gates": 4, "tower_height": 18.0, "hangars": 2,
		"desc": "Sunny shoreline municipal airport popular with weekend flyers.",
	},
	"frs": {
		"icao": "SFRS", "name": "Frostspire", "size": "regional",
		"pos_km": [-40.0, 195.0], "elevation_m": 420.0,
		"runways": [
			{"id": "02/20", "heading": 24.0, "length": 2600.0, "width": 45.0, "offset": [0.0, 0.0]},
		],
		"gates": 4, "tower_height": 30.0, "hangars": 2,
		"desc": "Gateway to the polar south. Snow squalls and mountain waves keep pilots honest.",
	},
	"sst": {
		"icao": "SSST", "name": "Sunset Strip", "size": "small",
		"pos_km": [176.0, -142.0], "elevation_m": 340.0,
		"runways": [
			{"id": "08/26", "heading": 84.0, "length": 900.0, "width": 18.0, "offset": [0.0, 0.0]},
		],
		"gates": 2, "tower_height": 10.0, "hangars": 1,
		"desc": "A dusty desert strip at the edge of the map. Bring a plane that can land short.",
	},
}
