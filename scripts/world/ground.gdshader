shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// Ground material for Chunk's terrain mesh. Mostly a plain textured/vertex-
// tinted surface (equivalent to the StandardMaterial3D this replaces -- see
// Chunk._build_ground_material), plus two added effects: a per-pixel normal
// map (derived from the same noise field the albedo texture's mottling
// uses, see Chunk._build_ground_material -- without this the ground lit as
// a perfectly flat plane with a painted-on color pattern, reading as flat/
// low-detail regardless of the color texture's own sharpness) and an
// animated foam/shimmer band right at the shoreline, driven by a per-vertex
// "shore mask" Chunk bakes into vertex-color alpha (see
// Biomes.shore_factor_at) -- 0 everywhere except a narrow band peaking
// exactly at the land/water noise threshold on either side, so the
// animation only ever shows up where the existing shore/shallow-water tint
// already reads as "the water's edge".

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(4.0, 4.0);
uniform float normal_map_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 tex_sample = texture(albedo_texture, uv);
	vec3 base = tex_sample.rgb * COLOR.rgb;
	NORMAL_MAP = texture(normal_texture, uv).rgb;
	NORMAL_MAP_DEPTH = normal_map_strength;

	// Three overlapping traveling waves (different direction/speed/phase)
	// read as an irregular lapping/foamy motion instead of one uniform
	// pulse -- the third, higher-frequency layer specifically breaks up
	// what would otherwise be an obviously-periodic 2-wave interference
	// pattern (see feature request: "improve the shoreline appearance").
	float shore = COLOR.a;
	float wave_a = sin(world_pos.x * 0.9 + world_pos.z * 0.6 - TIME * 2.2);
	float wave_b = sin(world_pos.x * 0.5 - world_pos.z * 0.8 - TIME * 1.4 + 1.7);
	float wave_c = sin(world_pos.x * 1.6 + world_pos.z * 1.3 - TIME * 3.1 + 0.6);
	float foam_wave = (wave_a + wave_b + wave_c * 0.6) * 0.19 + 0.5;
	float foam = shore * (0.3 + 0.7 * foam_wave);

	vec3 albedo = mix(base, vec3(0.95, 0.98, 1.0), foam * 0.9);

	// Volcanic-only: Chunk._build_ground_material doubles the texture's
	// alpha channel as an "ember" mask on scattered cooled-lava-crack
	// pixels -- 0 everywhere on every other biome's texture, so this is a
	// visual no-op anywhere but volcanic ground.
	float ember_mask = tex_sample.a;
	float ember_pulse = sin(TIME * 3.0 + world_pos.x * 1.2 + world_pos.z * 1.3) * 0.5 + 0.5;
	vec3 ember_color = vec3(1.0, 0.35, 0.05);
	albedo = mix(albedo, ember_color, ember_mask * (0.4 + 0.3 * ember_pulse));

	ALBEDO = albedo;
	ROUGHNESS = mix(0.95, 0.5, foam);
	SPECULAR = mix(0.3, 0.9, foam);
	EMISSION = ember_color * ember_mask * (0.5 + 1.0 * ember_pulse);
}
