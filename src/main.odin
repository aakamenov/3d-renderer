package main

import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/linalg"
import sdl "vendor:sdl2"

win_width: int = 800
win_height: int = 600
prev_frame_time: u32 = 0;
pixels: []u32 = nil

FPS :: 30
FRAME_TARGET_TIME :: 1000 / FPS
FOV :: 90.0
ORIGIN :: Vec3 { 0, 0, 0 }
GLOBAL_LIGHT :: Vec3 { 0, 0, 1 }

triangles_to_render := make([dynamic]Triangle, 64)

Render_Mode :: enum {
    Wireframe,
    Solid_Color,
    All,
    Textured,
    TexturedWireframe
}

main :: proc() {
    window, renderer, ok := initialize_window()

    if !ok {
        return
    }

    defer sdl.DestroyRenderer(renderer)
    defer sdl.DestroyWindow(window)
    defer sdl.Quit()

    pixels = make([]u32, win_width * win_height * size_of(u32))
    camera := camera_make_perspective(
        f64(linalg.to_radians(FOV)),
        f64(win_width) / f64(win_height),
        0.1,
        100,
    )

    texture := sdl.CreateTexture(
        renderer,
        u32(sdl.PixelFormatEnum.ARGB8888),
        .STREAMING,
        i32(win_width),
        i32(win_height),
    )

    // result, obj_ok := mesh_obj_load("./assets/cube.obj")
    // mesh = result

    // if !obj_ok {
    //     fmt.println("Failed to load .obj file.")

    //     return
    // }

    append(&mesh.faces, ..cube_faces[:])
    append(&mesh.vertices, ..cube_vertices[:])
    mesh.scale = 1

    render_mode := Render_Mode.All
    cull := true

    game: for {
        event: sdl.Event
        sdl.PollEvent(&event)

        #partial switch event.type {
            case .QUIT:
                break game
            case .KEYUP:
                #partial switch event.key.keysym.sym {
                    case .ESCAPE:
                        break game
                    case .NUM1:
                        render_mode = .All
                    case .NUM2:
                        render_mode = .Wireframe
                    case .NUM3:
                        render_mode = .Solid_Color
                    case .NUM4:
                        render_mode = .Textured
                    case .NUM5:
                        render_mode = .TexturedWireframe
                    case .c:
                        cull = !cull
                }
        }

        //sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
        //sdl.RenderClear(renderer)

        update(&camera, cull)

        slice.fill(pixels, 0xFF000000)
        render(render_mode)

        sdl.UpdateTexture(texture, nil, slice.first_ptr(pixels), i32(win_width) * size_of(u32))
        sdl.RenderCopy(renderer, texture, nil, nil)
        sdl.RenderPresent(renderer)
    }
}

