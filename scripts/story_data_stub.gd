extends RefCounted
## STORY MODE placeholder data (same schema as scripts/story_data.gd, see story_schema.md).
## scripts/story.gd uses this file only while story_data.gd does not exist yet.

const CAST := {
	"tank": {"name": "TANK", "roster_id": "tank"},
	"peligro": {"name": "LIL PELIGRO", "roster_id": "peligro"},
	"dusty": {"name": "DUSTY BUCKLES", "roster_id": "dusty"},
	"mom": {"name": "MOM", "anim_style": "swagger", "look": {
		"gear": Color(0.75, 0.3, 0.55), "skin": Color(0.42, 0.28, 0.2), "face": "tank",
		"hair": "curls", "hair_color": Color(0.08, 0.06, 0.05),
		"top": "hoodie", "top_color": Color(0.7, 0.45, 0.6), "top_accent": Color(0.95, 0.85, 0.9),
		"bottom_color": Color(0.25, 0.25, 0.32), "shoe_color": Color(0.9, 0.9, 0.9), "bulk": 0.9,
	}},
}

const CHAPTERS := [
	{
		"id": "ch1", "title": "CHAPTER 1", "name": "Rent Is Due",
		"teaser": "Mom wants $150 by Friday. The neighbor kid in the mask has a trampoline and a dream.",
		"payout": 150,
		"intro": [
			{
				"set": "kitchen", "time": "day", "music": "chill",
				"cast": {"tank": "left", "mom": "right"},
				"lines": [
					{"who": "narrator", "text": "Tank Magruder. Thirty-one. Lives in his mom's back bedroom.", "emote": "idle", "shot": "wide"},
					{"who": "mom", "text": "Tank. Baby. Light of my life. Where is the rent money?", "emote": "cross_arms", "shot": "close"},
					{"who": "tank", "text": "Ma, I got a business plan. Backyard wrestling. People PAY for this.", "emote": "flex"},
					{"who": "mom", "text": "One hundred fifty dollars. Friday. Or you sleep with the lawnmower.", "emote": "point", "action": "slam_table", "sfx": "thud"},
				],
			},
			{
				"set": "backyard", "time": "night", "music": "hype",
				"cast": {"tank": "left", "peligro": "right"},
				"lines": [
					{"who": "peligro", "text": "Yo Tank! Five bucks a head, the whole block is here. You ready to fly?", "emote": "cheer"},
					{"who": "tank", "text": "I don't fly, kid. I land.", "emote": "cross_arms", "shot": "low_hero"},
				],
			},
		],
		"match": {"opponent": "peligro", "cpu_skill": 0.25, "location": "backyard",
			"objective": "Pin Lil Peligro",
			"bonus": {"text": "Land 3 air tricks", "type": "air_tricks", "count": 3, "cash": 50}},
		"win": [
			{"set": "backyard", "time": "night", "cast": {"tank": "center"},
				"lines": [{"who": "tank", "text": "Rent: paid. Dignity: mostly intact.", "emote": "cheer", "cash": 150}]},
		],
		"lose": [
			{"set": "backyard", "time": "night", "cast": {"tank": "center"},
				"lines": [{"who": "tank", "text": "...the lawnmower's actually pretty comfy. Run it back.", "emote": "sad"}]},
		],
	},
	{
		"id": "ch2", "title": "CHAPTER 2", "name": "Table Manners",
		"teaser": "Dusty Buckles rolls into town with a folding table and a grudge against furniture.",
		"payout": 200,
		"intro": [
			{
				"set": "porch", "time": "dusk", "music": "tense",
				"cast": {"tank": "left", "dusty": "right"},
				"lines": [
					{"who": "dusty", "text": "Heard you're the big dog on this block. I eat big dogs for breakfast. With gravy.", "emote": "point"},
					{"who": "tank", "text": "That's... a weird breakfast, man.", "emote": "shrug"},
					{"who": "phone", "text": "MOM: bring milk home. and WIN.", "emote": "phone"},
				],
			},
		],
		"match": {"opponent": "dusty", "cpu_skill": 0.4, "location": "backyard",
			"objective": "Beat Dusty Buckles",
			"bonus": {"text": "Put somebody through a table", "type": "table_break", "count": 1, "cash": 75}},
		"win": [
			{"set": "backyard", "time": "night", "cast": {"tank": "center", "dusty": "right"},
				"lines": [{"who": "dusty", "text": "Dang. You owe me a table.", "emote": "sit"}]},
		],
		"lose": [
			{"set": "backyard", "time": "night", "cast": {"tank": "left", "dusty": "right"},
				"lines": [{"who": "dusty", "text": "Gravy, son. Gravy.", "emote": "laugh"}]},
		],
	},
]
