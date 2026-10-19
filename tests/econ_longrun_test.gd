extends RefCounted
## Long statistical run of the whole economy track (SLOW tier): cycles happen, indexes stay sane, townie businesses come and go within the slots,
## property values stay in a sensible band, and the same seed gives the same state hash.

const K = preload("res://tests/systems_kit.gd")
const E = preload("res://tests/econ_kit.gd")

func run() -> Array:
	var f: Array = []
	_cycles(f)
	_determinism(f)
	return f

func _run_days(n: int) -> Dictionary:
	var phases: Dictionary = {"boom": 0, "recession": 0}
	var last: String = "normal"
	var lo_u: float = 1.0
	var hi_u: float = 0.0
	var max_biz: int = 0
	for d in range(2, n + 2):
		K.set_time(d, 8)
		Economy.on_day(d)
		MarketTick.on_day(d)
		if MarketEconomy.phase != last:
			if MarketEconomy.phase != "normal":
				phases[MarketEconomy.phase] = int(phases[MarketEconomy.phase]) + 1
			last = MarketEconomy.phase
		lo_u = minf(lo_u, MarketEconomy.unemployment)
		hi_u = maxf(hi_u, MarketEconomy.unemployment)
		max_biz = maxi(max_biz, BusinessState.list.size())
		if d % 20 == 0:
			WorldIface.coins[1] = maxi(Economy.balance(1), 2000)      # keep the household afloat; we test the town, not the player
	return {"phases": phases, "lo_u": lo_u, "hi_u": hi_u, "max_biz": max_biz}

func _cycles(f: Array) -> void:
	var w := E.setup(5000)
	var days: int = TestFixture.pick(500, 250)
	var r: Dictionary = _run_days(days)
	K.expect(f, int(r["phases"]["boom"]) + int(r["phases"]["recession"]) >= 3, "booms and recessions happen (%s in %d days)" % [str(r["phases"]), days])
	var rel: float = MarketEconomy.price_idx / MarketEconomy.base_level
	K.expect(f, rel > 0.85 and rel < 1.15, "prices stay near their trend (%.3f)" % rel)
	K.expect(f, MarketEconomy.base_level > 1.0 and MarketEconomy.base_level < 3.0, "inflation is slow and bounded (level %.2f after %d days)" % [MarketEconomy.base_level, days])
	K.expect(f, float(r["hi_u"]) > float(r["lo_u"]) + 0.1, "unemployment moves with the cycle (%.2f to %.2f)" % [float(r["lo_u"]), float(r["hi_u"])])
	K.expect(f, int(r["max_biz"]) >= 2 and int(r["max_biz"]) <= 10, "townies run between 2 and 10 businesses (peak %d)" % int(r["max_biz"]))
	K.expect(f, BusinessState.closed_log.size() >= 1 or BusinessState.list.size() >= 2, "some businesses fail or thrive")
	for id in HousingProps.props:
		var p: Dictionary = HousingProps.props[id]
		var v: float = float(HousingProps.value(p)) / float(maxi(int(p["base"]), 1))
		K.expect(f, v > 0.4 and v < 2.6, "%s keeps a sensible value (%.2f x base)" % [str(p["label"]), v])
	K.expect(f, HousingProps.listings().size() == 5, "the market keeps five listings")
	K.expect(f, BankGamble.jackpot >= 400, "the jackpot rolls over from its floor")
	K.teardown()

func _determinism(f: Array) -> void:
	var hashes: Array = []
	for _i in 2:
		var w := E.setup(5000)
		_run_days(TestFixture.pick(150, 80))
		hashes.append(JSON.stringify(MarketTick.to_dict()).hash())
		K.teardown()
	K.expect(f, hashes[0] == hashes[1], "same seed, same economy state after the run")