update :: proc(camera: ^Camera, cull: bool) {    
    delta := sdl.GetTicks() - prev_frame_time
    prev_frame_time += delta

    time_to_wait := FRAME_TARGET_TIME - delta

    if time_to_wait > 0 && time_to_wait <= FRAME_TARGET_TIME {
        sdl.Delay(time_to_wait)
    }

    win_width_half := f64(win_width) / 2
    win_height_half := f64(win_height) / 2

    clear(&triangles_to_render)
    mesh.rotation.x += 0.5
    mesh.translation.z = 5;

    scale_mat := linalg.matrix4_scale(mesh.scale)
    trans_mat := linalg.matrix4_translate(mesh.translation)

    rot_mat_x := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.x), [3]f64 { 1, 0, 0 })
    rot_mat_y := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.y), [3]f64 { 0, 1, 0 })
    rot_mat_z := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.z), [3]f64 { 0, 0, 1 })

    #no_bounds_check  for face in mesh.faces {
        vertices: [3]Vec3 = {
            mesh.vertices[face.indices[0] - 1],
            mesh.vertices[face.indices[1] - 1],
            mesh.vertices[face.indices[2] - 1],
        }

        transformed_vertices: [3]Vec4 = ---

        #unroll for i in 0..<len(vertices) {
            world_mat := trans_mat * rot_mat_x * rot_mat_y * rot_mat_z * scale_mat * MAT4_IDENT
            transformed_vertices[i] = world_mat * vec4_from_vec3(vertices[i])
        }

        a := vec3_from_vec4(transformed_vertices[0])
        b := vec3_from_vec4(transformed_vertices[1])
        c := vec3_from_vec4(transformed_vertices[2])

        ab := linalg.normalize(b - a)
        ac := linalg.normalize(c - a)
        face_normal := linalg.normalize(linalg.cross(ab, ac))

        // Backface culling
        if cull {
            camera_ray := ORIGIN - a
            camera_normal := linalg.dot(face_normal, camera_ray)

            if camera_normal < 0 {
                continue
            }
        }

        projected_triangle: Triangle = ---

        // Project, scale and translate
        #unroll for i in 0..<len(transformed_vertices) {
            projected := camera_project(camera, transformed_vertices[i])

            // Invert y values to account for object model flipped screen y coordinate
            projected.y *= -1; 

            // Scale into the view
            projected.x *= win_width_half
            projected.y *= win_height_half

            // Translate to the middle of the screen
            projected.x += win_width_half
            projected.y += win_height_half

            projected_triangle.points[i] = { projected.x, projected.y }
        }

        // Negate the result as we want the dot product using the inverted light ray
        // because we specify the light vector as logically going towards the object.
        light_intensity := -linalg.dot(face_normal, GLOBAL_LIGHT)
        projected_triangle.color = color_apply_intensity(face.color, light_intensity)

        projected_triangle.uv = face.uv

        projected_triangle.avg_depth = (
            transformed_vertices[0].z +
            transformed_vertices[1].z +
            transformed_vertices[2].z
        ) / 3

        append(&triangles_to_render, projected_triangle)
    }

    sort :: proc(a: Triangle, b: Triangle) -> bool {
        return a.avg_depth > b.avg_depth
    }

    slice.sort_by(triangles_to_render[:], sort)
}

render :: proc(mode: Render_Mode) {
    // The size of the dot that marks the drawn vertex
    VERTEX_SIZE :: 6

    draw_grid()

    texture := slice.reinterpret([]u32, redbrick_texture)

    switch mode {
        case .All:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]
                int_coords := triangle_int_coords(&triangle)

                draw_filled_triangle(int_coords, triangle.color)
                draw_triangle(int_coords, 0x00000000)
            }
        case .Wireframe:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]
                int_coords := triangle_int_coords(&triangle)

                draw_rect({ int_coords[0].x, int_coords[0].y, VERTEX_SIZE, VERTEX_SIZE }, 0xFFFFFF00)
                draw_rect({ int_coords[1].x, int_coords[1].y, VERTEX_SIZE, VERTEX_SIZE }, 0xFFFFFF00)
                draw_rect({ int_coords[2].x, int_coords[2].y, VERTEX_SIZE, VERTEX_SIZE }, 0xFFFFFF00)

                draw_triangle(int_coords, 0xFFFFFFFF)
            }
        case .Solid_Color:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]
                int_coords := triangle_int_coords(&triangle)

                draw_filled_triangle(int_coords, triangle.color)
            }
        case .Textured:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]
                int_coords := triangle_int_coords(&triangle)

                draw_textured_triangle(int_coords, triangle.uv, texture)
            }
        case .TexturedWireframe:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]
                int_coords := triangle_int_coords(&triangle)

                draw_textured_triangle(int_coords, triangle.uv, texture)

                draw_rect({ int_coords[0].x, int_coords[0].y, VERTEX_SIZE, VERTEX_SIZE }, 0xFFFFFF00)
                draw_rect({ int_coords[1].x, int_coords[1].y, VERTEX_SIZE, VERTEX_SIZE }, 0xFFFFFF00)
                draw_rect({ int_coords[2].x, int_coords[2].y, VERTEX_SIZE, VERTEX_SIZE }, 0xFFFFFF00)
            }

    }
}

