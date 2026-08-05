#version 330 core

in vec2 v_local_pos;
in vec2 v_rect_size;
in vec4 v_color;
in vec4 v_color2;
in vec4 v_radii;
in vec4 v_shadow;
in vec4 v_shadow_color;
in vec4 v_params; // [draw_type, angle_or_scale, border_width, glass_blur]

uniform sampler2D u_backdrop_texture; // Glassmorphism backdrop scene texture

out vec4 FragColor;

// Analytical Signed Distance Field for Rounded Box with per-corner radii
float sdRoundedBox(vec2 p, vec2 b, vec4 r) {
    // Select corner radius based on quadrant: r = [top-left, top-right, bottom-right, bottom-left]
    float radius = (p.x > 0.0) ? ((p.y > 0.0) ? r.z : r.y) : ((p.y > 0.0) ? r.w : r.x);
    vec2 q = abs(p) - b + vec2(radius);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

void main() {
    vec2 half_size = v_rect_size * 0.5;

    // 1. Box Signed Distance Field
    float dist = sdRoundedBox(v_local_pos, half_size, v_radii);

    // 2. Drop Shadow SDF Evaluation (Gaussian Approximation)
    vec2 shadow_pos = v_local_pos - v_shadow.xy;
    float shadow_dist = sdRoundedBox(shadow_pos, half_size + vec2(v_shadow.w), v_radii);
    float shadow_blur = max(v_shadow.z, 0.5);
    float shadow_alpha = (1.0 - smoothstep(-shadow_blur, shadow_blur, shadow_dist)) * v_shadow_color.a;
    vec4 shadow_result = vec4(v_shadow_color.rgb, shadow_alpha);

    // If pixel is outside shadow region and box region, discard for speed
    if (dist > 1.5 && shadow_alpha <= 0.001) {
        discard;
    }

    // 3. Color Fill & Gradient Calculation
    float draw_type = v_params.x; // 0=Solid, 1=Linear, 2=Radial, 3=Glassmorphism
    vec4 fill_color = v_color;

    if (draw_type >= 0.9 && draw_type <= 1.1) {
        // Linear Gradient
        float angle = radians(v_params.y);
        vec2 dir = vec2(cos(angle), sin(angle));
        float t = clamp(dot(v_local_pos / v_rect_size, dir) + 0.5, 0.0, 1.0);
        fill_color = mix(v_color, v_color2, t);
    } else if (draw_type >= 1.9 && draw_type <= 2.1) {
        // Radial Gradient
        float t = clamp(length(v_local_pos) / (length(half_size) * max(v_params.y, 0.1)), 0.0, 1.0);
        fill_color = mix(v_color, v_color2, t);
    } else if (draw_type >= 2.9 && draw_type <= 3.1) {
        // Glassmorphism Backdrop Blur Simulation
        vec2 uv = gl_FragCoord.xy / textureSize(u_backdrop_texture, 0);
        vec4 backdrop = texture(u_backdrop_texture, uv);
        fill_color = mix(backdrop, v_color, v_color.a);
    }

    // 4. Anti-Aliased Box Alpha Mask via Smoothstep
    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);

    // 5. Border Stroking (if border_width > 0)
    float border_width = v_params.z;
    if (border_width > 0.0) {
        float inner_dist = sdRoundedBox(v_local_pos, half_size - vec2(border_width), max(v_radii - vec4(border_width), vec4(0.0)));
        float border_mask = smoothstep(-0.5, 0.5, inner_dist);
        fill_color = mix(fill_color, v_color2, border_mask);
    }

    vec4 box_result = vec4(fill_color.rgb, fill_color.a * alpha);

    // Composite Box over Drop Shadow
    FragColor = mix(shadow_result, box_result, box_result.a);
}
