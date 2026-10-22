class_name LAN
extends Reference
## Utilidades de red local sin estado (separadas del escáner para poder testearlas).


## De una lista de IPs locales, devuelve los prefijos /24 ("a.b.c.") de las
## IPv4 privadas: 10/8, 172.16/12 y 192.168/16. Así se ignoran loopback, VPN
## tipo Tailscale (100.64/10) e IPv6.
static func private_ipv4_prefixes(addresses: PoolStringArray) -> PoolStringArray:
	var out := PoolStringArray()
	for addr in addresses:
		var parts: PoolStringArray = addr.split(".")
		if parts.size() != 4 or not addr.is_valid_ip_address():
			continue
		var a := parts[0].to_int()
		var b := parts[1].to_int()
		var is_private := a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)
		if not is_private:
			continue
		var prefix := "%s.%s.%s." % [parts[0], parts[1], parts[2]]
		if not out.has(prefix):
			out.append(prefix)
	out.sort()
	return out


## La IPv4 privada con la que los móviles llegan a este equipo (para el QR del
## mando web). Prefiere 192.168.x.x, que es la de casi cualquier Wi-Fi de casa;
## "" si no hay ninguna (sin red).
static func best_private_ipv4(addresses: PoolStringArray) -> String:
	var best := ""
	for addr in addresses:
		if private_ipv4_prefixes(PoolStringArray([addr])).empty():
			continue
		if addr.begins_with("192.168."):
			return addr
		if best == "":
			best = addr
	return best


static func is_ipv4(addr: String) -> bool:
	return addr.is_valid_ip_address() and addr.split(".").size() == 4
