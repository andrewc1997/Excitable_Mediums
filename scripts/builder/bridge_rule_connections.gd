extends BuilderConnections

# Attach this script to the EXISTING "Connections" node.
# Keep the original BuilderConnections script in your project: this script
# inherits its setup(), get_path_length(), curve sampling, glow and styling.
# No additional scene nodes are needed.

const PortRules = preload("res://scripts/puzzle_node/puzzle_port_rules.gd")

var bridge_modes: Dictionary = {}
var spent_bridges: Dictionary = {}
var player_blocked: Dictionary = {}
var preview_player_slot: String = ""
var player_drag_active: bool = false

# Purely visual animations; they never modify bridge routing.
var drag_highlight_amount: float = 0.0
var drag_highlight_tween: Tween
var last_placed_bridge: String = ""
var placement_flash_strength: float = 0.0
var placement_flash_tween: Tween


func set_bridge_rules(modes: Dictionary, spent: Dictionary) -> void:
	bridge_modes = modes.duplicate(true)
	spent_bridges = spent.duplicate(true)
	queue_redraw()


func set_player_blocked(blocked: Dictionary) -> void:
	player_blocked = blocked.duplicate(true)
	queue_redraw()


func set_player_slot_preview(bridge_id: String) -> void:
	if preview_player_slot != bridge_id:
		preview_player_slot = bridge_id
		queue_redraw()


func set_player_drag_active(active: bool) -> void:
	if player_drag_active == active:
		return
	player_drag_active = active
	if drag_highlight_tween != null:
		drag_highlight_tween.kill()
		drag_highlight_tween = null
	if active:
		drag_highlight_tween = create_tween().set_loops()
		drag_highlight_tween.tween_method(
			Callable(self, "_set_drag_highlight_amount"), 0.0, 1.0, 0.7
		).set_trans(Tween.TRANS_SINE)
		drag_highlight_tween.tween_method(
			Callable(self, "_set_drag_highlight_amount"), 1.0, 0.0, 0.7
		).set_trans(Tween.TRANS_SINE)
	else:
		drag_highlight_amount = 0.0
	queue_redraw()


func _set_drag_highlight_amount(value: float) -> void:
	drag_highlight_amount = value
	queue_redraw()


