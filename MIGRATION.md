# Elemental Serenity — Three.js → Godot 迁移文档

本文档记录了将 **Elemental Serenity**（交互式 3D 自然 diorama）从
**Three.js / WebGL** 迁移到 **Godot 4.6** 的对应关系、实现方式与已知差异。

- 源项目：`C:\Users\31483\Desktop\Elemental-Serenity-main`（Vite + Three.js 0.182）
- 目标工程：本目录（Godot 4.6，Forward+ 渲染，仅桌面）
- 迁移原则：追求高还原度，逐个重写着色器；行为等价优先于实现照搬

---

## 1. 如何运行 / 操作

- 用 Godot 4.6 打开本工程，按 **F5** 运行。主场景 `scenes/Main.tscn`。
- **相机**：鼠标左键拖拽环绕，滚轮缩放（复刻原 OrbitControls，含极角限制）。
- **切换**（键盘或右下角 UI 按钮）：
  - `S` / **Season** 按钮 → 循环 spring → winter → autumn → rainy
  - `T` / **Day / Night** 按钮 → 昼夜切换
  - **Music** 按钮 → 背景音乐开关
  - **⚡ Lightning** 按钮（仅 rainy 显示）→ 手动触发闪电
- 切换季节/时间会弹出左上角 Toast，并重配环境音、全场景换色。

### Headless 自验证（开发用）
- Godot 可执行：`C:\Users\31483\Downloads\Godot_v4.6.3-stable_win64.exe\...console.exe`
- 导入：`godot --headless --path <proj> --import`
- 截图：`godot --path <proj> res://tools/Capture.tscn` → 输出 `_shots/capture.png`
- 环境变量控制初始态：`ELEM_SEASON=winter`、`ELEM_TIME=night`、`LIGHTNING_TEST=1`

---

## 2. 技术映射（Three.js → Godot）

| Three.js | Godot 4.6 |
| --- | --- |
| Scene / Object3D | `Node3D` 场景树 |
| WebGLRenderer + PerspectiveCamera + OrbitControls | Godot 渲染 + `Camera3D` + `scripts/OrbitCamera.gd` |
| GLB + Draco 加载 | **先解压 Draco**（Godot 不支持），再原生导入 |
| ShaderMaterial (GLSL) | `ShaderMaterial` + `.gdshader`（人工翻译） |
| onBeforeCompile 改内置着色器 | 独立 spatial 着色器，`ALBEDO`+`ROUGHNESS=1` 交引擎打光 |
| InstancedMesh（草/叶/花/萤火虫） | `MultiMeshInstance3D` + `INSTANCE_CUSTOM` |
| CPU 粒子系统（火/雨/雪/落叶/爆炸） | `GPUParticles3D` + `ParticleProcessMaterial` |
| CubeTexture skydome ShaderMaterial | `shader_type sky` + `WorldEnvironment`（`EYEDIR`） |
| GSAP 补间 | `Tween` / `create_tween()` |
| Web Audio | `AudioStreamPlayer` / `AudioStreamPlayer3D` |
| DOM/HTML UI | `CanvasLayer` + `Control` |
| EventEmitter 单例（Season/Env） | autoload 单例 `EnvState` + 信号 |

**关键坐标系说明**：Three.js 与 Godot 同为右手 Y-up，位置/旋转可直接映射。
Godot `.tscn` 的 `Transform3D` 序列化为**行主序**（basis 三行 + origin）。

---

## 3. 工程结构

```
elemental/
├── project.godot            # autoload: EnvState, AudioManager
├── scenes/Main.tscn         # 主场景（所有节点）
├── shaders/                 # 翻译后的 .gdshader
│   ├── ground / rocks / water / skydome / grass
│   ├── bush / windlines / fireflies / lightning / flowers
├── scripts/
│   ├── OrbitCamera.gd       # 相机（环绕 + 抖动）
│   ├── EnvState.gd          # 季节/昼夜单例 + 信号（autoload）
│   ├── SeasonData.gd        # 四季×昼夜全部配色数据
│   ├── AudioManager.gd      # 音乐 + 环境音（autoload）
│   ├── UI.gd                # 控制按钮 + Toast
│   ├── GrassField.gd        # 草地 MultiMesh
│   ├── FlowerField.gd       # 花朵 MultiMesh
│   ├── BushField.gd         # 灌木/树叶 MultiMesh（表面采样）
│   ├── Fire.gd              # 篝火（火/烟/余烬 + 灯）
│   ├── Weather.gd           # 雨/雪/落叶
│   ├── Fireflies.gd         # 萤火虫
│   ├── WindLines.gd         # 风线
│   ├── Lightning.gd         # 闪电
│   ├── Ground/Water/Sky/RocksMat.gd  # 材质季节响应
│   └── ApplyMaterialOverride.gd      # 通用材质覆盖
├── assets/{models,textures,audio,env}
└── tools/Capture.tscn       # 离屏截图工具
```

