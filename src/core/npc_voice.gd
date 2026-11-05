class_name NPCVoice
extends RefCounted
## How people talk about YOU. Every line is assembled from the copy grammar
## (data/copy.json + data/copy_people.json) and three things:
##   * who you are  - class, age, background, personality, motivation, secret, money, debt,
##                    fame, bounty, crew, wounds, upgrades, saga progress;
##   * what they SAW - acts done in their line of sight are remembered (NPC.memories)
##                    and the whole planet gossips about them (Game.flags "street_<planet>");
##   * who THEY are  - voice (their main trait / robot / merchant) and mood toward you.
## Stances (approve / disapprove / fear / amused) come from data/reactions.json.

const STANCES := ["approve", "disapprove", "fear", "amused"]
const MAX_MEMORIES := 6

static var _react: Dictionary = {}


static func reactions() -> Dictionary:
	if _react.is_empty():
		var path := "res://data/reactions.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_react = parsed
	return _react


# --- Who is talking -------------------------------------------------------------------------

static func voice(npc: Node) -> String:
	if npc.role == "merchant":
		return "merchant"
	var v := str(npc.look.get("variant", "")) if npc.look is Dictionary else ""
	if v.begins_with("r"):
		return "robot"
	var tr_list: Array = npc.traits
	return str(tr_list[0]) if not tr_list.is_empty() else "poor"


static func mood(npc: Node) -> String:
	for m in npc.memories:
		if str(m.get("stance", "")) == "fear":
			return "afraid"
	if int(npc.attitude) >= 15:
		return "warm"
	if int(npc.attitude) <= -15:
		return "cold"
	if Factions.total_bounty() >= 400 and (npc.traits as Array).has("poor"):
		return "afraid"
	return "neutral"


## How someone with this NPC's traits feels about an act of this kind.
static func stance_for(npc: Node, kind: String) -> String:
	var table: Dictionary = reactions().get("stance", {})
	var key := voice(npc)
	var row: Dictionary = table.get(key, table.get("poor", {}))
	var s := str(row.get(kind, table.get("default", {}).get(kind, "amused")))
	# Friends forgive, loyal informants cheer you on - except for murder.
	if kind != "murder" and (npc.loyal or int(npc.attitude) >= 35) and s in ["disapprove", "fear"]:
		s = "amused"
	return s


# --- Shared variables (everything is connected) -----------------------------------------------

static func vars(npc: Node = null, extra: Dictionary = {}) -> Dictionary:
	var v: Dictionary = Interactions._rumor_vars()
	v["name"] = Game.player_name
	v["years"] = str(Game.age)
	v["class"] = str(Origin.get_tag("class", str(Game.tags.get("class", ""))).get("name", "drifter")).to_lower()
	v["background"] = str(Origin.get_tag("background", str(Game.tags.get("background", ""))).get("name", "nobody")).to_lower()
	v["heir"] = DataDB.faction_name(Origin.heir_of())
	v["credits"] = str(Game.credits)
	v["debt"] = str(Game.air_debt)
	v["bounty"] = str(Factions.total_bounty())
	v["fame"] = str(int(Game.flags.get("fame", 0)))
	v["followers"] = str(int(Game.flags.get("followers", 0)))
	var ctrl := str(Game.current_planet.get("controller", ""))
	v["controller"] = DataDB.faction_name(ctrl) if ctrl != "" else "nobody"
	var crisis := PlanetGenerator.layer(Game.current_planet, "crises") if not Game.current_planet.is_empty() else {}
	v["crisis"] = str(crisis.get("name", "the bills")).to_lower()
	var names: Array = []
	for id in Crew.members:
		names.append(str(Crew.def(id).get("name", "")))
	v["crew"] = names[randi() % names.size()] if not names.is_empty() else "your crew"
	if npc:
		v["npc"] = npc.npc_name
		v["job"] = npc.job
		v["need"] = str(npc.need).to_lower()
		v["their_faction"] = DataDB.faction_name(npc.faction) if npc.faction != "" else "nobody"
	v.merge(extra, true)
	return v


static var _recent: Array[String] = []  # last lines said anywhere: never repeat one back-to-back


