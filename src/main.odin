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

triangles_to_render := make([dynamic]Triangle, 64)

Triangle :: struct{
    points: [3]Vec2,
    avg_depth: f32
}

Render_Mode :: enum {
    Wireframe,
    Solid_Color,
    All
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
        f32(linalg.to_radians(FOV)),
        f32(win_width) / f32(win_height),
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

    result, obj_ok := mesh_obj_load("./assets/cube.obj")
    mesh = result

    if !obj_ok {
        fmt.println("Failed to load .obj file.")

        return
    }

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
                    case .c:
                        cull = !cull
                }
        }

        //sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
        //sdl.RenderClear(renderer)

        update(&camera, cull)

        slice.fill(pixels, 0x00000000)
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

    win_width_half := f32(win_width) / 2
    win_height_half := f32(win_height) / 2

    clear(&triangles_to_render)
    mesh.rotation += 1
    mesh.translation.z = 5;

    scale_mat := linalg.matrix4_scale(mesh.scale)
    trans_mat := linalg.matrix4_translate(mesh.translation)
    rot_mat_x := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.x), [3]f32 { 1, 0, 0 })
    rot_mat_y := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.y), [3]f32 { 0, 1, 0 })
    rot_mat_z := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.z), [3]f32 { 0, 0, 1 })

    #no_bounds_check  for face in mesh.faces {
        vertices: [3]Vec3 = {
            mesh.vertices[face.a - 1],
            mesh.vertices[face.b - 1],
            mesh.vertices[face.c - 1],
        }

        transformed_vertices: [3]Vec4 = ---

        #unroll for i in 0..<len(vertices) {
            world_mat := scale_mat * MAT4_IDENT
            world_mat *= rot_mat_z
            world_mat *= rot_mat_y
            world_mat *= rot_mat_x
            world_mat = trans_mat * world_mat

            transformed_vertices[i] = world_mat * vec4_from_vec3(vertices[i])
        }

        // Backface culling
        if cull {
            a := vec3_from_vec4(transformed_vertices[0])
            b := vec3_from_vec4(transformed_vertices[1])
            c := vec3_from_vec4(transformed_vertices[2])

            ab := linalg.normalize(b - a)
            ac := linalg.normalize(c - a)
            face_normal := linalg.normalize(linalg.cross(ab, ac))

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

            // Scale into the view
            projected.x *= win_width_half
            projected.y *= win_height_half

            // Translate to the middle of the screen
            projected.x += win_width_half
            projected.y += win_height_half

            projected_triangle.points[i] = { projected.x, projected.y }
        }

        projected_triangle.avg_depth = (
            transformed_vertices[0].z +
            transformed_vertices[1].z +
            transformed_vertices[2].z
        ) / 3

        append(&triangles_to_render, projected_triangle)
    }

    sort :: proc(a: Triangle, b: Triangle) -> bool {
        return a.avg_depth < b.avg_depth
    }

    slice.sort_by(triangles_to_render[:], sort)
}

render :: proc(mode: Render_Mode) {
    draw_grid()

    switch mode {
        case .All:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]

                draw_filled_triangle(
                    { int(triangle.points[0].x), int(triangle.points[0].y), },
                    { int(triangle.points[1].x), int(triangle.points[1].y), },
                    { int(triangle.points[2].x), int(triangle.points[2].y), },
                    0xFFFFFFF,
                )

                draw_triangle(
                    { int(triangle.points[0].x), int(triangle.points[0].y), },
                    { int(triangle.points[1].x), int(triangle.points[1].y), },
                    { int(triangle.points[2].x), int(triangle.points[2].y), },
                    0xFFF00FF,
                )
            }
        case .Wireframe:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]
                draw_rect(int(triangle.points[0].x), int(triangle.points[0].y), 3, 3, 0xFFFFFF00)
                draw_rect(int(triangle.points[1].x), int(triangle.points[1].y), 3, 3, 0xFFFFFF00)
                draw_rect(int(triangle.points[2].x), int(triangle.points[2].y), 3, 3, 0xFFFFFF00)

                draw_triangle(
                    { int(triangle.points[0].x), int(triangle.points[0].y), },
                    { int(triangle.points[1].x), int(triangle.points[1].y), },
                    { int(triangle.points[2].x), int(triangle.points[2].y), },
                    0xFFF00FF,
                )
            }
        case .Solid_Color:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]

                draw_filled_triangle(
                    { int(triangle.points[0].x), int(triangle.points[0].y), },
                    { int(triangle.points[1].x), int(triangle.points[1].y), },
                    { int(triangle.points[2].x), int(triangle.points[2].y), },
                    0xFFF00FF,
                )
            }
    }
}

