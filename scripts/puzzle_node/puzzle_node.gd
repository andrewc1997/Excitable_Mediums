

@tool
class_name PuzzleNode
extends Node2D

const PortRules = preload("res://scripts/puzzle_node/puzzle_port_rules.gd")

# Excitable Mediums: EM4. Append-only Kind enum keeps old levels valid.

enum Kind {
	NORMAL,           # 0
	SPLITTER,         # 1
	ALTERNATING,      # 2
	TARGET,           # 3
	BLOCKER_SINGLE,   # 4
	BLOCKER_AMOUNT,   # 5
	BLOCKER_TARGET,   # 6
	GATE_AMOUNT,      # 7
	TRIGGER_TARGET,   # 8
	DELAY,            # 9
	REPEATER,         # 10
	BOUNCE,           # 11
	ONE_WAY_GATE,     # 12
	BEGIN,            # 13
	WORMHOLE          # 14 (append-only, old levels unchanged)
}

enum Channel { PURPLE, BLUE, GREEN, RED }
enum Direction { NORTH, EAST, SOUTH, WEST }

@export_category("Wormhole Visuals")
# The pair accent colour still comes from _wormhole_pair_color(), so
# matching endpoints keep their matching identity.
@export var wormhole_outer_color: Color = Color("#7c3aed")
@export var wormhole_inner_color: Color = Color("#22d3ee")
@export var wormhole_core_color: Color = Color("#0f172a")
@export_range(0.0, 8.0, 0.1) var wormhole_spin_speed: float = 1.6
@export_range(1, 6, 1) var wormhole_arm_count: int = 3
@export_range(1.0, 6.0, 0.1) var wormhole_line_width: float = 3.0
@export_range(0.35, 0.82, 0.01) var wormhole_radius_factor: float = 0.62
@export_range(1.0, 8.0, 0.1) var wormhole_flash_spin_multiplier: float = 3.5

const WORMHOLE_FLASH_DURATION: float = 0.38
var wormhole_spin_time: float = 0.0

@export var kind: Kind = Kind.NORMAL:
	set(value):
		kind = value
		queue_redraw()
@export var grid_cell: Vector2i = Vector2i.ZERO
@export var node_uid: String = ""
@export_range(1, 100, 1) var activation_cap: int = 1:
	set(value):
		activation_cap = maxi(1, value)
		queue_redraw()
@export_range(0, 100, 1) var refractory_ticks: int = 2
@export_range(1, 6, 1) var required_inputs: int = 1:
	set(value):
		required_inputs = maxi(1, value)
		queue_redraw()
@export_range(1, 6, 1) var output_count: int = 2:
	set(value):
		output_count = maxi(1, value)
		queue_redraw()
@export_range(1, 100, 1) var blocker_hits: int = 2:
	set(value):
		blocker_hits = maxi(1, value)
		queue_redraw()
@export_range(1, 100, 1) var gate_passes: int = 2:
	set(value):
		gate_passes = maxi(1, value)
		queue_redraw()
@export var channel: Channel = Channel.PURPLE:
	set(value):
		channel = value
		queue_redraw()
@export_range(1, 100, 1) var delay_ticks: int = 3:
	set(value):
		delay_ticks = maxi(1, value)
		queue_redraw()
@export_range(1, 100, 1) var repeat_count: int = 3:
	set(value):
		repeat_count = maxi(1, value)
		queue_redraw()
@export_range(1, 100, 1) var repeat_interval: int = 2:
	set(value):
		repeat_interval = maxi(1, value)
		queue_redraw()
@export var one_way_direction: Direction = Direction.EAST:
	set(value):
		one_way_direction = value
		queue_redraw()
@export var linked_target_uid: String = "" # Legacy only.

@export_category("Wormhole")
# A Wormhole points to its matching Wormhole UID, not a grid cell.
# Both ends store reciprocal UIDs so deleting/repositioning nodes is safe.
@export var wormhole_pair_uid: String = "":
	set(value):
		wormhole_pair_uid = value
		queue_redraw()


@export_category("Alternating Node")

@export_enum("Upper Branch", "Lower Branch")
var alternating_first_branch: int = 0:
	set(value):
		alternating_first_branch = clampi(value, 0, 1)
		queue_redraw()

# Saved per-level authoring rule. Player Mode currently uses this only
# for Alternating nodes. Old levels default to false (locked).
@export_category("Player Interaction")
@export var player_editable: bool = false:
	set(value):
		player_editable = value
		queue_redraw()

# Zero is the original authored orientation. Each click rotates
# the physical input port clockwise to its next attached arm.
@export_range(0, 100, 1) var port_rotation_steps: int = 0:
	set(value):
		port_rotation_steps = maxi(0, value)
		queue_redraw()




var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()
var runtime_test_mode: bool = false
var runtime_activations: int = 0
var runtime_broken: bool = false
var runtime_blocker_open: bool = false
var runtime_delay_held: int = 0
var runtime_delay_remaining: int = 0
var runtime_repeater_active: bool = false
var runtime_repeat_remaining: int = 0
var runtime_alternating_exit: int = -1
var runtime_wormhole_flash: float = 0.0

# Cosmetic player interaction only. The existing pulse simulation
# still uses alternating_first_branch and the per-signal cursor.
var player_switch_animating: bool = false

@export_category("Activation Animation")
@export_range(0.0, 0.5, 0.01) var pop_strength: float = 0.18
@export_range(0.1, 1.5, 0.01) var pop_duration: float = 0.55
@export_range(0.0, 1.5, 0.05) var wiggle_rotation: float = 1.0
@export_range(1.0, 8.0, 0.5) var wiggle_cycles: float = 3.0
@export_range(0.1, 4.0, 0.1) var wiggle_damping: float = 1.4

