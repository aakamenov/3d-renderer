package main

import "core:math/linalg"

Camera :: struct {
    projection: Mat4
}

camera_make_perspective :: proc "contextless" (fov, aspect, znear, zfar: f32) -> Camera {
    return {
        projection = linalg.matrix4_perspective(fov, aspect, znear, zfar, false)
    }
}

camera_project :: proc (camera: ^Camera, v: Vec4) -> Vec4 {
    result := camera.projection * v

    if result.w != 0 {
        result.x /= result.w
        result.y /= result.w
        result.z /= result.w
    }

    return result
}