func flash_player_blocker_placement(bridge_id: String) -> void:
	# Visual confirmation after a successful drop; no simulation changes.
	if placement_flash_tween != null:
		placement_flash_tween.kill()
	last_placed_bridge = bridge_id
	placement_flash_strength = 1.0
	queue_redraw()
	placement_flash_tween = create_tween()
	placement_flash_tween.tween_method(
		Callable(self, "_set_placement_flash_strength"), 1.0, 0.0, 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	placement_flash_tween.tween_callback(Callable(self, "_clear_placement_flash"))


func _set_placement_flash_strength(value: float) -> void:
	placement_flash_strength = value
	queue_redraw()


func _clear_placement_flash() -> void:
	placement_flash_strength = 0.0
	last_placed_bridge = ""
	queue_redraw()


func _draw() -> void:
	if grid == null:
		return

	for index in range(connections.size()):
		var connection: Dictionary = connections[index]
		var path: Array[Vector2i] = []
		for cell in connection.get("path", []):
			path.append(cell)
		if path.size() < 2:
			continue

		var length: float = get_path_length(path)
		if length <= 0.0:
			continue

		var bridge_id: String = PortRules.bridge_key(
			str(connection["from_uid"]), str(connection["to_uid"])
		)
		var mode: int = int(bridge_modes.get(bridge_id, 0))

		if spent_bridges.has(bridge_id):
			# The single-use link is physically gone after a full crossing.
			_draw_spent_mark(path, length)
			continue

		if mode == 5 and player_blocked.has(bridge_id):
			_draw_inactive_line(path, length)
			_draw_player_blocked_mark(path, length)
			if last_placed_bridge == bridge_id and placement_flash_strength > 0.0:
				_draw_placement_flash(path, length)
			continue
		if mode == 4:
			_draw_inactive_line(path, length)
		else:
			_draw_connection_line(path, length)
			if enable_line_glow:
				_draw_moving_glow(path, length, index)

		_draw_rule_marker(path, length, mode)
		if mode == 5 and player_drag_active:
			var spot: Vector2 = _visual_point_local(path, length * 0.5)
			var hovered: bool = preview_player_slot == bridge_id
			if hovered:
				# Strong mint-green magnetic landing target. The moving ring
				# makes it clear the drop can be released here.
				draw_circle(spot, 21.0 + drag_highlight_amount * 3.0, Color(0.13, 0.87, 0.67, 0.13))
				draw_arc(
					spot, 14.0 + drag_highlight_amount * 2.0,
					0.0, TAU, 40, Color("#3AF3BD"), 4.0, true
				)
				draw_circle(spot, 4.0, Color("#E0FFF3"))
			else:
				# All eligible sockets remain visible even while hovering
				# a different one.
				draw_arc(
					spot, 11.0 + drag_highlight_amount * 2.0,
					0.0, TAU, 32, Color("#59D8EB"), 2.5, true
				)


func _draw_player_blocked_mark(path: Array[Vector2i], length: float) -> void:
	var middle: Vector2 = _visual_point_local(path, length * 0.5)
	# A solid capped socket instead of the hollow, still available one.
	draw_circle(middle, 9.0, Color("#374957"))
	draw_arc(middle, 9.0, 0.0, TAU, 32, Color("#FF987D"), 2.0, true)
	draw_line(middle + Vector2(-4.0, -4.0), middle + Vector2(4.0, 4.0), Color.WHITE, 2.3, true)
	draw_line(middle + Vector2(-4.0, 4.0), middle + Vector2(4.0, -4.0), Color.WHITE, 2.3, true)


func _draw_placement_flash(path: Array[Vector2i], length: float) -> void:
	var center: Vector2 = _visual_point_local(path, length * 0.5)
	var expanded: float = 1.0 - placement_flash_strength
	draw_arc(
		center, 12.0 + 21.0 * expanded,
		0.0, TAU, 48,
		Color(0.19, 0.94, 0.68, placement_flash_strength),
		3.0, true
	)


func _draw_inactive_line(path: Array[Vector2i], length: float) -> void:
	var points := PackedVector2Array()
	var samples: int = maxi(2, int(ceil(length / SAMPLE_STEP)) + 1)
	for i in range(samples):
		var d: float = length * float(i) / float(samples - 1)
		points.append(_visual_point_local(path, d))
	draw_polyline(points, Color("#6A7784"), maxf(2.0, line_width * 0.55), true)


func _draw_spent_mark(path: Array[Vector2i], length: float) -> void:
	var midpoint: Vector2 = _visual_point_local(path, length * 0.5)
	var inactive: Color = Color("#73808B")
	draw_line(midpoint + Vector2(-5, -5), midpoint + Vector2(5, 5), inactive, 2.0, true)
	draw_line(midpoint + Vector2(-5, 5), midpoint + Vector2(5, -5), inactive, 2.0, true)


func _draw_rule_marker(path: Array[Vector2i], length: float, mode: int) -> void:
	if mode == 0:
		return
	if mode == 5:
		# Empty hollow slot awaiting a dragged player blocker.
		var slot: Vector2 = _visual_point_local(path, length * 0.5)
		draw_circle(slot, 7.0, Color("#FFFFFF"))
		draw_circle(slot, 4.5, Color("#0E7490"))
		return
	var center: Vector2 = _visual_point_local(path, length * 0.5)

	if mode == 3:
		# One-shot fuse.
		draw_circle(center, 5.2, Color("#E9AB4E"))
		draw_circle(center, 2.2, Color("#FFF4D8"))
		return

	if mode == 4:
		# Permanently blocked.
		draw_circle(center, 6.0, Color("#6A7784"))
		draw_line(center + Vector2(-4, -4), center + Vector2(4, 4), Color.WHITE, 2.0, true)
		draw_line(center + Vector2(-4, 4), center + Vector2(4, -4), Color.WHITE, 2.0, true)
		return

	# Directional diode marker. An arrow points in the permitted direction.
	var p0: Vector2 = _visual_point_local(path, maxf(0.0, length * 0.5 - 0.22))
	var p1: Vector2 = _visual_point_local(path, minf(length, length * 0.5 + 0.22))
	var direction: Vector2 = (p1 - p0).normalized()
	if direction.length_squared() < 0.0001:
		return
	if mode == 2:
		direction = -direction
	var side: Vector2 = direction.orthogonal()
	draw_circle(center, 7.0, Color("#1D526A"))
	draw_colored_polygon(PackedVector2Array([
		center + direction * 5.0,
		center - direction * 3.0 + side * 4.0,
		center - direction * 3.0 - side * 4.0
	]), Color("#E5FCFF"))