@export_category("Delay Charge Animation")
@export_range(0.0, 0.75, 0.01) var delay_charge_strength: float = 0.34
@export_range(0.0, 0.5, 0.01) var delay_release_dip: float = 0.15
@export_range(0.1, 1.0, 0.01) var delay_release_duration: float = 0.30

var pop_time_remaining: float = 0.0
var resting_rotation: float = 0.0
var delay_charge_progress: float = 0.0
var delay_release_remaining: float = 0.0
var delay_releasing: bool = false

const RADIUS: float = 21.0
const NORMAL_COLOR: Color = Color("#64748b")
const SPLITTER_COLOR: Color = Color("#d97706")
const ALTERNATING_COLOR: Color = Color("#0e7490")
const TARGET_COLOR: Color = Color("#997318")
const TARGET_FILL_COLOR: Color = Color("#2dbb71")
const BLOCKER_COLOR: Color = Color("#4b5563")
const GATE_COLOR: Color = Color("#256d69")
const DELAY_COLOR: Color = Color("#4361a8")
const REPEATER_COLOR: Color = Color("#7751a7")
const BOUNCE_COLOR: Color = Color("#b35b75")
const ONE_WAY_COLOR: Color = Color("#258a79")
const BROKEN_COLOR: Color = Color("#dc2626")
const SELECTION_COLOR: Color = Color("#38bdf8")
const OPEN_COLOR: Color = Color("#86efac")
const BEGIN_COLOR: Color = Color("#16876d")
const WORMHOLE_COLOR: Color = Color("#463c91")


func _ready() -> void:
	resting_rotation = rotation

func is_blocker() -> bool:
	return kind == Kind.BLOCKER_SINGLE or kind == Kind.BLOCKER_AMOUNT or kind == Kind.BLOCKER_TARGET
func is_gate() -> bool:
	return kind == Kind.GATE_AMOUNT or kind == Kind.ONE_WAY_GATE
func is_target() -> bool:
	return kind == Kind.TARGET or kind == Kind.TRIGGER_TARGET
func is_goal_target() -> bool:
	return kind == Kind.TARGET
func is_trigger_target() -> bool:
	return kind == Kind.TRIGGER_TARGET
func uses_channel() -> bool:
	return kind == Kind.TRIGGER_TARGET or kind == Kind.BLOCKER_TARGET
func has_unlimited_activations() -> bool:
	return kind == Kind.NORMAL or kind == Kind.WORMHOLE
func get_channel_color() -> Color:
	match channel:
		Channel.PURPLE: return Color("#a78bfa")
		Channel.BLUE: return Color("#38bdf8")
		Channel.GREEN: return Color("#4ade80")
		Channel.RED: return Color("#fb7185")
	return Color.WHITE
func get_remaining_activations() -> int:
	if has_unlimited_activations(): return -1
	return maxi(0, activation_cap - runtime_activations)
func get_counter_text() -> String:
	match kind:
		Kind.NORMAL, Kind.WORMHOLE, Kind.BLOCKER_SINGLE, Kind.BLOCKER_TARGET, Kind.BOUNCE, Kind.ONE_WAY_GATE: return ""
		Kind.BLOCKER_AMOUNT:
			return str(maxi(0, blocker_hits - runtime_activations)) if runtime_test_mode else str(blocker_hits)
		Kind.GATE_AMOUNT:
			return str(maxi(0, gate_passes - runtime_activations)) if runtime_test_mode else str(gate_passes)
		Kind.DELAY:
			return str(runtime_delay_remaining) if runtime_test_mode and runtime_delay_held > 0 else str(delay_ticks)
		Kind.REPEATER:
			return str(runtime_repeat_remaining) if runtime_test_mode and runtime_repeater_active else str(repeat_count)
		_:
			return str(get_remaining_activations()) if runtime_test_mode else str(activation_cap)

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if kind == Kind.WORMHOLE:
		# Idle vortex is always moving; flash briefly accelerates it.
		var flash_amount: float = clampf(
			runtime_wormhole_flash / WORMHOLE_FLASH_DURATION, 0.0, 1.0
		)
		var spin_multiplier: float = lerpf(
			1.0, maxf(1.0, wormhole_flash_spin_multiplier), flash_amount
		)
		wormhole_spin_time = wrapf(
			wormhole_spin_time + delta * wormhole_spin_speed * spin_multiplier,
			0.0, TAU
		)
		if runtime_wormhole_flash > 0.0:
			runtime_wormhole_flash = maxf(0.0, runtime_wormhole_flash - delta)
		queue_redraw()
	if kind == Kind.DELAY and delay_releasing:
		delay_release_remaining = maxf(0.0, delay_release_remaining - delta)
		var duration: float = maxf(delay_release_duration, 0.001)
		var progress: float = clampf(1.0 - delay_release_remaining / duration, 0.0, 1.0)
		var scale_value: float
		if progress < 0.42:
			var t: float = progress / 0.42
			t = 1.0 - pow(1.0 - t, 3.0)
			scale_value = lerpf(1.0 + delay_charge_strength, 1.0 - delay_release_dip, t)
		else:
			var t: float = (progress - 0.42) / 0.58
			scale_value = lerpf(1.0 - delay_release_dip, 1.0, t * t * (3.0 - 2.0 * t))
		scale = Vector2.ONE * scale_value
		rotation = resting_rotation
		if delay_release_remaining <= 0.0:
			delay_releasing = false
			scale = Vector2.ONE
		return
	if kind == Kind.DELAY and delay_charge_progress > 0.0:
		var charge: float = clampf(delay_charge_progress, 0.0, 1.0)
		scale = Vector2.ONE * (1.0 + charge * charge * (3.0 - 2.0 * charge) * delay_charge_strength)
		rotation = resting_rotation
		return
	if pop_time_remaining <= 0.0:
		return
	pop_time_remaining = maxf(0.0, pop_time_remaining - delta)
	var progress: float = clampf(1.0 - pop_time_remaining / maxf(pop_duration, 0.001), 0.0, 1.0)
	scale = Vector2.ONE * (1.0 + sin(progress * PI) * pop_strength)
	rotation = resting_rotation + sin(progress * TAU * wiggle_cycles) * pow(1.0 - progress, wiggle_damping) * wiggle_rotation
	if pop_time_remaining <= 0.0:
		scale = Vector2.ONE
		rotation = resting_rotation

