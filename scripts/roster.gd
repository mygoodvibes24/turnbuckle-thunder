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
##   anim_style    taunt / idle flavour for the animation agents
##   signature_set the move-set family; signature = its finisher's display name
##   look          the Dictionary passed to wrestler.gd setup()
##
## look keys. wrestler.gd reads everything with look.get(key, default), so unknown keys are
## safely ignored. Keys it renders TODAY:
##   gear (signature colour), skin, face "tank"|"kid", hair "locs"|"curls"|"none", hair_color,
##   top "tee"|"hoodie", top_color, top_accent, graphic "skull_bolt"|"peligro"|"none",
##   undershirt, bottom_color, bottom_fade, shoe_color, shoe_accent, chain, bracelet, tattoos,
##   wristband_color, mask, mask_color, mask_trim, bulk (0.8..1.15)
## "hair" / "top" therefore hold the CLOSEST shape the model can build right now. The intended
## designs are described by extra keys for the roster-models work (not rendered yet):
##   body          "male" | "female"
##   hair_style    "locs" | "curls" | "ponytail" | "spikes" | "twists" | "buzz"  (overrides hair)
##   top_style     "tee" | "hoodie" | "stage_top" | "studded_vest" | "western" | "tracksuit" |
##                 "designer_hoodie"                                            (overrides top)
##   bottom_style  "baggy_jeans" | "glam_pants" | "ripped_skinny" | "bootcut" | "track_pants" | "slim"
##   shoes         "sneakers" | "platforms" | "boots" | "cowboy_boots" | "shelltoes" | "high_tops"
##   hat           "none" | "cowboy" | "fedora" | "bucket";  hat_color
##   chain_color, chain_style ("rope" | "rope_thick" | "layered"), hair_tips, stripe_color,
##   stripe_count, lace_style, buckle_color, accessories: Array of tags (see each entry)
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
		"anim_style": "heavy",
		"signature_set": "heavy_hitter",
		"signature": "FRIDGE DROP",
		"look": {
			"gear": Color(0.8, 0.14, 0.1), "skin": Color(0.42, 0.28, 0.2), "face": "tank",
			"hair": "locs", "hair_color": Color(0.05, 0.036, 0.03),
			"top": "tee", "top_color": Color(0.075, 0.072, 0.078), "graphic": "skull_bolt", "undershirt": true,
			"bottom_color": Color(0.12, 0.115, 0.125), "bottom_fade": Color(0.34, 0.31, 0.28),
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
		"anim_style": "luchador",
		"signature_set": "high_flyer",
		"signature": "TRAMPOLINE RANA",
		"look": {
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
		"anim_style": "acrobatic",
		"signature_set": "pop_acrobat",
		"signature": "ENCORE SPLIT",
		"look": {
			"gear": Color(1.0, 0.28, 0.72), "skin": Color(0.8, 0.6, 0.47), "face": "kid",
			"hair": "curls", "hair_color": Color(0.96, 0.84, 0.58),
			"top": "tee", "top_color": Color(0.86, 0.16, 0.6), "top_accent": Color(0.82, 0.84, 0.92),
			"graphic": "none",
			"bottom_color": Color(0.6, 0.56, 0.72), "bottom_fade": Color(0.88, 0.85, 0.95),
			"shoe_color": Color(0.96, 0.95, 0.97), "shoe_accent": Color(1.0, 0.36, 0.76),
			"bracelet": true, "bulk": 0.8,
			# not rendered yet (roster models)
			"body": "female", "hair_style": "ponytail", "top_style": "stage_top",
			"bottom_style": "glam_pants", "shoes": "platforms", "hat": "none",
			"accessories": ["headset_mic", "sequins", "star_earrings", "fingerless_gloves"],
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
		"anim_style": "chaotic",
		"signature_set": "punk_chaos",
		"signature": "STAGE DIVE",
		"look": {
			"gear": Color(0.78, 1.0, 0.1), "skin": Color(0.86, 0.68, 0.56), "face": "kid",
			"hair": "curls", "hair_color": Color(0.48, 0.95, 0.12),
			"top": "tee", "top_color": Color(0.06, 0.06, 0.07), "top_accent": Color(0.82, 0.82, 0.84),
			"graphic": "none",
			"bottom_color": Color(0.08, 0.08, 0.1), "bottom_fade": Color(0.32, 0.32, 0.36),
			"shoe_color": Color(0.08, 0.07, 0.07), "shoe_accent": Color(0.78, 0.1, 0.1),
			"wristband_color": Color(0.05, 0.05, 0.05), "tattoos": true, "bulk": 0.92,
			# not rendered yet (roster models)
			"body": "male", "hair_style": "spikes", "top_style": "studded_vest",
			"bottom_style": "ripped_skinny", "shoes": "boots", "hat": "none",
			"vest_color": Color(0.1, 0.09, 0.09), "plaid_color": Color(0.72, 0.1, 0.12),
			"accessories": ["studs", "safety_pins", "studded_wristbands", "plaid_shirt_round_waist"],
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
		"anim_style": "power",
		"signature_set": "power_grapple",
		"signature": "HOEDOWN SLAM",
		"look": {
			"gear": Color(0.92, 0.58, 0.18), "skin": Color(0.74, 0.52, 0.38), "face": "tank",
			"hair": "curls", "hair_color": Color(0.34, 0.21, 0.11),
			"top": "tee", "top_color": Color(0.6, 0.15, 0.12), "top_accent": Color(0.95, 0.92, 0.85),
			"graphic": "none",
			"bottom_color": Color(0.2, 0.3, 0.48), "bottom_fade": Color(0.52, 0.62, 0.76),
			"shoe_color": Color(0.38, 0.22, 0.12), "shoe_accent": Color(0.62, 0.44, 0.26),
			"bulk": 1.15,
			# not rendered yet (roster models)
			"body": "male", "hair_style": "curls", "top_style": "western",
			"bottom_style": "bootcut", "shoes": "cowboy_boots",
			"hat": "cowboy", "hat_color": Color(0.9, 0.84, 0.7), "buckle_color": Color(0.95, 0.78, 0.3),
			"accessories": ["big_buckle", "pearl_snaps", "yoke_piping"],
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
		"anim_style": "technical",
		"signature_set": "technical",
		"signature": "BREAKBEAT LOCK",
		"look": {
			"gear": Color(1.0, 0.8, 0.16), "skin": Color(0.3, 0.2, 0.14), "face": "tank",
			"hair": "none", "hair_color": Color(0.04, 0.03, 0.03),
			"top": "hoodie", "top_color": Color(0.06, 0.06, 0.07), "top_accent": Color(0.95, 0.95, 0.95),
			"graphic": "none",
			"bottom_color": Color(0.07, 0.07, 0.08), "bottom_fade": Color(0.18, 0.18, 0.2),
			"shoe_color": Color(0.95, 0.95, 0.93), "shoe_accent": Color(0.06, 0.06, 0.06),
			"chain": true, "bulk": 1.02,
			# not rendered yet (roster models)
			"body": "male", "hair_style": "buzz", "top_style": "tracksuit",
			"bottom_style": "track_pants", "shoes": "shelltoes", "lace_style": "fat",
			"hat": "fedora", "hat_color": Color(0.05, 0.05, 0.055),
			"stripe_color": Color(0.95, 0.95, 0.95), "stripe_count": 2,
			"chain_color": Color(1.0, 0.8, 0.26), "chain_style": "rope_thick",
			"accessories": ["gold_rope_chain", "fat_laces", "track_stripes"],
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
		"anim_style": "swagger",
		"signature_set": "speed_combos",
		"signature": "PLATINUM FLURRY",
		"look": {
			"gear": Color(0.62, 0.36, 1.0), "skin": Color(0.46, 0.31, 0.22), "face": "kid",
			"hair": "locs", "hair_color": Color(0.06, 0.045, 0.04),
			"top": "hoodie", "top_color": Color(0.7, 0.6, 0.9), "top_accent": Color(0.2, 0.95, 0.75),
			"graphic": "none",
			"bottom_color": Color(0.1, 0.1, 0.12), "bottom_fade": Color(0.32, 0.32, 0.36),
			"shoe_color": Color(0.92, 0.15, 0.2), "shoe_accent": Color(0.98, 0.98, 0.98),
			"chain": true, "bracelet": true, "bulk": 0.84,
			# not rendered yet (roster models)
			"body": "male", "hair_style": "twists", "hair_tips": Color(0.95, 0.75, 0.3),
			"top_style": "designer_hoodie", "bottom_style": "slim", "shoes": "high_tops",
			"hat": "none", "chain_style": "layered", "chain_color": Color(0.92, 0.92, 0.96),
			"accessories": ["layered_chains", "stud_earrings", "tinted_shades"],
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
