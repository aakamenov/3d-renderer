package main

import "core:math"

Vec2 :: distinct [2]f32
Vec3 :: distinct [3]f32

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
