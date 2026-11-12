
shader_type canvas_item;
render_mode unshaded;


// ============================================
// COLOURS
// ============================================

uniform vec4 center_color : source_color =
    vec4(1.0, 1.0, 1.0, 1.0);

uniform vec4 edge_color : source_color =
    vec4(0.72, 0.85, 0.93, 1.0);


// ============================================
// GRADIENT
// ============================================

uniform float white_radius :
    hint_range(0.0, 0.8) = 0.18;

uniform float blue_radius :
    hint_range(0.1, 1.5) = 0.72;

uniform float blue_strength :
    hint_range(0.0, 1.0) = 0.75;


// ============================================
// CRT BUBBLE
// ============================================

uniform float bubble_strength :
    hint_range(0.0, 0.7) = 0.15;

uniform float glass_highlight :
    hint_range(0.0, 0.2) = 0.025;

uniform float rim_strength :
    hint_range(0.0, 0.3) = 0.02;


// ============================================
// SLOW BREATHING
// ============================================

uniform float breathe_speed :
    hint_range(0.0, 2.0) = 0.12;

uniform float breathe_amount :
    hint_range(0.0, 0.2) = 0.025;


// ============================================
// SUBTLE DRIFT
// ============================================

uniform float drift_speed :
    hint_range(0.0, 2.0) = 0.15;

uniform float drift_amount :
    hint_range(0.0, 0.08) = 0.006;


// ============================================
// FRAGMENT
// ============================================

void fragment() {

    float breathing = sin(
        TIME * breathe_speed * 6.2831853
    );

    float animated_strength = clamp(
        blue_strength * (
            1.0 + breathing * breathe_amount
        ),
        0.0,
        1.0
    );

    vec2 drift = vec2(
        sin(TIME * drift_speed),
        cos(TIME * drift_speed * 0.83)
    ) * drift_amount;

    vec2 position = UV - vec2(0.5) - drift;

    // Subtle CRT curvature
    float radius_squared = dot(
        position,
        position
    );

    vec2 curved_position = position * (
        1.0 + bubble_strength
        * radius_squared * 2.0
    );

    float distance_from_center = length(
        curved_position
    );

    float blend = smoothstep(
        white_radius,
        max(white_radius + 0.001, blue_radius),
        distance_from_center
    );

    blend *= animated_strength;

    vec3 final_color = mix(
        center_color.rgb,
        edge_color.rgb,
        clamp(blend, 0.0, 1.0)
    );

    // Very faint glass sheen
    float glass = 1.0 - smoothstep(
        0.0,
        0.78,
        length(position)
    );

    final_color += vec3(
        glass_highlight * glass
    );

    // Very subtle rim tint
    float edge_distance = min(
        min(UV.x, 1.0 - UV.x),
        min(UV.y, 1.0 - UV.y)
    );

    float rim = 1.0 - smoothstep(
        0.0,
        0.10,
        edge_distance
    );

    final_color = mix(
        final_color,
        edge_color.rgb,
        rim * rim_strength
    );

    COLOR = vec4(
        clamp(final_color, 0.0, 1.0),
        1.0
    );
}
