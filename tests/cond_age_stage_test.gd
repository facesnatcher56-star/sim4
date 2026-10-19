extends RefCounted
## Plain Cond and SysCond agree on `age_stage_is` (interaction tests such as organize_watch use it, and interactions go through plain Cond).

func run() -> Array:
	var fails: Array = []
	var f := Folk.create("Ada")
	for stage in ["adult", "teen", "elder"]:
		f.age_stage = stage
		for cond in [{"age_stage_is": "adult"}, {"age_stage_is": ["adult", "elder"]}, {"age_stage_is": ["child", "teen"]}, {"not": {"age_stage_is": "elder"}}]:
			var a: bool = Cond.check([cond], {"folk": f})
			var b: bool = SysCond.check([cond], f)
			if a != b:
				fails.append("Cond and SysCond disagree on %s for a %s" % [str(cond), stage])
	f.age_stage = "elder"
	if not Cond.check([{"age_stage_is": ["adult", "elder"]}], {"folk": f}):
		fails.append("an elder passes adult/elder")
	f.age_stage = "child"
	if Cond.check([{"age_stage_is": ["adult", "elder"]}], {"folk": f}):
		fails.append("a child fails adult/elder")
	if Cond.check([{"age_stage_is": "adult"}], {"folk": null}):
		fails.append("no folk fails")
	return fails
