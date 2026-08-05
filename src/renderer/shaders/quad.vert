#version 330 core

layout(location = 0) in vec2 a_position;      // Unit Quad [0..1, 0..1]
layout(location = 1) in vec4 a_rect;          // [x, y, w, h] in screen pixels
layout(location = 2) in vec4 a_color;         // Primary Color / Start Color [r, g, b, a]
layout(location = 3) in vec4 a_color2;        // Secondary Color / End Color [r, g, b, a]
layout(location = 4) in vec4 a_radii;         // Border Radii [top-left, top-right, bottom-right, bottom-left]
layout(location = 5) in vec4 a_shadow;        // Shadow [offset_x, offset_y, blur, spread]
layout(location = 6) in vec4 a_shadow_color;  // Shadow Color [r, g, b, a]
layout(location = 7) in vec4 a_params;        // [draw_type, angle, border_width, glass_blur]

uniform vec2 u_resolution; // Viewport [width, height]

out vec2 v_local_pos;       // Local pixel position relative to quad center
out vec2 v_rect_size;       // Quad size [w, h]
out vec4 v_color;
out vec4 v_color2;
out vec4 v_radii;
out vec4 v_shadow;
out vec4 v_shadow_color;
out vec4 v_params;

void main() {
    // Expand quad geometry to account for shadow blur and spread padding
    float shadow_pad = a_shadow.z * 3.0 + abs(a_shadow.x) + abs(a_shadow.y) + a_shadow.w;
    vec2 expanded_size = a_rect.zw + vec2(shadow_pad * 2.0);
    vec2 expanded_pos = a_rect.xy - vec2(shadow_pad) + a_position * expanded_size;

    // Convert screen coordinates to NDC [-1.0 to 1.0], Y-flipped for top-left origin
    vec2 ndc = (expanded_pos / u_resolution) * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);

    // Pass center-relative local coordinates for SDF evaluation
    v_rect_size = a_rect.zw;
    vec2 center = a_rect.xy + a_rect.zw * 0.5;
    v_local_pos = expanded_pos - center;

    v_color = a_color;
    v_color2 = a_color2;
    v_radii = a_radii;
    v_shadow = a_shadow;
    v_shadow_color = a_shadow_color;
    v_params = a_params;
}
