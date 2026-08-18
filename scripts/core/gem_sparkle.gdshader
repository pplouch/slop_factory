shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// Shared material for any resource-node "accent" mesh originally authored
// with StandardMaterial3D.emission_enabled = true (ore nuggets/veins/
// shards/facets, ice crystal shards, obsidian embers, Slopium's own
// glowing body) -- see GemSparkle, which swaps that flag directly into
// this shader's uniforms. Adds a traveling specular glint (view-angle
// dependent, the classic "catches the light as you look at it" gem cue)
// plus a slow emissive pulse on top of the original static glow -- both
// far more visible now that World's Environment has Glow enabled (see
// world.gd._configure_environment).

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_energy : hint_range(0.0, 4.0) = 0.3;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.25;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = albedo_color.rgb;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	ALPHA = alpha;

	float pulse = sin(TIME * 1.6 + VERTEX.x * 3.0 + VERTEX.y * 2.0) * 0.5 + 0.5;
	// View-angle-dependent glint (NORMAL/VIEW are both view-space in a
	// spatial fragment shader) modulated by a slow position-based sweep, so
	// the glint isn't just a static rim highlight but seems to travel
	// across the surface over time.
	float rim = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 6.0);
	float sweep = sin(TIME * 2.2 + VERTEX.x * 6.0 - VERTEX.z * 6.0) * 0.5 + 0.5;
	EMISSION = emission_color.rgb * emission_energy * (0.6 + 0.4 * pulse) + emission_color.rgb * rim * sweep * 1.5;
}
