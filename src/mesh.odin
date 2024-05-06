package main

import "core:os"
import "core:strings"
import "core:strconv"
import "core:unicode"

mesh := Mesh { }

Mesh :: struct {
    vertices: [dynamic]Vec3,
    faces: [dynamic]Face,
    rotation: Vec3,
    scale: Vec3,
    translation: Vec3,
    texture: Texture
}

Face :: struct {
    indices: [3]u32,
    uv: [3]Tex2d,
    color: u32
}

Triangle :: struct{
    points: [3]Vec4,
    uv: [3]Tex2d,
    avg_depth: f64,
    color: u32
}

triangle_int_coords :: #force_inline proc "contextless" (t: ^Triangle) -> [3]IntVec {
    return {
        { int(t.points[0].x), int(t.points[0].y), },
        { int(t.points[1].x), int(t.points[1].y), },
        { int(t.points[2].x), int(t.points[2].y), },
    }
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

    texture_free(mesh.texture)
}

mesh_obj_load :: proc(filepath: string) -> (mesh: Mesh, ok: bool) {
    data := os.read_entire_file(filepath) or_return
    defer delete(data)

    tex_coords := make([dynamic]Tex2d, 0, 64)
    defer delete(tex_coords)

    str := string(data)

    mesh = mesh_make(64)
    ok = true

    lines: for line in strings.split_lines_iterator(&str) {
        if len(line) == 0 || line[0] == '#' || len(line) < 3 {
            continue
        }

        type := [2]u8 {
            line[0],
            line[1],
        }

        switch type {
            case "v ":
                start := 2 // skip "v "
                if res, parse_ok := parse_float_array(line[start:], 3); parse_ok {
                    append(&mesh.vertices, res)
                } else {
                    ok = false

                    break lines
                }
            case "vt":
                start := 3 // skip "vt "
                if res, parse_ok := parse_float_array(line[start:], 2); parse_ok {
                    append(&tex_coords, Tex2d { res[0], res[1] })
                } else {
                    ok = false

                    break lines
                }
            case "f ":
                line := line[2:] // skip "f "

                // [3]vertex indices/[3]texture indices/[3]normal indices
                elems: [3][3]u32
                el_type := 0

                for group in strings.split_by_byte_iterator(&line, ' ') {
                    start := 0

                    for i in 0..<3 {
                        end := start

                        for end < len(group) {
                            if !unicode.is_number(rune(group[end])) {
                                break
                            }

                            end += 1
                        }

                        val: uint
                        parse_ok: bool

                        if val, parse_ok = strconv.parse_uint(group[start:end]); !parse_ok {
                            ok = false

                            break lines
                        }

                        elems[i][el_type] = u32(val)
                        start = end + 1
                    }

                    if el_type == 2 {
                        break
                    }

                    el_type += 1
                }

                if el_type != 2 {
                    ok = false

                    break lines
                }

                append(
                    &mesh.faces,
                    Face {
                        indices = {
                            elems[0][0] - 1,
                            elems[0][1] - 1,
                            elems[0][2] - 1,
                        },
                        uv = {
                            tex_coords[elems[1][0] - 1],
                            tex_coords[elems[1][1] - 1],
                            tex_coords[elems[1][2] - 1],
                        },
                        color = 0xFFFFFFFF
                    }
                )
            case:
        }
    }

    if !ok {
        mesh_delete(&mesh)

        return Mesh { }, false
    }

    return mesh, ok
}

// n MAX == 3
@(private)
parse_float_array :: proc(line: string, n: u8) -> (res: [3]f64, ok: bool) {
    line := line
    el_index: u8 = 0

    for num in strings.split_by_byte_iterator(&line, ' ') {
        val: f64
        parse_ok: bool

        if val, parse_ok = strconv.parse_f64(num); !parse_ok {
            return
        }

        res[el_index] = val
        el_index += 1

        if el_index == n {
            break
        }
    }

    if el_index == n {
        ok = true
    }

    return
}
