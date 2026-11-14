class_name HangarFormat
extends RefCounted
## Number formatting of the hangar (locale decimal separator, SI thousands grouping) shared
## by the HUD and the part advisor.


## Decimal number with the locale's decimal separator ("1,5" in Portuguese).
static func num(v: float, nd := 0) -> String:
	var s := String.num(v, nd)
	if nd > 0 and not s.contains("."):
		s += "." + "0".repeat(nd)
	if TranslationServer.get_locale().begins_with("pt"):
		s = s.replace(".", ",")
	return s


## Like num(), with thousands grouped by a space (SI style: "16 170").
static func numk(v: float, nd := 0) -> String:
	var s := String.num(absf(v), nd)
	var dot := s.find(".")
	var ip := s if dot < 0 else s.substr(0, dot)
	var fp := "" if dot < 0 else s.substr(dot + 1)
	var out := ""
	while ip.length() > 3:
		out = " " + ip.right(3) + out
		ip = ip.left(ip.length() - 3)
	out = ip + out
	if fp != "":
		out += ("," if TranslationServer.get_locale().begins_with("pt") else ".") + fp
	return ("-" if v < 0.0 else "") + out


## "850 kg" below a tonne, "25,4 t" above.
static func mass(kg: float) -> String:
	if kg < 1000.0:
		return "%s kg" % numk(kg)
	return "%s t" % numk(kg / 1000.0, 2 if kg < 10000.0 else 1)


## "US$ 1,2 M".
static func money(musd: float) -> String:
	return "US$ %s M" % num(musd, 2 if musd < 10.0 else 1)


## "845 kN" (one decimal below 10 kN, newtons below 1 kN).
static func thrust(kn: float) -> String:
	if kn < 1.0:
		return "%s N" % numk(kn * 1000.0, 1 if kn < 0.01 else 0)
	return "%s kN" % numk(kn, 1 if kn < 10.0 else 0)
