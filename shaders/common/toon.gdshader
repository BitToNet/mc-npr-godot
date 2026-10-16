shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx;
// ---------------------------------------------------------------------------
// Toon — the Godot stand-in for MeshToonMaterial.
// * every light is quantised through a dynamically generated 3-band grayscale
//   gradient map (see Style.build_ramp), giving 2/3-step hard cel shading.
// * the mesh is authored non-indexed with flat per-face normals AND per-face
//   vertex colours, so every triangle reads as one crisp colour facet.
// ---------------------------------------------------------------------------

uniform sampler2D ramp : filter_nearest, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);   // alpha unused: keep opaque

uniform float shade_min : hint_range(0.0, 1.0) = 0.42;   // darkest cel band
uniform float shade_max : hint_range(0.0, 1.0) = 1.0;    // lit cel band
uniform float shade_shift : hint_range(-0.6, 0.6) = 0.0; // push the terminator
uniform float exposure_gain : hint_range(0.0, 3.0) = 1.0;

uniform float rim_amount : hint_range(0.0, 1.5) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.98, 0.88, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.4;

uniform float spec_amount : hint_range(0.0, 1.0) = 0.0;
uniform float spec_sharp : hint_range(2.0, 256.0) = 48.0;
uniform vec4 spec_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float emission_amount : hint_range(0.0, 2.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float wind_strength = 0.0;   // sway amplitude in metres (multiplied by INSTANCE_CUSTOM.y)
uniform float wind_speed = 1.0;
uniform float wind_top_bias : hint_range(0.0, 4.0) = 1.0;

// S0.6: the builtin TIME could not be frozen, which made every screenshot differ
// from the next one by 1.6 %–5.7 % of its pixels and left the whole `B-` visual
// gate unusable.  This global uniform is written once per frame by
// scripts/render_clock.gd, so frame N always means the same instant.
// (Global uniforms take their default from project.godot's [shader_globals].)
global uniform float render_time;

varying vec3 v_color;
varying float v_wind_mask;
varying float v_instance_tint;

void vertex() {
	v_color = COLOR.rgb;
	v_instance_tint = 1.0 + INSTANCE_CUSTOM.z;
	// INSTANCE_CUSTOM: x = phase offset, y = sway scale, z = per-instance tint, w = spare
	float wind = INSTANCE_CUSTOM.y;
	v_wind_mask = 0.0;
	if (wind_strength > 0.0001 && wind > 0.0001) {
		float mask = clamp(VERTEX.y * wind_top_bias, 0.0, 1.0);
		mask *= mask;
		v_wind_mask = mask;
		float phase = INSTANCE_CUSTOM.x * 6.28318;
		float t = render_time * wind_speed;
		float s = sin(t * 1.9 + phase + VERTEX.x * 0.5 + VERTEX.z * 0.35);
		float c = cos(t * 1.35 + phase * 1.7 + VERTEX.z * 0.6);
		float amp = wind_strength * wind * mask;
		VERTEX.x += s * amp;
		VERTEX.z += c * amp * 0.7;
		VERTEX.y -= abs(s) * amp * 0.18;
	}
}

void fragment() {
	// NOTE: never write ALPHA here.  Godot classifies a shader that writes
	// ALPHA as transparent, and transparent materials do not write depth —
	// which would let the inverted-hull outline paint over its own object.
	ALBEDO = albedo_tint.rgb * v_color * v_instance_tint;
	if (emission_amount > 0.001) {
		EMISSION = emission_color.rgb * emission_amount;
	}
}

void light() {
	// ---- quantised diffuse -------------------------------------------------
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float u = clamp(ndl * 0.5 + 0.5 + shade_shift, 0.0, 0.999);
	float band = texture(ramp, vec2(u, 0.5)).r;
	float shade = mix(shade_min, shade_max, band) * exposure_gain;
	DIFFUSE_LIGHT += shade * ALBEDO * LIGHT_COLOR * ATTENUATION / PI;

	// ---- hard cel specular -------------------------------------------------
	if (spec_amount > 0.001) {
		vec3 h = normalize(normalize(LIGHT) + normalize(VIEW));
		float sp = pow(max(dot(normalize(NORMAL), h), 0.0), spec_sharp);
		sp = smoothstep(0.45, 0.50, sp);
		SPECULAR_LIGHT += sp * spec_amount * spec_color.rgb * LIGHT_COLOR * ATTENUATION;
	}

	// ---- silhouette rim (the "figurine edge catch") ------------------------
	if (rim_amount > 0.001) {
		float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float rim = pow(1.0 - ndv, rim_power) * rim_amount;
		DIFFUSE_LIGHT += rim * rim_color.rgb * LIGHT_COLOR * ATTENUATION * 0.6;
	}
}