---

## 4. 逐组件迁移说明

| 组件 | Godot 实现 | 备注 |
| --- | --- | --- |
| **地面** | `ground.gdshader`，单平面世界 XZ 采样，程序化混合地/岩/水色 | 无几何位移（原作也是） |
| **岩石** | `rocks.gdshader`，displacement+perlin 三色 + 朝上青苔 | 用脚本 material_override 到 GLB |
| **水面** | `water.gdshader` 半透明叠加层，涟漪/水花/结冰按季节 | 蓝色水体来自地面着色器 |
| **天空** | `skydome.gdshader`（sky 类型），渐变+动漫太阳/月亮/星 | 接 WorldEnvironment，供环境光 |
| **草地** | `GrassField.gd` MultiMesh，密度图绿通道≥0.9 撒点，billboard+风动+密度剔除 | 63838 根 |
| **花朵** | `FlowerField.gd` MultiMesh，2 花 atlas，季节可见度淡出 | ~100 朵 |
| **灌木/树/白桦** | `BushField.gd`，叶片撒在 bushEmitter 表面（三角形面积采样），按 type 分 3 MultiMesh | 1755 片 |
| **篝火** | `Fire.gd`，火/烟/余烬 3×GPUParticles + 2 闪烁 OmniLight | |
| **雨/雪/落叶** | `Weather.gd`，GPUParticles，按季节开关 | rainy/winter/autumn |
| **萤火虫** | `Fireflies.gd`，50 环形发光 quad，夜间显示，闪烁漂移 | |
| **风线** | `WindLines.gd`，波浪缎带池，间歇扫过 | |
| **闪电** | `Lightning.gd`，锯齿电弧 tube + 爆炸粒子 + 屏幕闪 + 相机抖动 + 雷 | rainy 自动 + 按钮手动 |
| **季节/昼夜** | `EnvState` autoload + 信号，各组件订阅换 uniform | 数据在 `SeasonData.gd` |
| **音频** | `AudioManager` autoload，3 轨音乐轮播 + 环境音门控 | |
| **UI** | `UI.gd` CanvasLayer，按钮 + Toast | |

---

## 5. 已知差异 / 降级项

1. **Draco 压缩**：原 GLB 全为 Draco 压缩，Godot 官方构建不支持。已用
   `@gltf-transform/cli` 解压为普通网格；Draco 原件备份在工程外
   `../elemental_draco_backup`。**今后新增 GLB 需同样先解压。**
2. **光照模型**：原作每季有 key/fill/ambient/rim 多灯精细配置，本迁移简化为
   单向光 + 天空环境光的 day/night 两档。氛围接近但非逐灯还原。
3. **色调**：Godot 用 ACES 色调映射 + 雾，整体比原作略柔/略淡。属可调项。
4. **落叶季节门控**：原作落叶不分季节常驻，本迁移改为仅 autumn 显示（更符合季节主题）。
5. **粒子实现**：原 CPU 粒子（精确 over-life 插值纹理）改为 GPUParticles + 渐变/曲线，
   表现逼近但非逐帧一致；数值可在各脚本微调。
6. **草/灌木 billboard**：略去了原作实例随机 Y 旋转与 billboard 叠加的细节，
   采用纯朝相机 billboard（更干净）。
7. **闪电亮度**：白昼强光下电弧偏淡（加色叠亮空），夜/雨中更明显；`intensity` 可调。
8. **未迁移**：调试 GUI（lil-gui）、性能监视器（three-perf）、`?mode=debug`、
   窗口失焦暂停音频、触觉反馈（移动端）——均为非核心或平台相关功能。

---

## 6. 验证情况

除音频外，所有视觉效果均通过 `tools/Capture.tscn` 离屏渲染截图核验：
spring/winter/autumn/rainy × day/night、各季节粒子、闪电、UI、花朵。
截图存于 `_shots/`。**音频需在编辑器 F5 试听确认**（headless 无声音输出）。

---

## 7. 后续可打磨项（P6）

- 色调/雾/闪电亮度微调以更贴近原作
- UI 按钮美化（当前为 Godot 默认主题）
- 逐季精细光照
- 性能：草/粒子数量按目标机型调整
- Web 导出（若需要，须改 Compatibility 后端并处理着色器降级）
