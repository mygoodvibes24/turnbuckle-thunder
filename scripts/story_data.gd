extends RefCounted
## City 2 City Wrestling - Backyard Brawl: STORY MODE script (const data only, load with preload).
## Format: /home/user/story_schema.md. CAST = every speaking/visible character; roster fighters
## point at scripts/roster.gd with roster_id, NPCs carry a wrestler.gd look dict (rendered keys
## first, descriptive not-yet-rendered keys after). CHAPTERS = 8 chapters, each with an intro
## cutscene (several scenes), a match, a one-scene win and a one-scene lose (lose sets up a retry).
##
## Running jokes / callbacks (keep them consistent if you edit):
##   - Mom calls him THEODORE when he is in trouble. The good cheese is off limits. Chili lives
##     in the blue dish.
##   - Gerald (Mrs. Okafor's nephew) wants Tank's room. Gerald has a job. Gerald has a fern.
##   - Pickles films on the BROOMCAM and calls every good moment "THAT'S THUMBNAIL."
##   - Scrubs_N_Slams, the channel's #1 commenter ("PROTECT YOUR NECK BABY"), is secretly Mom.
##   - Mr. Hollis's hydrangeas. Mr. Hollis "has been in more noise" -> he was HURRICANE HOLLIS.
##   - Rudy Two-Times says everything twice. Eleven dollars: the first tips ever.
##   - The KITCHEN CHAMPIONSHIP: a cereal-box belt nine-year-old Theodore made. Finale payoff.
##   - MC Lawn Dart's "SOMEBODY CALL HIS MAMA!" -> in the finale, she is right there.

const CAST := {
	"tank": {"name": "TANK", "roster_id": "tank"},
	"peligro": {"name": "LIL PELIGRO", "roster_id": "peligro"},
	"starla": {"name": "STARLA VOLT", "roster_id": "starla"},
	"razz": {"name": "RAZZ DECIBEL", "roster_id": "razz"},
	"dusty": {"name": "DUSTY BUCKLES", "roster_id": "dusty"},
	"booker": {"name": "BOOM BAP BOOKER", "roster_id": "booker"},
	"halo": {"name": "YUNG HALO", "roster_id": "halo"},
	# Bernadette Magruder: certified nursing assistant, county hospital ER, works doubles. Teal scrubs,
	# white clogs, hospital badge on a lanyard, reading glasses pushed up into her curls.
	"mom": {
		"name": "MOM", "anim_style": "diva",
		"look": {
			"anim_style": "diva",
			"gear": Color(0.2, 0.62, 0.62), "skin": Color(0.4, 0.27, 0.19), "face": "kid",
			"hair": "curls", "hair_color": Color(0.1, 0.07, 0.06),
			"top": "tee", "top_color": Color(0.22, 0.6, 0.6), "top_accent": Color(0.9, 0.92, 0.94),
			"graphic": "none", "sleeves": "short",
			"bottom_color": Color(0.2, 0.56, 0.57), "bottom_fade": Color(0.3, 0.66, 0.66),
			"shoe_color": Color(0.95, 0.95, 0.93), "shoe_accent": Color(0.82, 0.84, 0.86),
			"bracelet": true, "wristband_color": Color(0.85, 0.75, 0.3), "bulk": 0.9,
			# not rendered yet
			"body": "female", "hair_style": "curls", "top_style": "tee", "bottom_style": "slim",
			"shoes": "sneakers", "hat": "none", "outfit": "scrubs",
			"accessories": ["hospital_badge_lanyard", "reading_glasses_on_head", "watch"],
		},
	},
	# Darnell "Pickles" Pickett: best friend since second grade, cameraman, channel manager.
	# Films everything on the BROOMCAM (cracked phone duct-taped to a broom handle).
	"pickles": {
		"name": "PICKLES", "anim_style": "hyper",
		"look": {
			"anim_style": "hyper",
			"gear": Color(0.45, 0.78, 0.2), "skin": Color(0.56, 0.38, 0.26), "face": "kid",
			"hair": "curls", "hair_color": Color(0.06, 0.045, 0.04),
			"top": "hoodie", "top_color": Color(0.34, 0.6, 0.18), "top_accent": Color(0.95, 0.85, 0.2),
			"graphic": "none", "hood": false,
			"bottom_color": Color(0.5, 0.45, 0.34), "bottom_fade": Color(0.66, 0.6, 0.48),
			"shoe_color": Color(0.85, 0.2, 0.18), "shoe_accent": Color(0.95, 0.95, 0.95),
			"bulk": 0.84,
			# not rendered yet
			"body": "male", "hair_style": "curls", "top_style": "hoodie", "bottom_style": "baggy_jeans",
			"shoes": "high_tops", "hat": "bucket", "hat_color": Color(0.95, 0.85, 0.2),
			"accessories": ["broomcam", "headphones_round_neck", "duct_tape_roll"],
		},
	},
	# Mr. Hollis: the grumpy next-door neighbor with prize hydrangeas. Secretly HURRICANE HOLLIS,
	# six-time regional champion, forty years retired. White tank undershirt, gardening gloves.
	"hollis": {
		"name": "MR. HOLLIS", "anim_style": "oldschool",
		"look": {
			"anim_style": "oldschool",
			"gear": Color(0.55, 0.3, 0.75), "skin": Color(0.33, 0.22, 0.16), "face": "tank",
			"hair": "none", "hair_color": Color(0.82, 0.82, 0.8),
			"top": "tee", "top_color": Color(0.93, 0.92, 0.88), "top_accent": Color(0.55, 0.3, 0.75),
			"graphic": "none", "sleeves": "none",
			"bottom_color": Color(0.42, 0.36, 0.28), "bottom_fade": Color(0.5, 0.44, 0.36),
			"shoe_color": Color(0.3, 0.2, 0.14), "shoe_accent": Color(0.4, 0.3, 0.22),
			"tattoos": true, "bulk": 1.05,
			# not rendered yet
			"body": "male", "hair_style": "buzz", "top_style": "tee", "bottom_style": "slim",
			"shoes": "boots", "hat": "none",
			"accessories": ["gardening_gloves", "garden_hose", "white_mustache", "old_title_belt_tattoo"],
		},
	},
	# Rudy Two-Times: scrappy promoter who runs fights behind the store lot. Says everything twice.
	"rudy": {
		"name": "RUDY TWO-TIMES", "anim_style": "swagger",
		"look": {
			"anim_style": "swagger",
			"gear": Color(0.1, 0.7, 0.7), "skin": Color(0.78, 0.58, 0.44), "face": "tank",
			"hair": "curls", "hair_color": Color(0.15, 0.1, 0.07),
			"top": "hoodie", "top_color": Color(0.08, 0.62, 0.62), "top_accent": Color(0.6, 0.15, 0.55),
			"graphic": "none", "hood": false,
			"bottom_color": Color(0.08, 0.6, 0.6), "bottom_fade": Color(0.16, 0.7, 0.7),
			"shoe_color": Color(0.95, 0.95, 0.95), "shoe_accent": Color(0.6, 0.15, 0.55),
			"chain": true, "bracelet": true, "bulk": 0.95,
			# not rendered yet
			"body": "male", "hair_style": "curls", "top_style": "tracksuit", "bottom_style": "track_pants",
			"shoes": "sneakers", "hat": "bucket", "hat_color": Color(0.6, 0.15, 0.55),
			"stripe_color": Color(0.6, 0.15, 0.55), "stripe_count": 1, "chain_color": Color(1.0, 0.8, 0.26),
			"accessories": ["fanny_pack_of_cash", "clipboard", "toothpick"],
		},
	},
	# Preston Vale: slick influencer-promoter, boss of the VALE ELITE crew. The antagonist.
	"vale": {
		"name": "PRESTON VALE", "anim_style": "newschool",
		"look": {
			"anim_style": "newschool",
			"gear": Color(0.85, 0.75, 0.45), "skin": Color(0.86, 0.68, 0.56), "face": "kid",
			"hair": "none", "hair_color": Color(0.7, 0.55, 0.3),
			"top": "tee", "top_color": Color(0.96, 0.95, 0.92), "top_accent": Color(0.85, 0.75, 0.45),
			"graphic": "none", "sleeves": "long",
			"bottom_color": Color(0.12, 0.12, 0.16), "bottom_fade": Color(0.2, 0.2, 0.25),
			"shoe_color": Color(0.96, 0.96, 0.96), "shoe_accent": Color(0.85, 0.75, 0.45),
			"chain": true, "bulk": 0.86,
			# not rendered yet
			"body": "male", "hair_style": "buzz", "top_style": "designer_hoodie", "bottom_style": "slim",
			"shoes": "sneakers", "hat": "none", "chain_style": "layered",
			"chain_color": Color(0.92, 0.82, 0.5), "outfit": "cream_blazer_over_tee",
			"accessories": ["tinted_shades", "phone_on_gimbal", "contract_folder", "veneers"],
		},
	},
	# MC Lawn Dart: the backyard's hype MC (mc.gd) in person. Runs the LAWN DART LIVE hype channel.
	"lawndart": {
		"name": "MC LAWN DART", "anim_style": "hyper",
		"look": {
			"anim_style": "hyper",
			"gear": Color(1.0, 0.84, 0.2), "skin": Color(0.48, 0.32, 0.22), "face": "tank",
			"hair": "locs", "hair_color": Color(0.06, 0.045, 0.04),
			"top": "hoodie", "top_color": Color(1.0, 0.8, 0.16), "top_accent": Color(0.06, 0.06, 0.07),
			"graphic": "none", "hood": false,
			"bottom_color": Color(0.06, 0.06, 0.07), "bottom_fade": Color(0.2, 0.2, 0.22),
			"shoe_color": Color(1.0, 0.84, 0.2), "shoe_accent": Color(0.06, 0.06, 0.07),
			"chain": true, "bulk": 1.0,
			# not rendered yet
			"body": "male", "hair_style": "locs", "top_style": "tracksuit", "bottom_style": "track_pants",
			"shoes": "high_tops", "hat": "none", "chain_color": Color(1.0, 0.84, 0.2),
			"accessories": ["handheld_mic", "megaphone", "gold_sunglasses"],
		},
	},
}

