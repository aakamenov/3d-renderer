package main

Vec2 :: [2]f64
Vec3 :: [3]f64
Vec4 :: [4]f64
Mat4 :: matrix[4, 4]f64

IntRect :: struct {
    x: int,
    y: int,
    w: int,
    h: int
}
IntVec :: [2]int

MAT4_IDENT :: Mat4(1)

@(require_results)
vec4_from_vec3 :: #force_inline proc "contextless" (v: Vec3) -> Vec4 {
    return { v.x, v.y, v.z, 1 }
}

@(require_results)
vec3_from_vec4 :: #force_inline proc "contextless" (v: Vec4) -> Vec3 {
    return { v.x, v.y, v.z }
}
