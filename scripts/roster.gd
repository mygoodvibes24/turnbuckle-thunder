extends RefCounted
## City 2 City Wrestling - Backyard Brawl: the roster (const data, load with preload).
##
## Every entry:
##   id            unique key (Game.p1_id / Game.p2_id store it)
##   display_name  the fighter's name (HUD, win banner, select screen)
##   short_name    fits on a select-screen portrait card
##   genre         music-genre tag shown on the select screen
##   bio           one line
##   stats         POWER / AIR / FLOW / GRIT, 1..10 (every fighter totals 25)
##   anim_style    idle / taunt flavour (wrestler.gd EX_ANIM_STYLES); repeated inside look,
##                 which is where wrestler.gd reads it
##   signature_set wrestler.gd SIG_SETS key (also inside look); signature = finisher display name
##   look          the Dictionary passed to wrestler.gd setup()
##
## look keys. wrestler.gd reads everything with look.get(key, default), so unknown keys are
## safely ignored. Base model: gear (signature colour), skin, face "tank"|"kid", hair, hair_color,
##   top "tee"|"hoodie", top_color, top_accent, graphic, undershirt, bottom_color, bottom_fade,
##   shoe_color, shoe_accent, chain, bracelet, tattoos, wristband_color, sleeves, hood, mask,
##   mask_base, mask_paint, bulk (0.8..1.15).
## Generic outfit keys (all rendered; full list in wrestler.gd "# ---- outfits"):
##   body          "male" | "female"
##   hair_style    "locs" | "curls" | "ponytail" | "spikes" | "twists" | "buzz"  (overrides hair)
##   top_style     "tee" | "hoodie" | "stage_top" | "studded_vest" | "western" | "tracksuit" |
##                 "puffer" ("designer_hoodie" = puffer)                          (overrides top)
##   bottom_style  "baggy_jeans" | "high_shorts" | "leggings" | "skinny_ripped" | "bootcut" |
##                 "track_pants" | "stacked"  (aliases: glam_pants, ripped_skinny, slim)
##   shoes         "sneakers" | "platforms" | "combat_boots" | "cowboy_boots" | "shelltoes" |
##                 "hightops"  (aliases: boots, high_tops)
##   hat           "none" | "cowboy" | "fedora" | "bucket";  hat_color, hat_band
##   face          also "popstar" | "punk" | "country" (stubble) | "oldschool" (moustache) | "newschool"
##   makeup        "none" | "glam" | "eyeliner";  lip_color, shadow_color
##   outer_color / vest_color (jacket, vest), stripe_color (track stripes), bottom_accent,
##   hair_tips, chain_style ("rope" | "rope_thick" | "layered"), chain_color, buckle_color,
##   belt_color, bandana_color, metal ("gold" | "silver"),
##   accessories: Array of "headset", "hoops", "buckle", "rope_chain", "layered_chains",
##   "glasses", "bandana", "studded_belt", "face_tattoos"
## Characters are original archetypes inspired by music genres (no real people, bands or logos).

const STATS := ["POWER", "AIR", "FLOW", "GRIT"]

