package main

import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/linalg"
import sa "core:container/small_array"
import sdl "vendor:sdl2"

win_width: int = 800
win_height: int = 600
dt: f64
pixels: []u32
z_buffer: []f64

FPS :: 60
FRAME_TARGET_TIME :: 1000 / FPS
FOV :: 90.0
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

    pixels = make([]u32, win_width * win_height)
    z_buffer = make([]f64, win_width * win_height)

    znear := 0.1
    zfar := 100.
    aspect := f64(win_width) / f64(win_height)
    fovy := linalg.to_radians(FOV)
    fovx := linalg.atan(linalg.tan((fovy / 2) * aspect)) * 2

    camera := camera_make_perspective(fovy, aspect, znear, zfar)
    frustum_init(fovx, fovy, znear, zfar)

    sdl_texture := sdl.CreateTexture(
        renderer,
        u32(sdl.PixelFormatEnum.RGBA32),
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

    ok = texture_load(&mesh.texture, "./assets/cube.png")

    if !ok {
        return
    }

    render_mode := Render_Mode.All
    cull := true
    prev_frame_time: u32

    game: for {
        event: sdl.Event
        for sdl.PollEvent(&event) {
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
                        case .s, .w:
                            camera.velocity = 0
                    }
                case .KEYDOWN:
                    #partial switch event.key.keysym.sym {
                        case .w:
                            camera.velocity = (5 * dt) * camera.direction
                            camera.position += camera.velocity
                        case .s:
                            camera.velocity = (5 * dt) * camera.direction
                            camera.position -= camera.velocity
                        case .a:
                            camera.yaw += 1 * dt
                        case .d:
                            camera.yaw -= 1 * dt
                        case .UP:
                            camera.position.y += 3 * dt
                        case .DOWN:
                            camera.position.y -= 3 * dt
                    }
            }
        }

        //sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
        //sdl.RenderClear(renderer)

        update(&camera, cull)

        slice.fill(pixels, 0xFF000000)
        slice.fill(z_buffer, 0)

        render(render_mode)

        sdl.UpdateTexture(sdl_texture, nil, slice.first_ptr(pixels), i32(win_width) * size_of(u32))
        sdl.RenderCopy(renderer, sdl_texture, nil, nil)
        sdl.RenderPresent(renderer)

        time_to_wait := FRAME_TARGET_TIME - (sdl.GetTicks() - prev_frame_time)

        if time_to_wait > 0 && time_to_wait <= FRAME_TARGET_TIME {
            sdl.Delay(time_to_wait)
        }

        dt = f64(sdl.GetTicks() - prev_frame_time) / 1000
        prev_frame_time = sdl.GetTicks()
    }
}

update :: proc(camera: ^Camera, cull: bool) {
    win_width_half := f64(win_width) / 2
    win_height_half := f64(win_height) / 2

    clear(&triangles_to_render)
    //mesh.rotation.x += 40 * dt 
    mesh.translation.z = 5;

    camera_yaw_rot := linalg.matrix4_rotate(camera.yaw, [3]f64 { 0, 1, 0 })
    camera.direction = vec3_from_vec4(Vec4 { 0, 0, 1, 1 } * camera_yaw_rot)
    target := camera.direction + camera.position
    view_mat := camera_look_at(camera, target, { 0, 1, 0 })

    scale_mat := linalg.matrix4_scale(mesh.scale)
    trans_mat := linalg.matrix4_translate(mesh.translation)

    rot_mat_x := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.x), [3]f64 { 1, 0, 0 })
    rot_mat_y := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.y), [3]f64 { 0, 1, 0 })
    rot_mat_z := linalg.matrix4_rotate(linalg.to_radians(mesh.rotation.z), [3]f64 { 0, 0, 1 })

    #no_bounds_check for face, i in mesh.faces {
        vertices: [3]Vec3 = {
            mesh.vertices[face.indices[0]],
            mesh.vertices[face.indices[1]],
            mesh.vertices[face.indices[2]],
        }

        transformed_vertices: [3]Vec4 = ---

        #unroll for i in 0..<len(vertices) {
            world_mat := trans_mat * rot_mat_x * rot_mat_y * rot_mat_z * scale_mat * MAT4_IDENT
            v := world_mat * vec4_from_vec3(vertices[i])
            v = view_mat * v

            transformed_vertices[i] = v
        }

        a := vec3_from_vec4(transformed_vertices[0])
        b := vec3_from_vec4(transformed_vertices[1])
        c := vec3_from_vec4(transformed_vertices[2])

        ab := linalg.normalize(b - a)
        ac := linalg.normalize(c - a)
        face_normal := linalg.normalize(linalg.cross(ab, ac))

        // Backface culling
        if cull {
            camera_ray := 0 - a
            camera_normal := linalg.dot(face_normal, camera_ray)

            if camera_normal < 0 {
                continue
            }
        }

        polygon: Polygon
        triangles: sa.Small_Array(MAX_POLYGON_TRIANGLES, Triangle)

        polygon_from_triangle(&polygon, transformed_vertices, face.uv)
        polygon_clip(&polygon)
        polygon_tesselate(&polygon, &triangles)

        for i in 0..<triangles.len {
            triangle := triangles.data[i]
            projected_triangle: Triangle = ---

            // Project, scale and translate
            #unroll for i in 0..<len(triangle.points) {
                projected := camera_project(camera, triangle.points[i])

                // Invert y values to account for object model flipped screen y coordinate
                projected.y *= -1; 

                // Scale into the view
                projected.x *= win_width_half
                projected.y *= win_height_half

                // Translate to the middle of the screen
                projected.x += win_width_half
                projected.y += win_height_half

                projected_triangle.points[i] = projected
            }

            // Negate the result as we want the dot product using the inverted light ray
            // because we specify the light vector as logically going towards the object.
            light_intensity := -linalg.dot(face_normal, GLOBAL_LIGHT)
            projected_triangle.color = color_apply_intensity(face.color, light_intensity)

            projected_triangle.uv = triangle.uv

            append(&triangles_to_render, projected_triangle)
        }
    }
}

