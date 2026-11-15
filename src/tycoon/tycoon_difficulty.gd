class_name TycoonDifficulty
extends RefCounted
## Difficulty levels of a career (GDD section 16.4): Fácil / Normal / Difícil, one table in
## data/tycoon/difficulty.json. The level is picked in the leader creator, lives in
## TycoonState.difficulty and is saved with the campaign (old saves read as "normal").
## Every system that scales asks factor(state, key):
##   start_cash   TycoonState.new_campaign (the starting capital)
##   income       TycoonFinance.grant_amount, TycoonContracts._reward, BriefingDesk.make_offer,
##                RaceDirector.claim (prizes)
##   expectation  MissionProject.expected_points (what the press expects)
##   rival_speed  RaceDirector (the rivals' monthly attempt chance)
##   bankrupt_line  Bankruptcy.threshold (X of the bankruptcy line −X, era-1 credits; not a factor)

const PATH := "res://data/tycoon/difficulty.json"
const NORMAL := "normal"

static var _db: Dictionary = {}


static func db() -> Dictionary:
	if _db.is_empty():
		_db = TycoonState.load_json(PATH)
	return _db


## The levels in display order: [{"id", "name_key", "desc_key", <factors>}].
static func levels() -> Array:
	return db().get("levels", [])


static func level(id: String) -> Dictionary:
	for l: Dictionary in levels():
		if String(l["id"]) == id:
			return l
	return {}


static func default_id() -> String:
	return String(db().get("default", NORMAL))


## A known level id, else the default (old saves, typos).
static func sanitize(id: String) -> String:
	return id if not level(id).is_empty() else default_id()


## A factor of the campaign's level (1.0 when the table does not have it).
static func factor(s: TycoonState, key: String) -> float:
	if s == null:
		return 1.0
	return float(level(s.difficulty).get(key, 1.0))
