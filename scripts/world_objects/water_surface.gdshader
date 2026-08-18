shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// Shared surface material for Lake (see its own .tscn) -- real vertex-level
// wave displacement (two overlapping sine waves, different direction/
// speed/phase, computed in world space and converted back to the mesh's
// own local space so the same shader looks correct regardless of a given
// water body's own squashed non-uniform scale) plus the existing animated
// ripple/sparkle color and a fresnel-ish edge brighten, so standing water
// reads as a genuinely moving surface rather than a static tinted disc
// with just a scrolling color pattern painted on it (see feature request:
// "water still looks a bit off... a shader on the surface to create
// waves").

uniform vec4 water_color : source_color = vec4(0.25, 0.55, 0.85, 0.85);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.08;
uniform float wave_amplitude : hint_range(0.0, 0.5) = 0.12;

varying float wave_height;

void vertex() {
	// Displacement is computed in world space (not the mesh's own local
	// space) specifically so `wave_amplitude` means the same physical wave
	// height regardless of a given water body's own local Y-scale (Lake
	// squashes a unit sphere to 0.08 in Y) -- doing this in local space
	// would make the same amplitude read as either invisible or absurdly
	// large depending on which water body it's applied to.
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave_a = sin(world_pos.x * 1.1 + world_pos.z * 0.7 + TIME * 1.6);
	float wave_b = sin(world_pos.x * 0.5 - world_pos.z * 1.3 + TIME * 1.1 + 1.7);
	float wave = (wave_a + wave_b * 0.6) * wave_amplitude;
	wave_height = wave;
	world_pos.y += wave;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * 6.0;
	float ripple = sin(uv.x + TIME * 1.3) * 0.5 + sin(uv.y * 1.3 - TIME * 1.7) * 0.5;
	float sparkle = smoothstep(0.9, 1.0, sin(uv.x * 3.1 + TIME * 2.0) * sin(uv.y * 2.7 - TIME * 1.5));
	// The wave height doubles as a cheap brightness cue -- a crest catches
	// a little more light than a trough, reinforcing the vertex motion
	// visually without needing a fully recomputed per-fragment normal.
	vec3 base = water_color.rgb + ripple * 0.025 + wave_height * 0.06;
	// NORMAL here is Godot's own built-in, already correctly in view space
	// by the time fragment() runs -- no need to pass anything through
	// manually, unlike wave_height which genuinely only exists as
	// something vertex() computes.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 albedo = base + vec3(sparkle) * 0.45 + vec3(0.6, 0.75, 0.85) * fresnel * 0.4;
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	METALLIC = 0.35;
	ALPHA = water_color.a;
}
