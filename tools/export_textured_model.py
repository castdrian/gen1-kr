import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


def format_number(value):
    if abs(value) < 0.0000005:
        return "0"
    return format(value, ".6g")


def format_table(values):
    return "{" + ",".join(format_number(value) for value in values) + "}"


def material_image(material):
    if not material or not material.node_tree:
        return None
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            return node.image
    return None


def material_color(material):
    if material and material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                color = node.inputs.get("Base Color")
                if color:
                    return tuple(float(value) for value in color.default_value)
    if material:
        return tuple(float(value) for value in material.diffuse_color)
    return 0.08, 0.08, 0.08, 1.0


def ancestry_names(obj):
    names = []
    current = obj
    while current:
        names.append(current.name)
        current = current.parent
    return names


def has_branch(obj, branches):
    return any(
        name == branch or name.startswith(branch + "_")
        for name in ancestry_names(obj)
        for branch in branches
    )


def wheel_object_indices(objects, wheel_branches):
    points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
    min_x, max_x = min(point.x for point in points), max(point.x for point in points)
    min_y, max_y = min(point.y for point in points), max(point.y for point in points)
    min_z, max_z = min(point.z for point in points), max(point.z for point in points)
    width = max_x - min_x
    length = max_y - min_y
    height = max_z - min_z
    if wheel_branches:
        anchors = [
            (min_x + width * axle, min_y + length * side)
            for axle in (0.2, 0.77)
            for side in (0.1, 0.9)
        ]
    else:
        anchors = [
            (min_x + width * side, min_y + length * axle)
            for side in (0.1, 0.9)
            for axle in (0.2, 0.77)
        ]
    indices = {}
    for obj in objects:
        if wheel_branches and not has_branch(obj, wheel_branches):
            continue
        obj_points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
        if not obj_points:
            continue
        center = sum(obj_points, Vector((0.0, 0.0, 0.0))) / len(obj_points)
        if center.z > min_z + height * 0.55:
            continue
        if wheel_branches:
            closest = (0 if center.y < (min_y + max_y) / 2 else 2) + (
                0 if center.x < (min_x + max_x) / 2 else 1
            )
            indices[obj] = closest
        else:
            distances = [
                ((center.x - anchor_x) / width) ** 2
                + ((center.y - anchor_y) / length) ** 2
                for anchor_x, anchor_y in anchors
            ]
            closest = min(range(len(anchors)), key=distances.__getitem__)
            if distances[closest] < 0.01:
                indices[obj] = closest
    return indices


def collect_materials(objects):
    materials = []
    for obj in objects:
        obj.data.calc_loop_triangles()
        for triangle in obj.data.loop_triangles:
            material = obj.data.materials[triangle.material_index]
            if material not in materials:
                materials.append(material)
    return materials


