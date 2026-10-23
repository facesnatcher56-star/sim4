class_name MarketTick
extends RefCounted
## The one door of the economy track (task 13) into SystemsManager / SaveLoad: reset, daily order, game-event routing, save/restore.
## Everything is OFF until MarketEconomy.start() (a new game, or a loaded save); with it off every multiplier is 1.0 and nothing ticks, so
## the older systems and their tests are untouched. Daily order: economy -> shops -> work -> housing -> businesses -> bank -> gambling.
## See docs/ECONOMY.md for tier, cadence, active set and caps of every part.

static func reset() -> void:
	MarketEconomy.reset()
	ShopStock.reset()
	BankGamble.reset()
	BankAccounts.reset()
	BankInsurance.reset()
	BankWill.reset()
	HousingProps.reset()
	HousingRent.reset()
	BusinessState.reset()
	BusinessDay.reset()
	MarketWork.reset()
	MarketCommand.reset()

## New game: the economy starts.
static func new_game() -> void:
	MarketEconomy.start()

static func on_day(day: int) -> void:
	if not MarketEconomy.enabled:
		return
	MarketEconomy.on_day(day)
	ShopStock.on_day(day)
	MarketWork.on_day(day)
	HousingProps.on_day(day)
	HousingRent.on_day(day)
	BusinessDay.on_day(day)
	BankAccounts.on_day(day)
	BankGamble.on_day(day)

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if MarketEconomy.enabled:
		MarketWork.on_interaction(folk_id, iid, success)

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if not MarketEconomy.enabled:
		return
	if ev == "chronicle":
		BankInsurance.on_chronicle(payload)
		return
	MarketWork.on_game_event(ev, payload)
	HousingRent.on_game_event(ev, payload)

## Make the bank's insurance the Incidents hook (called when systems start and after loads).
static func install() -> void:
	BankInsurance.install()

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"economy": MarketEconomy.to_dict(), "shops": ShopStock.to_dict(), "gamble": BankGamble.to_dict(), "accounts": BankAccounts.to_dict(),
		"insurance": BankInsurance.to_dict(), "wills": BankWill.to_dict(), "props": HousingProps.to_dict(), "rent": HousingRent.to_dict(),
		"business": BusinessState.to_dict(), "work": MarketWork.to_dict(), "creation": Creation.to_dict(), "inventory": Inventory.to_dict(), "permits": WeaponPermits.to_dict(), "habits": Habits.to_dict(), "licences": Licences.to_dict()}

## A save without the block (made before task 13) switches the economy on with fresh state.
static func from_dict(d: Dictionary, has_block: bool) -> void:
	reset()
	if not has_block:
		MarketEconomy.start()
		return
	MarketEconomy.from_dict(d.get("economy", {}))
	ShopStock.from_dict(d.get("shops", {}))
	BankGamble.from_dict(d.get("gamble", {}))
	BankAccounts.from_dict(d.get("accounts", {}))
	BankInsurance.from_dict(d.get("insurance", {}))
	BankWill.from_dict(d.get("wills", {}))
	HousingProps.from_dict(d.get("props", {}))
	HousingRent.from_dict(d.get("rent", {}))
	BusinessState.from_dict(d.get("business", {}))
	Creation.from_dict(d.get("creation", {}))
	Inventory.from_dict(d.get("inventory", {}))
	WeaponPermits.from_dict(d.get("permits", {}))
	Habits.from_dict(d.get("habits", {}))
	Licences.from_dict(d.get("licences", {}))
	MarketWork.from_dict(d.get("work", {}))