static func say(template: String, npc: Node = null, extra: Dictionary = {}, rng: RandomNumberGenerator = null) -> String:
	var v := vars(npc, extra)
	var text := Copy.expand(template, rng, v)
	for i in 5:
		if not _recent.has(text):
			break
		text = Copy.expand(template, rng, v)
	# Everyone has a verbal tic of their own (NPC.tic), used now and then.
	if npc and "tic" in npc and str(npc.tic) != "" and (rng.randf() if rng else randf()) < 0.22:
		text += " " + Copy.expand(str(npc.tic), rng, v)
	_recent.append(text)
	if _recent.size() > 40:
		_recent.pop_front()
	return text


# --- What they think of you -------------------------------------------------------------------

## A remark about who you are, voiced by this NPC. `bubble` = short form for speech bubbles.
static func remark(npc: Node, rng: RandomNumberGenerator, bubble: bool = false) -> String:
	var topic := _pick_topic(npc, rng)
	var body := "#%s#" % topic
	var m := mood(npc)
	var vo := voice(npc)
	if not bubble and rng.randf() < 0.6:
		body = "#open_%s# %s" % [m, body]
	if rng.randf() < (0.25 if bubble else 0.45):
		body += " #close_%s#" % vo
	var text := say(body, npc, {}, rng)
	return text if bubble else "\"%s\"" % text


static func _pick_topic(npc: Node, rng: RandomNumberGenerator) -> String:
	var w := {}  # topic -> weight
	var t: Dictionary = Game.tags
	if Copy.has("pc_class_" + str(t.get("class", ""))):
		w["pc_class_" + str(t["class"])] = 3.0
	if Copy.has("pc_age_" + str(t.get("age", ""))):
		w["pc_age_" + str(t["age"])] = 2.0
	if Copy.has("pc_bg_" + str(t.get("background", ""))):
		w["pc_bg_" + str(t["background"])] = 3.0
	if Copy.has("pc_pers_" + str(t.get("personality", ""))):
		w["pc_pers_" + str(t["personality"])] = 1.5
	if Copy.has("pc_goal_" + str(t.get("motivation", ""))):
		w["pc_goal_" + str(t["motivation"])] = 1.5
	# Only the odd ones notice your secret.
	if (npc.traits as Array).has("weird") and Copy.has("pc_secret_" + str(t.get("secret", ""))):
		w["pc_secret_" + str(t["secret"])] = 2.5
	if Game.hp < Game.max_hp() * 0.4:
		w["pc_hurt"] = 5.0
	if Factions.total_bounty() >= 300:
		w["pc_wanted"] = 3.0
	if int(Game.flags.get("fame", 0)) >= 15:
		w["pc_famous"] = 3.0
	if Game.credits >= 1500:
		w["pc_flush"] = 2.0
	elif Game.credits < 25:
		w["pc_broke"] = 2.0
	if Game.air_debt >= 150:
		w["pc_debt"] = 2.0
	if not Crew.members.is_empty():
		w["pc_crew"] = 1.5
	if int(Game.flags.get("upgrade_count", 0)) > 0:
		w["pc_upgraded"] = 1.5
	if Causality.count("murder") >= 2 and Causality.infamy_at(Game.location_id) > 0:
		w["pc_killer"] = 3.0
	if Causality.count("charity") >= 3:
		w["pc_saint"] = 2.5
	if int(Game.flags.get("followers", 0)) >= 5:
		w["pc_leader"] = 2.0
	if not Game.current_planet.is_empty():
		w["pc_planet"] = 1.5
		w["pc_saga"] = 1.5
	if mood(npc) == "warm":
		w["npc_life"] = 2.0
	var total := 0.0
	for k in w:
		total += float(w[k])
	var roll := rng.randf() * total
	for k in w:
		roll -= float(w[k])
		if roll <= 0.0:
			return k
	return "pc_class_" + str(t.get("class", "working_poor"))


# --- What they saw ------------------------------------------------------------------------------

## Verdict tail: kind-specific if the grammar has one ("judge_hurt_approve"), else generic.
static func _judge(kind: String, stance: String) -> String:
	var k := "judge_%s_%s" % [kind, stance]
	return "#%s#" % k if Copy.has(k) else "#judge_%s#" % stance