const CHAPTERS := [
	# ------------------------------------------------------------------ CHAPTER 1 (rise)
	{
		"id": "ch1", "title": "CHAPTER 1", "name": "Rent Is Due",
		"teaser": "Mom wants $600 by the first. Tank has eleven dollars and a dream.",
		"payout": 100,
		"intro": [
			{
				"set": "kitchen", "time": "day", "music": "chill",
				"cast": {"tank": "left", "mom": "right"},
				"lines": [
					{"who": "narrator", "text": "The Eastside. 7:02 AM. The Magruder kitchen.", "emote": "idle", "shot": "wide"},
					{"who": "mom", "text": "Theodore Magruder. Why is there a dent in my refrigerator the exact shape of a grown man?", "emote": "point", "shot": "two_shot", "action": "enter_right"},
					{"who": "tank", "text": "Practicing the Fridge Drop, Ma. It's my finisher. The fridge is fine. Listen, it's humming.", "emote": "shrug"},
					{"who": "mom", "text": "It's humming because it's scared.", "emote": "cross_arms", "shot": "close"},
					{"who": "mom", "text": "Rent is due on the first. Your half is six hundred dollars. You are twenty-six years old.", "emote": "talk"},
					{"who": "tank", "text": "Twenty-five and a half. Emotionally.", "emote": "think"},
					{"who": "mom", "text": "Mrs. Okafor's nephew Gerald needs a room. Gerald has a JOB. Gerald has a FERN.", "emote": "point", "shot": "close"},
					{"who": "tank", "text": "Ma. Gerald couldn't wrestle that fern.", "emote": "shock"},
					{"who": "mom", "text": "Gerald doesn't have to. I'm on a double. Chili's in the blue dish. Do NOT eat the good cheese.", "emote": "talk", "action": "exit_right"},
				],
			},
			{
				"set": "bedroom", "time": "day", "music": "chill",
				"cast": {"tank": "center", "pickles": "right"},
				"lines": [
					{"who": "pickles", "text": "TANK! Our last video got forty-one views and ELEVEN DOLLARS in tips!", "emote": "cheer", "action": "enter_right", "cash": 11},
					{"who": "tank", "text": "Eleven dollars?! We're rich! ...How far is eleven from six hundred?", "emote": "cheer"},
					{"who": "pickles", "text": "Five hundred eighty-nine. I did the math on the Broomcam.", "emote": "think"},
					{"who": "pickles", "text": "Behold: the Broomcam. One phone, one roll of duct tape, one broom. Cinema.", "emote": "flex", "shot": "insert"},
					{"who": "phone", "text": "Scrubs_N_Slams: PROTECT YOUR NECK BABY. also eat a vegetable", "emote": "phone", "shot": "insert"},
					{"who": "tank", "text": "Who IS Scrubs_N_Slams? Every video. First comment. Every time.", "emote": "think"},
					{"who": "pickles", "text": "Our number one fan. Total mystery. Anyway, Lil Peligro wants to fight you for the yard. He's got a trampoline.", "emote": "shrug"},
				],
			},
			{
				"set": "backyard", "time": "dusk", "music": "hype",
				"cast": {"tank": "left", "peligro": "right", "hollis": "back_right", "pickles": "back_left"},
				"lines": [
					{"who": "narrator", "text": "The Magruder backyard. One kiddie pool. One shed. Mr. Hollis's prize hydrangeas, just over the fence.", "emote": "idle", "shot": "wide"},
					{"who": "hollis", "text": "Magruder! Anybody lands in my hydrangeas, I'm calling the city!", "emote": "angry"},
					{"who": "tank", "text": "Evening, Mr. Hollis! Love the flowers! Very... purple!", "emote": "talk"},
					{"who": "peligro", "text": "Big man! Today the student becomes the master! ...Wait. I was never your student. Today I just WIN!", "emote": "flex", "action": "enter_right"},
					{"who": "tank", "text": "Kid, I've been wrestling in this yard since you were bouncing in diapers.", "emote": "cross_arms"},
					{"who": "peligro", "text": "I STILL bounce! That's my whole thing!", "emote": "point"},
					{"who": "pickles", "text": "Rolling! Say something for the thumbnail!", "emote": "cheer"},
					{"who": "tank", "text": "Rent's due, Peligro. And I'm the landlord of this lawn.", "emote": "flex", "shot": "low_hero", "sfx": "bell"},
				],
			},
		],
		"match": {"opponent": "peligro", "cpu_skill": 0.3, "location": "backyard",
			"objective": "Win the match and start the rent fund",
			"bonus": {"text": "Hit your FRIDGE DROP once", "type": "signature", "count": 1, "cash": 25}},
		"win": [
			{
				"set": "backyard", "time": "night", "music": "hype",
				"cast": {"tank": "left", "peligro": "right", "pickles": "center"},
				"lines": [
					{"who": "pickles", "text": "THAT'S THUMBNAIL! Tips are pouring in! One hundred dollars, Tank!", "emote": "cheer", "cash": 100},
					{"who": "peligro", "text": "Okay, okay. You hit like a dropped fridge. Rematch someday. I'm getting a bigger trampoline.", "emote": "sit"},
					{"who": "tank", "text": "A hundred bucks. Ma's gonna cry. Or yell. One of those.", "emote": "flex", "shot": "low_hero"},
					{"who": "phone", "text": "Scrubs_N_Slams: that was GOOD baby. ice that shoulder", "emote": "phone", "shot": "insert"},
				],
			},
		],
		"lose": [
			{
				"set": "backyard", "time": "dusk", "music": "sad",
				"cast": {"tank": "left", "peligro": "right", "pickles": "center"},
				"lines": [
					{"who": "peligro", "text": "The yard is MINE! I'm putting a hammock right here!", "emote": "cheer"},
					{"who": "pickles", "text": "Good news: that fall got eight hundred views. Bad news: all eight hundred are laughing.", "emote": "shrug"},
					{"who": "tank", "text": "Ma's gonna rent my room to a fern.", "emote": "sad", "shot": "close"},
					{"who": "pickles", "text": "Get up. Fern people don't quit. Run it back!", "emote": "point"},
				],
			},
		],
	},
	# ------------------------------------------------------------------ CHAPTER 2 (rise)
	{
		"id": "ch2", "title": "CHAPTER 2", "name": "Noise Complaint",
		"teaser": "A punk band wants the yard. Mr. Hollis wants everybody to be quiet. Forever.",
		"payout": 150,
		"intro": [
			{
				"set": "porch", "time": "day", "music": "chill",
				"cast": {"tank": "left", "mom": "right"},
				"lines": [
					{"who": "narrator", "text": "Six days until rent. Mom just got home from a sixteen-hour shift.", "emote": "idle", "shot": "wide"},
					{"who": "tank", "text": "Ma! Look! A hundred dollars! From WRESTLING!", "emote": "cheer", "action": "enter_left"},
					{"who": "mom", "text": "Mm-hm. Is it real, or did you print it?", "emote": "sit"},
					{"who": "tank", "text": "It's tips! People PAY to watch me, Ma. I'm a content creator.", "emote": "flex"},
					{"who": "mom", "text": "Baby, you created a dent in my fridge.", "emote": "laugh", "shot": "close"},
					{"who": "mom", "text": "That's one hundred. Rent is six. I don't do math before coffee, but that's a big hole.", "emote": "sit"},
					{"who": "mom", "text": "Now hush. My feet are filing a complaint with management.", "emote": "facepalm"},
				],
			},
			{
				"set": "street", "time": "day", "music": "hype",
				"cast": {"tank": "left", "razz": "right", "pickles": "back_left"},
				"lines": [
					{"who": "razz", "text": "Oi, big lad! My band, the Gutter Choir, is playing YOUR backyard Saturday. Your mum said yes.", "emote": "point", "action": "enter_right"},
					{"who": "tank", "text": "My mom said YES?", "emote": "shock"},
					{"who": "razz", "text": "She said 'over my dead body.' In punk, that's a yes.", "emote": "shrug"},
					{"who": "pickles", "text": "Wait. A band means a crowd. Tank... a crowd TIPS.", "emote": "think"},
					{"who": "razz", "text": "We wrestle for it. I win, the yard's a mosh pit. You win, the Gutter Choir plays your entrance music.", "emote": "talk"},
					{"who": "tank", "text": "Is the music good?", "emote": "think"},
					{"who": "razz", "text": "It's LOUD, mate. That's better than good.", "emote": "flex", "shot": "low_hero"},
				],
			},
			{
				"set": "backyard", "time": "dusk", "music": "tense",
				"cast": {"tank": "left", "razz": "right", "hollis": "back_right"},
				"lines": [
					{"who": "hollis", "text": "Absolutely not. No bands. No body slams. My hydrangeas just started speaking to me again.", "emote": "angry"},
					{"who": "razz", "text": "Respect, grandpa. I'll keep it to one amp. Two. Three, tops.", "emote": "shrug"},
					{"who": "hollis", "text": "Son, I've been in more noise than you'll ever make. Fine. Stay off the flowers.", "emote": "cross_arms", "shot": "close"},
					{"who": "tank", "text": "...What did he mean, 'more noise'?", "emote": "think"},
					{"who": "narrator", "text": "Crowd: twenty-three neighbors, two dogs and one very confused pizza guy.", "emote": "idle", "shot": "wide"},
					{"who": "razz", "text": "LET'S MAKE SOME NOISE!", "emote": "cheer", "shot": "low_hero", "sfx": "cheer_small"},
				],
			},
		],
		"match": {"opponent": "razz", "cpu_skill": 0.37, "location": "backyard",
			"objective": "Win the yard back from the Gutter Choir",
			"bonus": {"text": "Break a table (Mom's old folding one... she said it's fine)", "type": "table_break", "count": 1, "cash": 40}},
		"win": [
			{
				"set": "backyard", "time": "night", "music": "hype",
				"cast": {"tank": "left", "razz": "right", "pickles": "center"},
				"lines": [
					{"who": "razz", "text": "You're mental, mate. I love it. Gutter Choir plays your entrance. Forever. Whether you want it or not.", "emote": "laugh"},
					{"who": "pickles", "text": "The neighbors tipped! One hundred fifty bucks!", "emote": "cheer", "cash": 150},
					{"who": "phone", "text": "MOM: why is my folding table on the internet in four pieces", "emote": "phone", "shot": "insert"},
					{"who": "tank", "text": "...Wait. She WATCHES the videos?", "emote": "shock"},
					{"who": "pickles", "text": "Nah. Somebody probably sent it to her. Probably.", "emote": "shrug"},
				],
			},
		],
		"lose": [
			{
				"set": "backyard", "time": "night", "music": "sad",
				"cast": {"tank": "left", "razz": "right"},
				"lines": [
					{"who": "razz", "text": "Don't be sad, big lad. Losing is extremely punk. You're basically a legend now.", "emote": "laugh"},
					{"who": "tank", "text": "My ears are ringing in two different keys.", "emote": "sit"},
					{"who": "razz", "text": "That's the spirit! Shake it off. We go again!", "emote": "point"},
				],
			},
		],
	},
	# ------------------------------------------------------------------ CHAPTER 3 (rise)
	{
		"id": "ch3", "title": "CHAPTER 3", "name": "Heartbreak Suplex",
		"teaser": "A pop star needs a villain for her music video. Tank needs a check.",
		"payout": 250,
		"intro": [
			{
				"set": "bedroom", "time": "night", "music": "chill",
				"cast": {"tank": "left", "pickles": "right"},
				"lines": [
					{"who": "pickles", "text": "Tank. TANK. MC Lawn Dart reposted the Razz match on LAWN DART LIVE!", "emote": "phone"},
					{"who": "tank", "text": "THE MC Lawn Dart? The guy who yells at backyards for a living?", "emote": "shock"},
					{"who": "tv", "text": "LAWN DART LIVE! THIS BIG MAN HITS LIKE A DROPPED FRIDGE! SOMEBODY CALL HIS MAMA!", "emote": "idle", "shot": "insert"},
					{"who": "pickles", "text": "Three thousand new subscribers overnight. And a DM.", "emote": "cheer"},
					{"who": "phone", "text": "STARLA VOLT: hi!! i need a big scary man for my music video. $250? xoxo", "emote": "phone", "shot": "insert"},
					{"who": "tank", "text": "Ask her if 'big scary man' gets a trailer.", "emote": "point"},
					{"who": "pickles", "text": "It's a store parking lot, Tank. You get a shopping cart.", "emote": "shrug"},
				],
			},
			{
				"set": "store_lot", "time": "day", "music": "hype",
				"cast": {"tank": "left", "starla": "right", "lawndart": "back_left"},
				"lines": [
					{"who": "starla", "text": "There he is, my villain! The song is 'Heartbreak Suplex.' You're the heartbreak. I'm the suplex.", "emote": "cheer", "action": "enter_right"},
					{"who": "tank", "text": "Hold on. I'm the VILLAIN?", "emote": "shock"},
					{"who": "starla", "text": "You look like a guy who'd eat a girl's fries. Don't take it personal. It's the brand.", "emote": "shrug"},
					{"who": "tank", "text": "I would NEVER eat a girl's fries. Without asking.", "emote": "sad", "shot": "close"},
					{"who": "lawndart", "text": "LIVE FROM A PARKING LOT, IT'S YOUR BOY, MC LAWN DART! I HEARD THERE WAS A FRIDGE IN TOWN!", "emote": "cheer", "shot": "low_hero", "action": "enter_left"},
					{"who": "starla", "text": "One thing, big guy. I do my own stunts. We shoot the fight in my aunt's backyard. Go easy and I'll know.", "emote": "point"},
					{"who": "tank", "text": "Ma raised me to never go easy. Also to wear clean socks. Today I'm one for two.", "emote": "cross_arms", "sfx": "bell"},
				],
			},
		],
		"match": {"opponent": "starla", "cpu_skill": 0.44, "location": "backyard",
			"objective": "Win the music-video fight. Make it look GOOD.",
			"bonus": {"text": "Land 2 air tricks (Starla bet you can't fly)", "type": "air_tricks", "count": 2, "cash": 50}},
		"win": [
			{
				"set": "store_lot", "time": "dusk", "music": "hype",
				"cast": {"tank": "left", "starla": "right", "lawndart": "center"},
				"lines": [
					{"who": "starla", "text": "Okay, that was AMAZING. You're not my villain. You're my co-star. I'm putting you in the credits.", "emote": "laugh"},
					{"who": "lawndart", "text": "THE FRIDGE CAN FLY! I'M PUTTING THIS ON EVERY SCREEN I OWN! I OWN TWO!", "emote": "cheer", "shot": "low_hero"},
					{"who": "starla", "text": "Here's your check, co-star. Don't spend it on anything I wouldn't.", "emote": "point", "cash": 250},
					{"who": "tank", "text": "Two hundred fifty dollars. I'm framing it. Then cashing it. Then framing the receipt.", "emote": "flex"},
				],
			},
		],
		"lose": [
			{
				"set": "store_lot", "time": "dusk", "music": "sad",
				"cast": {"tank": "left", "starla": "right"},
				"lines": [
					{"who": "starla", "text": "CUT! Babe, you were supposed to suplex the heartbreak, not BE the heartbreak.", "emote": "facepalm"},
					{"who": "tank", "text": "In my defense, the heartbreak was fast.", "emote": "sit"},
					{"who": "starla", "text": "Great footage, honestly. But I need the big ending. Places! Take two!", "emote": "laugh"},
				],
			},
		],
	},
	# ------------------------------------------------------------------ CHAPTER 4 (rise)
	{
		"id": "ch4", "title": "CHAPTER 4", "name": "Two-Times Tuesday",
		"teaser": "A promoter who says everything twice. A cowboy who barely says anything.",
		"payout": 400,
		"intro": [
			{
				"set": "kitchen", "time": "night", "music": "chill",
				"cast": {"tank": "left", "mom": "right"},
				"lines": [
					{"who": "narrator", "text": "Two days until rent. Tank has $500. Mom has been awake since yesterday.", "emote": "idle", "shot": "wide"},
					{"who": "mom", "text": "Theodore. Who ate the good cheese.", "emote": "eat"},
					{"who": "tank", "text": "A burglar. A hungry, handsome burglar.", "emote": "shrug"},
					{"who": "mom", "text": "A burglar with your exact teeth marks. Also, Gerald came by and measured your room. He brought the fern.", "emote": "facepalm"},
					{"who": "tank", "text": "Ma, I'm almost there. One more match. A real promoter called.", "emote": "talk"},
					{"who": "mom", "text": "The last 'promoter' in this family was Uncle Lou selling sunglasses out of his trunk.", "emote": "cross_arms"},
					{"who": "mom", "text": "I don't want you hurt for strangers on a phone. My knees hurt for strangers every night. One of us is enough.", "emote": "sad", "shot": "close"},
					{"who": "tank", "text": "That's why I'm doing it, Ma.", "emote": "sad", "shot": "close"},
					{"who": "mom", "text": "...Eat the chili. Leave the cheese.", "emote": "idle"},
				],
			},
			{
				"set": "store_lot", "time": "night", "music": "tense",
				"cast": {"tank": "left", "rudy": "center", "dusty": "right", "pickles": "back_left"},
				"lines": [
					{"who": "rudy", "text": "Tank Magruder! Tank Magruder! Rudy Two-Times. Promoter. Promoter.", "emote": "talk", "action": "enter_left"},
					{"who": "pickles", "text": "Why does he say everything twice?", "emote": "think"},
					{"who": "rudy", "text": "Lotta noise out here, kid. Lotta noise. Gotta make sure it lands. Make sure it lands.", "emote": "shrug"},
					{"who": "rudy", "text": "Four hundred to the winner, cash, out back in my cousin's yard. Plus a car wash coupon. Barely expired.", "emote": "point"},
					{"who": "dusty", "text": "Evenin'.", "emote": "cross_arms", "action": "enter_right"},
					{"who": "tank", "text": "That's it? Just 'evening'?", "emote": "shrug"},
					{"who": "dusty", "text": "Don't talk much. Grandma's ranch needs a new well pump. Every dollar I win goes home.", "emote": "talk", "shot": "close"},
					{"who": "tank", "text": "...Man. I was really hoping you'd be a jerk.", "emote": "sad"},
					{"who": "dusty", "text": "Sorry, partner. Raised right. Still gonna slam you into next week.", "emote": "laugh"},
					{"who": "rudy", "text": "Beautiful! Beautiful! Fight! Fight!", "emote": "cheer", "sfx": "bell"},
				],
			},
		],
		"match": {"opponent": "dusty", "cpu_skill": 0.5, "location": "backyard",
			"objective": "Win Rudy's Tuesday main event",
			"bonus": {"text": "Dive off a high perch (Rudy pays extra for altitude, extra for altitude)", "type": "perch_dive", "count": 1, "cash": 60}},
		"win": [
			{
				"set": "store_lot", "time": "night", "music": "hype",
				"cast": {"tank": "left", "rudy": "center", "dusty": "right"},
				"lines": [
					{"who": "rudy", "text": "Winner! Winner! Four hundred! Four hundred! Plus the coupon. The coupon.", "emote": "cheer", "cash": 400},
					{"who": "dusty", "text": "You fight honest, Magruder. You ever need a partner, I'll ride out.", "emote": "talk", "action": "shake_hands"},
					{"who": "tank", "text": "Here. Take a hundred for the well pump. Grandmas gotta drink.", "emote": "talk"},
					{"who": "dusty", "text": "...I'll pay you back in pie. My grandma's pie will change your life, partner.", "emote": "shock", "shot": "close"},
				],
			},
		],
		"lose": [
			{
				"set": "store_lot", "time": "night", "music": "sad",
				"cast": {"tank": "left", "rudy": "center", "dusty": "right"},
				"lines": [
					{"who": "rudy", "text": "Tough loss! Tough loss! Run it back next Tuesday! Or tonight. Tonight!", "emote": "shrug"},
					{"who": "dusty", "text": "Get up, partner. You were winning right up until you weren't. Happens to bulls too.", "emote": "point"},
					{"who": "tank", "text": "Did a bull ever get thrown into a kiddie pool?", "emote": "sit"},
					{"who": "dusty", "text": "Once. He got back up. Go on.", "emote": "laugh"},
				],
			},
		],
	},
	# ------------------------------------------------------------------ CHAPTER 5 (the shiny trap)
	{
		"id": "ch5", "title": "CHAPTER 5", "name": "Sign Here",
		"teaser": "Rent is paid. Then a smooth talker on a rooftop slides over a very shiny contract.",
		"payout": 600,
		"intro": [
			{
				"set": "kitchen", "time": "day", "music": "chill",
				"cast": {"tank": "left", "mom": "right"},
				"lines": [
					{"who": "tank", "text": "Ma. Six hundred dollars. Rent. Paid. By me. Theodore. Your son.", "emote": "flex", "action": "slam_table", "sfx": "pop"},
					{"who": "mom", "text": "...Mm.", "emote": "shock", "shot": "close"},
					{"who": "mom", "text": "I'm counting it again. Not because I don't trust you. Because I want to count it again.", "emote": "think"},
					{"who": "mom", "text": "Look at you. Don't let it go to your head. It's big enough. I've seen it on the internet.", "emote": "laugh"},
					{"who": "tank", "text": "WAIT. You've seen th-", "emote": "shock"},
					{"who": "mom", "text": "Bye! Late for work! Chili's in the blue dish!", "emote": "talk", "action": "exit_right"},
				],
			},
			{
				"set": "rooftop", "time": "night", "music": "tense",
				"cast": {"tank": "left", "vale": "center", "halo": "right", "pickles": "back_left"},
				"lines": [
					{"who": "narrator", "text": "Downtown. A rooftop party. Valet parking for people who don't own cars.", "emote": "idle", "shot": "wide"},
					{"who": "vale", "text": "Tank Magruder. Preston Vale, Vale Elite. I turn backyard guys into front-yard guys.", "emote": "talk", "action": "enter_right"},
					{"who": "tank", "text": "What's the difference?", "emote": "think"},
					{"who": "vale", "text": "About a hundred thousand followers and a pool.", "emote": "laugh"},
					{"who": "vale", "text": "Sign tonight. One showcase match with my guy, Yung Halo. Six hundred, guaranteed. Then the sky.", "emote": "point"},
					{"who": "halo", "text": "Don't get excited. I drop a song every week. I'll drop you before the chorus.", "emote": "cross_arms"},
					{"who": "pickles", "text": "Tank. This contract is eleven pages. The font is tiny. I think page nine says 'forever.'", "emote": "think", "shot": "over_shoulder"},
					{"who": "tank", "text": "Six hundred guaranteed, Pickles. Ma's feet. The good cheese. I'm signing.", "emote": "shrug"},
					{"who": "vale", "text": "Smart man. Sign here, here, and initial where it says 'all rights.'", "emote": "talk", "shot": "close"},
					{"who": "halo", "text": "...You should read it, man.", "emote": "sad", "shot": "close"},
					{"who": "vale", "text": "Halo. Stretch. Smile. Cameras are on.", "emote": "point"},
				],
			},
		],
		"match": {"opponent": "halo", "cpu_skill": 0.57, "location": "backyard",
			"objective": "Win the Vale Elite showcase",
			"bonus": {"text": "Score 4,000 style points (Vale wants 'content')", "type": "style_score", "count": 4000, "cash": 80}},
		"win": [
			{
				"set": "rooftop", "time": "night", "music": "tense",
				"cast": {"tank": "left", "vale": "center", "halo": "right"},
				"lines": [
					{"who": "vale", "text": "THAT is a product! Six hundred, as promised. See? I'm a man of my word. Several words. Eleven pages.", "emote": "cheer", "cash": 600},
					{"who": "tank", "text": "Man, I thought you'd be shady. You're alright, Vale.", "emote": "laugh"},
					{"who": "halo", "text": "Good match, big man. For real. ...Read page nine tonight.", "emote": "sad", "shot": "close"},
					{"who": "vale", "text": "Halo. Car. Now. Welcome to the family, Tank!", "emote": "point"},
				],
			},
		],
		"lose": [
			{
				"set": "rooftop", "time": "night", "music": "sad",
				"cast": {"tank": "left", "vale": "center", "halo": "right"},
				"lines": [
					{"who": "halo", "text": "Told you. Before the chorus.", "emote": "flex"},
					{"who": "vale", "text": "Don't sweat it, big guy. You're under contract either way. Losers make great content too. Again!", "emote": "laugh"},
					{"who": "tank", "text": "...Did he say 'either way'?", "emote": "think"},
				],
			},
		],
	},
	# ------------------------------------------------------------------ CHAPTER 6 (setback)
	{
		"id": "ch6", "title": "CHAPTER 6", "name": "Page Nine",
		"teaser": "The fine print bites. Vale owns the channel, and he wants Tank to lose on purpose.",
		"payout": 750,
		"intro": [
			{
				"set": "bedroom", "time": "day", "music": "sad",
				"cast": {"tank": "left", "pickles": "right"},
				"lines": [
					{"who": "pickles", "text": "Tank. Our channel. It says 'owned by Vale Elite.' He renamed it TANK THE GOON.", "emote": "shock"},
					{"who": "tv", "text": "VALE ELITE PRESENTS: TANK THE GOON! WATCH A BIG DUMB FRIDGE FALL OFF A SHED! (clown horn)", "emote": "idle", "shot": "insert"},
					{"who": "tank", "text": "He put clown horns on me. On my ART.", "emote": "angry"},
					{"who": "pickles", "text": "Page nine: 'all footage, likeness and catchphrases.' He owns 'That's thumbnail,' Tank. He owns MY thing.", "emote": "sad"},
					{"who": "phone", "text": "VALE: Big news! Sat you face Boom Bap Booker. You lose in round two. Legend's comeback. Sells great!", "emote": "phone", "shot": "insert"},
					{"who": "tank", "text": "I don't lose on purpose.", "emote": "cross_arms"},
					{"who": "pickles", "text": "Then don't. But I'm not filming a dive. And I'm not filming for HIM. I'm out, Tank.", "emote": "sad", "action": "exit_right"},
				],
			},
			{
				"set": "kitchen", "time": "night", "music": "sad",
				"cast": {"tank": "left", "mom": "right"},
				"lines": [
					{"who": "mom", "text": "There's a man named Preston on my voicemail calling you 'the asset.' Explain.", "emote": "cross_arms", "action": "enter_right"},
					{"who": "tank", "text": "I signed something, Ma. I didn't read it. He owns the channel. He kinda owns... me.", "emote": "sad"},
					{"who": "mom", "text": "Theodore! I read every form at that hospital TWICE. Because somebody always hides the bite in the small print.", "emote": "angry", "action": "slam_table", "sfx": "thud"},
					{"who": "tank", "text": "I was trying to HELP! You work doubles! Your feet! I wanted to be the guy who makes it easier!", "emote": "angry"},
					{"who": "mom", "text": "Baby, I never asked you for easier. I asked you to show up. You've been a stranger in my house for a month.", "emote": "sad", "shot": "close"},
					{"who": "mom", "text": "I don't need your money. I need you at this table, eating my chili, telling me about your day like a person.", "emote": "sad"},
					{"who": "tank", "text": "...My day was bad, Ma.", "emote": "sit", "shot": "close"},
					{"who": "mom", "text": "Then tell me. Then go do the right thing. In that order.", "emote": "talk", "action": "hug"},
				],
			},
			{
				"set": "street", "time": "dusk", "music": "tense",
				"cast": {"tank": "left", "booker": "right"},
				"lines": [
					{"who": "booker", "text": "Young man. Your boss says you're supposed to lay down for me in round two.", "emote": "cross_arms", "action": "enter_right"},
					{"who": "tank", "text": "You KNOW about that?", "emote": "shock"},
					{"who": "booker", "text": "I've been in this game since breakbeats came on vinyl. I can hear a rigged record spinning.", "emote": "laugh"},
					{"who": "booker", "text": "I don't want a gift. I want a fight. Bring everything, or don't bring nothing.", "emote": "point", "shot": "close"},
					{"who": "tank", "text": "Then you're getting everything, Mr. Booker.", "emote": "flex", "shot": "low_hero"},
					{"who": "booker", "text": "'Mister.' Okay. I like you already. Now I gotta hurt you.", "emote": "laugh", "sfx": "bell"},
				],
			},
		],
		"match": {"opponent": "booker", "cpu_skill": 0.64, "location": "backyard",
			"objective": "Win for real. No dives. No deals.",
			"bonus": {"text": "Hit your FRIDGE DROP twice. Your moves, your way.", "type": "signature", "count": 2, "cash": 75}},
		"win": [
			{
				"set": "backyard", "time": "night", "music": "sad",
				"cast": {"tank": "left", "booker": "center", "vale": "right"},
				"lines": [
					{"who": "booker", "text": "That right there was REAL. You didn't lie down. That's rarer than clean vinyl, son.", "emote": "talk", "action": "shake_hands"},
					{"who": "vale", "text": "You were supposed to LOSE! You're done, Magruder. I keep the channel. I keep EVERYTHING.", "emote": "angry", "action": "enter_right"},
					{"who": "tank", "text": "Keep it. I'm keeping me.", "emote": "cross_arms", "shot": "low_hero"},
					{"who": "booker", "text": "The crowd passed a hat. This is yours, not his. Now go home. Your mama's waiting.", "emote": "point", "cash": 750},
				],
			},
		],
		"lose": [
			{
				"set": "backyard", "time": "night", "music": "sad",
				"cast": {"tank": "left", "booker": "right"},
				"lines": [
					{"who": "booker", "text": "Hey. That wasn't a dive. I'd know. You just lost. Honest losing, you can come back from.", "emote": "talk"},
					{"who": "tank", "text": "My whole body sounds like a scratched record.", "emote": "sit"},
					{"who": "booker", "text": "Then flip it to the B-side and come take my head off. Again.", "emote": "point"},
				],
			},
		],
	},
	# ------------------------------------------------------------------ CHAPTER 7 (comeback)
	{
		"id": "ch7", "title": "CHAPTER 7", "name": "Back to the Yard",
		"teaser": "No channel. No promoter. Just a yard, a mop, and everybody who believed in him.",
		"payout": 1000,
		"intro": [
			{
				"set": "rooftop", "time": "night", "music": "sad",
				"cast": {"tank": "left", "mom": "right"},
				"lines": [
					{"who": "narrator", "text": "The roof of the Magruder house. 2 AM. Population: one big sad man.", "emote": "idle", "shot": "wide"},
					{"who": "mom", "text": "Scoot. I brought chili. AND the good cheese. Don't get used to it.", "emote": "eat", "action": "enter_right"},
					{"who": "tank", "text": "Ma, you climbed out the WINDOW? Your knees!", "emote": "shock"},
					{"who": "mom", "text": "My knees did a double and a half today. A window is nothing.", "emote": "laugh"},
					{"who": "tank", "text": "I lost the channel. Pickles quit. Vale's telling everybody I'm a goon.", "emote": "sad", "shot": "close"},
					{"who": "mom", "text": "Hand me my phone. Look. Read the username.", "emote": "phone"},
					{"who": "phone", "text": "Scrubs_N_Slams - 112 comments - member since your very first video", "emote": "phone", "shot": "insert"},
					{"who": "tank", "text": "...YOU'RE SCRUBS_N_SLAMS?!", "emote": "shock", "shot": "close"},
					{"who": "mom", "text": "I watch on my break. The whole nurses' station watches. Darlene from cardiology cried at the Dusty match.", "emote": "shrug"},
					{"who": "mom", "text": "I was never ashamed of the wrestling, baby. I was scared of it. That's a different thing.", "emote": "sad", "shot": "close"},
					{"who": "mom", "text": "Block party's in two weeks. You gonna sit up here, or go get your name back?", "emote": "point"},
					{"who": "tank", "text": "...Pass the cheese, Ma. I got work to do.", "emote": "flex", "shot": "low_hero"},
				],
			},
			{
				"set": "backyard", "time": "day", "music": "hype",
				"cast": {"tank": "left", "hollis": "right", "pickles": "back_left"},
				"lines": [
					{"who": "hollis", "text": "Magruder. Over here. Your stance is garbage and your elbow drop is a lie.", "emote": "cross_arms", "action": "enter_right"},
					{"who": "tank", "text": "Mr. Hollis? You know what an elbow drop IS?", "emote": "shock"},
					{"who": "hollis", "text": "Forty years ago they called me HURRICANE HOLLIS. Six regional titles. Two bad knees. One good garden.", "emote": "flex", "shot": "low_hero"},
					{"who": "hollis", "text": "I watched every match from that fence. You fight like Bernadette talks: loud and honest. Let's fix the rest.", "emote": "talk"},
					{"who": "pickles", "text": "...Hey. I built a new camera. It's a mop this time. The Mopcam. Upgrade.", "emote": "sad", "action": "enter_left"},
					{"who": "tank", "text": "PICKLES!", "emote": "cheer", "action": "hug"},
					{"who": "pickles", "text": "New channel. From scratch. MAGRUDER MAYHEM: MOM'S HOUSE. Vale can't own what we haven't made yet.", "emote": "laugh"},
				],
			},
			{
				"set": "street", "time": "dusk", "music": "hype",
				"cast": {"tank": "left", "lawndart": "center", "peligro": "right"},
				"lines": [
					{"who": "lawndart", "text": "BLOCK PARTY CARD! Main event slot is OPEN! But nobody headlines MY block without earning it!", "emote": "cheer", "shot": "low_hero"},
					{"who": "lawndart", "text": "You want it? Go through the People's Champ. Undefeated since the day he lost to YOU!", "emote": "point"},
					{"who": "peligro", "text": "Remember me? Bigger trampoline. Bigger following. Bigger chip on my shoulder.", "emote": "flex", "action": "enter_right"},
					{"who": "tank", "text": "Kid, I'm proud of you. Now I'm gonna slam you into your new trampoline.", "emote": "laugh"},
					{"who": "peligro", "text": "That's the spirit, hermano! No holding back!", "emote": "cheer", "sfx": "bell"},
				],
			},
		],
		"match": {"opponent": "peligro", "cpu_skill": 0.72, "location": "backyard",
			"objective": "Beat the People's Champ for the block party main event",
			"bonus": {"text": "Land 4 air tricks (Hurricane Hollis's homework)", "type": "air_tricks", "count": 4, "cash": 100}},
		"win": [
			{
				"set": "backyard", "time": "night", "music": "hype",
				"cast": {"tank": "left", "lawndart": "center", "peligro": "right", "pickles": "back_left"},
				"lines": [
					{"who": "lawndart", "text": "THE FRIDGE IS BACK IN STOCK! MAIN EVENT! BLOCK PARTY! BABY!", "emote": "cheer", "shot": "low_hero"},
					{"who": "peligro", "text": "Ow. Okay. You earned it. I'll be front row with a sign. A BIG one.", "emote": "sit"},
					{"who": "pickles", "text": "Twelve thousand subs in one night. A thousand in tips. THAT'S THUMBNAIL. And nobody owns it but us.", "emote": "cheer", "cash": 1000},
				],
			},
		],
		"lose": [
			{
				"set": "backyard", "time": "dusk", "music": "sad",
				"cast": {"tank": "left", "peligro": "right", "hollis": "back_right"},
				"lines": [
					{"who": "peligro", "text": "The student becomes the master! FINALLY! I've been practicing that line for months!", "emote": "cheer"},
					{"who": "hollis", "text": "Get up, Magruder. Hurricanes don't stay down. They circle back. Again.", "emote": "point"},
					{"who": "tank", "text": "Yes sir. Also, sorry about the hydrangeas. Again.", "emote": "sit"},
				],
			},
		],
	},
	# ------------------------------------------------------------------ CHAPTER 8 (finale)
	{
		"id": "ch8", "title": "CHAPTER 8", "name": "Block Party",
		"teaser": "The whole block. Every rival. Mom's first Saturday off in three years. Tank's freedom on the line.",
		"payout": 2500,
		"intro": [
			{
				"set": "kitchen", "time": "day", "music": "chill",
				"cast": {"tank": "left", "mom": "right"},
				"lines": [
					{"who": "narrator", "text": "Block party day. Mom took her first Saturday off in three years.", "emote": "idle", "shot": "wide"},
					{"who": "mom", "text": "Before you go. Close your eyes.", "emote": "talk"},
					{"who": "tank", "text": "Is it the good cheese? Is it a WHOLE BLOCK of the good cheese?", "emote": "think"},
					{"who": "mom", "text": "Better. Open.", "emote": "laugh"},
					{"who": "narrator", "text": "THE KITCHEN CHAMPIONSHIP. Cereal box, tinfoil, glitter glue. Made by nine-year-old Theodore.", "emote": "idle", "shot": "insert"},
					{"who": "tank", "text": "You KEPT this?!", "emote": "shock", "shot": "close"},
					{"who": "mom", "text": "I keep everything you make, baby. Win or lose, you bring this home. That's the only title in this house.", "emote": "sad", "shot": "close"},
					{"who": "tank", "text": "Love you, Ma.", "emote": "sad", "action": "hug"},
					{"who": "mom", "text": "Love you too. Also: Vale bet your contract on today. You win, you're free. You lose, he owns you till forty.", "emote": "point"},
					{"who": "tank", "text": "WHAT?!", "emote": "shock"},
					{"who": "mom", "text": "I read it twice. Then Darlene's son read it. He's in law school. He's very motivated. He loved the Dusty match.", "emote": "shrug"},
				],
			},
			{
				"set": "car", "time": "day", "music": "tense",
				"cast": {"tank": "left", "halo": "right"},
				"lines": [
					{"who": "halo", "text": "Get in. Two minutes. Vale's not here. Nice car, right? It's his. My songs are his. My NAME is his.", "emote": "sit"},
					{"who": "halo", "text": "If I win today, I'm still his. If you win... maybe that's proof nobody has to be.", "emote": "sad", "shot": "close"},
					{"who": "tank", "text": "You want me to beat you?", "emote": "think"},
					{"who": "halo", "text": "NO. I want you to TRY. I'm fighting like my life's on it. 'Cause it kinda is.", "emote": "angry"},
					{"who": "tank", "text": "Then let's give 'em a real one.", "emote": "talk", "action": "shake_hands"},
				],
			},
			{
				"set": "street", "time": "dusk", "music": "hype",
				"cast": {"tank": "center", "razz": "left", "starla": "right", "dusty": "back_left", "booker": "back_right"},
				"lines": [
					{"who": "narrator", "text": "Hydrangea Street Block Party. Population: everybody.", "emote": "idle", "shot": "wide"},
					{"who": "razz", "text": "Gutter Choir's playing your entrance, big lad! We learned a SECOND CHORD for it!", "emote": "cheer"},
					{"who": "starla", "text": "I brought lights, a fog machine, and two backup dancers. You're welcome, co-star.", "emote": "point"},
					{"who": "dusty", "text": "Brought Grandma's pie. Well pump's fixed. Figured I owed you a slice.", "emote": "talk"},
					{"who": "booker", "text": "Remember. Holds on the one, slams on the two. And don't you dare lie down.", "emote": "cross_arms"},
					{"who": "tank", "text": "Y'all... I started out rolling around a yard for eleven dollars.", "emote": "sad", "shot": "low_hero"},
				],
			},
			{
				"set": "backyard", "time": "night", "music": "hype",
				"cast": {"tank": "left", "lawndart": "center", "vale": "right", "mom": "back_left", "hollis": "back_right"},
				"lines": [
					{"who": "lawndart", "text": "LIVE FROM THE BIGGEST BACKYARD ON THE EASTSIDE... IT'S BLOCK PARTY MAIN EVENT TIME!", "emote": "cheer", "shot": "low_hero", "sfx": "cheer_small"},
					{"who": "vale", "text": "Last chance, Magruder. Lose gracefully and I'll let you keep a catchphrase. A small one.", "emote": "point"},
					{"who": "mom", "text": "Mr. Vale. I work doubles in an ER. I've seen scarier things than you in a waiting room at 3 AM.", "emote": "cross_arms", "action": "walk_to:center"},
					{"who": "hollis", "text": "And I've seen HER, son. I'd sit down.", "emote": "laugh"},
					{"who": "lawndart", "text": "SOMEBODY CALL HIS MAMA! ...Oh. She's right here. And she is NOT playing!", "emote": "shock"},
					{"who": "tank", "text": "This one's for the yard. For Ma. For everybody who paid eleven bucks to believe.", "emote": "flex", "shot": "low_hero", "sfx": "bell"},
				],
			},
		],
		"match": {"opponent": "halo", "cpu_skill": 0.8, "location": "backyard",
			"objective": "Main event: win your freedom in front of the whole block",
			"bonus": {"text": "Score 6,000 style points. Give the block a SHOW.", "type": "style_score", "count": 6000, "cash": 250}},
		"win": [
			{
				"set": "backyard", "time": "night", "music": "hype",
				"cast": {"tank": "center", "mom": "left", "halo": "right", "vale": "back_right", "pickles": "back_left"},
				"lines": [
					{"who": "halo", "text": "You did it, big man. ...WE did it. Nobody owns either of us now.", "emote": "cheer", "action": "shake_hands"},
					{"who": "mom", "text": "Mr. Vale. Page nine is now confetti. Darlene's son has a few more pages for you. Run along.", "emote": "point"},
					{"who": "vale", "text": "This isn't over! I have LAWYERS! ...I have a lawyer. He's my cousin.", "emote": "shock", "action": "exit_right"},
					{"who": "pickles", "text": "Purse plus tips: TWENTY-FIVE HUNDRED DOLLARS! Two hundred thousand views! THAT'S THUMBNAIL!", "emote": "cheer", "cash": 2500},
					{"who": "mom", "text": "Come here, champ. Kitchen Champion of the World. Undisputed.", "emote": "sad", "action": "hug"},
					{"who": "tank", "text": "Ma... I think I can cover rent for, like, a while.", "emote": "sad", "shot": "close"},
					{"who": "mom", "text": "Good. Rent's still due on the first. And Gerald is still asking about your room.", "emote": "laugh"},
					{"who": "narrator", "text": "Tank Magruder. No job. Still lives with his mom. Undisputed Kitchen Champion. THE END... for now.", "emote": "idle", "shot": "wide"},
				],
			},
		],
		"lose": [
			{
				"set": "backyard", "time": "night", "music": "sad",
				"cast": {"tank": "left", "mom": "back_left", "halo": "right"},
				"lines": [
					{"who": "halo", "text": "Hey. Get up. I didn't want it like this. Make me fight you again. Please.", "emote": "sad"},
					{"who": "mom", "text": "Theodore. I did not take a Saturday off to watch you nap in the grass. UP.", "emote": "point", "shot": "close"},
					{"who": "tank", "text": "Yes, ma'am.", "emote": "flex", "shot": "low_hero"},
				],
			},
		],
	},
]
