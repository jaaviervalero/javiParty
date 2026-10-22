extends Node
## Prueba de integración con el simulador (tools/dsu_simulator.py --auto):
##   godot --headless --path . tests/e2e_scan.tscn
## Escanea la red, espera a que aparezca algún mando con datos y lo imprime.

const WAIT_SEC := 8.0
var _t := 0.0


func _ready() -> void:
	NetworkScanner.start()


func _process(delta: float) -> void:
	_t += delta
	if _t < WAIT_SEC:
		return
	var ok := false
	for c: DSUController in DSUClient.controllers.values():
		print("total=%d intervalo=%.2fms %s conectado=%s pps=%.1f pkt#%d rtt=%.1fms acc=%s botones=[%s] dev=%s" % [
			c.packets_total, c.interval_ms, c.key, c.connected, c.pps, c.packet_number, c.rtt_ms, c.accel,
			DSUProtocol.buttons_to_string(c.buttons), c.device_id()])
		ok = ok or (c.connected and c.packets_total > 50)
	print("jugadores: ", PlayerManager.connected_players().size(), " · stats ", DSUClient.stats)
	print("E2E OK" if ok else "E2E FALLO: ningún mando con datos")
	get_tree().quit(0 if ok else 1)