def atlas_regions(materials, path, material_colors=False):
    cell = 256
    columns = 4
    rows = max(1, math.ceil((len(materials) + 1) / columns))
    width, height = columns * cell, rows * cell
    pixels = [0.0] * (width * height * 4)
    regions = {}
    for index, material in enumerate(materials):
        x0 = (index % columns) * cell
        y0 = (index // columns) * cell
        image = None if material_colors else material_image(material)
        color = material_color(material)
        if image and image.size[0] > 0 and image.size[1] > 0:
            source = image.pixels[:]
            source_width, source_height = image.size[:]
            scale = min(cell / source_width, cell / source_height)
            draw_width = max(1, round(source_width * scale))
            draw_height = max(1, round(source_height * scale))
            for y in range(draw_height):
                source_y = min(source_height - 1, int(y * source_height / draw_height))
                for x in range(draw_width):
                    source_x = min(source_width - 1, int(x * source_width / draw_width))
                    source_offset = (source_y * source_width + source_x) * 4
                    target_offset = ((y0 + y) * width + x0 + x) * 4
                    pixels[target_offset:target_offset + 4] = source[source_offset:source_offset + 4]
        else:
            draw_width, draw_height = 1, 1
            pixels[(y0 * width + x0) * 4:(y0 * width + x0) * 4 + 4] = color
        regions[material] = (
            x0 / width,
            y0 / height,
            draw_width / width,
            draw_height / height,
        )
    index = len(materials)
    x0 = (index % columns) * cell
    y0 = (index // columns) * cell
    for y in range(cell):
        for x in range(cell):
            offset = ((y0 + y) * width + x0 + x) * 4
            pixels[offset:offset + 4] = (0.8, 0.01, 0.01, 1.0)
    atlas = bpy.data.images.new("recomp_rider_mustang_atlas", width, height, alpha=True)
    atlas.pixels = pixels
    atlas.filepath_raw = str(path)
    atlas.file_format = "PNG"
    atlas.save()
    return regions, ((x0 + cell / 2) / width, 1.0 - (y0 + cell / 2) / height)


def repaired_tail_light(obj, material):
    return material.name == "Material#2" and obj.name in {
        "Geom3D.064", "Geom3D.065", "Geom3D.091",
    }


def write_lua(path, vertices, wheels):
    parts = [vertices[index:index + 30000] for index in range(0, len(vertices), 30000)]
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("return {texture=true,vertices={")
        stream.write(",".join(format_table(vertex) for vertex in parts[0]))
        stream.write("},parts={")
        for index, part in enumerate(parts[1:]):
            if index:
                stream.write(",")
            stream.write("{")
            stream.write(",".join(format_table(vertex) for vertex in part))
            stream.write("}")
        stream.write("},wheels={")
        for index, wheel in enumerate(wheels):
            if index:
                stream.write(",")
            stream.write("{name=")
            stream.write(repr(wheel["name"]))
            stream.write(",center=")
            stream.write(format_table(wheel["center"]))
            stream.write(",vertices={")
            stream.write(",".join(format_table(vertex) for vertex in wheel["vertices"]))
            stream.write("}}")
        stream.write("}}\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("texture", type=Path)
    parser.add_argument("source", type=Path)
    parser.add_argument("--width-scale", type=float, default=7.05)
    parser.add_argument("--length-scale", type=float, default=6.76)
    parser.add_argument("--height-scale", type=float, default=4.92)
    parser.add_argument("--decimation", type=float, default=0.8)
    parser.add_argument("--static-wheels", action="store_true")
    parser.add_argument("--material-colors", action="store_true")
    parser.add_argument("--wheel-branch", action="append", default=[])
    parser.add_argument("--exclude-branch", action="append", default=[])
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    args = parser.parse_args(argv)
    bpy.ops.import_scene.gltf(filepath=str(args.source.resolve()))
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and obj.name == "Cube":
            bpy.data.objects.remove(obj, do_unlink=True)
    objects = [
        obj for obj in bpy.context.scene.objects
        if obj.type == "MESH" and not has_branch(obj, args.exclude_branch)
    ]
    for obj in objects:
        obj.matrix_world = Matrix.Rotation(math.pi / 2, 4, "Z") @ obj.matrix_world
        if args.decimation < 1 and len(obj.data.polygons) >= 128:
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new("low_poly", "DECIMATE")
            modifier.ratio = args.decimation
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            obj.select_set(False)
    bpy.context.view_layer.update()
    materials = collect_materials(objects)
    regions, tail_light_uv = atlas_regions(materials, args.texture,
                                            args.material_colors)
    points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
    center_x = (min(point.x for point in points) + max(point.x for point in points)) / 2
    ground = min(point.z for point in points)
    length_center = (min(point.y for point in points) + max(point.y for point in points)) / 2
    wheel_indices = {} if args.static_wheels else wheel_object_indices(
        objects, args.wheel_branch)
    body = []
    wheel_vertices = [[] for _ in range(4)]
    wheel_points = [[] for _ in range(4)]
    light = Vector((0.7, 1.0, 0.8)).normalized()
    for obj in objects:
        uv_layer = obj.data.uv_layers.active
        normal_matrix = obj.matrix_world.to_3x3()
        for triangle in obj.data.loop_triangles:
            material = obj.data.materials[triangle.material_index]
            offset_u, offset_v, scale_u, scale_v = regions[material]
            repair_tail_light = repaired_tail_light(obj, material)
            normal = (normal_matrix @ triangle.normal).normalized()
            shade = 0.84 + 0.16 * max(0.0, normal.dot(light))
            target = wheel_vertices[wheel_indices[obj]] if obj in wheel_indices else body
            if obj in wheel_indices:
                wheel_points[wheel_indices[obj]].extend(
                    obj.matrix_world @ obj.data.vertices[index].co for index in triangle.vertices)
            for loop_index, vertex_index in zip(triangle.loops, triangle.vertices):
                point = obj.matrix_world @ obj.data.vertices[vertex_index].co
                uv = uv_layer.data[loop_index].uv if uv_layer else (0.5, 0.5)
                texture_u, texture_v = tail_light_uv if repair_tail_light else (
                    offset_u + (uv[0] % 1.0) * scale_u,
                    1.0 - (offset_v + (uv[1] % 1.0) * scale_v),
                )
                target.append((
                    (point.x - center_x) * args.width_scale,
                    (point.z - ground) * args.height_scale,
                    -(point.y - length_center) * args.length_scale,
                    texture_u,
                    texture_v,
                    shade,
                ))
    wheels = []
    if not args.static_wheels:
        for index, vertices in enumerate(wheel_vertices):
            points_for_wheel = wheel_points[index]
            if not points_for_wheel:
                continue
            center = sum(points_for_wheel, Vector((0.0, 0.0, 0.0))) / len(points_for_wheel)
            translated = []
            for vertex in vertices:
                translated.append((
                    vertex[0] - (center.x - center_x) * args.width_scale,
                    vertex[1] - (center.z - ground) * args.height_scale,
                    vertex[2] + (center.y - length_center) * args.length_scale,
                    vertex[3], vertex[4], vertex[5],
                ))
            wheels.append({
                "name": f"wheel_{index + 1}",
                "center": (
                    (center.x - center_x) * args.width_scale,
                    (center.z - ground) * args.height_scale,
                    -(center.y - length_center) * args.length_scale,
                ),
                "vertices": translated,
            })
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.texture.parent.mkdir(parents=True, exist_ok=True)
    write_lua(args.output, body, wheels)
    print(f"wrote {args.output} ({len(body) // 3} body triangles, {len(wheels)} wheels, {len(materials)} atlas regions)")


if __name__ == "__main__":
    main()