## Muttered aside about something they saw (speech bubble).
static func aside(npc: Node, mem: Dictionary, rng: RandomNumberGenerator) -> String:
	var kind := str(mem.get("kind", "weird"))
	return say("#aside_open# #act_%s#. %s" % [kind, _judge(kind, str(mem.get("stance", "amused")))], npc,
		{"target": str(mem.get("target", "someone"))}, rng)


## Immediate reaction when an act happens in front of them (speech bubble).
static func react_now(npc: Node, kind: String, stance: String, target: String, rng: RandomNumberGenerator) -> String:
	var whole := "now_%s_%s" % [kind, stance]
	var tpl := "#%s#" % whole if Copy.has(whole) else "#now_%s# %s" % [kind, _judge(kind, stance)]
	if rng.randf() < 0.3:
		tpl += " #close_%s#" % voice(npc)
	return say(tpl, npc, {"target": target}, rng)


## Bringing it up later, when you talk to them.
static func recall(npc: Node, mem: Dictionary, rng: RandomNumberGenerator) -> String:
	var kind := str(mem.get("kind", "weird"))
	var tpl := "#recall_open# #act_%s#. %s" % [kind, _judge(kind, str(mem.get("stance", "amused")))]
	return "\"%s\"" % say(tpl, npc, {"target": str(mem.get("target", "someone"))}, rng)


## The planet's version of events, for people who weren't there.
static func gossip(npc: Node, rng: RandomNumberGenerator) -> String:
	var street := street_memory()
	if street.is_empty():
		return ""
	var kinds := street.keys()
	var kind: String = kinds[rng.randi() % kinds.size()]
	var tpl := "#gossip_open# #act_%s#. %s" % [kind, _judge(kind, stance_for(npc, kind))]
	return "\"%s\"" % say(tpl, npc, {"target": "someone"}, rng)


static func street_memory(location_id: String = "") -> Dictionary:
	var key := "street_" + (location_id if location_id != "" else Game.location_id)
	var d = Game.flags.get(key, {})
	return d if d is Dictionary else {}


static func add_street_memory(kind: String) -> void:
	var key := "street_" + Game.location_id
	var d := street_memory()
	d[kind] = int(d.get(kind, 0)) + 1
	Game.flags[key] = d


## How the street's stories about you colour a stranger's first impression (-30..30).
static func street_bias(npc: Node) -> int:
	var street := street_memory()
	var w := {"approve": 3, "amused": 1, "disapprove": -3, "fear": -4}
	var total := 0
	for kind in street:
		total += int(w.get(stance_for(npc, kind), 0)) * mini(int(street[kind]), 5)
	return clampi(total, -30, 30)


## A planet where you've killed in the street is a planet where people cross the road.
static func street_feared(npc: Node) -> bool:
	var street := street_memory()
	var bloody := int(street.get("murder", 0)) * 2 + int(street.get("kill_cop", 0)) + int(street.get("fight", 0))
	return bloody >= 4 and stance_for(npc, "murder") == "fear"


## Summary for "Ask what people say about you".
static func street_rep(npc: Node, rng: RandomNumberGenerator) -> String:
	var street := street_memory()
	if street.is_empty():
		return say("\"#rep_nothing#\"", npc, {}, rng)
	var top := ""
	var total := 0
	for k in street:
		total += int(street[k])
		if top == "" or int(street[k]) > int(street[top]):
			top = k
	var tpl := "\"#rep_open# #act_%s#. #rep_count#\"" % top
	return say(tpl, npc, {"target": "someone", "stories": str(total)}, rng)


## A line after an interaction resolves: how they take what you just did to them.
static func afterword(npc: Node, verb_id: String, success: bool, rng: RandomNumberGenerator) -> String:
	var kind := str(reactions().get("verb_kind", {}).get(verb_id, "talk"))
	var sym := "after_%s_%s" % [kind, "ok" if success else "fail"]
	if not Copy.has(sym):
		return ""
	var tpl := "#%s#" % sym
	if rng.randf() < 0.4:
		tpl += " #close_%s#" % voice(npc)
	return "\"%s\"" % say(tpl, npc, {}, rng)
