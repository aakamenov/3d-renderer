package main

import "core:math/linalg"
import sa "core:container/small_array"

MAX_POLYGON_VERTICES :: 10
MAX_POLYGON_TRIANGLES :: MAX_POLYGON_VERTICES - 2

planes: [Frustum_Plane]Plane

Frustum_Plane :: enum {
    Left,
    Right,
    Top,
    Bottom,
    Near,
    Far
}

Plane :: struct {
    point: Vec3,
    normal: Vec3
}

Polygon :: struct {
    vertices: sa.Small_Array(MAX_POLYGON_VERTICES, Vec3),
    uv: sa.Small_Array(MAX_POLYGON_VERTICES, Tex2d),
}

frustum_init :: proc(fovx, fovy, znear, zfar: f64) {
    cos_half_fovx := linalg.cos(fovx / 2)
    sin_half_fovx := linalg.sin(fovx / 2)
    cos_half_fovy := linalg.cos(fovy / 2)
    sin_half_fovy := linalg.sin(fovy / 2)

    planes[.Left].point = 0
    planes[.Left].normal.x = cos_half_fovx
    planes[.Left].normal.y = 0
    planes[.Left].normal.z = sin_half_fovx

    planes[.Right].point = 0
    planes[.Right].normal.x = -cos_half_fovx
    planes[.Right].normal.y = 0
    planes[.Right].normal.z = sin_half_fovx

    planes[.Top].point = 0
    planes[.Top].normal.x = 0
    planes[.Top].normal.y = -cos_half_fovy
    planes[.Top].normal.z = sin_half_fovy

    planes[.Bottom].point = 0
    planes[.Bottom].normal.x = 0
    planes[.Bottom].normal.y = cos_half_fovy
    planes[.Bottom].normal.z = sin_half_fovy

    planes[.Near].point = { 0, 0, znear }
    planes[.Near].normal.x = 0
    planes[.Near].normal.y = 0
    planes[.Near].normal.z = 1

    planes[.Far].point = { 0, 0, zfar }
    planes[.Far].normal.x = 0
    planes[.Far].normal.y = 0
    planes[.Far].normal.z = -1
}

polygon_from_triangle :: #force_inline proc "contextless" (
    p: ^Polygon,
    vertices: [3]Vec4,
    uv: [3]Tex2d
) {
    p.vertices.data[0] = vec3_from_vec4(vertices[0])
    p.vertices.data[1] = vec3_from_vec4(vertices[1])
    p.vertices.data[2] = vec3_from_vec4(vertices[2])
    p.vertices.len = 3

    p.uv.data[0] = uv[0]
    p.uv.data[1] = uv[1]
    p.uv.data[2] = uv[2]
    p.uv.len = 3
}

polygon_tesselate :: proc(p: ^Polygon, triangles: ^sa.Small_Array(MAX_POLYGON_TRIANGLES, Triangle)) {
    if p.vertices.len == 0 {
        return
    }

    triangles.len = p.vertices.len - 2
    first := vec4_from_vec3(p.vertices.data[0])
    first_tex := p.uv.data[0]

    for i in 0..<p.vertices.len - 2 {
        triangles.data[i].points[0] = first
        triangles.data[i].points[1] = vec4_from_vec3(p.vertices.data[i + 1])
        triangles.data[i].points[2] = vec4_from_vec3(p.vertices.data[i + 2])

        triangles.data[i].uv[0] = first_tex
        triangles.data[i].uv[1] = p.uv.data[i + 1]
        triangles.data[i].uv[2] = p.uv.data[i + 2]
    }
}

polygon_clip :: #force_inline proc "contextless" (p: ^Polygon) {
    plane_clip(p, .Left)
    plane_clip(p, .Right)
    plane_clip(p, .Top)
    plane_clip(p, .Bottom)
    plane_clip(p, .Near)
    plane_clip(p, .Far)
}

plane_clip :: proc "contextless" (p: ^Polygon, plane: Frustum_Plane) {
    if p.vertices.len == 0 {
        return
    }

    plane := planes[plane]
    inside: sa.Small_Array(MAX_POLYGON_VERTICES, Vec3)
    inside_tex: sa.Small_Array(MAX_POLYGON_VERTICES, Tex2d)

    prev := p.vertices.data[p.vertices.len - 1]
    prev_dot := linalg.dot(prev - plane.point, plane.normal)
    prev_tex := p.uv.data[p.uv.len - 1]

    for i in 0..<p.vertices.len {
        curr := p.vertices.data[i]
        curr_dot := linalg.dot(curr - plane.point, plane.normal)
        curr_tex := p.uv.data[i]

        if curr_dot * prev_dot < 0 {
            t := prev_dot / (prev_dot - curr_dot)
            intersection := Vec3 {
                linalg.lerp(prev.x, curr.x, t),
                linalg.lerp(prev.y, curr.y, t),
                linalg.lerp(prev.z, curr.z, t)
            }
            interp_tex := Tex2d {
                linalg.lerp(prev_tex[0], curr_tex[0], t),
                linalg.lerp(prev_tex[1], curr_tex[1], t)
            }

            sa.push(&inside, intersection)
            sa.push(&inside_tex, interp_tex)
        }

        if curr_dot > 0 {
            sa.push(&inside, curr)
            sa.push(&inside_tex, curr_tex)
        }

        prev = curr
        prev_dot = curr_dot
        prev_tex = curr_tex
    }

    sa.clear(& p.vertices)
    sa.push(&p.vertices, ..sa.slice(&inside))

    sa.clear(&p.uv)
    sa.push(&p.uv, ..sa.slice(&inside_tex))
}
