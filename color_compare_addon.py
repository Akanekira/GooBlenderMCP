bl_info = {
    "name": "Color Compare Toggle",
    "description": "快速切换所有后处理效果，用于与 Unity 对比颜色",
    "author": "GooBlenderProj",
    "version": (2, 0, 0),
    "blender": (4, 0, 0),
    "location": "3D Viewport > N Panel > 色彩对比",
    "category": "Render",
}

import bpy

# ─── 存储 AgX 基准状态 ────────────────────────────────────────────────────────
_agx_state = {
    "view_transform": "AgX",
    "look": "AgX - Medium High Contrast",
    "use_curve_mapping": True,
}

# 合成器节点名称（与场景中的节点 name 字段对应）
_COMPOSITOR_NODE_NAMES = [
    "色调映射",
    "色彩校正",
    "色彩平衡",
    "Hue/Saturation/Value",
]


# ─── 工具函数 ─────────────────────────────────────────────────────────────────

def _get_compositor_nodes(scene):
    """返回目标合成器节点列表，不存在则返回空列表"""
    if not scene.use_nodes or not scene.node_tree:
        return []
    nodes = []
    for name in _COMPOSITOR_NODE_NAMES:
        n = scene.node_tree.nodes.get(name)
        if n:
            nodes.append(n)
    return nodes


def _all_compositor_muted(scene):
    nodes = _get_compositor_nodes(scene)
    if not nodes:
        return False
    return all(n.mute for n in nodes)


# ─── Operator：切换色彩管理 ──────────────────────────────────────────────────

class VIEW3D_OT_toggle_color_mgmt(bpy.types.Operator):
    bl_idname = "view3d.toggle_color_mgmt"
    bl_label = "切换色彩管理"
    bl_description = "在 AgX（原始效果）和 Standard（Unity 对比）之间切换"

    def execute(self, context):
        vs = context.scene.view_settings
        if vs.view_transform == "AgX":
            _agx_state["view_transform"] = vs.view_transform
            _agx_state["look"] = vs.look
            _agx_state["use_curve_mapping"] = vs.use_curve_mapping
            vs.view_transform = "Standard"
            vs.look = "None"
            vs.use_curve_mapping = False
            self.report({"INFO"}, "色彩管理 → Standard")
        else:
            vs.view_transform = _agx_state["view_transform"]
            vs.look = _agx_state["look"]
            vs.use_curve_mapping = _agx_state["use_curve_mapping"]
            self.report({"INFO"}, "色彩管理 → AgX")
        return {"FINISHED"}


class VIEW3D_OT_save_agx_state(bpy.types.Operator):
    bl_idname = "view3d.save_agx_state"
    bl_label = "记录当前为 AgX 基准"
    bl_description = "将当前色彩管理设置保存为 AgX 还原基准"

    def execute(self, context):
        vs = context.scene.view_settings
        _agx_state["view_transform"] = vs.view_transform
        _agx_state["look"] = vs.look
        _agx_state["use_curve_mapping"] = vs.use_curve_mapping
        self.report({"INFO"}, "已记录 AgX 基准")
        return {"FINISHED"}


# ─── Operator：切换合成器节点链 ──────────────────────────────────────────────

class VIEW3D_OT_toggle_compositor(bpy.types.Operator):
    bl_idname = "view3d.toggle_compositor"
    bl_label = "切换合成器节点"
    bl_description = "静音/取消静音：色调映射、色彩校正、色彩平衡、色相饱和度"

    def execute(self, context):
        nodes = _get_compositor_nodes(context.scene)
        if not nodes:
            self.report({"WARNING"}, "未找到目标合成器节点")
            return {"CANCELLED"}
        mute = not _all_compositor_muted(context.scene)
        for n in nodes:
            n.mute = mute
        state = "已静音（关闭）" if mute else "已激活（开启）"
        self.report({"INFO"}, "合成器节点 " + state)
        return {"FINISHED"}


# ─── Operator：切换 Bloom ────────────────────────────────────────────────────

class VIEW3D_OT_toggle_bloom(bpy.types.Operator):
    bl_idname = "view3d.toggle_bloom"
    bl_label = "切换 Bloom"
    bl_description = "开启/关闭 EEVEE Bloom 泛光效果"

    def execute(self, context):
        eevee = context.scene.eevee
        if not hasattr(eevee, "use_bloom"):
            self.report({"WARNING"}, "当前渲染引擎不支持 Bloom")
            return {"CANCELLED"}
        eevee.use_bloom = not eevee.use_bloom
        state = "开启" if eevee.use_bloom else "关闭"
        self.report({"INFO"}, "Bloom " + state)
        return {"FINISHED"}


# ─── Operator：一键关闭所有后处理 ────────────────────────────────────────────

