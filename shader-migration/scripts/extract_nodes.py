"""
extract_nodes.py
通过 Blender Socket (localhost:9876) 提取材质/节点群组的完整节点树，
输出 JSON 到 docs/raw_data/。

用法：
    python extract_nodes.py --material M_actor_pelica_cloth_04
    python extract_nodes.py --group "Arknights: Endfield_PBRToonBase"
    python extract_nodes.py --group "Arknights: Endfield_PBRToonBase" --recursive
"""

import socket, json, time, argparse, os
from datetime import datetime

RAW_DATA_DIR = os.path.join(os.path.dirname(__file__), '../docs/raw_data')
os.makedirs(RAW_DATA_DIR, exist_ok=True)


def blender_exec(code: str, timeout: float = 10, wait: float = 2) -> dict:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(('localhost', 9876))
    cmd = json.dumps({'type': 'execute_code', 'params': {'code': code}}) + '\n'
    s.sendall(cmd.encode())
    time.sleep(wait)
    s.settimeout(5)
    data = b''
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    except Exception:
        pass
    s.close()
    return json.loads(data.decode('utf-8'))


EXTRACT_GROUP_CODE = r'''
import bpy, json, os, tempfile

def node_info(node):
    info = {
        'name': node.name,
        'type': node.type,
        'bl_idname': node.bl_idname,
        'inputs': [{'name': i.name, 'type': i.type} for i in node.inputs],
        'outputs': [{'name': o.name, 'type': o.type} for o in node.outputs],
    }
    if node.type == 'GROUP' and node.node_tree:
        info['group_name'] = node.node_tree.name
    # 记录可用默认值
    defaults = {}
    for inp in node.inputs:
        if hasattr(inp, 'default_value'):
            try:
                v = inp.default_value
                defaults[inp.name] = list(v) if hasattr(v, '__iter__') else v
            except Exception:
                pass
    if defaults:
        info['input_defaults'] = defaults
    return info

_target = TARGET_GROUP
ng = bpy.data.node_groups.get(_target)
if not ng:
    result_data = {'error': 'NodeGroup not found: ' + _target}
else:
    nodes = [node_info(n) for n in ng.nodes]
    links = [{
        'from_node': lnk.from_node.name,
        'from_socket': lnk.from_socket.name,
        'to_node': lnk.to_node.name,
        'to_socket': lnk.to_socket.name,
    } for lnk in ng.links]
    inputs_if = [{'name': s.name, 'bl_idname': s.bl_socket_idname}
                 for s in ng.interface.items_tree
                 if hasattr(s, 'bl_socket_idname') and s.in_out == 'INPUT']
    outputs_if = [{'name': s.name, 'bl_idname': s.bl_socket_idname}
                  for s in ng.interface.items_tree
                  if hasattr(s, 'bl_socket_idname') and s.in_out == 'OUTPUT']
    result_data = {
        'group': ng.name,
        'node_count': len(nodes),
        'link_count': len(links),
        'interface_inputs': inputs_if,
        'interface_outputs': outputs_if,
        'nodes': nodes,
        'links': links,
    }

tmp = os.path.join(tempfile.gettempdir(), 'blender_extract_out.json')
with open(tmp, 'w', encoding='utf-8') as f:
    json.dump(result_data, f, ensure_ascii=False, indent=2)
result = tmp
'''

EXTRACT_MATERIAL_CODE = r'''
import bpy, json, os, tempfile

def node_info(node):
    info = {
        'name': node.name,
        'type': node.type,
        'bl_idname': node.bl_idname,
        'inputs': [{'name': i.name, 'type': i.type} for i in node.inputs],
        'outputs': [{'name': o.name, 'type': o.type} for o in node.outputs],
    }
    if node.type == 'GROUP' and node.node_tree:
        info['group_name'] = node.node_tree.name
    if node.type == 'TEX_IMAGE' and node.image:
        info['image'] = node.image.name
    return info

_target = TARGET_MAT
mat = bpy.data.materials.get(_target)
if not mat:
    result_data = {'error': 'Material not found: ' + _target}
else:
    tree = mat.node_tree
    nodes = [node_info(n) for n in tree.nodes]
    links = [{
        'from_node': lnk.from_node.name,
        'from_socket': lnk.from_socket.name,
        'to_node': lnk.to_node.name,
        'to_socket': lnk.to_socket.name,
    } for lnk in tree.links]
    result_data = {
        'material': mat.name,
        'node_count': len(nodes),
        'link_count': len(links),
        'nodes': nodes,
        'links': links,
    }

tmp = os.path.join(tempfile.gettempdir(), 'blender_extract_out.json')
with open(tmp, 'w', encoding='utf-8') as f:
    json.dump(result_data, f, ensure_ascii=False, indent=2)
result = tmp
'''

import tempfile as _tempfile
TEMP_OUT = os.path.join(_tempfile.gettempdir(), 'blender_extract_out.json')


def extract_group(group_name: str) -> dict:
    code = EXTRACT_GROUP_CODE.replace('TARGET_GROUP', repr(group_name))
    blender_exec(code, wait=4)
    with open(TEMP_OUT, encoding='utf-8') as f:
        return json.load(f)


def extract_material(mat_name: str) -> dict:
    code = EXTRACT_MATERIAL_CODE.replace('TARGET_MAT', repr(mat_name))
    blender_exec(code)
    with open(TEMP_OUT, encoding='utf-8') as f:
        return json.load(f)


def save(data: dict, name: str):
    date = datetime.now().strftime('%Y%m%d')
    safe_name = name.replace(':', '_').replace(' ', '_').replace('/', '_')
    path = os.path.join(RAW_DATA_DIR, f'{safe_name}_{date}.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f'Saved: {path}')
    return path


def extract_recursive(group_name: str, visited: set = None):
    if visited is None:
        visited = set()
    if group_name in visited:
        return
    visited.add(group_name)

    print(f'Extracting group: {group_name}')
    data = extract_group(group_name)
    save(data, group_name)

    # 递归子群组
    for node in data.get('nodes', []):
        if node.get('type') == 'GROUP' and node.get('group_name'):
            extract_recursive(node['group_name'], visited)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--material', help='材质名称')
    parser.add_argument('--group', help='节点群组名称')
    parser.add_argument('--recursive', action='store_true', help='递归提取子群组')
    args = parser.parse_args()

    if args.material:
        data = extract_material(args.material)
        save(data, args.material)

    if args.group:
        if args.recursive:
            extract_recursive(args.group)
        else:
            data = extract_group(args.group)
            save(data, args.group)
