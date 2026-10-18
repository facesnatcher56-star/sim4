extends RefCounted
## VARIETY: clothes / hair colours do not blend with the floors and ground of the world (seen from the iso camera), and
## the colour palettes give enough distinct colour bands for the distinctness rule.


func run() -> Array:
	var f: Array = []
	var c: Dictionary = Genetics.cfg()
	var pc: Dictionary = c.get("palette", {})
	var mind: float = float(pc.get("min_distance", 0.18))
	for key in ["shirt_colors", "pants_colors", "accent_colors"]:
		for hx in c.get(key, []):
			if not GeneticsUnique.colour_ok(str(hx), mind):
				f.append("%s %s blends with a floor colour" % [key, hx])
	for e in c.get("hair_colors", []):
		if not GeneticsUnique.colour_ok(str(e["hex"]), float(pc.get("hair_min_distance", 0.1))):
			f.append("hair %s blends with a floor colour" % e["id"])
	var roles: Dictionary = FolkOutfits.cfg().get("roles", {})
	for rid in roles:
		for key2 in ["shirt", "pants", "accent"]:
			for hx2 in roles[rid].get(key2, []):
				if not GeneticsUnique.colour_ok(str(hx2), mind):
					f.append("role %s %s %s blends with a floor colour" % [rid, key2, hx2])
	var g := RandomNumberGenerator.new()
	g.seed = 3
	var bad_n := 0
	for i in 500:
		if not GeneticsUnique.palette_ok(Genetics.random_appearance(g)):
			bad_n += 1
	if bad_n > 0:
		f.append("%d of 500 random appearances fail the palette check" % bad_n)
	# the check does catch a floor-coloured shirt
	var wood: Dictionary = Genetics.neutral_appearance()
	wood["shirt"] = "#b8864e"
	if GeneticsUnique.palette_ok(wood):
		f.append("palette check did not flag a wood-coloured shirt")
	var bands := {}
	for hx in c.get("shirt_colors", []):
		bands[GeneticsLook.cband(str(hx))] = true
	if bands.size() < 14:
		f.append("only %d shirt colour bands" % bands.size())
	return f