render :: proc(mode: Render_Mode) {
    // The size of the dot that marks the drawn vertex
    VERTEX_SIZE :: 6

    draw_grid()

    switch mode {
        case .All:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]

                draw_filled_triangle(triangle.points, triangle.color)

                int_coords := triangle_int_coords(&triangle)
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

                draw_filled_triangle(triangle.points, triangle.color)
            }
        case .Textured:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]

                draw_textured_triangle(triangle.points, triangle.uv, mesh.texture)
            }
        case .TexturedWireframe:
            #no_bounds_check for i in 0..<len(triangles_to_render) {
                triangle := triangles_to_render[i]

                draw_textured_triangle(triangle.points, triangle.uv, mesh.texture)

                int_coords := triangle_int_coords(&triangle)
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

draw_filled_triangle :: proc(points: [3]Vec4, color: u32) {
    sort_points :: #force_inline proc "contextless" (points: [3]Vec4) -> [3]Vec4 {
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

        return { p1, p2, p3 }
    }

    points := sort_points(points)

    p1 := IntVec { int(points[0].x), int(points[0].y) }
    p2 := IntVec { int(points[1].x), int(points[1].y) }
    p3 := IntVec { int(points[2].x), int(points[2].y) }

    inv_slope_2 := f64(p3.x - p1.x) / abs(f64(p3.y - p1.y))

    // Draw the upper part (flat bottom)
    if p2.y - p1.y != 0 {
        inv_slope_1 := f64(p2.x - p1.x) / abs(f64(p2.y - p1.y))

        for y in p1.y..=p2.y {
            x_start := p2.x + int(f64(y - p2.y) * inv_slope_1)
            x_end := p1.x + int(f64(y - p1.y) * inv_slope_2)

            if x_end < x_start {
                temp := x_start
                x_start = x_end
                x_end = temp
            }

            for x in x_start..<x_end {
                draw_triangle_pixel({ x, y }, points, color)
            }
        }
    }

    // Draw the bottom part (flat top)
    if p3.y - p2.y != 0 {
        inv_slope_1 := f64(p3.x - p2.x) / abs(f64(p3.y - p2.y))

        for y in p2.y..=p3.y {
            x_start := p2.x + int(f64(y - p2.y) * inv_slope_1)
            x_end := p1.x + int(f64(y - p1.y) * inv_slope_2)

            if x_end < x_start {
                temp := x_start
                x_start = x_end
                x_end = temp
            }

            for x in x_start..<x_end {
                draw_triangle_pixel({ x, y }, points, color)
            }
        }
    }
}

