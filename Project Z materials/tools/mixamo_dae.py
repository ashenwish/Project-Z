"""Загрузка анимации Mixamo в формате Collada (.dae, «Without Skin») для переноса на героя.

Отдаёт тот же интерфейс, что mocap.Bvh: n, frame_time, pose(fr) -> {имя сустава: позиция},
имена без префикса mixamorig (Hips, LeftUpLeg, RightHand, ...), оси как в BVH (Y вверх, Z вперёд).
mirror=True зеркалит запись: левая и правая стороны меняются местами.
"""
import re
import xml.etree.ElementTree as ET

import numpy as np

NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}


def _clean(name):
    return re.sub(r"^mixamorig\d*[_:]", "", name)


class Dae:
    def __init__(self, path, mirror=False):
        root = ET.parse(path).getroot()
        self.mirror = mirror
        # скелет: узлы JOINT с матрицей покоя
        self.order, self.parent, self.rest = [], {}, {}
        scene = root.find("c:library_visual_scenes/c:visual_scene", NS)

        def walk(node, parent):
            nid = node.get("id")
            is_joint = node.get("type") == "JOINT"
            if is_joint:
                m = node.find("c:matrix", NS)
                self.rest[nid] = np.array(m.text.split(), float).reshape(4, 4) if m is not None else np.eye(4)
                self.parent[nid] = parent
                self.order.append(nid)
            for ch in node.findall("c:node", NS):
                walk(ch, nid if is_joint else parent)

        for n in scene.findall("c:node", NS):
            walk(n, None)
        self.names = {nid: _clean(root.find(f".//c:node[@id='{nid}']", NS).get("name")) for nid in self.order}

        # анимация: матрица на кадр для каждого узла
        self.anim, times = {}, None
        for an in root.iter(f"{{{NS['c']}}}animation"):
            ch = an.find("c:channel", NS)
            if ch is None:
                continue
            target = ch.get("target").split("/")[0]
            sampler = an.find("c:sampler", NS)
            src = {i.get("semantic"): i.get("source").lstrip("#") for i in sampler.findall("c:input", NS)}
            arr = lambda sid: np.array(an.find(f"c:source[@id='{sid}']/c:float_array", NS).text.split(), float)
            t = arr(src["INPUT"])
            out = arr(src["OUTPUT"]).reshape(-1, 4, 4)
            self.anim[target] = out
            if times is None or len(t) > len(times):
                times = t
        self.n = len(times)
        self.frame_time = float(times[1] - times[0]) if self.n > 1 else 1 / 30

    def pose(self, fr):
        world, out = {}, {}
        for nid in self.order:
            local = self.anim[nid][min(fr, len(self.anim[nid]) - 1)] if nid in self.anim else self.rest[nid]
            p = self.parent[nid]
            world[nid] = world[p] @ local if p else local
            out[self.names[nid]] = world[nid][:3, 3].copy()
        if self.mirror:
            m = {}
            for k, v in out.items():
                k2 = k.replace("Left", "\0").replace("Right", "Left").replace("\0", "Right")
                m[k2] = v * np.array([-1, 1, 1])
            out = m
        return out
