shader_type canvas_item;
// Radial anamorphic dash streaks: thin lines rushing from screen center
// toward the edges, gated per angular segment so only a scattering show at
// once, reshuffled a few times over the burst. Intensity is driven from
// SpeedLines (0 = invisible); the whole effect lives in the alpha channel.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(0.75, 0.85, 1.0, 1.0);

float seg_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	// Aspect-correct so streak reach is radially even.
	centered.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(centered);
	float angle = atan(centered.y, centered.x);
	float shuffle = floor(TIME * 18.0);
	float seg = floor((angle / TAU + 0.5) * 96.0);
	// ~1 in 4 segments carries a streak; each has its own start radius.
	float gate = step(0.72, seg_hash(seg + shuffle * 131.0));
	float start = mix(0.16, 0.42, seg_hash(seg * 3.7 + shuffle));
	float reach = smoothstep(start, start + 0.3, r);
	COLOR = vec4(line_color.rgb, gate * reach * intensity * line_color.a);
}