draw_grid :: proc() {
    SIZE :: 20

    for x := 0; x < win_width; x += SIZE {
        for y := 0; y < win_height; y += SIZE {
            set_pixel(x, y, 0xFF333333)
        }
    } 
}

draw_line :: #force_inline proc "contextless" (from: [2]int, to: [2]int, color: u32) {
    delta_x := (to.x - from.x)
    delta_y := (to.y - from.y)

    side_len := math.abs(delta_x) if math.abs(delta_x) >= math.abs(delta_y) else math.abs(delta_y)

    x_inc := f32(delta_x) / f32(side_len)
    y_inc := f32(delta_y) / f32(side_len)

    x := f32(from.x)
    y := f32(from.y)

    for _ in 0..=side_len {
        set_pixel(int(math.round(x)), int(math.round(y)), color)
        x += x_inc
        y += y_inc
    }
}

draw_rect :: #force_inline proc "contextless" (x: int, y: int, width: int, height: int, color: u32) {
    for w in 0..=width {
        for h in 0..=height {
            x := x + w
            y := y + h
            set_pixel(x, y, color)
        } 
    }
}

draw_triangle :: #force_inline proc "contextless" (p1: [2]int, p2: [2]int, p3: [2]int, color: u32) {
    draw_line({p1.x, p1.y}, {p2.x, p2.y}, color)
    draw_line({p2.x, p2.y}, {p3.x, p3.y}, color)
    draw_line({p3.x, p3.y}, {p1.x, p1.y}, color)
}

draw_filled_triangle :: #force_inline proc(p1: [2]int, p2: [2]int, p3: [2]int, color: u32) {
    p1 := p1
    p2 := p2
    p3 := p3

    if p1.y > p2.y {
        slice.ptr_swap_non_overlapping(&p1, &p2, size_of(int) * 2)
    }

    if p2.y > p3.y {
        slice.ptr_swap_non_overlapping(&p2, &p3, size_of(int) * 2)
    }

    if p1.y > p2.y {
        slice.ptr_swap_non_overlapping(&p1, &p2, size_of(int) * 2)
    }

    if p2.y == p3.y {
        // The triangle itself has a flat bottom
        fill_flat_btm(p1, p2, p3, color)
    } else if p1.y == p2.y {
        // The triangle itself has a flat top
        fill_flat_top(p1, p2, p3, color)
    } else {
        x_mid := (f32((p3.x - p1.x) * (p2.y - p1.y)) / f32(p3.y - p1.y)) + f32(p1.x)
        p_mid := [2]int { int(x_mid), p2.y }

        fill_flat_btm(p1, p2, p_mid, color)
        fill_flat_top(p2, p_mid, p3, color)
    }
}

fill_flat_btm :: #force_inline proc(p1: [2]int, p2: [2]int, p3: [2]int, color: u32) {
    inv_slope_1 := f32(p2.x - p1.x) / f32(p2.y - p1.y)
    inv_slope_2 := f32(p3.x - p1.x) / f32(p3.y - p1.y)

    x_start := f32(p1.x)
    x_end := f32(p1.x)

    for y in p1.y..=p3.y {
        draw_line({ int(x_start), y }, { int(x_end), y }, color)

        x_start += inv_slope_1
        x_end += inv_slope_2
    }
}

fill_flat_top :: #force_inline proc(p1: [2]int, p2: [2]int, p3: [2]int, color: u32) {
    inv_slope_1 := f32(p3.x - p1.x) / f32(p3.y - p1.y)
    inv_slope_2 := f32(p3.x - p2.x) / f32(p3.y - p2.y)

    x_start := f32(p3.x)
    x_end := f32(p3.x)

    for y := p3.y; y >= p1.y; y -= 1 {
        draw_line({ int(x_start), y }, { int(x_end), y }, color)

        x_start -= inv_slope_1
        x_end -= inv_slope_2
    }
}

set_pixel :: #force_inline proc "contextless" (x: int, y: int, color: u32) {
    if x >= 0 && x < win_width && y >= 0 && y < win_height {
        pixels[(y * win_width) + x] = color
    }
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
