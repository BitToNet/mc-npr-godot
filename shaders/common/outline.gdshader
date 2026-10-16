shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never, depth_test_default;
// ---------------------------------------------------------------------------
// Outline — classic inverted hull.
// The mesh carries FLAT normals (for the faceted cel look) in NORMAL and the
// matching SMOOTH/area-weighted normals in the TANGENT slot.  The hull is
// grown along those smooth normals so the silhouette stays crack free.
// Rendered front-face-culled on top of every toon material via `next_pass`.
//
// `depth_draw_never` is load bearing, not a micro-optimisation
// -----------------------------------------------------------
// The ink hull is the surface pushed OUT along its normal, and Godot renders a
// material's `next_pass` into the directional shadow map as well.  So the
// shadow map was recording a caster floating a few centimetres above the very
// terrain it belongs to, and the terrain then shadowed itself -- which showed
// up as dotted dark dashes crawling over the snow fields and the meadows and
// read as dirt rather than as line work.  Refusing to write depth keeps the ink
// out of the shadow map, while the base toon pass has already written the
// surface depth, so the hull still depth-tests correctly against its own object
// and the silhouette ink is completely unaffected.
// ---------------------------------------------------------------------------

uniform vec4 ink : source_color = vec4(0.074, 0.066, 0.105, 1.0);
uniform float width = 2.0;           // ink thickness in *pixels*
uniform float width_scale = 1.0;     // global art-direction multiplier
uniform float pixel_span = 0.04;     // world units covered by one screen pixel
uniform float enabled = 1.0;

void vertex() {
	vec3 n = NORMAL;
	// Prefer the smooth normal baked into the tangent slot when it exists.
	if (dot(TANGENT, TANGENT) > 0.0001) {
		n = TANGENT;
	}
	// Constant thickness on screen: the camera publishes how much world space
	// one pixel covers, and we divide by the object's own scale so a scaled
	// prop keeps exactly the same ink weight.
	float s = (length(MODEL_MATRIX[0].xyz) + length(MODEL_MATRIX[1].xyz) + length(MODEL_MATRIX[2].xyz)) / 3.0;
	s = max(s, 0.0001);
	vec3 nrm = normalize(n);
	VERTEX += nrm * (width * width_scale * pixel_span / s);
}

void fragment() {
	if (enabled < 0.5) {
		discard;
	}
	// no ALPHA here either: the ink pass must stay opaque so the depth buffer
	// keeps it behind the object it is outlining.
	ALBEDO = ink.rgb;
}