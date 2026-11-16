

@tool
class_name PuzzleNode
extends Node2D

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
	BEGIN             # 13
}

enum Channel { PURPLE, BLUE, GREEN, RED }
enum Direction { NORTH, EAST, SOUTH, WEST }

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


@export_category("Alternating Node")

@export_enum("Upper Branch", "Lower Branch")
var alternating_first_branch: int = 0:
	set(value):
		alternating_first_branch = clampi(value, 0, 1)
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
	return kind == Kind.NORMAL
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
		Kind.NORMAL, Kind.BLOCKER_SINGLE, Kind.BLOCKER_TARGET, Kind.BOUNCE, Kind.ONE_WAY_GATE: return ""
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

		Kind.NORMAL:

			draw_circle(
				Vector2.ZERO,
				2.0,
				Color.WHITE
			)

		Kind.ALTERNATING:
			_draw_alternating_symbol()

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
