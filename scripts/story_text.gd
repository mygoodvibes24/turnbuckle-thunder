extends RefCounted
## City 2 City Wrestling: story-text tokens (caw_contract.md). Load with preload, call statically:
##   const StoryText := preload("res://scripts/story_text.gd")
##   label.text = StoryText.resolve("{NAME}! Rent's due, {First}.")
##
## The story protagonist is the player's created wrestler (Game.caw_data(), user://caw.cfg) when
## one exists, else Tank. Tokens (case of the token picks the case of the result):
##   {NAME} {Name} {name}          short name ("TANK" / "Tank")         - what everyone calls them
##   {FULLNAME} {Fullname}         ring name ("TANK MAGRUDER" / "Tank Magruder")
##   {FIRST} {First}               first name (Mom, when they're in trouble: "Theodore")
##   {SIG} {Sig}                   their finisher's name ("FRIDGE DROP")
##   {he} {him} {his} {son} {boy}  pronouns / words (he|she|they): he/she/they, him/her/them,
##   {man} {guy}                   his/her/their, son/daughter/kid, boy/girl/kid, man/woman/person,
##                                 guy/girl/person. {He} = capitalised, {HIS} = upper case.
## Unknown tokens are left alone. resolve() is idempotent (already-resolved text has no tokens).

const TANK_DEFAULTS := {"short_name": "TANK", "ring_name": "TANK MAGRUDER", "first_name": "THEODORE", "pronouns": "he",
	"signature": "FRIDGE DROP"}

const PRONOUNS := {
	"he": {"he": "he", "him": "him", "his": "his", "son": "son", "boy": "boy", "man": "man", "guy": "guy"},
	"she": {"he": "she", "him": "her", "his": "her", "son": "daughter", "boy": "girl", "man": "woman", "guy": "girl"},
	"they": {"he": "they", "him": "them", "his": "their", "son": "kid", "boy": "kid", "man": "person", "guy": "person"},
}


static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null


## True when a created wrestler exists (and the Game helpers from the CAW editor are present).
static func caw_active() -> bool:
	var g := _game()
	return g != null and g.has_method("caw_exists") and bool(g.call("caw_exists"))


## The roster id the story's protagonist fights as: "caw" or "tank".
static func hero_id() -> String:
	return "caw" if caw_active() else "tank"


## The protagonist's saved fields (Tank's when there is no created wrestler).
static func hero() -> Dictionary:
	var d := TANK_DEFAULTS.duplicate()
	if caw_active():
		var g := _game()
		var cd: Variant = g.call("caw_data") if g.has_method("caw_data") else {}
		if cd is Dictionary:
			var c: Dictionary = cd
			var ring := str(c.get("ring_name", "")).strip_edges().to_upper()
			if ring != "":
				d["ring_name"] = ring
				var sn := str(c.get("short_name", "")).strip_edges().to_upper()
				d["short_name"] = sn if sn != "" else ring.split(" ", false)[0]
				var fn := str(c.get("first_name", "")).strip_edges().to_upper()
				d["first_name"] = fn if fn != "" else str(d["short_name"])
			var ce: Variant = g.call("caw_entry") if g.has_method("caw_entry") else {}
			if ce is Dictionary and str((ce as Dictionary).get("signature", "")) != "":
				d["signature"] = str((ce as Dictionary)["signature"]).to_upper()
			var pr := str(c.get("pronouns", "he")).to_lower()
			d["pronouns"] = pr if PRONOUNS.has(pr) else "he"
	return d


## The protagonist's ring name ("TANK MAGRUDER" or the created wrestler's).
static func hero_full_name() -> String:
	return str(hero()["ring_name"])


static func hero_short_name() -> String:
	return str(hero()["short_name"])


## "BIG DEE" -> "Big Dee". Words without vowels (MC, DJ) stay upper case.
static func title_case(s: String) -> String:
	var out: PackedStringArray = []
	for w in s.split(" "):
		var lw := w.to_lower()
		var has_vowel := false
		for ch in "aeiouy":
			if lw.contains(ch):
				has_vowel = true
				break
		if not has_vowel or w.length() < 2:
			out.append(w.to_upper())
		else:
			out.append(lw.substr(0, 1).to_upper() + lw.substr(1))
	return " ".join(out)


static func table() -> Dictionary:
	var h := hero()
	var t: Dictionary = (PRONOUNS[str(h["pronouns"])] as Dictionary).duplicate()
	t["name"] = title_case(str(h["short_name"]))
	t["fullname"] = title_case(str(h["ring_name"]))
	t["first"] = title_case(str(h["first_name"]))
	t["sig"] = title_case(str(h["signature"]))
	return t


static func resolve(text: String) -> String:
	if not text.contains("{"):
		return text
	return _resolve_with(text, table())


static func _resolve_with(text: String, t: Dictionary) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		var a := text.find("{", i)
		if a < 0:
			out += text.substr(i)
			break
		var b := text.find("}", a + 1)
		if b < 0:
			out += text.substr(i)
			break
		out += text.substr(i, a - i)
		var key := text.substr(a + 1, b - a - 1)
		var kl := key.to_lower()
		if t.has(kl) and key.length() > 0:
			var v := str(t[kl])
			if key == key.to_upper() and key != kl:
				v = v.to_upper()
			elif key.substr(0, 1) == key.substr(0, 1).to_upper() and key.substr(0, 1) != kl.substr(0, 1):
				v = v.substr(0, 1).to_upper() + v.substr(1)
			out += v
		else:
			out += text.substr(a, b - a + 1)
		i = b + 1
	return out


## A deep copy of story data (Arrays / Dictionaries of scenes, chapters...) with every String
## value resolved. Keys are left alone.
static func resolve_deep(v: Variant) -> Variant:
	return _deep(v, table())


static func _deep(v: Variant, t: Dictionary) -> Variant:
	if v is String:
		var s: String = v
		return _resolve_with(s, t) if s.contains("{") else s
	if v is Array:
		var out: Array = []
		for x: Variant in (v as Array):
			out.append(_deep(x, t))
		return out
	if v is Dictionary:
		var d: Dictionary = {}
		var src: Dictionary = v
		for k: Variant in src:
			d[k] = _deep(src[k], t)
		return d
	return v


## The story CAST with the protagonist slot ("tank") filled in: the created wrestler's name and
## look when one exists, else Tank (name resolved). Other entries are untouched.
static func hero_cast(cast: Dictionary) -> Dictionary:
	var c: Dictionary = cast.duplicate()
	var e: Dictionary = {}
	if c.has("tank") and c["tank"] is Dictionary:
		e = (c["tank"] as Dictionary).duplicate()
	if caw_active():
		var g := _game()
		var ce: Variant = g.call("caw_entry") if g.has_method("caw_entry") else {}
		if ce is Dictionary and (ce as Dictionary).has("look"):
			var lk: Dictionary = ((ce as Dictionary)["look"] as Dictionary).duplicate(true)
			e = {"name": hero_short_name(), "look": lk}
			if (ce as Dictionary).has("anim_style"):
				e["anim_style"] = (ce as Dictionary)["anim_style"]
		else:
			e["name"] = hero_short_name()
	else:
		e["name"] = resolve(str(e.get("name", "{NAME}")))
		if not e.has("roster_id") and not e.has("look"):
			e["roster_id"] = "tank"
	c["tank"] = e
	return c
