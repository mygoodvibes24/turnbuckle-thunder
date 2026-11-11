extends RefCounted
## Looks for the five music-genre characters (original archetypes, no real people), keyed by
## character id. Each entry: "name" (display name) and "look" (the dictionary wrestler.gd's
## setup() takes -- see the "# ---- outfits" keys in wrestler.gd's body-building section).
## Use: preload("res://scripts/roster_looks.gd").LOOKS["popstar"]["look"]
## "signature_set" names a SIG_SETS row (falls back to "tank" until the supers add one);
## "anim_style" picks the idle / taunt flavour.

const LOOKS := {
	"popstar": {
		"name": "STARLA VEX",
		"look": {
			"gear": Color(0.95, 0.3, 0.7), "skin": Color(0.8, 0.58, 0.44), "body": "female", "face": "popstar",
			"anim_style": "diva", "signature_set": "popstar",
			"hair": "ponytail", "hair_color": Color(0.86, 0.76, 0.56), "hair_tip": Color(0.95, 0.88, 0.74),
			"makeup": "glam", "lip_color": Color(0.82, 0.14, 0.42), "shadow_color": Color(0.62, 0.36, 0.82),
			"top": "stage_top", "top_color": Color(0.92, 0.2, 0.62), "top_accent": Color(0.98, 0.8, 0.95),
			"outer_color": Color(0.72, 0.74, 0.86),
			"bottom": "high_shorts", "bottom_color": Color(0.07, 0.06, 0.09), "bottom_accent": Color(1.0, 0.8, 0.35),
			"shoes": "platforms", "shoe_color": Color(0.95, 0.94, 0.95), "shoe_accent": Color(0.85, 0.5, 0.92),
			"accessories": ["headset", "hoops"], "metal": "gold", "bulk": 0.9,
		},
	},
	"punk": {
		"name": "CRASH CORVID",
		"look": {
			"gear": Color(0.55, 0.95, 0.15), "skin": Color(0.88, 0.7, 0.6), "face": "punk",
			"anim_style": "punk", "signature_set": "punk",
			"hair": "spikes", "hair_color": Color(0.35, 0.85, 0.12), "hair_tip": Color(0.75, 1.0, 0.4),
			"makeup": "eyeliner",
			"top": "studded_vest", "top_color": Color(0.1, 0.1, 0.11), "top_accent": Color(0.85, 0.12, 0.1),
			"outer_color": Color(0.07, 0.065, 0.065), "graphic": "vermin",
			"bottom": "skinny_ripped", "bottom_color": Color(0.1, 0.1, 0.12), "bottom_fade": Color(0.32, 0.32, 0.36),
			"shoes": "combat_boots", "shoe_color": Color(0.05, 0.05, 0.05), "shoe_accent": Color(0.3, 0.3, 0.3),
			"accessories": ["studded_belt"], "wristband_color": Color(0.05, 0.05, 0.05), "tattoos": true, "bulk": 0.92,
		},
	},
	"country": {
		"name": "COLT CALHOUN",
		"look": {
			"gear": Color(0.85, 0.55, 0.2), "skin": Color(0.8, 0.6, 0.46), "face": "country",
			"anim_style": "cowboy", "signature_set": "country",
			"hair": "short", "hair_color": Color(0.32, 0.2, 0.11),
			"hat": "cowboy", "hat_color": Color(0.78, 0.68, 0.5), "hat_band": Color(0.3, 0.17, 0.08),
			"top": "western", "top_color": Color(0.45, 0.1, 0.12), "top_accent": Color(0.86, 0.8, 0.66),
			"bottom": "bootcut", "bottom_color": Color(0.17, 0.24, 0.42), "bottom_fade": Color(0.46, 0.54, 0.7),
			"shoes": "cowboy_boots", "shoe_color": Color(0.42, 0.24, 0.12), "shoe_accent": Color(0.86, 0.78, 0.6),
			"accessories": ["buckle", "bandana"], "metal": "silver", "belt_color": Color(0.3, 0.17, 0.08),
			"bandana_color": Color(0.66, 0.08, 0.07), "bulk": 1.1,
		},
	},
	"oldschool": {
		"name": "BIG CASSETTE",
		"look": {
			"gear": Color(1.0, 0.78, 0.25), "skin": Color(0.36, 0.24, 0.17), "face": "oldschool",
			"anim_style": "oldschool", "signature_set": "oldschool",
			"hair": "short", "hair_color": Color(0.04, 0.03, 0.03),
			"hat": "bucket", "hat_color": Color(0.06, 0.06, 0.065),
			"top": "tracksuit", "top_color": Color(0.05, 0.05, 0.055), "top_accent": Color(0.95, 0.95, 0.92),
			"bottom": "track_pants", "bottom_color": Color(0.05, 0.05, 0.055), "bottom_accent": Color(0.95, 0.95, 0.92),
			"shoes": "shelltoes", "shoe_color": Color(0.95, 0.95, 0.93), "shoe_accent": Color(0.06, 0.06, 0.06),
			"accessories": ["rope_chain", "glasses"], "metal": "gold", "bulk": 1.05,
		},
	},
	"newschool": {
		"name": "NEON KAYO",
		"look": {
			"gear": Color(0.6, 0.3, 0.95), "skin": Color(0.5, 0.34, 0.24), "face": "newschool",
			"anim_style": "newschool", "signature_set": "newschool",
			"hair": "twists", "hair_color": Color(0.05, 0.04, 0.035), "hair_tip": Color(0.95, 0.62, 0.2),
			"top": "puffer", "top_color": Color(0.36, 0.16, 0.6), "top_accent": Color(0.62, 0.95, 0.2),
			"graphic": "drip_heart",
			"bottom": "stacked", "bottom_color": Color(0.4, 0.5, 0.64), "bottom_fade": Color(0.74, 0.8, 0.88),
			"shoes": "hightops", "shoe_color": Color(0.95, 0.95, 0.95), "shoe_accent": Color(0.85, 0.12, 0.2),
			"accessories": ["layered_chains", "face_tattoos"], "metal": "gold", "bulk": 0.92,
		},
	},
}