draw_triangle_pixel :: #force_inline proc "contextless" (at: IntVec, points: [3]Vec4, color: u32) {
    weights := barycentric_weights(
        { points[0].x, points[0].y},
        { points[1].x, points[1].y},
        { points[2].x, points[2].y},
        Vec2 { f64(at.x), f64(at.y) }
    )

    interp_w := (1 / points[0].w) * weights[0] +
                (1 / points[1].w) * weights[1] +
                (1 / points[2].w) * weights[2]

    z_buffer_index := (win_width * at.y) + at.x

    if interp_w < z_buffer[z_buffer_index] {
        return
    }

    set_pixel(at, color)
    z_buffer[z_buffer_index] = interp_w
}

draw_textured_triangle :: proc(points: [3]Vec4, uv: [3]Tex2d, texture: Texture) {
    sort_points :: #force_inline proc "contextless" (points: [3]Vec4, uv: [3]Tex2d) -> ([3]Vec4, [3]Tex2d) {
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

        return { p1, p2, p3 }, { uv1, uv2, uv3 }
    }

    points, uv := sort_points(points, uv)

    // Flip the V component to account for inverted UV coordinates
    uv[0][1] = 1 - uv[0][1]
    uv[1][1] = 1 - uv[1][1]
    uv[2][1] = 1 - uv[2][1]

    p1 := IntVec { int(points[0].x), int(points[0].y) }
    p2 := IntVec { int(points[1].x), int(points[1].y) }
    p3 := IntVec { int(points[2].x), int(points[2].y) }

    inv_slope_2 := f64(p3.x - p1.x) / abs(f64(p3.y - p1.y))

    // Draw the upper part (flat bottom)
    if p2.y - p1.y != 0 {
        inv_slope_1 := f64(p2.x - p1.x) / abs(f64(p2.y - p1.y))

        for y in p1.y..=p2.y {
            x_start := p2.x + int(f64(y - p2.y) * inv_slope_1)
            x_end := p1.x + int(f64(y - p1.y) * inv_slope_2)

            if x_end < x_start {
                temp := x_start
                x_start = x_end
                x_end = temp
            }

            for x in x_start..<x_end {
                draw_texel(texture, points, uv, { x, y })
            }
        }
    }

    // Draw the bottom part (flat top)
    if p3.y - p2.y != 0 {
        inv_slope_1 := f64(p3.x - p2.x) / abs(f64(p3.y - p2.y))

        for y in p2.y..=p3.y {
            x_start := p2.x + int(f64(y - p2.y) * inv_slope_1)
            x_end := p1.x + int(f64(y - p1.y) * inv_slope_2)

            if x_end < x_start {
                temp := x_start
                x_start = x_end
                x_end = temp
            }

            for x in x_start..<x_end {
                draw_texel(texture, points, uv, { x, y })
            }
        }
    }
}

draw_texel :: #force_inline proc "contextless" (
    texture: Texture,
    points: [3]Vec4,
    uv: [3]Tex2d,
    at: IntVec
) {
    weights := barycentric_weights(
        { points[0].x, points[0].y},
        { points[1].x, points[1].y},
        { points[2].x, points[2].y},
        Vec2 { f64(at.x), f64(at.y) }
    )

    u := (uv[0][0] / points[0].w) * weights[0] +
         (uv[1][0] / points[1].w) * weights[1] +
         (uv[2][0] / points[2].w) * weights[2]

    v := (uv[0][1] / points[0].w) * weights[0] +
         (uv[1][1] / points[1].w) * weights[1] +
         (uv[2][1] / points[2].w) * weights[2]

    interp_w := (1 / points[0].w) * weights[0] +
                (1 / points[1].w) * weights[1] +
                (1 / points[2].w) * weights[2]

    z_buffer_index := (win_width * at.y) + at.x

    if interp_w < z_buffer[z_buffer_index] {
        return
    }

    u /= interp_w
    v /= interp_w

    width := texture.size[0]
    height := texture.size[1]
    x := abs(int(u * f64(width))) % width
    y := abs(int(v * f64(height))) % height

    set_pixel(at, texture.pixels[(width * y) + x])
    z_buffer[z_buffer_index] = interp_w
}

barycentric_weights :: #force_inline proc "contextless" (a, b, c, p: Vec2) -> Vec3 {
    ac := c - a
    ab := b - a
    pc := c - p
    pb := b - p
    ap := p - a

    area_abc := linalg.cross(ac, ab)

    alpha := linalg.cross(pc, pb) / area_abc
    beta := linalg.cross(ac, ap) / area_abc
    gamma := 1 - alpha - beta

    return { alpha, beta, gamma }
}

set_pixel :: #force_inline proc "contextless" (p: IntVec, color: u32) {
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