func flash_wormhole() -> void:
	# A brief flare on both the entry and exit portal.
	runtime_wormhole_flash = WORMHOLE_FLASH_DURATION
	queue_redraw()

func play_activation_animation() -> void:
	if kind == Kind.NORMAL: return
	if pop_time_remaining <= 0.0 and not delay_releasing and delay_charge_progress <= 0.0:
		resting_rotation = rotation
	pop_time_remaining = pop_duration
	if kind != Kind.DELAY or (not delay_releasing and delay_charge_progress <= 0.0):
		scale = Vector2.ONE
		rotation = resting_rotation
func set_delay_charge_progress(progress: float) -> void:
	if kind != Kind.DELAY or delay_releasing: return
	var value: float = clampf(progress, 0.0, 1.0)
	if delay_charge_progress > 0.0 and value <= 0.0:
		scale = Vector2.ONE
	delay_charge_progress = value
func play_delay_release_animation() -> void:
	if kind != Kind.DELAY: return
	delay_charge_progress = 0.0
	delay_releasing = true
	delay_release_remaining = delay_release_duration
	pop_time_remaining = 0.0
	scale = Vector2.ONE * (1.0 + delay_charge_strength)
	rotation = resting_rotation

func set_test_display(active: bool, activations: int = 0, broken: bool = false) -> void:
	var count: int = maxi(0, activations)
	if active and runtime_test_mode and count > runtime_activations:
		play_activation_animation()
	runtime_test_mode = active
	runtime_activations = count
	runtime_broken = broken
	queue_redraw()
func set_blocker_open(is_open: bool) -> void:
	runtime_blocker_open = is_open
	queue_redraw()
func set_delay_display(held_count: int, remaining_ticks: int) -> void:
	var count: int = maxi(0, held_count)
	var left: int = maxi(0, remaining_ticks)
	if count == runtime_delay_held and left == runtime_delay_remaining: return
	runtime_delay_held = count
	runtime_delay_remaining = left
	queue_redraw()
func set_repeater_display(active: bool, remaining: int) -> void:
	runtime_repeater_active = active
	runtime_repeat_remaining = maxi(0, remaining)
	queue_redraw()



func clear_test_display() -> void:

	runtime_test_mode = false
	runtime_activations = 0
	runtime_broken = false
	runtime_blocker_open = false

	runtime_delay_held = 0
	runtime_delay_remaining = 0

	runtime_repeater_active = false
	runtime_repeat_remaining = 0

	runtime_alternating_exit = -1
	runtime_wormhole_flash = 0.0

	pop_time_remaining = 0.0
	delay_charge_progress = 0.0
	delay_release_remaining = 0.0
	delay_releasing = false

	scale = Vector2.ONE
	rotation = resting_rotation

	queue_redraw()



func get_target_fill_fraction() -> float:
	if not is_target() or not runtime_test_mode: return 0.0
	return clampf(float(runtime_activations) / float(maxi(1, activation_cap)), 0.0, 1.0)
func _draw_target_fill(fraction: float) -> void:
	if fraction <= 0.0: return
	var color: Color = TARGET_FILL_COLOR if kind == Kind.TARGET else get_channel_color()
	if fraction >= 1.0:
		draw_circle(Vector2.ZERO, RADIUS, color)
		return
	var fill_y: float = RADIUS * (1.0 - 2.0 * fraction)
	var half_width: float = sqrt(maxf(0.0, RADIUS * RADIUS - fill_y * fill_y))
	var points := PackedVector2Array([Vector2(-half_width, fill_y), Vector2(half_width, fill_y)])
	var start_angle: float = asin(clampf(fill_y / RADIUS, -1.0, 1.0))
	for i in range(49):
		var angle: float = lerpf(start_angle, PI - start_angle, float(i) / 48.0)
		points.append(Vector2(cos(angle) * RADIUS, sin(angle) * RADIUS))
	draw_colored_polygon(points, color)