const ROSTER := [
	{
		"id": "tank",
		"display_name": "TANK MAGRUDER",
		"short_name": "TANK",
		"genre": "HARDCORE",
		"bio": "Backyard legend from the block. Hits like a dropped fridge and never stays down.",
		"stats": {"POWER": 9, "AIR": 3, "FLOW": 4, "GRIT": 9},
		"anim_style": "swagger",
		"signature_set": "tank",
		"signature": "FRIDGE DROP",
		"look": {
			"anim_style": "swagger", "signature_set": "tank",
			"gear": Color(0.8, 0.14, 0.1), "skin": Color(0.42, 0.28, 0.2), "face": "tank",
			"hair": "locs", "hair_color": Color(0.05, 0.036, 0.03),
			"top": "tee", "top_color": Color(0.075, 0.072, 0.078), "graphic": "skull_bolt", "undershirt": true,
			"bottom_color": Color(0.13, 0.13, 0.16), "bottom_fade": Color(0.33, 0.3, 0.28),
			"shoe_color": Color(0.06, 0.06, 0.065), "shoe_accent": Color(0.92, 0.92, 0.9),
			"chain": true, "bracelet": true, "tattoos": true, "bulk": 1.0,
		},
	},
	{
		"id": "peligro",
		"display_name": "LIL PELIGRO",
		"short_name": "PELIGRO",
		"genre": "LUCHA LIBRE",
		"bio": "Masked high-flyer who learned to fly off his cousin's trampoline. Lands nothing twice.",
		"stats": {"POWER": 4, "AIR": 9, "FLOW": 7, "GRIT": 5},
		"anim_style": "hyper",
		"signature_set": "peligro",
		"signature": "TRAMPOLINE RANA",
		"look": {
			"anim_style": "hyper", "signature_set": "peligro",
			"gear": Color(0.15, 0.75, 0.3), "skin": Color(0.62, 0.43, 0.3), "face": "kid",
			"mask": true, "mask_color": Color(0.12, 0.7, 0.28), "mask_trim": Color(1.0, 0.82, 0.1),
			"hair": "curls", "hair_color": Color(0.07, 0.055, 0.045),
			"top": "hoodie", "top_color": Color(0.46, 0.47, 0.49), "top_accent": Color(0.12, 0.62, 0.26),
			"graphic": "peligro",
			"bottom_color": Color(0.36, 0.47, 0.62), "bottom_fade": Color(0.7, 0.76, 0.84),
			"shoe_color": Color(0.9, 0.9, 0.88), "shoe_accent": Color(0.13, 0.55, 0.26),
			"wristband_color": Color(0.1, 0.1, 0.1), "bulk": 0.86,
		},
	},
	{
		# POP STAR: glam stage outfit, high ponytail, platform sneakers, headset mic. Acrobatic.
		"id": "starla",
		"display_name": "STARLA VOLT",
		"short_name": "STARLA",
		"genre": "POP",
		"bio": "Arena-pop headliner who does her own stunts. Hits the high notes and the top rope.",
		"stats": {"POWER": 3, "AIR": 10, "FLOW": 8, "GRIT": 4},
		"anim_style": "diva",
		"signature_set": "peligro",
		"signature": "ENCORE SPLIT",
		"look": {
			"anim_style": "diva", "signature_set": "peligro",
			"gear": Color(1.0, 0.28, 0.72), "skin": Color(0.8, 0.6, 0.47), "body": "female", "face": "popstar",
			"hair_style": "ponytail", "hair_color": Color(0.94, 0.84, 0.6), "hair_tips": Color(0.98, 0.9, 0.78),
			"makeup": "glam", "lip_color": Color(0.84, 0.14, 0.44), "shadow_color": Color(0.62, 0.36, 0.84),
			"top_style": "stage_top", "top_color": Color(0.9, 0.18, 0.62), "top_accent": Color(0.98, 0.82, 0.95),
			"outer_color": Color(0.74, 0.76, 0.88),
			"bottom_style": "high_shorts", "bottom_color": Color(0.07, 0.06, 0.09), "bottom_accent": Color(1.0, 0.8, 0.35),
			"shoes": "platforms", "shoe_color": Color(0.96, 0.95, 0.97), "shoe_accent": Color(1.0, 0.42, 0.78),
			"hat": "none", "accessories": ["headset", "hoops"], "metal": "gold", "bulk": 0.9,
		},
	},
	{
		# PUNK ROCKER: spiked hair, studded vest, ripped skinny jeans, combat boots. Chaotic brawler.
		"id": "razz",
		"display_name": "RAZZ DECIBEL",
		"short_name": "RAZZ",
		"genre": "PUNK",
		"bio": "Three-chord chaos merchant. Started a mosh pit at his own birthday party. Age six.",
		"stats": {"POWER": 7, "AIR": 5, "FLOW": 4, "GRIT": 9},
		"anim_style": "punk",
		"signature_set": "tank",
		"signature": "STAGE DIVE",
		"look": {
			"anim_style": "punk", "signature_set": "tank",
			"gear": Color(0.78, 1.0, 0.1), "skin": Color(0.86, 0.68, 0.56), "body": "male", "face": "punk",
			"hair_style": "spikes", "hair_color": Color(0.42, 0.9, 0.1), "hair_tips": Color(0.8, 1.0, 0.42),
			"makeup": "eyeliner",
			"top_style": "studded_vest", "top_color": Color(0.06, 0.06, 0.07), "top_accent": Color(0.82, 0.12, 0.1),
			"vest_color": Color(0.08, 0.075, 0.075), "graphic": "vermin",
			"bottom_style": "skinny_ripped", "bottom_color": Color(0.08, 0.08, 0.1), "bottom_fade": Color(0.32, 0.32, 0.36),
			"shoes": "combat_boots", "shoe_color": Color(0.05, 0.05, 0.05), "shoe_accent": Color(0.3, 0.3, 0.3),
			"hat": "none", "accessories": ["studded_belt"], "wristband_color": Color(0.05, 0.05, 0.05),
			"tattoos": true, "bulk": 0.92,
		},
	},
	{
		# COUNTRY SINGER: cowboy hat, pearl-snap western shirt, big buckle, bootcut, boots. Power grappler.
		"id": "dusty",
		"display_name": "DUSTY BUCKLES",
		"short_name": "DUSTY",
		"genre": "COUNTRY",
		"bio": "Honky-tonk heartbreaker with a bull-rider's grip. Ropes steers, slams city boys.",
		"stats": {"POWER": 10, "AIR": 2, "FLOW": 4, "GRIT": 9},
		"anim_style": "cowboy",
		"signature_set": "tank",
		"signature": "HOEDOWN SLAM",
		"look": {
			"anim_style": "cowboy", "signature_set": "tank",
			"gear": Color(0.92, 0.58, 0.18), "skin": Color(0.74, 0.52, 0.38), "body": "male", "face": "country",
			"hair_style": "buzz", "hair_color": Color(0.34, 0.21, 0.11),
			"hat": "cowboy", "hat_color": Color(0.86, 0.78, 0.6), "hat_band": Color(0.3, 0.17, 0.08),
			"top_style": "western", "top_color": Color(0.5, 0.11, 0.12), "top_accent": Color(0.9, 0.85, 0.72),
			"bottom_style": "bootcut", "bottom_color": Color(0.2, 0.3, 0.48), "bottom_fade": Color(0.52, 0.62, 0.76),
			"shoes": "cowboy_boots", "shoe_color": Color(0.42, 0.24, 0.12), "shoe_accent": Color(0.86, 0.78, 0.6),
			"buckle_color": Color(0.95, 0.78, 0.3), "belt_color": Color(0.3, 0.17, 0.08),
			"bandana_color": Color(0.66, 0.08, 0.07), "accessories": ["buckle", "bandana"], "metal": "silver", "bulk": 1.15,
		},
	},
	{
		# OLD-SCHOOL HIP HOP MC: fedora, black tracksuit with stripes, thick gold rope chain,
		# shell-toe sneakers with fat laces. Technical.
		"id": "booker",
		"display_name": "BOOM BAP BOOKER",
		"short_name": "BOOKER",
		"genre": "OLD SCHOOL HIP HOP",
		"bio": "Park-jam MC from back in the day. Every hold lands on the one, every slam on the two.",
		"stats": {"POWER": 6, "AIR": 4, "FLOW": 9, "GRIT": 6},
		"anim_style": "oldschool",
		"signature_set": "tank",
		"signature": "BREAKBEAT LOCK",
		"look": {
			"anim_style": "oldschool", "signature_set": "tank",
			"gear": Color(1.0, 0.8, 0.16), "skin": Color(0.3, 0.2, 0.14), "body": "male", "face": "oldschool",
			"hair_style": "buzz", "hair_color": Color(0.04, 0.03, 0.03),
			"hat": "fedora", "hat_color": Color(0.05, 0.05, 0.055), "hat_band": Color(0.16, 0.16, 0.17),
			"top_style": "tracksuit", "top_color": Color(0.1, 0.1, 0.11),
			"bottom_style": "track_pants", "bottom_color": Color(0.1, 0.1, 0.11),
			"stripe_color": Color(0.95, 0.95, 0.95), "stripe_count": 2,
			"shoes": "shelltoes", "lace_style": "fat", "shoe_color": Color(0.95, 0.95, 0.93), "shoe_accent": Color(0.06, 0.06, 0.06),
			"chain_style": "rope_thick", "chain_color": Color(1.0, 0.8, 0.26),
			"accessories": ["glasses"], "metal": "gold", "bulk": 1.02,
		},
	},
	{
		# NEW-SCHOOL RAPPER: designer streetwear hoodie, layered chains, slim jeans, flashy
		# high-tops, short twists. Fast combos.
		"id": "halo",
		"display_name": "YUNG HALO",
		"short_name": "HALO",
		"genre": "NEW SCHOOL RAP",
		"bio": "Chart-climbing phenom. Drops combos faster than he drops singles, and he drops weekly.",
		"stats": {"POWER": 5, "AIR": 6, "FLOW": 9, "GRIT": 5},
		"anim_style": "newschool",
		"signature_set": "peligro",
		"signature": "PLATINUM FLURRY",
		"look": {
			"anim_style": "newschool", "signature_set": "peligro",
			"gear": Color(0.62, 0.36, 1.0), "skin": Color(0.46, 0.31, 0.22), "body": "male", "face": "newschool",
			"hair_style": "twists", "hair_color": Color(0.06, 0.045, 0.04), "hair_tips": Color(0.95, 0.75, 0.3),
			"top_style": "puffer", "top_color": Color(0.42, 0.24, 0.7), "top_accent": Color(0.2, 0.95, 0.75),
			"graphic": "drip_heart",
			"bottom_style": "stacked", "bottom_color": Color(0.1, 0.1, 0.12), "bottom_fade": Color(0.32, 0.32, 0.36),
			"shoes": "hightops", "shoe_color": Color(0.96, 0.96, 0.96), "shoe_accent": Color(0.92, 0.15, 0.2),
			"hat": "none", "chain_style": "layered", "chain_color": Color(1.0, 0.8, 0.3),
			"accessories": ["face_tattoos"], "metal": "gold", "bulk": 0.88,
		},
	},
]


static func count() -> int:
	return ROSTER.size()


static func index_of(id: String) -> int:
	for i in ROSTER.size():
		var e: Dictionary = ROSTER[i]
		if e["id"] == id:
			return i
	return -1


static func find(id: String) -> Dictionary:
	var i := index_of(id)
	if i < 0:
		i = 0
	return ROSTER[i]
