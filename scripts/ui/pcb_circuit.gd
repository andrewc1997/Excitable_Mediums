
extends Path2D


# ==================================================
# RANDOM PULSE SPEED
# ==================================================

@export_category("Pulse Speed")

@export var min_speed: float = 80.0
@export var max_speed: float = 160.0


# ==================================================
# AUTOMATIC FIRING
# ==================================================

@export_category("Automatic Firing")

@export var auto_fire: bool = false
@export var min_delay: float = 3.0
@export var max_delay: float = 6.0


# ==================================================
# BEAM APPEARANCE
# ==================================================

@export_category("Beam")

@export var beam_width: float = 7.0
@export var beam_color: Color = Color("#91D1FA")

@export_range(0.0, 1.0, 0.05)
var travel_opacity: float = 0.75

@export var sample_spacing: float = 2.0


# ==================================================
# TRAIL OPTIONS
# ==================================================

@export_category("Moving Trail")

# ON:  Short fading trail following the pulse
# OFF: Full beam growing from the start
@export var use_fading_trail: bool = true

@export_range(5.0, 500.0, 5.0)
var trail_length: float = 50.0


# ==================================================
# OPTIONAL SOFT EDGE
# ==================================================

@export_category("Soft Edge")

@export var enable_soft_edge: bool = false
@export var soft_edge_width: float = 12.0
@export var soft_edge_opacity: float = 0.10


# ==================================================
# DESTINATION ILLUMINATION
# ==================================================

@export_category("Destination")

@export var flash_time: float = 0.18
@export var hold_time: float = 0.4
@export var fade_time: float = 1.5
@export var terminus_scale: float = 1.2


# ==================================================
# NODE REFERENCES
# ==================================================

@onready var follower: PathFollow2D = $PathFollow2D
@onready var pulse: Sprite2D = $PathFollow2D/PulseSprite

@onready var inactive_trace: Line2D = $InactiveTrace
@onready var active_trace: Line2D = $ActiveTrace

@onready var terminus: Sprite2D = $Terminus
@onready var pulse_timer: Timer = $PulseTimer


# ==================================================
# VARIABLES
# ==================================================

var is_active: bool = false
var is_travelling: bool = false

var curve_length: float = 0.0
var current_speed: float = 0.0

var soft_edge: Line2D

var applied_fading_mode: bool = true


# ==================================================
# READY
# ==================================================

func _ready() -> void:

	if curve == null or curve.point_count < 2:
		push_warning("PCB Circuit needs a valid curve.")
		return

	# Independent runtime curve
	curve = curve.duplicate(true) as Curve2D

	curve.bake_interval = 2.0
	curve_length = curve.get_baked_length()

	if curve_length <= 0.0:
		push_warning("PCB Circuit has no length.")
		return

	# Path follower
	follower.loop = false
	follower.rotates = false
	follower.cubic_interp = true
	follower.progress = 0.0

	# Hide unused inactive trace
	inactive_trace.hide()

	# Main beam
	_configure_line(
		active_trace,
		beam_width,
		beam_color
	)

	active_trace.z_index = 2

	# Optional soft edge
	soft_edge = Line2D.new()
	soft_edge.name = "SoftEdge"

	add_child(soft_edge)

	var edge_color: Color = beam_color
	edge_color.a = soft_edge_opacity

	_configure_line(
		soft_edge,
		soft_edge_width,
		edge_color
	)

	soft_edge.z_index = 1
	soft_edge.visible = enable_soft_edge

	# Crisp circle texture
	var circle_texture: Texture2D = (
		_make_crisp_circle_texture()
	)

	# Pulse head
	pulse.texture = circle_texture
	pulse.position = Vector2.ZERO
	pulse.offset = Vector2.ZERO
	pulse.centered = true

	pulse.scale = Vector2.ONE * (
		beam_width / 30.0
	)

	pulse.modulate = beam_color
	pulse.z_index = 4
	pulse.hide()

	# Terminus
	terminus.texture = circle_texture

	terminus.position = curve.sample_baked(
		curve_length,
		true
	)

	terminus.scale = Vector2.ONE * (
		beam_width / 30.0
	)

	terminus.modulate = beam_color
	terminus.modulate.a = 0.0

	terminus.z_index = 4
	terminus.hide()

	_clear_beam()

	# Timer
	pulse_timer.one_shot = true
	pulse_timer.timeout.connect(_on_timer_timeout)

	if auto_fire:
		_schedule_next()