func _draw() -> void:

	var color: Color = NORMAL_COLOR
	var symbol: String = ""

	match kind:

		Kind.SPLITTER:
			color = SPLITTER_COLOR
			symbol = "%d<%d" % [
				required_inputs,
				output_count
			]

		Kind.ALTERNATING:
			color = ALTERNATING_COLOR

		Kind.TARGET:
			color = TARGET_COLOR
			symbol = "T"

		Kind.TRIGGER_TARGET:
			color = get_channel_color().darkened(0.45)
			symbol = "T"

		Kind.BLOCKER_SINGLE, Kind.BLOCKER_AMOUNT:
			color = BLOCKER_COLOR

		Kind.BLOCKER_TARGET:
			color = get_channel_color().darkened(0.55)

		Kind.GATE_AMOUNT:
			color = GATE_COLOR

		Kind.DELAY:
			color = DELAY_COLOR

		Kind.REPEATER:
			color = REPEATER_COLOR

		Kind.BOUNCE:
			color = BOUNCE_COLOR

		Kind.ONE_WAY_GATE:
			color = ONE_WAY_COLOR

		Kind.BEGIN:
			color = BEGIN_COLOR

		Kind.WORMHOLE:
			color = WORMHOLE_COLOR

	if runtime_broken:
		color = BROKEN_COLOR

	if selected:

		draw_arc(
			Vector2.ZERO,
			RADIUS + 7.0,
			0.0,
			TAU,
			48,
			SELECTION_COLOR,
			3.0,
			true
		)

	draw_circle(
		Vector2.ZERO,
		RADIUS,
		color
	)

	if is_target() and not runtime_broken:

		_draw_target_fill(
			get_target_fill_fraction()
		)

	var outline: Color = (
		get_channel_color()
		if uses_channel()
		else Color.WHITE
	)

	draw_arc(
		Vector2.ZERO,
		RADIUS,
		0.0,
		TAU,
		48,
		outline,
		2.5,
		true
	)

	match kind:

		Kind.BEGIN:
			_draw_begin_symbol()

		Kind.WORMHOLE:
			_draw_wormhole_symbol()

		Kind.NORMAL:

			draw_circle(
				Vector2.ZERO,
				2.0,
				Color.WHITE
			)

		Kind.ALTERNATING:
			if not _draw_player_port_rotor():
				_draw_alternating_symbol()
			# Tiny cyan handle on an adjustable switch; no outer ring.
			if player_editable and not player_switch_animating:
				draw_circle(Vector2(-13.5, -12.0), 3.1, Color("#67E8F9"))
				draw_circle(Vector2(-13.5, -12.0), 1.0, Color("#FFFFFF"))

		Kind.SPLITTER:
			if _draw_player_port_rotor():
				# Retain the remaining activation cap after switching to port artwork.
				_draw_centered_text(get_counter_text(), 13.0, 10, Color.WHITE)
			else:
				_draw_centered_text(
					"%d<%d" % [required_inputs, output_count],
					-1.0, 12, Color.WHITE
				)
				_draw_centered_text(get_counter_text(), 12.0, 10, Color.WHITE)
			if player_editable and not player_switch_animating:
				draw_circle(Vector2(-13.5, -12.0), 3.1, Color("#67E8F9"))
				draw_circle(Vector2(-13.5, -12.0), 1.0, Color.WHITE)

		Kind.BLOCKER_SINGLE, Kind.BLOCKER_AMOUNT, Kind.BLOCKER_TARGET:
			_draw_blocker_symbol()

		Kind.GATE_AMOUNT:
			_draw_gate_symbol()

		Kind.ONE_WAY_GATE:
			_draw_one_way_symbol()

		Kind.DELAY:
			_draw_delay_symbol()

		Kind.REPEATER:
			_draw_repeater_symbol()

		Kind.BOUNCE:
			_draw_bounce_symbol()

		_:

			_draw_centered_text(
				symbol,
				-1.0,
				12 if kind == Kind.SPLITTER else 15,
				Color.WHITE
			)

			_draw_centered_text(
				get_counter_text(),
				12.0,
				10,
				Color.WHITE
			)

			# Cyan handle: this Splitter can be dragged in Player Mode.
			if kind == Kind.SPLITTER and player_editable:
				draw_circle(Vector2(-13.5, -12.0), 3.1, Color("#67E8F9"))
				draw_circle(Vector2(-13.5, -12.0), 1.0, Color.WHITE)

			if kind == Kind.TRIGGER_TARGET:

				draw_circle(
					Vector2(13, -12),
					3.5,
					get_channel_color()
				)

	if runtime_broken:

		draw_line(
			Vector2(-15, -15),
			Vector2(15, 15),
			Color.WHITE,
			2.5,
			true
		)

		draw_line(
			Vector2(15, -15),
			Vector2(-15, 15),
			Color.WHITE,
			2.5,
			true
		)



func _wormhole_pair_color() -> Color:
	if wormhole_pair_uid.is_empty():
		return Color("#8b93a9")
	var ends: Array[String] = [node_uid, wormhole_pair_uid]
	ends.sort()
	var pair_key: String = ends[0] + ":" + ends[1]
	var palette: Array[Color] = [
		Color("#5eead4"), Color("#b4a0ff"), Color("#fda4af"),
		Color("#86efac"), Color("#7dd3fc"), Color("#f0abfc")
	]
	var code: int = 0
	for byte in pair_key.to_utf8_buffer():
		code = (code * 31 + int(byte)) % 2147483647
	return palette[code % palette.size()]


