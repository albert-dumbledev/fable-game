shader_type spatial;
// Procedural stone-tile arena floor: large tiles with darker grout and
// per-tile brightness variation, plus a pulsing emissive rune circle at
// arena center. World-space XZ so tiling is independent of mesh UVs.
// The grid contrast is deliberate — ground detail is what makes movement
// (especially dashing) read as fast in first person.

uniform vec3 tile_color : source_color = vec3(0.30, 0.29, 0.33);
uniform vec3 grout_color : source_color = vec3(0.16, 0.15, 0.19);
uniform float tile_size = 4.0;
uniform float grout_width = 0.10;
uniform vec3 rune_color : source_color = vec3(1.0, 0.70, 0.28);
uniform float rune_intensity = 1.8;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float tile_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 xz = world_pos.xz;
	vec2 cell = floor(xz / tile_size);
	vec2 local_uv = fract(xz / tile_size);

	float variation = mix(0.82, 1.12, tile_hash(cell));
	vec2 edge = min(local_uv, 1.0 - local_uv) * tile_size;
	float grout = 1.0 - smoothstep(grout_width * 0.5, grout_width, min(edge.x, edge.y));
	vec3 albedo = mix(tile_color * variation, grout_color, grout);

	// Twin concentric rings at spawn, breathing slowly.
	float r = length(xz);
	float outer_ring = 1.0 - smoothstep(0.05, 0.16, abs(r - 3.4));
	float inner_ring = 1.0 - smoothstep(0.03, 0.10, abs(r - 1.9));
	float pulse = 0.7 + 0.3 * sin(TIME * 1.3);
	float rune = max(outer_ring, inner_ring * 0.7) * pulse;

	ALBEDO = albedo;
	ROUGHNESS = mix(0.92, 1.0, grout);
	EMISSION = rune_color * rune * rune_intensity;
}
