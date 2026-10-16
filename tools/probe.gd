extends SceneTree
## API probe: verifies that every engine call used by the project actually
## exists in the installed Godot build.  Run with:
##   Godot --headless --path . --script res://tools/probe.gd

func _dump_class(cn: String, names: PackedStringArray) -> void:
	var props := {}
	for p in ClassDB.class_get_property_list(cn, true):
		props[String(p["name"])] = true
	var meths := {}
	for m in ClassDB.class_get_method_list(cn, true):
		meths[String(m["name"])] = true
	var miss_props: Array[String] = []
	var miss_meths: Array[String] = []
	var ok: Array[String] = []
	for n in names:
		if props.has(n):
			ok.append("P:" + n)
		elif meths.has(n):
			ok.append("M:" + n)
		else:
			if n.begins_with("_"):
				miss_props.append(n)
			else:
				miss_props.append(n)
	print("=== ", cn)
	print("  OK   : ", ", ".join(ok))
	print("  MISS : ", ", ".join(miss_props))

func _consts(cn: String) -> void:
	var out: Array[String] = []
	for c in ClassDB.class_get_integer_constant_list(cn, true):
		out.append(String(c))
	print("=== consts ", cn, " : ", ", ".join(out))

func _initialize() -> void:
	print("Godot ", Engine.get_version_info())
	_dump_class("SurfaceTool", PackedStringArray([
		"begin", "add_vertex", "set_normal", "set_color", "set_uv", "set_tangent",
		"set_custom", "set_custom_format", "generate_normals", "set_smooth_group",
		"set_material", "commit", "index", "deindex", "generate_tangents", "clear",
		"add_triangle_fan", "set_uv2", "create_from"]))
	_dump_class("Mesh", PackedStringArray([
		"surface_get_arrays", "surface_set_material", "surface_get_material", "get_surface_count",
		"create_convex_shape", "get_aabb", "surface_get_format", "create_trimesh_shape"]))
	_dump_class("ArrayMesh", PackedStringArray(["add_surface_from_arrays", "clear_surfaces", "surface_update_vertex_region"]))
	_dump_class("FastNoiseLite", PackedStringArray([
		"noise_type", "seed", "frequency", "fractal_type", "fractal_octaves",
		"fractal_lacunarity", "fractal_gain", "fractal_weighted_strength",
		"fractal_ping_pong_strength", "domain_warp_enabled", "domain_warp_amplitude",
		"domain_warp_frequency", "domain_warp_fractal_octaves", "get_noise_2d", "get_noise_3d",
		"get_image", "cellular_distance_function", "cellular_return_type"]))
	_dump_class("Gradient", PackedStringArray([
		"offsets", "colors", "interpolation_mode", "add_point", "set_offset", "set_color",
		"sample", "remove_point"]))
	_dump_class("GradientTexture1D", PackedStringArray(["gradient", "width", "use_hdr"]))
	_dump_class("Environment", PackedStringArray([
		"background_mode", "background_color", "sky", "ambient_light_source", "ambient_light_color",
		"ambient_light_energy", "ambient_light_sky_contribution", "fog_enabled", "fog_light_color",
		"fog_density", "fog_sky_affect", "tonemap_mode", "tonemap_exposure", "tonemap_white",
		"adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation",
		"glow_enabled", "glow_intensity", "glow_bloom", "dof_blur_far_enabled", "dof_blur_far_distance",
		"dof_blur_far_transition", "dof_blur_near_enabled", "dof_blur_near_distance",
		"dof_blur_near_transition", "dof_blur_amount", "ssao_enabled", "sdfgi_enabled",
		"volumetric_fog_enabled", "reflected_light_source", "default_environment"]))
	_dump_class("DirectionalLight3D", PackedStringArray([
		"light_color", "light_energy", "light_indirect_energy", "light_specular", "shadow_enabled",
		"shadow_bias", "shadow_normal_bias", "shadow_blur", "shadow_opacity", "shadow_caster_mask",
		"directional_shadow_mode", "directional_shadow_split_1", "directional_shadow_blend_splits",
		"directional_shadow_max_distance", "directional_shadow_fade_start", "sky_mode",
		"light_angular_distance", "light_negative", "rotation_degrees", "shadow_filter"]))
	_dump_class("Camera3D", PackedStringArray([
		"projection", "size", "near", "far", "fov", "attributes", "current", "make_current",
		"project_ray_normal", "keep_aspect", "h_offset", "v_offset", "cull_mask", "environment"]))
	_dump_class("CameraAttributesPractical", PackedStringArray([
		"dof_blur_far_enabled", "dof_blur_far_distance", "dof_blur_far_transition",
		"dof_blur_near_enabled", "dof_blur_near_distance", "dof_blur_near_transition",
		"dof_blur_amount", "auto_exposure_enabled"]))
	_dump_class("MultiMesh", PackedStringArray([
		"transform_format", "instance_count", "visible_instance_count", "mesh", "use_colors",
		"use_custom_data", "set_instance_transform", "set_instance_color", "set_instance_custom_data",
		"set_instance_transform_2d", "buffer"]))
	_dump_class("MultiMeshInstance3D", PackedStringArray(["multimesh", "material_override", "cast_shadow", "material_overlay"]))
	_dump_class("MeshInstance3D", PackedStringArray(["mesh", "material_override", "cast_shadow", "extra_cull_margin", "skeleton"]))
	_dump_class("ProceduralSkyMaterial", PackedStringArray([
		"sky_top_color", "sky_horizon_color", "sky_curve", "sky_energy_multiplier",
		"ground_bottom_color", "ground_horizon_color", "ground_curve", "ground_energy_multiplier",
		"sun_angle_max", "sun_curve", "use_debanding", "energy_multiplier"]))
	_dump_class("SystemFont", PackedStringArray(["font_names", "font_italic", "font_weight", "font_stretch", "allow_system_fallback", "antialiasing"]))
	_dump_class("StyleBoxFlat", PackedStringArray([
		"bg_color", "border_width_left", "border_width_top", "border_width_right", "border_width_bottom",
		"border_color", "corner_radius_top_left", "corner_radius_bottom_right", "shadow_color",
		"shadow_size", "shadow_offset", "anti_aliasing", "draw_center", "content_margin_left",
		"content_margin_top", "expand_margin_left", "skew"]))
	_dump_class("Theme", PackedStringArray([
		"set_color", "set_constant", "set_font", "set_font_size", "set_stylebox", "default_font",
		"default_font_size", "set_type_variation"]))
	_dump_class("ShaderMaterial", PackedStringArray(["shader", "set_shader_parameter", "get_shader_parameter", "next_pass"]))
	_dump_class("Material", PackedStringArray(["next_pass", "render_priority"]))
	_dump_class("Mesh", PackedStringArray(["ARRAY_CUSTOM_RGBA_FLOAT"]))
	_consts("Mesh")
	_consts("SurfaceTool")
	_consts("MultiMesh")
	_consts("Light3D")
	_consts("BaseMaterial3D")
	print("=== project settings present ===")
	for k in [
		"rendering/lights_and_shadows/directional_shadow/size",
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
		"rendering/lights_and_shadows/directional_shadow/16_bits",
		"rendering/anti_aliasing/quality/msaa_3d",
		"rendering/anti_aliasing/quality/screen_space_aa",
		"rendering/environment/defaults/default_environment",
		"rendering/textures/default_filters/use_nearest_mipmap_filter",
		"rendering/limits/time/time_rollover_secs",
	]:
		print("  ", k, " -> ", ProjectSettings.get_setting(k, "<unset>"))
	print("=== InputEventKey props ===")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	print("  physical_keycode ok: ", ev.as_text())
	print("PROBE DONE")
	quit()