func _draw_wormhole_symbol() -> void:
	# A continuously swirling vortex, drawn entirely in this node's
	# local space. No extra scenes, shaders, textures or game logic needed.
	var pair_accent: Color = _wormhole_pair_color()
	var outer_ink: Color = wormhole_outer_color.lerp(pair_accent, 0.65)
	var inner_ink: Color = wormhole_inner_color.lerp(pair_accent, 0.30)
	var radius: float = clampf(
		RADIUS * wormhole_radius_factor, 7.5, RADIUS - 3.0
	)
	var flash: float = clampf(
		runtime_wormhole_flash / WORMHOLE_FLASH_DURATION, 0.0, 1.0
	)
	var glow: float = 0.5 + 0.5 * sin(wormhole_spin_time * 1.7)

	# Dark, recessed interior and a softly breathing halo.
	var shadow: Color = wormhole_core_color
	shadow.a = 0.88
	draw_circle(Vector2.ZERO, radius + 1.0, shadow)
	var halo: Color = outer_ink
	halo.a = 0.18 + glow * 0.12 + flash * 0.25
	draw_circle(Vector2.ZERO, radius + 3.0, halo)

	# The faint rim gives the vortex a contained, portal-like edge.
	var rim_color: Color = pair_accent
	rim_color.a = 0.55 + flash * 0.40
	draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 48, rim_color, 1.7, true)

	# Rotating bright fragments on the outer rim.
	for fragment in range(3):
		var fragment_angle: float = (
			wormhole_spin_time * 0.7 + TAU * float(fragment) / 3.0
		)
		var fragment_ink: Color = inner_ink
		fragment_ink.a = 0.42 + glow * 0.22 + flash * 0.20
		draw_arc(
			Vector2.ZERO, radius + 2.2,
			fragment_angle, fragment_angle + 0.42,
			12, fragment_ink, 2.2, true
		)

	# Draw inward spiralling arms. Their phase moves every frame,
	# while the inner ends lead into the dark centre of the tunnel.
	var count: int = maxi(1, wormhole_arm_count)
	var steps: int = 36
	for arm_index in range(count):
		var arm_offset: float = TAU * float(arm_index) / float(count)
		var points: PackedVector2Array = PackedVector2Array()
		for step in range(steps + 1):
			var t: float = float(step) / float(steps)
			var angle: float = (
				wormhole_spin_time + arm_offset + t * TAU * 1.35
			)
			var distance: float = lerpf(radius * 0.93, 1.9, t)
			points.append(Vector2(cos(angle), sin(angle)) * distance)

		# A coloured under-stroke adds depth; the thin cyan highlight
		# follows the same curve and intensifies during teleportation.
		var arm_base: Color = outer_ink
		arm_base.a = 0.75 + flash * 0.25
		draw_polyline(
			points, arm_base,
			wormhole_line_width + 1.0 + flash * 0.8, true
		)
		var arm_highlight: Color = inner_ink
		arm_highlight.a = 0.63 + flash * 0.37
		draw_polyline(
			points, arm_highlight,
			maxf(0.8, wormhole_line_width * 0.42 + flash * 0.7), true
		)

		# Each arm carries a small moving bead of energy around the rim.
		draw_circle(points[0], 1.3 + flash * 0.7, arm_highlight)

	# A small dark core makes the lines seem to disappear inward.
	draw_circle(Vector2.ZERO, 4.4, wormhole_core_color)
	var core_rim: Color = inner_ink
	core_rim.a = 0.65 + flash * 0.35
	draw_arc(Vector2.ZERO, 4.6, 0.0, TAU, 24, core_rim, 1.1, true)
	draw_circle(Vector2.ZERO, 1.6 + flash * 0.7, pair_accent)

	# Keep the existing unpaired warning and teleport-arrival flare.
	if wormhole_pair_uid.is_empty():
		_draw_centered_text("?", 8.0, 10, Color("#fca5a5"))
	if flash > 0.0:
		var progress: float = 1.0 - flash
		var flare: Color = pair_accent
		flare.a = flash * 0.90
		draw_arc(
			Vector2.ZERO, radius + 3.5 + progress * 6.0,
			0.0, TAU, 48, flare, 2.2 + flash * 1.4, true
		)


func _draw_begin_symbol() -> void:
	# A green, unmistakably clickable Play button in Builder and Player Mode.
	# Draw everything in node-local coordinates, so Player Mode scaling and
	# fades work without any special cases.
	draw_circle(Vector2.ZERO, 15.0, Color("#0B5F4D"))
	draw_arc(
		Vector2.ZERO, 15.0, 0.0, TAU, 40,
		Color("#70E7B7"), 1.6, true
	)
	# The triangle is shifted slightly right for optical centering.
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-5.0, -9.0),
			Vector2(10.0, 0.0),
			Vector2(-5.0, 9.0)
		]),
		Color.WHITE
	)


func _draw_blocker_symbol() -> void:
	if runtime_test_mode and runtime_blocker_open:
		_draw_open_passage()
		return
	draw_line(Vector2(-15,-3), Vector2(3,-3), Color.WHITE, 2.7, true)
	draw_line(Vector2(3,-14), Vector2(3,12), Color.WHITE, 3.0, true)
	_draw_centered_text(get_counter_text(), 16.0, 10, Color.WHITE)
	if kind == Kind.BLOCKER_TARGET: draw_circle(Vector2(12,-12), 3.5, get_channel_color())
func _draw_gate_symbol() -> void:
	var opened: bool = true if not runtime_test_mode else runtime_blocker_open
	if opened:
		_draw_open_passage()
	else:
		draw_line(Vector2(-14,-3), Vector2(3,-3), Color.WHITE, 2.7, true)
		draw_line(Vector2(3,-14), Vector2(3,12), Color("#fca5a5"), 3.0, true)
	_draw_centered_text(get_counter_text(), 16.0, 10, Color.WHITE)
func _draw_open_passage() -> void:
	draw_line(Vector2(-15,-2), Vector2(15,-2), OPEN_COLOR, 3.0, true)
