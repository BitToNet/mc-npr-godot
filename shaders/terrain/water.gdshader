shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx, diffuse_lambert;
// ---------------------------------------------------------------------------
// Water — clear, semi transparent, banded like everything else.
// Vertex colour channels are baked at build time by water.gd:
//   rgb = shore..depth gradient, a = foam mask,
// and UV2 carries (rim_mask, wave_phase).
// ---------------------------------------------------------------------------

uniform sampler2D ramp : filter_nearest, repeat_disable;

uniform vec4 shallow_color : source_color = vec4(0.62, 0.96, 0.93, 1.0);
uniform vec4 deep_color : source_color = vec4(0.10, 0.60, 0.86, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 0.98, 1.0);
uniform float surface_alpha : hint_range(0.0, 1.0) = 0.86;
uniform float wave_height : hint_range(0.0, 0.6) = 0.075;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.85;
uniform float rim_wave : hint_range(0.0, 1.0) = 0.16;
uniform float shade_min : hint_range(0.0, 1.0) = 0.62;
uniform float sparkle : hint_range(0.0, 1.0) = 0.0;

// S0.6: see shaders/toon.gdshader — the builtin TIME is replaced by the global
// uniform written every frame by scripts/render_clock.gd, so that a screenshot
// is byte-reproducible and the `B-` visual gate becomes usable.
global uniform float render_time;

varying vec3 v_color;
varying float v_foam;
varying float v_rim;
varying float v_wave;

void vertex() {
	v_color = COLOR.rgb;
	v_foam = COLOR.a;
	v_rim = UV2.x;
	v_wave = UV2.y;

	float t = render_time * wave_speed;
	// broad rolling swell + a finer chop + a bobbing rim so the tile edge breathes
	float swell = sin(t * 1.1 + VERTEX.x * 0.22 + VERTEX.z * 0.16);
	float chop = sin(t * 2.3 + VERTEX.x * 0.75 - VERTEX.z * 0.55) * 0.45;
	float edge = sin(t * 1.6 + v_rim * 12.0) * v_rim;
	VERTEX.y += (swell + chop) * wave_height + edge * rim_wave;
}

void fragment() {
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, v_color.r);
	// hard cel band on the water body so it matches the terrain language
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float band = texture(ramp, vec2(clamp(ndv * 0.7 + 0.35, 0.0, 0.999), 0.5)).r;
	base *= mix(shade_min, 1.12, band);
	// a little extra body so the water stays vivid over the pale sea floor
	base = mix(base, base * 1.25 + vec3(0.02), 0.55);

	// foam line where the water meets the beach
	float foam = smoothstep(0.35, 0.95, v_foam + sin(render_time * 2.4 + v_wave * 6.0) * 0.12);
	base = mix(base, foam_color.rgb, foam * 0.85);

	ALBEDO = base;
	ALPHA = clamp(surface_alpha + foam * 0.18, 0.0, 1.0);
	ROUGHNESS = 0.08;

	if (sparkle > 0.001) {
		// soft twinkle only: a spatial term here reads as painted stripes
		float s = sin(render_time * 1.7 + v_wave * 0.6) * 0.5 + 0.5;
		EMISSION += vec3(1.0, 1.0, 1.0) * pow(s, 6.0) * sparkle * 0.12;
	}
}

void light() {
	// (no early return: the light processor disallows it)
	vec3 h = normalize(normalize(LIGHT) + normalize(VIEW));
	float sp = pow(max(dot(normalize(NORMAL), h), 0.0), 64.0);
	sp = smoothstep(0.30, 0.42, sp + UV2.x * 0.1);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * (0.62 + 0.42 * sp) * 1.35 / PI;
	SPECULAR_LIGHT += sp * LIGHT_COLOR * ATTENUATION * 0.35;
}