draw_grid :: proc() {
    SIZE :: 20

    for x := 0; x < win_width; x += SIZE {
        for y := 0; y < win_height; y += SIZE {
            set_pixel({ x, y }, 0xFF333333)
        }
    } 
}

draw_line :: #force_inline proc "contextless" (from: IntVec, to: IntVec, color: u32) {
    delta_x := (to.x - from.x)
    delta_y := (to.y - from.y)

    side_len := abs(delta_x) if abs(delta_x) >= abs(delta_y) else abs(delta_y)

    x_inc := f64(delta_x) / f64(side_len)
    y_inc := f64(delta_y) / f64(side_len)

    x := f64(from.x)
    y := f64(from.y)

    for _ in 0..=side_len {
        set_pixel({ int(math.round(x)), int(math.round(y)) }, color)
        x += x_inc
        y += y_inc
    }
}

draw_rect :: #force_inline proc "contextless" (r: IntRect, color: u32) {
    for w in 0..<r.w {
        for h in 0..<r.h {
            x := r.x + w
            y := r.y + h

            set_pixel({ x, y }, color)
        } 
    }
}

draw_triangle :: #force_inline proc "contextless" (p: [3]IntVec, color: u32) {
    draw_line(p[0], p[1], color)
    draw_line(p[1], p[2], color)
    draw_line(p[2], p[0], color)
}

draw_filled_triangle :: #force_inline proc(points: [3]IntVec, color: u32) {
    p1, p2, p3 := points[0], points[1], points[2]

    if p1.y > p2.y {
        swap(&p1, &p2)
    }

    if p2.y > p3.y {
        swap(&p2, &p3)
    }

    if p1.y > p2.y {
        swap(&p1, &p2)
    }

    if p2.y == p3.y {
        // The triangle itself has a flat bottom
        fill_flat_btm({ p1, p2, p3 }, color)
    } else if p1.y == p2.y {
        // The triangle itself has a flat top
        fill_flat_top({ p1, p2, p3 }, color)
    } else {
        x_mid := (f64((p3.x - p1.x) * (p2.y - p1.y)) / f64(p3.y - p1.y)) + f64(p1.x)
        p_mid := [2]int { int(x_mid), p2.y }

        fill_flat_btm({ p1, p2, p_mid }, color)
        fill_flat_top({ p2, p_mid, p3 }, color)
    }
}

fill_flat_btm :: #force_inline proc(p: [3]IntVec, color: u32) {
    inv_slope_1 := f64(p[1].x - p[0].x) / f64(p[1].y - p[0].y)
    inv_slope_2 := f64(p[2].x - p[0].x) / f64(p[2].y - p[0].y)

    x_start := f64(p[0].x)
    x_end := f64(p[0].x)

    for y in p[0].y..=p[2].y {
        draw_line({ int(x_start), y }, { int(x_end), y }, color)

        x_start += inv_slope_1
        x_end += inv_slope_2
    }
}

fill_flat_top :: #force_inline proc(p: [3]IntVec, color: u32) {
    inv_slope_1 := f64(p[2].x - p[0].x) / f64(p[2].y - p[0].y)
    inv_slope_2 := f64(p[2].x - p[1].x) / f64(p[2].y - p[1].y)

    x_start := f64(p[2].x)
    x_end := f64(p[2].x)

    for y := p[2].y; y >= p[0].y; y -= 1 {
        draw_line({ int(x_start), y }, { int(x_end), y }, color)

        x_start -= inv_slope_1
        x_end -= inv_slope_2
    }
}

