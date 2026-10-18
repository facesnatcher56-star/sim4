extends RefCounted
## FireView (headless: nodes only, nothing is drawn): one emitter per burning tile, capped; soot decals for scorched tiles; haze while a lot is smoky;
## everything is cleaned up when the fire is out.

const K = preload("res://tests/systems_kit.gd")
const FK = preload("res://tests/fire_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := FK.setup()
	K.make_folk(w, "Mia", [], 1, Vector2i(30, 30)).set_meta("away", "work")
	var o := FK.house(w)
	var fv := FireView.new()
	fv.sync_now()
	K.expect(f, fv.emitter_count() == 0 and fv.scorch_count() == 0 and fv.haze_count() == 0, "nothing to draw without fire")
	Fire.ignite(o["stove"], "cooking")
	Fire.ignite(o["sofa"], "candle")
	fv.sync_now()
	K.expect(f, fv.emitter_count() == 2, "an emitter per burning object (%d)" % fv.emitter_count())
	var node: Node3D = fv._emitters[int(Fire.active()[0]["id"])]
	K.expect(f, node.get_node_or_null("Flame") != null and node.get_node_or_null("Smoke") != null and node.get_node_or_null("Glow") != null, "flames + smoke + glow")
	var flame: CPUParticles3D = node.get_node("Flame")
	var amount1: int = flame.amount
	FK.run(14)
	fv.sync_now()
	K.expect(f, (fv._emitters.size() >= 1) and fv.haze_count() >= 1, "smoke haze over the lot")
	var any: Node3D = fv._emitters[int(Fire.active()[0]["id"])]
	K.expect(f, int((any.get_node("Flame") as CPUParticles3D).amount) >= amount1, "flames grow with the stage")
	Fire.extinguish_lot("home", "brigade")
	FK.run(1)
	fv.sync_now()
	K.expect(f, fv.emitter_count() == 0 and fv.haze_count() == 0, "emitters + haze are removed when the fire is out")
	K.expect(f, fv.scorch_count() >= 1, "soot marks stay (%d)" % fv.scorch_count())
	Fire.scorch.clear()
	fv.sync_now()
	K.expect(f, fv.scorch_count() == 0, "soot fades with the scorch list")
	# the cap
	for i in 40:
		Fire.ignite(Vector2i(40 + i, 3), "wildfire", {"force": true})
	fv.sync_now()
	K.expect(f, fv.emitter_count() == FireView.MAX_EMITTERS, "at most %d burning tiles are drawn (%d)" % [FireView.MAX_EMITTERS, fv.emitter_count()])
	fv.queue_free()
	for c in fv.get_children():
		c.free()
	fv.free()
	FK.teardown()
	return f