func _draw_delay_symbol() -> void:
	var center := Vector2(0,-5)
	draw_arc(center, 9.0, 0.0, TAU, 32, Color.WHITE, 1.8, true)
	for i in range(4):
		var angle: float = -PI / 2.0 + float(i) * PI / 2.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * 6.8, center + direction * 8.8, Color("#bdd7ff"), 1.0, true)
	var progress: float = 0.0
	if runtime_test_mode and runtime_delay_held > 0:
		progress = clampf(float(delay_ticks - runtime_delay_remaining) / float(maxi(1, delay_ticks)), 0.0, 1.0)
	var hand_angle: float = -PI / 2.0 + progress * TAU
	draw_line(center, center + Vector2(cos(hand_angle), sin(hand_angle)) * 6.4, Color.WHITE, 2.0, true)
	draw_circle(center, 1.3, Color.WHITE)
	_draw_centered_text(get_counter_text(), 15.0, 11, Color.WHITE)
	if runtime_test_mode and runtime_delay_held > 0:
		_draw_centered_text("x%d" % runtime_delay_held, -16.0, 9, Color("#b9f4ff"))
func _draw_repeater_symbol() -> void:
	for i in range(3):
		draw_circle(Vector2(-10 + i * 10, -5), 3.1, Color.WHITE)
	_draw_centered_text(get_counter_text(), 16.0, 12, Color.WHITE)
	if runtime_repeater_active: draw_arc(Vector2.ZERO, RADIUS + 3.0, 0.0, TAU, 40, Color("#e9d5ff"), 2.0, true)
func _draw_bounce_symbol() -> void:
	# U-turn icon, without relying on symbol font support.
	draw_arc(Vector2(0, -1), 11.0, PI, TAU, 24, Color.WHITE, 2.6, true)
	draw_line(Vector2(-11,-1), Vector2(-11,10), Color.WHITE, 2.6, true)
	draw_line(Vector2(11,-1), Vector2(11,10), Color.WHITE, 2.6, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-16,7),Vector2(-6,7),Vector2(-11,14)]), Color.WHITE)
func _draw_one_way_symbol() -> void:
	# The arrow points in the direction in which pulses can travel.
	var forward: Vector2 = Vector2.RIGHT
	match one_way_direction:
		Direction.NORTH: forward = Vector2.UP
		Direction.EAST: forward = Vector2.RIGHT
		Direction.SOUTH: forward = Vector2.DOWN
		Direction.WEST: forward = Vector2.LEFT
	var side: Vector2 = forward.orthogonal()
	var tip: Vector2 = forward * 14.0
	var base: Vector2 = forward * 2.0
	var tail: Vector2 = -forward * 12.0
	draw_line(tail, base, Color.WHITE, 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		tip, base + side * 7.0, base - side * 7.0
	]), Color.WHITE)

func _draw_centered_text(message: String, baseline_y: float, font_size: int, color: Color) -> void:
	if message.is_empty(): return
	var font: Font = ThemeDB.fallback_font
	var width: float = font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(-width / 2.0, baseline_y), message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
func refresh_visuals() -> void:
	queue_redraw()



func set_alternating_display(
	exit_index: int
) -> void:

	runtime_alternating_exit = exit_index
	queue_redraw()


func _draw_alternating_symbol() -> void:

	# While picked up, temporarily show a symmetric rotor. This
	# allows a full 120-degree Honeycomb or 90-degree Square turn
	# without a sudden visual snap when the node is put down.
	if player_switch_animating:
		_draw_switch_rotor()
		return

	# Only the Honeycomb icon uses the actual 120-degree branches.
	# Square and Rhombus retain their original symbol unchanged.
	if _draw_honeycomb_alternating_symbol():
		return

	# The highlighted branch is the NEXT available route.
	# The other branch is greyed out.
	#
	# 0 = Upper / North-East
	# 1 = Lower / South-East

	var incoming_start := Vector2(-16.0, 0.0)
	var junction := Vector2(-2.0, 0.0)

	var upper_exit := Vector2(15.0, -11.0)
	var lower_exit := Vector2(15.0, 11.0)

	# Visual colours
	var incoming_color := Color("#E5F2F5")
	var available_color := Color("#F4FFFF")
	var unavailable_color := Color("#526B74")

	# In Builder mode, use the configured first branch.
	# In test mode, show the next branch to be used.
	var selected_exit: int = alternating_first_branch

	if runtime_alternating_exit >= 0:
		selected_exit = runtime_alternating_exit

	var upper_available: bool = selected_exit % 2 == 0
	var lower_available: bool = not upper_available

	# Incoming path
	draw_line(
		incoming_start,
		junction,
		incoming_color,
		3.0,
		true
	)

	# Upper path
	draw_line(
		junction,
		upper_exit,
		available_color if upper_available else unavailable_color,
		3.8 if upper_available else 2.8,
		true
	)

	# Lower path
	draw_line(
		junction,
		lower_exit,
		available_color if lower_available else unavailable_color,
		3.8 if lower_available else 2.8,
		true
	)

	# Junction
	draw_circle(
		junction,
		2.4,
		Color.WHITE
	)


# ============================================================
# 3-ARM / 4-ARM ROTOR USED ONLY DURING PLAYER CLICK ANIMATION
#
# This is a cosmetic part. We don't change connection endpoints,
# bridge geometry, or any pulse routing rules.
# ============================================================

