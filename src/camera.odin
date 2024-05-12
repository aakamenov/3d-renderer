package main

import "core:math/linalg"

Camera :: struct {
    position: Vec3,
    direction: Vec3,
    velocity: Vec3,
    yaw: f64,
    projection: Mat4
}

camera_make_perspective :: proc "contextless" (fov, aspect, znear, zfar: f64) -> Camera {
    return {
        projection = linalg.matrix4_perspective(fov, aspect, znear, zfar, false),
        direction = { 0, 0, 1 }
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

camera_look_at :: proc(camera: ^Camera, target, up: Vec3) -> Mat4 {
    z := linalg.normalize(target - camera.position);
    x := linalg.normalize(linalg.cross(up, z));
    y := linalg.cross(z, x);

    return {
        x.x, x.y, x.z, -linalg.dot(x, camera.position),
        y.x, y.y, y.z, -linalg.dot(y, camera.position),
        z.x, z.y, z.z, -linalg.dot(z, camera.position),
        0, 0, 0, 1
    }
}
