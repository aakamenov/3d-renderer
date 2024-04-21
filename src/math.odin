package main

import "core:math"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32;

MAT4_IDENT :: Mat4(1);

vec3_rot_x :: #force_inline proc "contextless" (vec: Vec3, angle: f32) -> Vec3 {
    return {
        vec.x,
        vec.y * math.cos(angle) - vec.z * math.sin(angle),
        vec.y * math.sin(angle) + vec.z * math.cos(angle)
    }
}

vec3_rot_y :: #force_inline proc "contextless" (vec: Vec3, angle: f32) -> Vec3 {
    return {
        vec.x * math.cos(angle) - vec.z * math.sin(angle),
        vec.y,
        vec.x * math.sin(angle) + vec.z * math.cos(angle)
    }
}

vec3_rot_z :: #force_inline proc "contextless" (vec: Vec3, angle: f32) -> Vec3 {
    return {
        vec.x * math.cos(angle) - vec.y * math.sin(angle),
        vec.x * math.sin(angle) + vec.y * math.cos(angle),
        vec.z
    }
}

@(require_results)
vec4_from_vec3 :: #force_inline proc "contextless" (v: Vec3) -> Vec4 {
    return { v.x, v.y, v.z, 1 }
}

@(require_results)
vec3_from_vec4 :: #force_inline proc "contextless" (v: Vec4) -> Vec3 {
    return { v.x, v.y, v.z }
}
