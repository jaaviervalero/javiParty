extends CanvasLayer
## Autoload "DebugOverlay": datos crudos de red y sensores por mando.
## Se abre/cierra con F3, la tecla Menú del mando de la tele o HOME en un móvil.
## Se refresca a 10 Hz para no gastar CPU en la tele.

const REFRESH_SEC := 0.1

var _panel: PanelContainer
var _label: Label
var _timer := 0.0


func _ready() -> void:
	layer = 100
	pause_mode = Node.PAUSE_MODE_PROCESS
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.13, 0.82)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_stylebox_override("panel", style)
	_panel.rect_position = Vector2(12, 12)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = Label.new()
	# Godot 3.6 no tiene SystemFont: la fuente de depuración es la del juego.
	_label.add_font_override("font", Fonts.get_font(400, 13))
	_label.add_color_override("font_color", Color("d8f3ff"))
	_panel.add_child(_label)
	visible = Settings.debug_overlay


func toggle() -> void:
	visible = not visible
	Settings.debug_overlay = visible
	Settings.save()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		toggle()
		get_tree().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer < REFRESH_SEC:
		return
	_timer = 0.0
	_label.text = _build_text()
	_panel.rect_size = _panel.get_combined_minimum_size()


func _build_text() -> String:
	var lines := PoolStringArray()
	var s: Dictionary = DSUClient.stats
	lines.append("javiParty debug · %d fps · IPs %s · UDP local :%d · id %08x" % [
		Engine.get_frames_per_second(), ", ".join(_local_ipv4()), DSUClient.local_port, DSUClient.client_id])
	lines.append("escaneo %s %s · barridos %d · servidores %d · rx %d · descartados: crc %d ver %d tam %d magic %d tipo %d desconocido %d" % [
		"ON" if NetworkScanner.active else "OFF", ",".join(NetworkScanner.subnets), NetworkScanner.sweeps,
		DSUClient.server_count(), s.rx, s.bad_crc, s.bad_version, s.bad_size, s.bad_magic,
		s.unknown_type, s.unknown_sender])
	if DSUClient.controllers.empty():
		lines.append("(sin mandos)")
	for c in DSUClient.controllers.values():
		lines.append("")
		lines.append("%s %s  MAC %s  modelo %d  conexión %d  batería 0x%02x" % [
			_player_tag(c), c.key, DSUProtocol.mac_to_string(c.mac), c.model, c.connection, c.battery])
		lines.append("  %s  pkt#%d  %.1f pps  intervalo %.1f±%.1f ms  RTT %s  viejos %d" % [
			"CONECTADO" if c.connected else "DESCONECTADO", c.packet_number, c.pps,
			c.interval_ms, c.jitter_ms, "%.1f ms" % c.rtt_ms if c.rtt_ms >= 0 else "?", c.dropped_old])
		lines.append("  botones DSU [%s] → juego [%s]  L(%+.2f,%+.2f) R(%+.2f,%+.2f)" % [
			DSUProtocol.buttons_to_string(c.buttons), _logical_buttons(c), c.left_stick.x,
			c.left_stick.y, c.right_stick.x, c.right_stick.y])
		lines.append("  acc  x %+.3f  y %+.3f  z %+.3f   |a| %.3f g" % [
			c.accel.x, c.accel.y, c.accel.z, c.accel.length()])
		lines.append("  gyro p %+8.2f  y %+8.2f  r %+8.2f °/s   ts %d µs" % [
			c.gyro.x, c.gyro.y, c.gyro.z, c.motion_timestamp])
		if c.touch1.get("active", false) or c.touch2.get("active", false):
			lines.append("  toque1 %s  toque2 %s" % [_touch(c.touch1), _touch(c.touch2)])
	return "\n".join(lines)


func _player_tag(c) -> String:
	for p in PlayerManager.players:
		if p != null and p.controller == c:
			return "J%d" % (p.index + 1)
	return "--"


func _logical_buttons(c) -> String:
	for p in PlayerManager.players:
		if p != null and p.controller == c:
			return Pad.to_string_names(p.buttons())
	return "-"


func _touch(t: Dictionary) -> String:
	if not t.get("active", false):
		return "-"
	return "#%d (%d,%d)" % [t.id, t.pos.x, t.pos.y]


func _local_ipv4() -> PoolStringArray:
	var out := PoolStringArray()
	for a in IP.get_local_addresses():
		if a.split(".").size() == 4 and not a.begins_with("127."):
			out.append(a)
	return out
