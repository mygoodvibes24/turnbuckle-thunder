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
##   story         (optional) true for the story-mode characters (Mom, Pickles, Hollis, Rudy, Vale,
##                 Lawn Dart). scripts/story_data.gd CAST points at them with roster_id, so cutscenes
##                 and Versus share ONE look; each sits in its own "---- LOOK: <id>" block.
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
## Story-cast keys (wrestler.gd "# --- story-cast outfits" has the full list): top "scrubs" | "polo" |
##   "hawaiian" | "suit_jacket" (shirt_color); bottom "scrub_pants" | "slacks" | "suit_pants" |
##   "cargo_shorts" (sock_color, sock_stripe); shoes "clogs" | "dress_shoes" | "walkers"; hat "sun_hat" |
##   "cap_back"; hair "bun" (hair_tie) | "slick" | "balding"; face "older" | "mom" | "grin" | "smug";
##   graphic "rec"; accessories "badge", "fanny_pack", "headphones", "mic", "phone_stick", "watch",
##   "garden_gloves", "gold_chain", "champ_buckle", "belt", "sunglasses", "shades_up", "readers", "readers_up"
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
	{
		# STORY CHARACTER. Bernadette Magruder: ER nursing assistant, teal scrubs, white clogs. Balanced, never stays down.
		"id": "mom",
		"display_name": "MAMA MAGRUDER",
		"short_name": "MAMA",
		"genre": "HOUSE RULES",
		"bio": "County ER, sixteen-hour doubles, zero patience. Uses your full government name, then your ribs.",
		"stats": {"POWER": 6, "AIR": 4, "FLOW": 6, "GRIT": 9},
		"anim_style": "diva",
		"signature_set": "tank",
		"signature": "DOUBLE SHIFT",
		"story": true,
		# ---- LOOK: mom (shared with the story cutscenes via story_data.gd CAST roster_id) ----
		"look": {
			"signature_set": "tank", "anim_style": "diva", "body": "female", "bulk": 0.95,
			"gear": Color(0.2, 0.62, 0.62), "skin": Color(0.4, 0.27, 0.19), "face": "mom",
			"hair": "bun", "hair_color": Color(0.1, 0.07, 0.06), "hair_tie": Color(0.86, 0.32, 0.46),
			"top": "scrubs", "top_color": Color(0.16, 0.55, 0.56), "top_accent": Color(0.9, 0.92, 0.94),
			"bottom": "scrub_pants", "bottom_color": Color(0.15, 0.51, 0.53), "bottom_fade": Color(0.24, 0.6, 0.62),
			"shoes": "clogs", "shoe_color": Color(0.95, 0.95, 0.93), "shoe_accent": Color(0.84, 0.85, 0.87),
			"accessories": ["badge", "readers_up", "watch"], "lanyard_color": Color(0.12, 0.26, 0.58),
			"watch_color": Color(0.88, 0.89, 0.92), "glasses_color": Color(0.55, 0.2, 0.3),
		},
		# ---- END LOOK: mom ----
	},
	{
		# STORY CHARACTER. Darnell "Pickles" Pickett: cameraman of the BROOMCAM. Scrappy high-flyer.
		"id": "pickles",
		"display_name": "PICKLES PICKETT",
		"short_name": "PICKLES",
		"genre": "CAMERA CREW",
		"bio": "Best friend since second grade. Dives off anything if the angle's good. THAT'S THUMBNAIL.",
		"stats": {"POWER": 3, "AIR": 9, "FLOW": 8, "GRIT": 5},
		"anim_style": "hyper",
		"signature_set": "peligro",
		"signature": "THUMBNAIL DROP",
		"story": true,
		# ---- LOOK: pickles (shared with the story cutscenes via story_data.gd CAST roster_id) ----
		"look": {
			"signature_set": "peligro", "anim_style": "hyper", "bulk": 0.84,
			"gear": Color(0.45, 0.78, 0.2), "skin": Color(0.56, 0.38, 0.26), "face": "grin",
			"hair": "curls", "hair_color": Color(0.06, 0.045, 0.04),
			"top": "tee", "top_color": Color(0.3, 0.56, 0.16), "top_accent": Color(0.98, 0.88, 0.22), "graphic": "rec",
			"bottom": "cargo_shorts", "bottom_color": Color(0.52, 0.47, 0.34), "bottom_fade": Color(0.66, 0.6, 0.48),
			"sock_color": Color(0.95, 0.95, 0.93), "sock_stripe": Color(0.3, 0.56, 0.16),
			"shoes": "hightops", "shoe_color": Color(0.85, 0.2, 0.18), "shoe_accent": Color(0.95, 0.95, 0.95),
			"hat": "cap_back", "hat_color": Color(0.98, 0.84, 0.2), "hat_band": Color(0.3, 0.56, 0.16),
			"accessories": ["phone_stick"],
		},
		# ---- END LOOK: pickles ----
	},
	{
		# STORY CHARACTER. Mr. Hollis, the grumpy neighbor: secretly HURRICANE HOLLIS. Veteran power + grit.
		"id": "hollis",
		"display_name": "HURRICANE HOLLIS",
		"short_name": "HOLLIS",
		"genre": "OLD SCHOOL LEGEND",
		"bio": "Six-time regional champ, forty years retired. Has been in more noise than you'll ever make.",
		"stats": {"POWER": 9, "AIR": 2, "FLOW": 4, "GRIT": 10},
		"anim_style": "oldschool",
		"signature_set": "tank",
		"signature": "HYDRANGEA HAMMER",
		"story": true,
		# ---- LOOK: hollis (shared with the story cutscenes via story_data.gd CAST roster_id) ----
		"look": {
			"signature_set": "tank", "anim_style": "oldschool", "bulk": 1.05, "tattoos": true,
			"gear": Color(0.55, 0.3, 0.75), "skin": Color(0.33, 0.22, 0.16), "face": "older",
			"hair": "balding", "hair_color": Color(0.86, 0.85, 0.82),
			"top": "polo", "top_color": Color(0.5, 0.4, 0.66), "top_accent": Color(0.95, 0.8, 0.35),
			"bottom": "slacks", "bottom_color": Color(0.62, 0.55, 0.42), "bottom_fade": Color(0.7, 0.64, 0.52),
			"shoes": "walkers", "shoe_color": Color(0.93, 0.92, 0.88), "shoe_accent": Color(0.74, 0.73, 0.7),
			"hat": "sun_hat", "hat_color": Color(0.86, 0.74, 0.5), "hat_band": Color(0.4, 0.22, 0.55),
			"accessories": ["garden_gloves", "champ_buckle"], "glove_color": Color(0.42, 0.58, 0.3),
			"buckle_color": Color(1.0, 0.8, 0.32), "belt_color": Color(0.2, 0.12, 0.07),
		},
		# ---- END LOOK: hollis ----
	},
	{
		# STORY CHARACTER. Rudy Two-Times: scrappy store-lot promoter who says everything twice. Brawler.
		"id": "rudy",
		"display_name": "RUDY TWO-TIMES",
		"short_name": "RUDY",
		"genre": "PROMOTER",
		"bio": "Runs the fights behind the store lot. Hits you twice. Hits you twice.",
		"stats": {"POWER": 7, "AIR": 4, "FLOW": 6, "GRIT": 8},
		"anim_style": "swagger",
		"signature_set": "tank",
		"signature": "TWO-TIMES TOMBSTONE TOMBSTONE",
		"story": true,
		# ---- LOOK: rudy (shared with the story cutscenes via story_data.gd CAST roster_id) ----
		"look": {
			"signature_set": "tank", "anim_style": "swagger", "bulk": 0.95,
			"gear": Color(0.1, 0.7, 0.7), "skin": Color(0.78, 0.58, 0.44), "face": "oldschool",
			"hair": "slick", "hair_color": Color(0.12, 0.08, 0.06),
			"top": "hawaiian", "top_color": Color(0.07, 0.52, 0.56), "top_accent": Color(0.9, 0.26, 0.6),
			"bottom": "slacks", "bottom_color": Color(0.86, 0.82, 0.72), "bottom_fade": Color(0.92, 0.88, 0.8),
			"shoes": "dress_shoes", "shoe_color": Color(0.93, 0.91, 0.87), "shoe_accent": Color(0.6, 0.15, 0.55),
			"accessories": ["gold_chain", "shades_up", "fanny_pack"], "chain_color": Color(1.0, 0.8, 0.26),
			"pack_color": Color(0.1, 0.1, 0.12),
		},
		# ---- END LOOK: rudy ----
	},
	{
		# STORY CHARACTER. Preston Vale: slick villain promoter. All flow, glass jaw, cheats with style.
		"id": "vale",
		"display_name": "PRESTON VALE",
		"short_name": "VALE",
		"genre": "THE MONEY",
		"bio": "Influencer-promoter of VALE ELITE. Never reads the fine print because he wrote it.",
		"stats": {"POWER": 5, "AIR": 6, "FLOW": 10, "GRIT": 4},
		"anim_style": "newschool",
		"signature_set": "peligro",
		"signature": "PAGE NINE",
		"story": true,
		# ---- LOOK: vale (shared with the story cutscenes via story_data.gd CAST roster_id) ----
		"look": {
			"signature_set": "peligro", "anim_style": "newschool", "bulk": 0.88,
			"gear": Color(0.85, 0.75, 0.45), "skin": Color(0.86, 0.68, 0.56), "face": "smug",
			"hair": "slick", "hair_color": Color(0.72, 0.56, 0.3),
			"top": "suit_jacket", "top_color": Color(0.9, 0.86, 0.76), "top_accent": Color(0.86, 0.68, 0.24),
			"shirt_color": Color(0.08, 0.08, 0.09),
			"bottom": "suit_pants", "bottom_color": Color(0.88, 0.84, 0.74), "bottom_fade": Color(0.92, 0.88, 0.8),
			"shoes": "dress_shoes", "shoe_color": Color(0.1, 0.07, 0.06), "shoe_accent": Color(0.85, 0.75, 0.45),
			"accessories": ["watch"], "watch_color": Color(1.0, 0.8, 0.32),
		},
		# ---- END LOOK: vale ----
	},
	{
		# STORY CHARACTER. MC Lawn Dart: the backyard's hype MC (mc.gd) in person. Quick and flashy.
		"id": "lawndart",
		"display_name": "MC LAWN DART",
		"short_name": "LAWN DART",
		"genre": "HYPE MAN",
		"bio": "The voice of LAWN DART LIVE. Wrestles exactly like he talks: loud, fast and nonstop.",
		"stats": {"POWER": 6, "AIR": 7, "FLOW": 7, "GRIT": 5},
		"anim_style": "hyper",
		"signature_set": "peligro",
		"signature": "SOMEBODY CALL HIS MAMA",
		"story": true,
		# ---- LOOK: lawndart (shared with the story cutscenes via story_data.gd CAST roster_id) ----
		"look": {
			"signature_set": "peligro", "anim_style": "hyper", "bulk": 1.0,
			"gear": Color(1.0, 0.84, 0.2), "skin": Color(0.48, 0.32, 0.22), "face": "tank",
			"hair": "locs", "hair_color": Color(0.06, 0.045, 0.04),
			"top": "tracksuit", "top_color": Color(1.0, 0.8, 0.16), "top_accent": Color(0.06, 0.06, 0.07),
			"bottom": "track_pants", "bottom_color": Color(0.06, 0.06, 0.07), "bottom_fade": Color(0.2, 0.2, 0.22),
			"bottom_accent": Color(1.0, 0.8, 0.16),
			"shoes": "hightops", "shoe_color": Color(1.0, 0.84, 0.2), "shoe_accent": Color(0.06, 0.06, 0.07),
			"accessories": ["headphones", "mic", "sunglasses", "gold_chain"], "chain_color": Color(1.0, 0.84, 0.2),
			"headphone_color": Color(0.07, 0.07, 0.08), "headphone_accent": Color(1.0, 0.84, 0.2),
		},
		# ---- END LOOK: lawndart ----
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
