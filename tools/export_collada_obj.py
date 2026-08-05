import argparse
import xml.etree.ElementTree as ET
from pathlib import Path

import collada
import numpy as np
from PIL import Image


NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}


def image_color(effect, base):
    diffuse = effect.diffuse
    if isinstance(diffuse, tuple):
        return tuple(float(x) for x in diffuse[:3])
    image = getattr(getattr(diffuse, "sampler", None), "surface", None)
    image = getattr(image, "image", None)
    path = getattr(image, "path", None)
    if path:
        try:
            with Image.open(base / path) as source:
                rgb = source.convert("RGB").resize((1, 1)).getpixel((0, 0))
            return tuple(channel / 255 for channel in rgb)
        except (OSError, ValueError):
            pass
    return (0.5, 0.5, 0.5)


def geometry_ids(root, names):
    nodes = {
        node.attrib["id"]: node
        for node in root.findall("c:library_nodes/c:node", NS)
    }
    visual = root.find("c:library_visual_scenes/c:visual_scene/c:node", NS)
    ids = set()
    group_ids = {}
    wheel_ids = set()

    def collect(node, group):
        for child in list(node):
            tag = child.tag.rsplit("}", 1)[-1]
            if tag == "instance_geometry":
                geometry_id = child.attrib["url"][1:]
                ids.add(geometry_id)
                group_ids[geometry_id] = group
            elif tag == "instance_node":
                target = nodes.get(child.attrib["url"][1:])
                if target is not None:
                    collect(target, group)
            elif tag == "node":
                collect(child, child.attrib.get("name") or group)

    for child in list(visual):
        if child.attrib.get("name") in names:
            before = set(ids)
            collect(child, child.attrib.get("name"))
            if child.attrib.get("name") in {"group_0", "group_1"}:
                wheel_ids.update(ids - before)
    return ids, group_ids, wheel_ids


def write_obj(source, output, names, max_triangles, max_edge):
    document = collada.Collada(str(source))
    root = ET.parse(source).getroot()
    selected, group_ids, wheel_ids = geometry_ids(root, names)
    objects = [obj for obj in document.scene.objects("geometry")
               if obj.original.id in selected]
    materials = {}
    triangles = []
    for obj in objects:
        matrix = np.asarray(obj.matrix, dtype=float)
        for primitive in obj.primitives():
            if not hasattr(primitive, "vertex"):
                continue
            vertices = np.asarray(primitive.vertex, dtype=float)
            indices = np.asarray(getattr(primitive, "vertex_index", ()), dtype=int)
            if vertices.size == 0:
                continue
            if indices.ndim != 2 or indices.shape[1] != 3:
                continue
            material = primitive.material
            name = material.id if material is not None else "default"
            if name not in materials:
                effect = material.effect if material is not None else None
                color = image_color(effect, source.parent) if effect else (0.5, 0.5, 0.5)
                readable = material.name if material is not None else name
                readable = "_".join(readable.split())
                materials[name] = (f"{name}_{readable}", color)
            transformed = np.hstack((vertices, np.ones((len(vertices), 1)))) @ matrix.T
            group = group_ids.get(obj.original.id, "BODY")
            if obj.original.id in wheel_ids:
                center = transformed[:, :3].mean(axis=0)
                side = "LEFT" if center[0] < 55 else "RIGHT"
                end = "FRONT" if center[1] > 0 else "REAR"
                group = f"TIRE_{side}_{end}"
            for index in indices:
                triangle = transformed[index, :3]
                edge_a = triangle[1] - triangle[0]
                edge_b = triangle[2] - triangle[0]
                if np.linalg.norm(np.cross(edge_a, edge_b)) < 0.000001:
                    continue
                edge_c = triangle[2] - triangle[1]
                if max_edge and max(np.linalg.norm(edge_a),
                                    np.linalg.norm(edge_b),
                                    np.linalg.norm(edge_c)) > max_edge:
                    continue
                triangles.append((group, materials[name][0], triangle))
    if max_triangles and len(triangles) > max_triangles:
        stride = len(triangles) / max_triangles
        triangles = [triangles[min(len(triangles) - 1, int(i * stride))]
                     for i in range(max_triangles)]
    output.parent.mkdir(parents=True, exist_ok=True)
    mtl = output.with_suffix(".mtl")
    with mtl.open("w", encoding="utf-8", newline="\n") as stream:
        for _, (readable, color) in materials.items():
            stream.write(f"newmtl {readable}\nKd {color[0]:.6f} {color[1]:.6f} {color[2]:.6f}\n")
    with output.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(f"mtllib {mtl.name}\n")
        vertex_index = 1
        last_group = None
        for group, key, vertices in triangles:
            if group != last_group:
                stream.write(f"o {group}\n")
                last_group = group
            stream.write(f"usemtl {key}\n")
            for vertex in vertices:
                stream.write("v " + " ".join(f"{value:.7f}" for value in vertex) + "\n")
            stream.write(f"f {vertex_index} {vertex_index + 1} {vertex_index + 2}\n")
            vertex_index += 3
    print(f"wrote {output} ({len(triangles)} triangles from {len(objects)} geometry instances)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--top-level", action="append", required=True)
    parser.add_argument("--max-triangles", type=int, default=0)
    parser.add_argument("--max-edge", type=float, default=40.0)
    args = parser.parse_args()
    write_obj(args.source, args.output, set(args.top_level), args.max_triangles,
              args.max_edge)


if __name__ == "__main__":
    main()