func _draw_switch_rotor() -> void:
	# Show the SAME ONE available exit throughout the lift/turn.
	# Other directions stay dark. The symbol spins with its holder.
	var arm_directions: Array[Vector2] = []
	var outgoing: Array[Dictionary] = []
	var incoming_dirs: Array[Vector2] = []

	var host: Node = self
	var live_grid: SquarePuzzleGrid = null
	var connections_node: Node = null
	while host != null:
		live_grid = host.get_node_or_null("Grid") as SquarePuzzleGrid
		connections_node = host.get_node_or_null("Connections")
		if live_grid != null and connections_node != null:
			break
		host = host.get_parent()

	if live_grid != null:
		var cell_origin: Vector2 = live_grid.cell_to_local(grid_cell)
		for neighbour in live_grid.get_neighbors(grid_cell):
			var direction: Vector2 = (
				live_grid.cell_to_local(neighbour) - cell_origin
			).normalized()
			if direction.length_squared() > 0.001:
				arm_directions.append(direction)

		var records: Variant = connections_node.get("connections")
		if records is Array:
			for record in records:
				if not (record is Dictionary):
					continue
				var path: Array = record.get("path", [])
				if path.size() < 2:
					continue
				if str(record.get("from_uid", "")) == node_uid:
					var out_dir: Vector2 = (
						live_grid.cell_to_local(path[1])
						- live_grid.cell_to_local(path[0])
					).normalized()
					outgoing.append({
						"to": str(record.get("to_uid", "")),
						"direction": out_dir
					})
				if str(record.get("to_uid", "")) == node_uid:
					var end_index: int = path.size() - 1
					incoming_dirs.append((
						live_grid.cell_to_local(path[end_index - 1])
						- live_grid.cell_to_local(path[end_index])
					).normalized())

	# Match the ordering in TestLevel._activate_alternating().
	outgoing.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_direction: Vector2 = a["direction"]
			var b_direction: Vector2 = b["direction"]
			var a_y: float = a_direction.y
			var b_y: float = b_direction.y
			if absf(a_y - b_y) > 0.0001:
				return a_y < b_y
			return str(a["to"]) < str(b["to"])
	)

	var next_index: int = alternating_first_branch
	if runtime_alternating_exit >= 0:
		next_index = runtime_alternating_exit
	var active_direction: Vector2 = Vector2.RIGHT
	if not outgoing.is_empty():
		active_direction = outgoing[posmod(next_index, outgoing.size())]["direction"]

	if arm_directions.is_empty():
		arm_directions.append(Vector2.RIGHT)
		arm_directions.append(Vector2.DOWN)
		arm_directions.append(Vector2.LEFT)
		arm_directions.append(Vector2.UP)

	var highlighted: bool = false
	for direction in arm_directions:
		var color: Color = Color("#526B74")
		var width: float = 2.6
		for incoming in incoming_dirs:
			if direction.dot(incoming) > 0.98:
				color = Color("#96B5BC")
				width = 3.0
				break
		if not highlighted and direction.dot(active_direction) > 0.98:
			color = Color("#F4FFFF")
			width = 4.0
			highlighted = true
		draw_line(Vector2.ZERO, direction * 16.0, color, width, true)

	draw_circle(Vector2.ZERO, 2.6, Color.WHITE)


func _draw_honeycomb_alternating_symbol() -> bool:
	# Find the Builder owning this node. It can be either a direct
	# child of PlacedNodes or nested inside a PlayerVisualScale wrapper.
	var host: Node = self
	var found_grid: SquarePuzzleGrid = null
	var found_connections: Node = null
	while host != null:
		var grid_candidate: SquarePuzzleGrid = (
			host.get_node_or_null("Grid") as SquarePuzzleGrid
		)
		var connections_candidate: Node = host.get_node_or_null("Connections")
		if grid_candidate != null and connections_candidate != null:
			found_grid = grid_candidate
			found_connections = connections_candidate
			break
		host = host.get_parent()

	# The old left/right fork is used for Square, Rhombus and
	# when previewing the PuzzleNode scene on its own.
	if found_grid == null or not found_grid.is_honeycomb():
		return false

	var neighbour_cells: Array[Vector2i] = found_grid.get_neighbors(grid_cell)
	if neighbour_cells.is_empty():
		return false

	# Calculate directions in the node's own local space, so
	# scale wrappers and future rotations cannot misalign the icon.
	var origin_global: Vector2 = found_grid.to_global(
		found_grid.cell_to_local(grid_cell)
	)
	var origin_local: Vector2 = to_local(origin_global)
	var arms: Array[Vector2] = []
	for neighbour in neighbour_cells:
		var end_global: Vector2 = found_grid.to_global(
			found_grid.cell_to_local(neighbour)
		)
		var direction: Vector2 = (to_local(end_global) - origin_local).normalized()
		if direction.length_squared() > 0.0001:
			arms.append(direction)

	var incoming_arms: Array[Vector2] = []
	var outgoing: Array[Dictionary] = []
	var all_connections: Variant = found_connections.get("connections")
	if all_connections is Array:
		for entry in all_connections:
			if not (entry is Dictionary):
				continue
			var path: Array = entry.get("path", [])
			if path.size() < 2:
				continue

			if str(entry.get("from_uid", "")) == node_uid:
				var start_cell: Vector2i = path[0]
				var next_cell: Vector2i = path[1]
				var delta: Vector2 = (
					found_grid.cell_to_local(next_cell)
					- found_grid.cell_to_local(start_cell)
				).normalized()
				var endpoint_global: Vector2 = found_grid.to_global(
					found_grid.cell_to_local(next_cell)
				)
				var local_dir: Vector2 = (
					to_local(endpoint_global) - origin_local
				).normalized()
				outgoing.append({
					"to": str(entry.get("to_uid", "")),
					"direction": local_dir,
					"sort_y": delta.y
				})

			if str(entry.get("to_uid", "")) == node_uid:
				var last_index: int = path.size() - 1
				var prior_cell: Vector2i = path[last_index - 1]
				var source_global: Vector2 = found_grid.to_global(
					found_grid.cell_to_local(prior_cell)
				)
				var incoming_dir: Vector2 = (
					to_local(source_global) - origin_local
				).normalized()
				incoming_arms.append(incoming_dir)

	# IMPORTANT: This is the same ordering used in
	# builder_test_level.gd::_activate_alternating(): visually
	# higher outgoing connection first, then destination UID.
	outgoing.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if absf(float(a["sort_y"]) - float(b["sort_y"])) > 0.0001:
				return float(a["sort_y"]) < float(b["sort_y"])
			return str(a["to"]) < str(b["to"])
	)

	var selected_exit: int = alternating_first_branch
	if runtime_alternating_exit >= 0:
		selected_exit = runtime_alternating_exit
	var active_index: int = -1
	if not outgoing.is_empty():
		active_index = posmod(selected_exit, outgoing.size())

	var available_color: Color = Color("#F4FFFF")
	var incoming_color: Color = Color("#D1E9EF")
	var unavailable_color: Color = Color("#526B74")

	for arm in arms:
		var arm_color: Color = unavailable_color
		var arm_width: float = 2.6

		for incoming_dir in incoming_arms:
			if arm.dot(incoming_dir) > 0.98:
				arm_color = incoming_color
				arm_width = 3.0
				break

		for index in range(outgoing.size()):
			var out_dir: Vector2 = outgoing[index]["direction"]
			if arm.dot(out_dir) > 0.98:
				if index == active_index:
					arm_color = available_color
					arm_width = 3.8
				else:
					arm_color = unavailable_color
					arm_width = 2.6
				break

		draw_line(Vector2.ZERO, arm * 16.0, arm_color, arm_width, true)

	draw_circle(Vector2.ZERO, 2.4, Color.WHITE)
	return true