draw_textured_triangle :: proc(points: [3]IntVec, uv: [3]Tex2d, texture: []u32) {
    p1, p2, p3 := points[0], points[1], points[2]
    uv1, uv2, uv3 := uv[0], uv[1], uv[2]

    if p1.y > p2.y {
        swap(&p1, &p2)
        swap(&uv1, &uv2)
    }

    if p2.y > p3.y {
        swap(&p2, &p3)
        swap(&uv2, &uv3)
    }

    if p1.y > p2.y {
        swap(&p1, &p2)
        swap(&uv1, &uv2)
    }

    // Draw the upper part (flat bottom)
    inv_slope_1: f64
    inv_slope_2: f64

    if p2.y - p1.y != 0 do inv_slope_1 = f64(p2.x - p1.x) / abs(f64(p2.y - p1.y))
    if p3.y - p1.y != 0 do inv_slope_2 = f64(p3.x - p1.x) / abs(f64(p3.y - p1.y))

    if inv_slope_1 != 0 {
        for y in p1.y..=p2.y {
            x_start := p2.x + int(f64(y - p2.y) * inv_slope_1)
            x_end := p1.x + int(f64(y - p1.y) * inv_slope_2)

            if x_end < x_start {
                temp := x_start
                x_start = x_end
                x_end = temp
            }

            for x in x_start..<x_end {
                set_pixel({x, y}, 0xFFFF00FF)
            }
        }
    }

    // Draw the bottom part (flat top)
    inv_slope_1 = 0

    if p3.y - p2.y != 0 do inv_slope_1 = f64(p3.x - p2.x) / abs(f64(p3.y - p2.y))

    if inv_slope_1 != 0 {
        for y in p2.y..=p3.y {
            x_start := p2.x + int(f64(y - p2.y) * inv_slope_1)
            x_end := p1.x + int(f64(y - p1.y) * inv_slope_2)

            if x_end < x_start {
                temp := x_start
                x_start = x_end
                x_end = temp
            }

            for x in x_start..<x_end {
                set_pixel({x, y}, 0x00000000)
            }
        }
    }
}

set_pixel :: #force_inline proc "contextless" (p: IntVec color: u32) {
    if p.x >= 0 && p.x < win_width && p.y >= 0 && p.y < win_height {
        pixels[(p.y * win_width) + p.x] = color
    }
}

color_apply_intensity :: #force_inline proc "contextless" (color: u32, factor: f64) -> u32 {
    factor := math.clamp(factor, 0, 1)

    a := color & 0xFF000000
    r := u32(f64(color & 0x00FF0000) * factor)
    g := u32(f64(color & 0x0000FF00) * factor)
    b := u32(f64(color & 0x000000FF) * factor)

    return a | (r & 0x00FF0000) | (g & 0x0000FF00) | (b & 0x000000FF)
}

initialize_window :: proc() -> (win: ^sdl.Window, ren: ^sdl.Renderer, success: bool) {
    if sdl.Init({.VIDEO, .TIMER, .EVENTS, .GAMECONTROLLER}) != 0 {
        fmt.eprintfln("Error initializing SDL.")

        return
    }

    mode: sdl.DisplayMode = ---
    if sdl.GetCurrentDisplayMode(0, &mode) == 0 {
        win_width = int(mode.w)
        win_height = int(mode.h)
    }

    win = sdl.CreateWindow(
        "Pikuma 3D Renderer",
        sdl.WINDOWPOS_CENTERED,
        sdl.WINDOWPOS_CENTERED,
        i32(win_width),
        i32(win_height),
        {.ALLOW_HIGHDPI, .FULLSCREEN},
    )

    if win == nil {
        fmt.eprintfln("Error initializing a SDL Window.")

        return
    }

    ren = sdl.CreateRenderer(win, 0, {.TARGETTEXTURE})

    if ren == nil {
        fmt.eprintfln("Error initializing a SDL Renderer.")

        return
    }

    sdl.RenderSetLogicalSize(ren, i32(win_width), i32(win_height))

    success = true

    return
}

swap :: #force_inline proc "contextless" (a, b: ^$T/[$N]$E) {
    temp: T = a^
    a^ = b^
    b^ = temp
}
