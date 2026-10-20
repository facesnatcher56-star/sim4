extends RefCounted
## Task 32e: thought balloons of folk standing together never overlap, and the order is stable between frames.

func run() -> Array:
	var f: Array = []
	var sz := Vector2(120, 30)
	var items: Array = [
		{"id": 7, "pos": Vector2(300, 200), "size": sz},
		{"id": 3, "pos": Vector2(300, 200), "size": sz},
		{"id": 9, "pos": Vector2(310, 205), "size": sz},
		{"id": 4, "pos": Vector2(900, 200), "size": sz}]
	var a: Array = ThoughtLayer.layout_rects(items)
	for i in items.size():
		for j in range(i + 1, items.size()):
			if Rect2(a[i], sz).intersects(Rect2(a[j], sz)):
				f.append("balloons %d and %d overlap" % [items[i]["id"], items[j]["id"]])
	if a[3] != items[3]["pos"]:
		f.append("a lone balloon must not move")
	if a[1] != items[1]["pos"]:
		f.append("lowest folk id keeps the spot")
	var items2: Array = items.duplicate()
	items2.reverse()
	var b: Array = ThoughtLayer.layout_rects(items2)
	b.reverse()
	if a != b:
		f.append("layout depends on input order (unstable between frames)")
	return f
