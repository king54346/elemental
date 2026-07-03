# 迁移目标：Elemental Serenity → Godot

## 一句话目标

将现有的 **Three.js / WebGL 交互式 3D 自然场景** `Elemental-Serenity-main` 完整迁移到 **Godot 4.x**，
在保持视觉效果、氛围与交互一致的前提下，得到一个可在 Godot 中运行、可导出多平台的工程。

---

## 源项目概况

| 项目 | 说明 |
| --- | --- |
| 名称 | Elemental Serenity（交互式 3D 自然 diorama） |
| 技术栈 | Vite 6 + Three.js 0.182 + GSAP + GLSL + Sass |
| 规模 | `src/` 约 12,000 行 JS + 约 40 个 GLSL 着色器文件 |
| 源目录 | `C:\Users\31483\Desktop\Elemental-Serenity-main` |
| 目标目录 | 待定（建议 `C:\Users\31483\Documents\elemental`，Godot 工程根） |
| 目标引擎 | Godot 4.x（GDScript，Forward+ / Mobile 渲染） |

### 核心功能模块（需逐一对应到 Godot）

- **核心**：渲染器、相机、尺寸/时间循环、事件系统、资源加载（`Game/Core`、`Game/Utils`）
- **世界组件**：桥、灌木、营地、篝火、萤火虫、雾、雨、岩石、天空穹顶、落雪、帐篷、树干、风线、落叶
- **管理器**：生态群系(Biome)、草地(Grass)、灌木(Bush)、季节(Season)、环境(Environment)
- **系统**：闪电(Lightning)、粒子(Particle)
- **着色器**：
  - `Chunks/`（改写 Three.js 内置着色器：grass / ground / rocks / water）
  - `Materials/`（完整材质：fire / fireflies / flowers / lightning / reveal / skydome / windLines / bush）
- **UI**：音乐控制、闪电按钮、Toast 提示
- **音频**：背景音乐 + 环境音（鸟/虫/火/雨/狼/雷等）+ UI 音效
- **资源**：8 个 GLB 模型、~25 张贴图、2 套 cubemap 环境图、20+ 音频文件

---

## 目标产物（Definition of Done）

1. 一个可用 Godot 4.x 打开并运行的工程，进入即呈现同款自然场景。
2. 视觉要素基本还原：程序化草地、天空/环境光、篝火与烟、萤火虫、雾、水面、季节与昼夜氛围。
3. 交互还原：相机漫游、音乐控制、触发闪电/天气等按钮。
4. 音频还原：背景音乐 + 环境音循环 + UI 音效。
5. 资源全部导入并正确引用（模型/贴图/音频/环境图）。
6. 附一份迁移说明文档，记录对应关系与未还原/降级的部分。

---

## 关键技术映射（Three.js → Godot）

| Three.js | Godot 4 对应 |
| --- | --- |
| Scene / Object3D | `Node3D` 场景树 |
| WebGLRenderer + Camera | Godot 渲染管线 + `Camera3D` |
| GLB + Draco 加载 | Godot 直接导入 `.glb`（`.tres`/`.scn`） |
| 自定义 ShaderMaterial (GLSL) | `ShaderMaterial` + Godot Shading Language（需人工翻译 GLSL） |
| 改写内置着色器 chunk | Godot 空间着色器 / `NodeMaterial` 重建 |
| InstancedMesh（草/粒子） | `MultiMeshInstance3D` |
| 粒子系统（雨/雪/萤火虫/火） | `GPUParticles3D` + 自定义 process 材质 |
| GSAP 补间 | `Tween` / `AnimationPlayer` |
| CubeTexture 环境图 | `WorldEnvironment` + `Sky`/`PanoramaSky` |
| Web Audio / 音频管理 | `AudioStreamPlayer(3D)` + Bus |
| DOM/HTML UI | Godot `Control` UI |
| 事件系统 EventEmitter | Godot signal / 自定义 signal bus |

---

## 主要风险与难点

1. **GLSL 着色器翻译**：Three.js 的 chunk 改写与自定义材质无法自动转换，需逐个用 Godot Shading Language 重写，是工作量与还原度的最大变量。
2. **程序化草地/实例化渲染**：依赖贴图驱动的位移、密度、风动，需要用 MultiMesh + 着色器重建。
3. **粒子系统**：火/烟/雨/雪/萤火虫从 CPU/自定义几何改为 `GPUParticles3D`，表现需调参逼近。
4. **昼夜/季节/环境切换**：原本靠 JS 管理器驱动着色器 uniform 与光照，需要在 Godot 中用脚本 + 环境资源重组。
5. **确定性随机（Mersenne Twister）**：布局若依赖固定种子，需要在 Godot 端复现同种子或改用预烘焙布局。

---

## 建议的分阶段路线（后续细化为任务清单）

- **P0 搭骨架**：新建 Godot 工程、导入全部资源、搭好场景树与相机漫游、跑通空场景。
- **P1 静态世界**：放置 GLB 模型（营地/桥/帐篷/树干/岩石）、地面、天空盒与基础光照。
- **P2 着色器**：翻译草地、水、地面、岩石着色器；重建 skydome。
- **P3 动态与粒子**：篝火/烟、萤火虫、雨、雪、落叶、风线、闪电。
- **P4 系统层**：季节 / 昼夜 / 生态群系 / 环境管理器逻辑。
- **P5 音频与 UI**：背景音乐、环境音、UI 音效、控制按钮、Toast。
- **P6 打磨**：性能优化、参数调优、移动端适配、迁移文档。

---

## 已确认的决策（2026-07-01）

1. **目标平台：仅桌面**（Windows/Mac/Linux）→ 使用 **Forward+** 渲染后端，着色器自由度最高。
2. **还原优先级：追求高还原度** → 逐个把 GLSL 着色器重写为 Godot Shading Language，最大程度还原原效果。
3. **工程根目录：`C:\Users\31483\Documents\elemental`**（GOAL.md 所在目录直接作为 Godot 工程根）。
4. 目标 Godot 版本：**4.6**（工程已由用户创建，d3d12 驱动 + Jolt 物理）。
