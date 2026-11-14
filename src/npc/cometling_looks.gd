class_name CometlingLooks
extends RefCounted
## Colour variants of the Cometlings (docs/creatures.md). Body colours are soft
## versions of the MARGIN palette plus four species colours; the spot colour paints
## the comet tips of the ears and the tail. The antenna glow comes from the role
## (Cometling.ROLE_GLOW).

const VARIANTS := [
	{"id": "sky", "en": "Cleanroom Sky", "pt": "Céu de Sala Limpa", "body": Color("#bfe9ff"), "spot": Color("#f59a36")},
	{"id": "mint", "en": "Go Mint", "pt": "Menta Liberada", "body": Color("#aeeeb6"), "spot": Color("#5fb0d8")},
	{"id": "butter", "en": "Caution Butter", "pt": "Manteiga Atenção", "body": Color("#ffe08f"), "spot": Color("#ff6b6b")},
	{"id": "coral", "en": "Beacon Coral", "pt": "Coral Sinalizador", "body": Color("#ffa3a3"), "spot": Color("#ffcc55")},
	{"id": "lilac", "en": "Nebula Lilac", "pt": "Lilás Nebulosa", "body": Color("#c9b8ff"), "spot": Color("#ffcc55")},
	{"id": "peach", "en": "Re-entry Peach", "pt": "Pêssego Reentrada", "body": Color("#ffcaa8"), "spot": Color("#5fb0d8")},
	{"id": "cloud", "en": "VAB Cloud", "pt": "Nuvem do Hangar", "body": Color("#eef1f4"), "spot": Color("#f59a36")},
	{"id": "seafoam", "en": "Coast Seafoam", "pt": "Espuma do Litoral", "body": Color("#a6eadb"), "spot": Color("#ff8fb8")},
	{"id": "tangerine", "en": "Signal Tangerine", "pt": "Tangerina Sinal", "body": Color("#ffbd7a"), "spot": Color("#5fb0d8")},
]


static func count() -> int:
	return VARIANTS.size()


static func get_variant(i: int) -> Dictionary:
	return VARIANTS[posmod(i, VARIANTS.size())]


static func index_of(id: String) -> int:
	for i in VARIANTS.size():
		if VARIANTS[i]["id"] == id:
			return i
	return 0


static func variant_name(i: int) -> String:
	var v := get_variant(i)
	return v["pt"] if TranslationServer.get_locale().begins_with("pt") else v["en"]


static func apply(c: Cometling, variant: int, role: String) -> void:
	var v := get_variant(variant)
	c.role = role
	c.set_colors(v["body"], v["spot"])
