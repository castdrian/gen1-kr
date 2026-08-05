import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

PALETTE_WIDTH = 16


def is_scanner_material(material):
    name = material.name.lower() if material else ""
    return name in {"scanner", "scanner2"} or "color_a01" in name or "color_a11" in name


def is_edge_material(material):
    return material is not None and material.name.lower().startswith("edge_color")


def material_color(material):
    if is_scanner_material(material):
        return (0.95, 0.01, 0.005, 1.0)
    color = None
    node_tree = material.node_tree
    if node_tree:
        for node in node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                value = node.inputs.get("Base Color")
                if value:
                    color = tuple(float(x) for x in value.default_value[:4])
                    break
            if node.type == "BSDF_DIFFUSE":
                value = node.inputs.get("Color")
                if value:
                    color = tuple(float(x) for x in value.default_value[:4])
                    break
    if color is None and material:
        color = tuple(float(x) for x in material.diffuse_color[:4])
    if color is None:
        color = (0.08, 0.08, 0.08, 1.0)
    if material and not material.name.lower().startswith("edge_"):
        color = tuple(min(1.0, channel * 1.35 + 0.08)
                      for channel in color[:3]) + (color[3],)
    lifts = {
        "lack": 0.28,
        "glass": 0.22,
        "Material.001": 0.30,
        "Material.002": 0.42,
        "Material.003": 0.30,
    }
    if material and material.name in lifts:
        lift = lifts[material.name]
        color = tuple(min(1.0, channel * 1.8 + lift)
                      for channel in color[:3]) + (color[3],)
    return color


def apply_decimation(objects, ratio, tire_ratio):
    for obj in objects:
        object_ratio = tire_ratio if "TIRE" in obj.name else ratio
        if obj.name == "Cube.001":
            object_ratio = 1.0
        if object_ratio >= 1.0 or len(obj.data.polygons) < 3:
            continue
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new("low_poly", "DECIMATE")
        modifier.ratio = object_ratio
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def format_number(value):
    if abs(value) < 0.0000005:
        return "0"
    return format(value, ".6g")


def format_table(values):
    return "{" + ",".join(format_number(value) for value in values) + "}"


def material_name(obj, triangle, scanner_min_x, scanner_max_x):
    material = obj.data.materials[triangle.material_index]
    name = material.name if material else "default"
    lower = name.lower()
    if "color_a01" in lower:
        return "scanner_0"
    if "color_a11" in lower:
        center_x = sum(
            (obj.matrix_world @ obj.data.vertices[index].co).x
            for index in triangle.vertices
        ) / 3
        ratio = (center_x - scanner_min_x) / max(0.000001, scanner_max_x - scanner_min_x)
        return "scanner_0" if ratio < 0.5 else "scanner_1"
    if not is_scanner_material(material):
        return name
    center_x = sum(
        (obj.matrix_world @ obj.data.vertices[index].co).x
        for index in triangle.vertices
    ) / 3
    ratio = (center_x - scanner_min_x) / max(0.000001, scanner_max_x - scanner_min_x)
    bucket = min(2, max(0, int(ratio * 3)))
    return f"{name}_{bucket}"


