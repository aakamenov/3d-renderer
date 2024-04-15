package main

import "core:fmt"
import "core:slice"
import "core:math"
import sdl "vendor:sdl2"

win_width: int = 800
win_height: int = 600
prev_frame_time: u32 = 0;
pixels: []u32 = nil

FPS :: 30
FRAME_TARGET_TIME :: 1000 / FPS
FOV :: 640
ORIGIN :: Vec3 { 0, 0, -5. }

triangles_to_render := make([dynamic]Triangle, 64)

Triangle :: distinct [3]Vec2

Camera :: struct {
    pos: Vec3,
    rot: Vec3,
    angle: f32
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

    texture := sdl.CreateTexture(
        renderer,
        u32(sdl.PixelFormatEnum.ARGB8888),
        .STREAMING,
        i32(win_width),
        i32(win_height),
    )

    result, obj_ok := mesh_obj_load("./assets/f22.obj")
    mesh = result

    if !obj_ok {
        fmt.println("Failed to load .obj file.")

        return
    }

    game: for {
        event: sdl.Event
        sdl.PollEvent(&event)

        #partial switch event.type {
            case .QUIT:
                break game
            case .KEYDOWN:
                if event.key.keysym.sym == .ESCAPE {
                    break game
                }
            case:
        }

        //sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
        //sdl.RenderClear(renderer)

        update()

        slice.fill(pixels, 0x00000000)
        render()

        sdl.UpdateTexture(texture, nil, slice.first_ptr(pixels), i32(win_width) * size_of(u32))
        sdl.RenderCopy(renderer, texture, nil, nil)
        sdl.RenderPresent(renderer)
    }
}

update :: proc() {
    delta := sdl.GetTicks() - prev_frame_time
    prev_frame_time += delta

    time_to_wait := FRAME_TARGET_TIME - delta

    if time_to_wait > 0 && time_to_wait <= FRAME_TARGET_TIME {
        sdl.Delay(time_to_wait)
    }

    clear(&triangles_to_render)
    mesh.rotation.x += 0.01

    for i in 0..<len(mesh.faces) {
        face := mesh.faces[i]
        vertices: [3]Vec3 = {
            mesh.vertices[face.a - 1],
            mesh.vertices[face.b - 1],
            mesh.vertices[face.c - 1],
        }

        projected_triange: Triangle = ---

        for vertex, i in vertices {
            p := vec3_rot_x(vertex, mesh.rotation.x)
            p = vec3_rot_y(p, mesh.rotation.y)
            p = vec3_rot_z(p, mesh.rotation.z)

            p.z -= ORIGIN.z

            projected := project_perspective(p)
            projected.x += f32(win_width) / 2
            projected.y += f32(win_height) / 2

            projected_triange[i] = projected
        }

        append(&triangles_to_render, projected_triange)
    }
}

render :: proc() {
    draw_grid()

    #no_bounds_check for i in 0..<len(triangles_to_render) {
        triangle := triangles_to_render[i]
        draw_rect(int(triangle[0].x), int(triangle[0].y), 3, 3, 0xFFFFFF00)
        draw_rect(int(triangle[1].x), int(triangle[1].y), 3, 3, 0xFFFFFF00)
        draw_rect(int(triangle[2].x), int(triangle[2].y), 3, 3, 0xFFFFFF00)

        draw_triangle(
            { int(triangle[0].x), int(triangle[0].y), },
            { int(triangle[1].x), int(triangle[1].y), },
            { int(triangle[2].x), int(triangle[2].y), },
            0xFF00FF00,
        )
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

set_pixel :: #force_inline proc "contextless" (x: int, y: int, color: u32) {
    if x >= 0 && x < win_width && y >= 0 && y < win_height {
        pixels[(y * win_width) + x] = color
    }
}

project_orthographic :: #force_inline proc "contextless" (p: Vec3) -> Vec2 {
    return {
        p.x * FOV,
        p.y * FOV
    }
}

project_perspective :: #force_inline proc(p: Vec3) -> Vec2 {
    return {
        (p.x * FOV) / p.z,
        (p.y * FOV) / p.z
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
