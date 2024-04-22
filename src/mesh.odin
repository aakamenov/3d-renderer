package main

import "core:os"
import "core:strings"
import "core:strconv"

cube_vertices: [8] Vec3 = {
    { -1, -1, -1 },
    { -1, 1, -1 },
    { 1, 1, -1 },
    { 1, -1, -1 },
    { 1, 1, 1 },
    { 1, -1, 1 },
    { -1, 1, 1 },
    { -1, -1, 1 }
}

// 6 cube faces, 2 triangles per face
cube_faces: [6 * 2] Face = {
    // front
    { { 1, 2, 3 }, 0xFFFFFFFF },
    { { 1, 3, 4 }, 0xFFFFFFFF },
    //right
    { { 4, 3, 5 }, 0xFFFFFFFF },
    { { 4, 5, 6 }, 0xFFFFFFFF },
    // back
    { { 6, 5, 7 }, 0xFFFFFFFF },
    { { 6, 7, 8 }, 0xFFFFFFFF },
    // left
    { { 8, 7, 2 }, 0xFFFFFFFF },
    { { 8, 2, 1 }, 0xFFFFFFFF },
    // top
    { { 2, 7, 5 }, 0xFFFFFFFF },
    { { 2, 5, 3 }, 0xFFFFFFFF },
    // bottom
    { { 6, 8, 1 }, 0xFFFFFFFF },
    { { 6, 1, 4 }, 0xFFFFFFFF },
}

mesh := Mesh { }

Mesh :: struct {
    vertices: [dynamic]Vec3,
    faces: [dynamic]Face,
    rotation: Vec3,
    scale: Vec3,
    translation: Vec3,
}

Face :: struct {
    indices: [3]u32,
    color: u32
}

mesh_make :: proc(cap: u16 = 0) -> Mesh {
    return {
        vertices = make([dynamic]Vec3, 0, cap),
        faces = make([dynamic]Face, 0, cap * 2),
        scale = 1,
        translation = 0
    }
}

mesh_delete :: proc(mesh: ^Mesh) {
    delete(mesh.faces)
    delete(mesh.vertices)
}

mesh_obj_load :: proc(filepath: string) -> (mesh: Mesh, ok: bool) {
    data := os.read_entire_file(filepath) or_return
    defer delete(data)

    str := string(data)

    mesh = mesh_make(64)
    ok = true

    lines: for line in strings.split_lines_iterator(&str) {
        if len(line) == 0 || line[0] == '#' || len(line) < 2 {
            continue
        }

        curr := 0
        start := 2
        line_len := len(line)

        type := [2]u8 {
            line[0],
            line[1],
        }

        switch type {
            case "v ":
                p := Vec3 { }

                for start < line_len {
                    end := -1 

                    if curr < 2 {
                        end = strings.index(line[start:], " ")

                        if end == -1 {
                            ok = false

                            break lines
                        }

                        end += start
                    } else {
                        end = line_len
                    }

                    val, parse_ok := strconv.parse_f32(line[start:end])

                    if !parse_ok {
                        ok = false

                        break lines
                    }

                    p[curr] = val
                    curr += 1
                    start = end + 1

                    if curr == 3 {
                        break
                    }
                }

                append(&mesh.vertices, p)
            case "f ":
                f := [3]u32 { }

                for start < line_len {
                    end := strings.index(line[start:], "/")

                    if end == -1 {
                        ok = false

                        break lines
                    }

                    end += start
                    val, parse_ok := strconv.parse_uint(line[start:end])

                    if !parse_ok {
                        ok = false

                        break lines
                    }

                    f[curr] = u32(val)
                    curr += 1
                    start = end

                    if curr == 3 {
                        break
                    }

                    if curr <= 2 {
                        offset := strings.index(line[start:], " ")

                        if start == -1 {
                            ok = false

                            break lines
                        }

                        start += offset + 1
                    } else {
                        end = line_len
                    }
                }

                append(
                    &mesh.faces,
                    Face { indices = f, color = 0xFFFFFFFF }
                )
            case '#':
                continue
            case:
        }
    }

    if !ok {
        mesh_delete(&mesh)

        return Mesh { }, false
    }

    return mesh, ok
}
