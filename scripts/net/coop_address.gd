class_name CoopAddress
extends RefCounted
## Host address <-> short join code. The code is base32 (A-Z, 2-7) of 4 IPv4 bytes + 2 port bytes + 1 check byte, shown as
## XXXX-XXXX-XXXX. Typing "ip", "ip:port" or the code all work. IPv4 only for now.
## NAT / internet play: there is NO relay yet. A host behind a router must forward UDP <port> (or use a VPN overlay such as
## Tailscale / ZeroTier and share that address); the LAN code works as is. `resolve_hook` is the place a later NAT punch or relay
## plugs in: set it to a Callable(text: String) -> Dictionary({"ip","port"} or {}) and it is asked first for any input.

const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
static var resolve_hook: Callable = Callable()

static func _check_byte(b: PackedByteArray) -> int:
	var s := 0x5A
	for i in b.size():
		s = (s * 31 + b[i] + i) & 0xFF
	return s

static func encode(ip: String, port: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4 or port < 1 or port > 65535:
		return ""
	var b := PackedByteArray()
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return ""
		b.append(int(p))
	b.append(port >> 8)
	b.append(port & 0xFF)
	b.append(_check_byte(b))
	var bits := 0
	var acc := 0
	var out := ""
	for x in b:
		acc = ((acc << 8) | x) & 0xFFFFFF
		bits += 8
		while bits >= 5:
			out += ALPHABET[(acc >> (bits - 5)) & 31]
			bits -= 5
	if bits > 0:
		out += ALPHABET[(acc << (5 - bits)) & 31]
	return "%s-%s-%s" % [out.substr(0, 4), out.substr(4, 4), out.substr(8)]

## {"ok": true, "ip", "port"} or {"ok": false, "err": plain-language reason}.
static func decode(code: String) -> Dictionary:
	var c := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if c.length() != 12:
		return {"ok": false, "err": "That code should be 12 letters and digits (like ABCD-EFGH-IJKL)."}
	var acc := 0
	var bits := 0
	var b := PackedByteArray()
	for ch in c:
		var v := ALPHABET.find(ch)
		if v < 0:
			return {"ok": false, "err": "That code has a character that is not allowed (%s)." % ch}
		acc = ((acc << 5) | v) & 0xFFFFFF
		bits += 5
		if bits >= 8:
			b.append((acc >> (bits - 8)) & 0xFF)
			bits -= 8
	if b.size() < 7:
		return {"ok": false, "err": "That code is too short."}
	if _check_byte(b.slice(0, 6)) != b[6]:
		return {"ok": false, "err": "That code doesn't look right. Check it with the host and try again."}
	return {"ok": true, "ip": "%d.%d.%d.%d" % [b[0], b[1], b[2], b[3]], "port": (b[4] << 8) | b[5]}

## Accepts a code, "ip", or "ip:port".
static func parse(text: String) -> Dictionary:
	var t := text.strip_edges()
	if resolve_hook.is_valid():
		var r: Variant = resolve_hook.call(t)
		if r is Dictionary and not (r as Dictionary).is_empty():
			return {"ok": true, "ip": str(r["ip"]), "port": int(r["port"])}
	if t == "":
		return {"ok": false, "err": "Type the host's code or address first."}
	if t.contains(".") or t.contains(":"):
		var ip := t
		var port := CoopProto.DEFAULT_PORT
		if t.contains(":"):
			ip = t.get_slice(":", 0)
			var ps := t.get_slice(":", 1)
			if not ps.is_valid_int() or int(ps) < 1 or int(ps) > 65535:
				return {"ok": false, "err": "The port after the ':' should be a number between 1 and 65535."}
			port = int(ps)
		if ip != "localhost" and not ip.is_valid_ip_address():
			return {"ok": false, "err": "That doesn't look like an address (like 192.168.1.20 or 192.168.1.20:24680)."}
		return {"ok": true, "ip": "127.0.0.1" if ip == "localhost" else ip, "port": port}
	return decode(t)

## The best guess of the host's LAN address (private IPv4), or "" when none is found.
static func local_ip() -> String:
	var best := ""
	for a in IP.get_local_addresses():
		if not a.is_valid_ip_address() or a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if best == "":
			best = a
	return best