class VIEW3D_OT_disable_all_postfx(bpy.types.Operator):
    bl_idname = "view3d.disable_all_postfx"
    bl_label = "一键关闭所有后处理"
    bl_description = "同时关闭色彩管理 AgX、合成器节点链、Bloom"

    def execute(self, context):
        vs = context.scene.view_settings
        # 保存 AgX 状态
        if vs.view_transform == "AgX":
            _agx_state["view_transform"] = vs.view_transform
            _agx_state["look"] = vs.look
            _agx_state["use_curve_mapping"] = vs.use_curve_mapping
        # 关闭色彩管理
        vs.view_transform = "Standard"
        vs.look = "None"
        vs.use_curve_mapping = False
        # 静音合成器节点
        for n in _get_compositor_nodes(context.scene):
            n.mute = True
        # 关闭 Bloom
        if hasattr(context.scene.eevee, "use_bloom"):
            context.scene.eevee.use_bloom = False
        self.report({"INFO"}, "所有后处理已关闭（Unity 对比模式）")
        return {"FINISHED"}


class VIEW3D_OT_restore_all_postfx(bpy.types.Operator):
    bl_idname = "view3d.restore_all_postfx"
    bl_label = "一键还原所有后处理"
    bl_description = "同时还原色彩管理 AgX、合成器节点链、Bloom"

    def execute(self, context):
        vs = context.scene.view_settings
        # 还原色彩管理
        vs.view_transform = _agx_state["view_transform"]
        vs.look = _agx_state["look"]
        vs.use_curve_mapping = _agx_state["use_curve_mapping"]
        # 取消静音合成器节点
        for n in _get_compositor_nodes(context.scene):
            n.mute = False
        # 开启 Bloom
        if hasattr(context.scene.eevee, "use_bloom"):
            context.scene.eevee.use_bloom = True
        self.report({"INFO"}, "所有后处理已还原（原始效果）")
        return {"FINISHED"}


# ─── Panel ───────────────────────────────────────────────────────────────────

class VIEW3D_PT_color_compare(bpy.types.Panel):
    bl_label = "色彩对比"
    bl_idname = "VIEW3D_PT_color_compare"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "色彩对比"

    def draw(self, context):
        layout = self.layout
        scene = context.scene
        vs = scene.view_settings
        eevee = scene.eevee

        # ── 一键区 ──
        row = layout.row(align=True)
        row.operator("view3d.disable_all_postfx", text="全关（Unity）", icon="HIDE_ON")
        row.operator("view3d.restore_all_postfx", text="全开（原始）", icon="HIDE_OFF")

        layout.separator()

        # ── 色彩管理 ──
        box = layout.box()
        box.label(text="色彩管理", icon="COLOR")
        is_agx = vs.view_transform == "AgX"
        box.label(
            text=("AgX + " + vs.look) if is_agx else "Standard（对比模式）",
        )
        if is_agx:
            box.operator("view3d.toggle_color_mgmt",
                         text="切换为 Standard", icon="FORWARD")
        else:
            box.operator("view3d.toggle_color_mgmt",
                         text="切换回 AgX", icon="BACK")
        box.operator("view3d.save_agx_state",
                     text="记录当前为 AgX 基准", icon="BOOKMARKS")

        layout.separator()

        # ── 合成器节点链 ──
        box = layout.box()
        box.label(text="合成器节点链", icon="NODE_COMPOSITING")
        nodes = _get_compositor_nodes(scene)
        if nodes:
            all_muted = _all_compositor_muted(scene)
            for n in nodes:
                icon = "HIDE_ON" if n.mute else "HIDE_OFF"
                box.label(text=n.name, icon=icon)
            if all_muted:
                box.operator("view3d.toggle_compositor",
                             text="取消静音（开启）", icon="HIDE_OFF")
            else:
                box.operator("view3d.toggle_compositor",
                             text="全部静音（关闭）", icon="HIDE_ON")
        else:
            box.label(text="未找到目标节点", icon="ERROR")

        layout.separator()

        # ── EEVEE 后处理 ──
        box = layout.box()
        box.label(text="EEVEE 后处理", icon="SHADERFX")
        if hasattr(eevee, "use_bloom"):
            bloom_icon = "HIDE_OFF" if eevee.use_bloom else "HIDE_ON"
            row = box.row()
            row.label(text="Bloom", icon=bloom_icon)
            row.operator("view3d.toggle_bloom",
                         text="关闭" if eevee.use_bloom else "开启",
                         icon="FORWARD")
        else:
            box.label(text="Bloom 不可用", icon="ERROR")


# ─── 注册 ─────────────────────────────────────────────────────────────────────

classes = (
    VIEW3D_OT_toggle_color_mgmt,
    VIEW3D_OT_save_agx_state,
    VIEW3D_OT_toggle_compositor,
    VIEW3D_OT_toggle_bloom,
    VIEW3D_OT_disable_all_postfx,
    VIEW3D_OT_restore_all_postfx,
    VIEW3D_PT_color_compare,
)


def register():
    for cls in classes:
        bpy.utils.register_class(cls)


def unregister():
    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
