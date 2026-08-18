shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Shared material for PropScatter's foliage MultiMeshes (grass/fern/reed/
// frost-tuft blade clusters -- see PropScatter._build_blade_cluster_mesh).
// cull_disabled since blades are single-sided triangles splayed around Y,
// so roughly half of them would otherwise face away from the camera.
// The only behavior beyond a plain vertex-colored surface is a gentle wind
// sway: each blade's local VERTEX.y already ranges from 0 at its planted
// base to its own height at the tip (see the mesh builder), so using it
// directly as the bend-blend factor bends tips while keeping bases pinned,
// with no extra per-vertex data needed.

uniform float sway_strength : hint_range(0.0, 1.0) = 0.16;
uniform float sway_speed = 1.6;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = VERTEX.y;
	float sway = sin(TIME * sway_speed + world_pos.x * 0.6 + world_pos.z * 0.6) * sway_strength * bend;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