# ==================================================
# CONFIGURE LINE
# ==================================================

func _configure_line(
	line: Line2D,
	line_width: float,
	line_color: Color
) -> void:

	line.width = line_width

	line.gradient = null
	line.width_curve = null
	line.texture = null

	line.default_color = line_color

	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND

	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.round_precision = 16

	line.antialiased = true


# ==================================================
# CREATE FADING GRADIENT
# ==================================================

func _make_trail_gradient(
	base_color: Color
) -> Gradient:

	var gradient := Gradient.new()

	var tail_color: Color = base_color
	tail_color.a = 0.0

	gradient.set_color(0, tail_color)
	gradient.set_color(1, base_color)

	return gradient


# ==================================================
# APPLY SELECTED TRAIL STYLE
# ==================================================

func _apply_trail_style() -> void:

	var edge_color: Color = beam_color
	edge_color.a = soft_edge_opacity

	if use_fading_trail:

		# Short trail with transparent tail
		active_trace.gradient = (
			_make_trail_gradient(beam_color)
		)

		soft_edge.gradient = (
			_make_trail_gradient(edge_color)
		)

	else:

		# Original full-length travelling beam
		active_trace.gradient = null
		soft_edge.gradient = null

		active_trace.default_color = beam_color
		soft_edge.default_color = edge_color

	applied_fading_mode = use_fading_trail


# ==================================================
# PROCESS
# ==================================================

func _process(_delta: float) -> void:

	if not is_travelling:
		return

	# Allow toggling while the game is running
	if use_fading_trail != applied_fading_mode:
		_apply_trail_style()

	_update_travelling_beam()


# ==================================================
# FIRE PULSE
# ==================================================

func fire_pulse() -> void:

	if is_active or curve_length <= 0.0:
		return

	is_active = true
	is_travelling = true

	pulse_timer.stop()

	# Choose random travel speed
	current_speed = randf_range(
		minf(min_speed, max_speed),
		maxf(min_speed, max_speed)
	)

	current_speed = maxf(current_speed, 1.0)

	var duration: float = (
		curve_length / current_speed
	)

	# Reset beam
	_clear_beam()

	# Select fading or full trail
	_apply_trail_style()

	_set_beam_opacity(travel_opacity)

	follower.progress = 0.0

	# Reset pulse
	pulse.modulate = beam_color
	pulse.modulate.a = travel_opacity
	pulse.show()

	# Reset terminus
	terminus.hide()
	terminus.modulate = beam_color
	terminus.modulate.a = 0.0

	terminus.scale = Vector2.ONE * (
		beam_width / 30.0
	)

	# Travel at constant random speed
	var travel: Tween = create_tween()

	travel.tween_property(
		follower,
		"progress",
		curve_length,
		duration
	).set_trans(Tween.TRANS_LINEAR)

	await travel.finished

	# Finish travelling
	_update_travelling_beam()

	is_travelling = false
	pulse.hide()

	# Illuminate the entire PCB circuit
	await _illuminate_destination()

	is_active = false

	if auto_fire:
		_schedule_next()


# ==================================================
# UPDATE TRAVELLING BEAM
# ==================================================

func _update_travelling_beam() -> void:

	var head_distance: float = clampf(
		follower.progress,
		0.0,
		curve_length
	)

	var start_distance: float = 0.0

	if use_fading_trail:

		# Only keep the selected trail length
		start_distance = maxf(
			0.0,
			head_distance - trail_length
		)

	# Otherwise start_distance remains zero,
	# revealing the entire travelled distance.

	var points: PackedVector2Array = (
		_get_segment_points(
			start_distance,
			head_distance
		)
	)

	active_trace.points = points
	soft_edge.points = points


# ==================================================
# SAMPLE CURVE SEGMENT
# ==================================================