# ============================================================
# TWO-WAY PHYSICAL ROTOR VISUALS
# One muted/unused port + two active output ports.
# Alternating: one bright output, one muted output.
# Splitter: both outputs bright.
# This is the same port selection function used by TestLevel.
# ============================================================

func _draw_player_port_rotor() -> bool:
	# Honeycomb alternators: three physical ports, ONE red (blocked),
	# TWO white (open). Rotation changes the red port, not an output pair.
	if kind != Kind.ALTERNATING and kind != Kind.SPLITTER:
		return false

	var host: Node = self
	var live_grid: PuzzleGridBase = null
	var connections_node: Node = null
	var tools_node: Node = null
	while host != null:
		live_grid = host.get_node_or_null("Grid") as PuzzleGridBase
		connections_node = host.get_node_or_null("Connections")
		tools_node = host.get_node_or_null("LevelTools")
		if live_grid != null and connections_node != null and tools_node != null:
			break
		host = host.get_parent()

	if live_grid == null or connections_node == null or tools_node == null:
		return false
	if not bool(tools_node.get("allow_reverse_travel")):
		return false

	var shape: SquarePuzzleGrid = live_grid as SquarePuzzleGrid
	var is_hex: bool = shape != null and shape.is_honeycomb()
	if kind == Kind.ALTERNATING and not is_hex:
		return false
	if kind == Kind.SPLITTER and not player_editable:
		return false

	var builder_node: Node = live_grid.get_parent()
	var nodes_lookup: Dictionary = builder_node.get("nodes_by_id")
	var raw_records: Variant = connections_node.get("connections")
	if not (raw_records is Array):
		return false

	var ports: Array[Dictionary] = []
	var closed_to: String = ""
	if kind == Kind.ALTERNATING:
		ports = PortRules.three_way_ports(
			node_uid, raw_records, nodes_lookup, live_grid
		)
		if ports.size() != 3:
			return false
		var closed_index: int = posmod(port_rotation_steps, 3)
		if runtime_test_mode and runtime_alternating_exit >= 0:
			closed_index = posmod(runtime_alternating_exit, 3)
		closed_to = str(ports[closed_index]["to"])
	else:
		var splitter: Dictionary = PortRules.get_rotor(
			node_uid, raw_records, nodes_lookup, live_grid,
			port_rotation_steps, true
		)
		if not bool(splitter.get("valid", false)):
			return false
		ports.assign(splitter["ports"])
		closed_to = str(splitter["input"]["to"])

	for port in ports:
		var path: Array = port["path"]
		if path.size() < 2:
			continue
		var start_world: Vector2 = live_grid.to_global(live_grid.cell_to_local(path[0]))
		var end_world: Vector2 = live_grid.to_global(live_grid.cell_to_local(path[1]))
		var direction: Vector2 = (to_local(end_world) - to_local(start_world)).normalized()
		if direction.length_squared() < 0.001:
			continue
		# When the wrapper rotates, keep the arms moving with it.
		if player_switch_animating:
			var holder: Node2D = get_parent() as Node2D
			if holder != null and holder.has_meta("em_player_visual_wrapper"):
				direction = direction.rotated(holder.rotation)

		var closed: bool = str(port["to"]) == closed_to
		var ink: Color = Color("#F4FFFF")
		var width: float = 3.8
		if closed:
			# Closed Alternating arm: subtle grey, never red.
			ink = Color("#8E9DA8", 0.55) if kind == Kind.ALTERNATING else Color("#8295A3")
			width = 2.8
		draw_line(Vector2.ZERO, direction * 16.0, ink, width, true)

	draw_circle(Vector2.ZERO, 2.4, Color.WHITE)
	return true
