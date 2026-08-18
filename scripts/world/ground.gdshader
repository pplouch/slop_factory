shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// Ground material for Chunk's terrain mesh. Mostly a plain textured/vertex-
// tinted surface (equivalent to the StandardMaterial3D this replaces -- see
// Chunk._build_ground_material), plus a per-pixel normal map (derived from
// the same noise field the albedo texture's mottling uses -- without this
// the ground lit as a perfectly flat plane with a painted-on color pattern)
// and the water rendering: a dedicated, non-tiling per-chunk water_tint/
// water_wave texture pair (see Chunk.WATER_MASK_SIZE) sampled directly from
// this mesh's own local VERTEX position rather than through vertex color --
// vertex color aliased badly at the water's edge (see feature request:
// "coastlines... unorganic squared coast") since it could only ever be as
// fine as the mesh's own vertex spacing. Water itself gets small, flat foam
// right at the coastline (shore mask) and progressively bigger analytic
// waves (a tangent-space normal perturbation, not real geometry -- this
// mesh isn't dense enough to resolve an actual wave shape) the farther a
// pixel is from shore (depth mask), the opposite of the old setup where the
// shoreline was the only place anything visibly moved (see feature request:
// "on shorelines, create small flat waves that fit the coast shape... add
// waves farther from the coast").

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D water_tint_texture : source_color, filter_linear_mipmap;
uniform sampler2D water_wave_texture : filter_linear_mipmap;
uniform vec2 uv_scale = vec2(4.0, 4.0);
uniform float normal_map_strength : hint_range(0.0, 2.0) = 1.0;
uniform float chunk_size = 25.0;

varying vec3 world_pos;
// Maps this mesh's own local VERTEX.xz (unaffected by the chunk node's own
// world transform) onto 0..1 across the whole chunk -- Chunk's water-mask
// bake loop uses this exact same local-space convention, so one texture
// lines up exactly once onto one chunk rather than needing to go through
// the grain texture's own tiled UV.
varying vec2 mask_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mask_uv = VERTEX.xz / chunk_size + 0.5;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 tex_sample = texture(albedo_texture, uv);

	vec4 water_tint = texture(water_tint_texture, mask_uv);
	vec3 wave_data = texture(water_wave_texture, mask_uv).rgb;
	float shore = wave_data.r;
	float depth = wave_data.g;
	// Only nonzero where Biomes.hazard_sample_at baked real lava into this
	// pixel (see Chunk._build_ground_material) -- 0 everywhere else
	// (regular water, oil, dry land), so every use below is a no-op
	// anywhere but an actual lava feature.
	float lava_glow = wave_data.b;

	vec3 base = tex_sample.rgb * COLOR.rgb * water_tint.rgb;

	// Small, flat foam right at the coastline -- three overlapping
	// traveling waves (different direction/speed/phase) read as an
	// irregular lapping motion instead of one uniform pulse, kept subtle
	// (see feature request: "small flat waves that fit the coast shape").
	float wave_a = sin(world_pos.x * 0.9 + world_pos.z * 0.6 - TIME * 2.2);
	float wave_b = sin(world_pos.x * 0.5 - world_pos.z * 0.8 - TIME * 1.4 + 1.7);
	float wave_c = sin(world_pos.x * 1.6 + world_pos.z * 1.3 - TIME * 3.1 + 0.6);
	float foam_wave = (wave_a + wave_b + wave_c * 0.6) * 0.19 + 0.5;
	float foam = shore * (0.3 + 0.4 * foam_wave);

	vec3 albedo = mix(base, vec3(0.95, 0.98, 1.0), foam * 0.85);

	// Base tangent-space slope from the mottled ground texture's own normal
	// map (unchanged in spirit from before, just decoded by hand here so it
	// can be combined with the wave slope below rather than handed straight
	// to NORMAL_MAP/NORMAL_MAP_DEPTH).
	vec3 base_n = texture(normal_texture, uv).rgb * 2.0 - 1.0;
	vec2 slope = base_n.xy * normal_map_strength;

	// Bigger waves the farther into open water a pixel is: an analytic
	// tangent-space slope (partial derivatives of two traveling sine waves)
	// added on top of the texture-derived slope, amplitude scaled by
	// `depth` (0 right at the shoreline, saturating well into open water) --
	// this mesh's own vertex spacing (see Chunk.SUBDIVISIONS) isn't dense
	// enough to resolve an actual displaced wave shape without looking
	// faceted, so this fakes the bump via lighting instead, the same trick
	// the base normal map already uses.
	float deep_amp = depth * 0.9;
	float phase_a = world_pos.x * 0.5 + world_pos.z * 0.3 - TIME * 1.1;
	float phase_b = world_pos.x * 0.3 - world_pos.z * 0.6 + TIME * 0.8 + 2.1;
	float cos_a = cos(phase_a);
	float cos_b = cos(phase_b);
	vec2 wave_slope = deep_amp * vec2(0.5 * cos_a + 0.3 * cos_b, 0.3 * cos_a - 0.6 * cos_b);
	slope += wave_slope;

	vec3 combined_n = normalize(vec3(slope, 1.0));
	NORMAL_MAP = combined_n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Volcanic-only: Chunk._build_ground_material doubles the texture's
	// alpha channel as an "ember" mask on scattered cooled-lava-crack
	// pixels -- 0 everywhere on every other biome's texture, so this is a
	// visual no-op anywhere but volcanic ground.
	float ember_mask = tex_sample.a;
	float ember_pulse = sin(TIME * 3.0 + world_pos.x * 1.2 + world_pos.z * 1.3) * 0.5 + 0.5;
	vec3 ember_color = vec3(1.0, 0.35, 0.05);
	albedo = mix(albedo, ember_color, ember_mask * (0.4 + 0.3 * ember_pulse));
	// Lava reuses the ground texture's own ember color/pulse (same "glowing
	// volcanic crack" vibe, see feature request: "add lava lakes/rivers") --
	// additively mixed toward the glow color rather than replacing albedo
	// outright, since water_tint already carries lava's own molten-orange
	// tint from Biomes.hazard_sample_at.
	albedo = mix(albedo, ember_color, lava_glow * (0.5 + 0.4 * ember_pulse));

	float water_sheen = max(foam, depth * 0.5);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.95, 0.35, water_sheen);
	SPECULAR = mix(0.3, 0.9, water_sheen);
	EMISSION = ember_color * (ember_mask * (0.5 + 1.0 * ember_pulse) + lava_glow * (0.6 + 0.6 * ember_pulse));
}