def build_named_model(width_scale, length_scale, height_scale, decimation, tire_decimation):
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    apply_decimation(objects, decimation, tire_decimation)
    points = []
    body_points = []
    wheel_origins = []
    for obj in objects:
        if "TIRE" in obj.name:
            continue
        body_points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
    for obj in objects:
        if "TIRE" not in obj.name:
            continue
        origin = obj.matrix_world.translation
        if origin.length < 0.000001:
            origin = sum((obj.matrix_world @ vertex.co for vertex in obj.data.vertices),
                         Vector((0.0, 0.0, 0.0))) / max(1, len(obj.data.vertices))
        wheel_origins.append(origin)
    wheel_center_x = (sum(point.x for point in wheel_origins)
                      / max(1, len(wheel_origins)))
    body_x = sorted(point.x for point in body_points)
    body_center_x = body_x[len(body_x) // 2] if body_x else wheel_center_x
    for obj in objects:
        obj.data.calc_loop_triangles()
        for vertex in obj.data.vertices:
            point = obj.matrix_world @ vertex.co
            points.append(point)
    ground = min(point.z for point in points)
    body_min_y = min(point.y for point in body_points)
    body_max_y = max(point.y for point in body_points)
    length_center = (body_min_y + body_max_y) / 2
    scanner_points = []
    for obj in objects:
        for triangle in obj.data.loop_triangles:
            material = obj.data.materials[triangle.material_index]
            if not is_scanner_material(material):
                continue
            scanner_points.extend(
                (obj.matrix_world @ obj.data.vertices[index].co).x
                for index in triangle.vertices
            )
    scanner_min_x = min(scanner_points) if scanner_points else 0.0
    scanner_max_x = max(scanner_points) if scanner_points else 1.0
    materials = []
    material_names = []
    material_ids = {}
    material_sources = {}
    for obj in objects:
        for triangle in obj.data.loop_triangles:
            name = material_name(obj, triangle, scanner_min_x, scanner_max_x)
            if name not in material_ids:
                material_ids[name] = len(materials)
                material = obj.data.materials[triangle.material_index]
                material_sources[name] = material
                materials.append(material_color(material) if material else (0.08, 0.08, 0.08, 1.0))
                material_names.append(name)
    if len(materials) > PALETTE_WIDTH:
        keep = [index for index, name in enumerate(material_names)
                if name.startswith("scanner")]
        keep.extend(index for index in range(len(materials)) if index not in keep)
        keep = keep[:PALETTE_WIDTH]
        palette_names = [material_names[index] for index in keep]
        palette = [materials[index] for index in keep]
        remap = {old: new for new, old in enumerate(keep)}
        for name, material_id in list(material_ids.items()):
            if material_id in remap:
                material_ids[name] = remap[material_id]
            else:
                color = materials[material_id]
                material_ids[name] = min(
                    range(PALETTE_WIDTH),
                    key=lambda index: sum((color[channel] - palette[index][channel]) ** 2
                                          for channel in range(3)))
        material_names, materials = palette_names, palette
    body_vertices = []
    wheels = []
    for obj in objects:
        wheel = "TIRE" in obj.name
        wheel_vertices = []
        origin = obj.matrix_world.translation if wheel else None
        if wheel and origin.length < 0.000001:
            origin = sum((obj.matrix_world @ vertex.co for vertex in obj.data.vertices),
                         Vector((0.0, 0.0, 0.0))) / max(1, len(obj.data.vertices))
        for triangle in obj.data.loop_triangles:
            name = material_name(obj, triangle, scanner_min_x, scanner_max_x)
            material_id = material_ids[name]
            normal = obj.matrix_world.to_3x3() @ triangle.normal
            normal = Vector((normal.x, normal.z, -normal.y)).normalized()
            light = Vector((0.7, 1.0, 0.8)).normalized()
            shade = 0.72 + 0.28 * max(0.0, normal.dot(light))
            u = (material_id + 0.5) / PALETTE_WIDTH
            for vertex_index in triangle.vertices:
                point = obj.matrix_world @ obj.data.vertices[vertex_index].co
                if origin:
                    point = point - origin
                vertex = (
                    (point.x - body_center_x) * width_scale,
                    (point.z - (0 if origin else ground)) * height_scale,
                    -(point.y - (0 if origin else length_center)) * length_scale,
                    u,
                    0.5,
                    shade,
                )
                (wheel_vertices if wheel else body_vertices).append(vertex)
        if wheel:
            center = origin
            wheel_depth = max(
                abs((obj.matrix_world @ vertex.co).y - center.y)
                for vertex in obj.data.vertices
            )
            center_y = min(body_max_y - wheel_depth,
                           max(body_min_y + wheel_depth, center.y))
            side = -1 if "LEFT" in obj.name else 1 if "RIGHT" in obj.name \
                   else (-1 if center.x < wheel_center_x else 1)
            centered_x = body_center_x + side * abs(center.x - wheel_center_x)
            wheels.append({
                "name": obj.name,
                "center": (
                    (centered_x - body_center_x) * width_scale,
                    (center.z - ground) * height_scale,
                    -(center_y - length_center) * length_scale,
                ),
                "vertices": wheel_vertices,
            })
    return material_names, materials, body_vertices, wheels


def mustang_wheel_classifier(points):
    min_x, max_x = min(point.x for point in points), max(point.x for point in points)
    min_y, max_y = min(point.y for point in points), max(point.y for point in points)
    min_z, max_z = min(point.z for point in points), max(point.z for point in points)
    width = max_x - min_x
    length = max_y - min_y
    height = max_z - min_z
    center_x = (min_x + max_x) / 2
    rear_y = min_y + length * 0.22
    front_y = min_y + length * 0.78
    wheel_z = min_z + height * 0.30
    radius_limit = min(length * 0.18, height * 0.70)

    def classify(point):
        axle = 0 if abs(point.y - rear_y) < abs(point.y - front_y) else 1
        axle_y = rear_y if axle == 0 else front_y
        radius = ((point.y - axle_y) ** 2 + (point.z - wheel_z) ** 2) ** 0.5
        if abs(point.x - center_x) < width * 0.28 or radius > radius_limit:
            return None
        side = 0 if point.x < center_x else 1
        return side * 2 + axle

    return classify


def wheel_object_indices(objects):
    points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
    min_x, max_x = min(point.x for point in points), max(point.x for point in points)
    min_y, max_y = min(point.y for point in points), max(point.y for point in points)
    min_z, max_z = min(point.z for point in points), max(point.z for point in points)
    width = max_x - min_x
    length = max_y - min_y
    height = max_z - min_z
    anchors = [
        (min_x + width * side, min_y + length * axle)
        for side in (0.1, 0.9)
        for axle in (0.2, 0.77)
    ]
    indices = {}
    for obj in objects:
        obj_points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
        if not obj_points:
            continue
        center = sum(obj_points, Vector((0.0, 0.0, 0.0))) / len(obj_points)
        if center.z > min_z + height * 0.55:
            continue
        distances = [
            ((center.x - anchor_x) / width) ** 2
            + ((center.y - anchor_y) / length) ** 2
            for anchor_x, anchor_y in anchors
        ]
        closest = min(range(len(anchors)), key=distances.__getitem__)
        if distances[closest] < 0.01:
            indices[obj] = closest
    return indices


def build_blend_model(width_scale, length_scale, height_scale, decimation,
                      animate_wheels=True):
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    apply_decimation(objects, decimation, decimation)
    points = []
    triangle_records = []
    scanner_points = []
    for obj in objects:
        obj.data.calc_loop_triangles()
        for vertex in obj.data.vertices:
            points.append(obj.matrix_world @ vertex.co)
        for triangle in obj.data.loop_triangles:
            vertices = [obj.matrix_world @ obj.data.vertices[index].co
                        for index in triangle.vertices]
            material = obj.data.materials[triangle.material_index]
            if is_edge_material(material):
                continue
            if is_scanner_material(material):
                scanner_points.extend(point.x for point in vertices)
            center = sum(vertices, Vector((0.0, 0.0, 0.0))) / 3
            triangle_records.append((obj, triangle, vertices, center))
    ground = min(point.z for point in points)
    center_x = (min(point.x for point in points) + max(point.x for point in points)) / 2
    length_center = (min(point.y for point in points) + max(point.y for point in points)) / 2
    wheel_indices = wheel_object_indices(objects) if animate_wheels else {}
    scanner_min_x = min(scanner_points) if scanner_points else 0.0
    scanner_max_x = max(scanner_points) if scanner_points else 1.0
    material_names = []
    materials = []
    material_ids = {}
    for obj, triangle, _, _ in triangle_records:
        name = material_name(obj, triangle, scanner_min_x, scanner_max_x)
        if name not in material_ids:
            material_ids[name] = len(materials)
            material = obj.data.materials[triangle.material_index]
            material_names.append(name)
            materials.append(material_color(material) if material else (0.08, 0.08, 0.08, 1.0))
    if len(materials) > PALETTE_WIDTH:
        keep = [index for index, name in enumerate(material_names)
                if name.startswith("scanner")]
        keep.extend(index for index in range(len(materials)) if index not in keep)
        keep = keep[:PALETTE_WIDTH]
        palette_names = [material_names[index] for index in keep]
        palette = [materials[index] for index in keep]
        remap = {old: new for new, old in enumerate(keep)}
        for name, material_id in list(material_ids.items()):
            if material_id in remap:
                material_ids[name] = remap[material_id]
            else:
                color = materials[material_id]
                material_ids[name] = min(
                    range(PALETTE_WIDTH),
                    key=lambda index: sum((color[channel] - palette[index][channel]) ** 2
                                          for channel in range(3)))
        material_names, materials = palette_names, palette
    body_vertices = []
    wheel_vertices = [[] for _ in range(4)]
    wheel_points = [[] for _ in range(4)]
    light = Vector((0.7, 1.0, 0.8)).normalized()
    for obj, triangle, vertices, center in triangle_records:
        wheel_index = wheel_indices.get(obj)
        name = material_name(obj, triangle, scanner_min_x, scanner_max_x)
        material_id = material_ids[name]
        normal = (obj.matrix_world.to_3x3() @ triangle.normal).normalized()
        shade = 0.72 + 0.28 * max(0.0, normal.dot(light))
        u = (material_id + 0.5) / PALETTE_WIDTH
        target = wheel_vertices[wheel_index] if wheel_index is not None else body_vertices
        if wheel_index is not None:
            wheel_points[wheel_index].extend(vertices)
        for point in vertices:
            target.append((
                (point.x - center_x) * width_scale,
                (point.z - ground) * height_scale,
                -(point.y - length_center) * length_scale,
                u,
                0.5,
                shade,
            ))
    wheels = []
    for index, vertices in enumerate(wheel_vertices):
        points_for_wheel = wheel_points[index]
        if not points_for_wheel:
            continue
        center = sum(points_for_wheel, Vector((0.0, 0.0, 0.0))) / len(points_for_wheel)
        translated = []
        for vertex in vertices:
            translated.append((
                vertex[0] - (center.x - center_x) * width_scale,
                vertex[1] - (center.z - ground) * height_scale,
                vertex[2] + (center.y - length_center) * length_scale,
                vertex[3], vertex[4], vertex[5],
            ))
        wheels.append({
            "name": f"wheel_{index + 1}",
            "center": (
                (center.x - center_x) * width_scale,
                (center.z - ground) * height_scale,
                -(center.y - length_center) * length_scale,
            ),
            "vertices": translated,
        })
    return material_names, materials, body_vertices, wheels


def build_model(width_scale, length_scale, height_scale, decimation, tire_decimation,
                wheel_mode):
    if wheel_mode == "mustang":
        return build_blend_model(width_scale, length_scale, height_scale, decimation)
    if wheel_mode == "static":
        return build_blend_model(width_scale, length_scale, height_scale, decimation,
                                 animate_wheels=False)
    return build_named_model(width_scale, length_scale, height_scale, decimation,
                             tire_decimation)


def write_lua(path, material_names, materials, vertices, wheels):
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("return {paletteWidth=16,names={")
        stream.write(",".join(repr(name) for name in material_names))
        stream.write("},materials={")
        stream.write(",".join(format_table(material) for material in materials))
        stream.write("},vertices={")
        stream.write(",".join(format_table(vertex) for vertex in vertices))
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
    parser.add_argument("--source", type=Path)
    parser.add_argument("--width-scale", type=float, default=5.8)
    parser.add_argument("--length-scale", type=float, default=5.2)
    parser.add_argument("--height-scale", type=float, default=5.2)
    parser.add_argument("--model-scale", type=float, default=1.5)
    parser.add_argument("--decimation", type=float, default=0.3)
    parser.add_argument("--tire-decimation", type=float, default=0.3)
    parser.add_argument("--wheel-mode", choices=("named", "mustang", "static"), default="named")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    args = parser.parse_args(argv)
    if args.source:
        source = args.source.resolve()
        suffix = source.suffix.lower()
        if suffix == ".fbx":
            bpy.ops.wm.fbx_import(filepath=str(source))
        elif suffix in {".glb", ".gltf"}:
            bpy.ops.import_scene.gltf(filepath=str(source))
        else:
            raise SystemExit("source must be FBX, GLB, or glTF")
        for obj in list(bpy.context.scene.objects):
            if obj.type == "MESH" and obj.name == "Cube":
                bpy.data.objects.remove(obj, do_unlink=True)
        for obj in bpy.context.scene.objects:
            if obj.type == "MESH":
                obj.matrix_world = Matrix.Rotation(math.pi / 2, 4, "Z") @ obj.matrix_world
        bpy.context.view_layer.update()
    material_names, materials, vertices, wheels = build_model(
        args.width_scale * args.model_scale,
        args.length_scale * args.model_scale,
        args.height_scale * args.model_scale,
        args.decimation,
        args.tire_decimation,
        args.wheel_mode)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_lua(args.output, material_names, materials, vertices, wheels)
    print(f"wrote {args.output} ({len(materials)} materials, {len(vertices) // 3} body triangles, {len(wheels)} wheels)")


if __name__ == "__main__":
    main()
