class_name ReviewBoard
extends RefCounted
## The four Cometling newspapers that review a mission after launch (GDD 6.6). Each one
## starts from the project grade, shifts it by the launch outcome and by its own bias, and
## adds a seeded noise of +-0.7 (the campaign rng, so the same seed gives the same reviews):
##   O Eco da Cauda (popular)        novelty, "firsts", crewed flights, hype
##   Revista Órbita (technical)      Engineering and Reliability, few defects
##   Boletim da Coma (scientific)    science actually brought down to the ground
##   Folha do Contribuinte           value for money, contracts, failures
## Biases and noise come from data/tycoon/projects.json ("review").

## ctx: {"grade", "outcome" ("fail" | "partial" | "full" | "exceptional"), "novelty" (bool),
##   "crewed" (bool), "hype", "bar_scores" [eng, sci, ops, rel] 0..10, "defects", "q" (work
##   volume vs expectation), "contract" (bool)}
## Returns [{"id", "name_key", "kind_key", "score" (int 0..10), "quote_key"}] in a fixed order.
static func review(rng: RandomNumberGenerator, ctx: Dictionary) -> Array[Dictionary]:
	var cfg := ProjectRules.section("review")
	var noise := float(cfg.get("noise", 0.7))
	var outcome := String(ctx.get("outcome", "full"))
	var base := float(ctx.get("grade", 5.0)) + float(cfg.get("outcome_shift", {}).get(outcome, 0.0))
	if ctx.get("novelty", false):
		base += float(cfg.get("novelty_bonus", 0.4))
	var out: Array[Dictionary] = []
	for paper: Dictionary in cfg.get("papers", []):
		var raw := base + bias(paper, ctx) + rng.randf_range(-noise, noise)
		var score := clampi(roundi(raw), 0, 10)
		out.append({"id": paper["id"], "name_key": paper.get("name_key", ""), "kind_key": paper.get("kind_key", ""),
			"score": score, "quote_key": quote_key(String(paper["id"]), score, outcome)})
	return out


## The paper's own lean (before noise), from what it cares about.
static func bias(paper: Dictionary, ctx: Dictionary) -> float:
	var bars: Array = ctx.get("bar_scores", [5.0, 5.0, 5.0, 5.0])
	var fail := String(ctx.get("outcome", "")) == "fail"
	match String(paper.get("id", "")):
		"echo":
			var b := 0.0
			if ctx.get("novelty", false):
				b += float(paper.get("novelty", 1.2))
			if ctx.get("crewed", false):
				b += float(paper.get("crewed", 0.8))
			b += float(paper.get("hype", 0.012)) * (float(ctx.get("hype", 0.0)) - float(paper.get("hype_pivot", 30.0)))
			return b
		"orbita":
			var tech := (float(bars[ProjectRules.ENG]) + float(bars[ProjectRules.REL])) * 0.5
			return float(paper.get("tech", 0.3)) * (tech - float(paper.get("tech_pivot", 6.0))) \
				- float(paper.get("defects", 0.25)) * float(ctx.get("defects", 0.0))
		"coma":
			var b := float(paper.get("science", 0.35)) * (float(bars[ProjectRules.SCI]) - float(paper.get("science_pivot", 6.0)))
			return b + (float(paper.get("fail_extra", -0.8)) if fail else 0.0)
		"folha":
			var b := clampf((float(ctx.get("q", 1.0)) - 1.0) * float(paper.get("value", 1.2)), -1.5, float(paper.get("value_cap", 1.0)))
			if ctx.get("contract", false):
				b += float(paper.get("contract", 0.4))
			return b + (float(paper.get("fail_extra", -1.0)) if fail else 0.0)
	return 0.0


## TY_PJ_Q_<PAPER>_<LOW|MID|HIGH|FAIL>
static func quote_key(paper_id: String, score: int, outcome: String) -> String:
	var band := "MID"
	if outcome == "fail":
		band = "FAIL"
	elif score >= 8:
		band = "HIGH"
	elif score < 5:
		band = "LOW"
	return "TY_PJ_Q_%s_%s" % [paper_id.to_upper(), band]


static func average(reviews: Array) -> float:
	if reviews.is_empty():
		return 0.0
	var s := 0.0
	for r: Dictionary in reviews:
		s += float(r.get("score", 0))
	return s / reviews.size()