func _get_segment_points(
	start_distance: float,
	end_distance: float
) -> PackedVector2Array:

	var points := PackedVector2Array()

	var start: float = clampf(
		start_distance,
		0.0,
		curve_length
	)

	var finish: float = clampf(
		end_distance,
		start,
		curve_length
	)

	points.append(
		curve.sample_baked(start, true)
	)

	var spacing: float = maxf(
		sample_spacing,
		0.5
	)

	var distance: float = start + spacing

	while distance < finish:

		points.append(
			curve.sample_baked(distance, true)
		)

		distance += spacing

	points.append(
		curve.sample_baked(finish, true)
	)

	return points


# ==================================================
# REVEAL FULL CIRCUIT AT DESTINATION
# ==================================================

func _reveal_full_circuit() -> void:

	# Both trail modes produce the same
	# full-length circuit when the pulse arrives.

	active_trace.gradient = null
	soft_edge.gradient = null

	active_trace.default_color = beam_color

	var edge_color: Color = beam_color
	edge_color.a = soft_edge_opacity

	soft_edge.default_color = edge_color

	var full_points: PackedVector2Array = (
		_get_segment_points(
			0.0,
			curve_length
		)
	)

	active_trace.points = full_points
	soft_edge.points = full_points


# ==================================================
# SHARED BEAM OPACITY
# ==================================================

func _set_beam_opacity(value: float) -> void:

	var opacity: float = clampf(
		value,
		0.0,
		1.0
	)

	active_trace.modulate.a = opacity
	soft_edge.modulate.a = opacity


# ==================================================
# DESTINATION ILLUMINATION
# ==================================================

func _illuminate_destination() -> void:

	_reveal_full_circuit()

	_set_beam_opacity(travel_opacity)

	# Show terminus
	terminus.show()

	terminus.modulate = beam_color
	terminus.modulate.a = travel_opacity

	var original_size: float = (
		beam_width / 30.0
	)

	terminus.scale = Vector2.ONE * original_size

	# Illuminate complete circuit
	var flash: Tween = create_tween()
	flash.set_parallel(true)

	flash.tween_method(
		_set_beam_opacity,
		travel_opacity,
		1.0,
		maxf(flash_time, 0.01)
	)

	flash.tween_property(
		terminus,
		"modulate:a",
		1.0,
		maxf(flash_time, 0.01)
	)

	flash.tween_property(
		terminus,
		"scale",
		Vector2.ONE * (
			original_size * terminus_scale
		),
		maxf(flash_time, 0.01)
	)

	await flash.finished

	# Hold completed circuit
	if hold_time > 0.0:

		await get_tree().create_timer(
			hold_time
		).timeout

	# Fade complete circuit
	var fade: Tween = create_tween()
	fade.set_parallel(true)

	fade.tween_method(
		_set_beam_opacity,
		1.0,
		0.0,
		maxf(fade_time, 0.01)
	)

	fade.tween_property(
		terminus,
		"modulate:a",
		0.0,
		maxf(fade_time, 0.01)
	)

	await fade.finished

	_clear_beam()
	terminus.hide()


# ==================================================
# CLEAR BEAM
# ==================================================

func _clear_beam() -> void:

	active_trace.clear_points()
	soft_edge.clear_points()

	active_trace.gradient = null
	soft_edge.gradient = null

	_set_beam_opacity(0.0)


# ==================================================
# AUTOMATIC FIRING
# ==================================================

func _schedule_next() -> void:

	if not auto_fire:
		return

	pulse_timer.start(
		randf_range(
			minf(min_delay, max_delay),
			maxf(min_delay, max_delay)
		)
	)


func _on_timer_timeout() -> void:

	if auto_fire and not is_active:
		fire_pulse()


# ==================================================
# CRISP PULSE TEXTURE
# ==================================================

func _make_crisp_circle_texture() -> Texture2D:

	var size: int = 32

	var image: Image = Image.create_empty(
		size,
		size,
		false,
		Image.FORMAT_RGBA8
	)

	var centre := Vector2(16.0, 16.0)
	var radius: float = 15.0

	for y in range(size):
		for x in range(size):

			var position := Vector2(
				float(x) + 0.5,
				float(y) + 0.5
			)

			var distance: float = (
				position.distance_to(centre)
			)

			var alpha: float = clampf(
				radius - distance,
				0.0,
				1.0
			)

			image.set_pixel(
				x,
				y,
				Color(1.0, 1.0, 1.0, alpha)
			)

	return ImageTexture.create_from_image(image)
