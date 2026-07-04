shader_type canvas_item;
// Low-health heartbeat vignette: a red edge glow whose intensity the HUD
// pulses when health is critical. Zero intensity = fully invisible.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.7, 0.05, 0.05, 1.0);

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float edge = smoothstep(0.35, 0.78, length(centered));
	COLOR = vec4(tint.rgb, edge * intensity * tint.a);
}
