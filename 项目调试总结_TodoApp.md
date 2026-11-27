# 待办事项 App（TodoApp）项目总结报告

> 初始记录：2026-11-26 15:16；历史同步日期：2026-11-26；本轮状态更新：2026-11-27
> 工程路径：`D:\DevEcoStudioProjects\TodoApp`
> 历史源码副本：`D:\OneDrive\文档\deepseek-harness\default-workspace\TodoApp`；本次未重新同步或比对

## 本轮升级复核摘要与提交指引

提交版报告与Markdown正文按2026年11月27日“示例任务”页面更新同步：默认折叠演示设置、96vp横排统计、列表旁换组及普通刷新恢复正常场景；本地测试表为网络29项、合计116项。Word继续保留学校封面、A4、原字体行距、自动多级标题编号、5张原生表与11张图片；模板版、修复版与DeepSeek版保留为历史稿。本轮报告同步及版式结果见 `docs/报告同步记录_2026-11-27.md`。

本次于08:29:39—08:29:57（北京时间）重新执行完整 `scripts/verify.ps1`，116项检查通过，退出码0；增量HAP构建显示BUILD SUCCESSFUL，33任务中15执行、18已是最新，HAP未签名。日志为 `docs/evidence/report-sync-verification-2026-11-27.txt`。00:44阶段的112项与较早network-ux日志保留历史含义；本次未操作模拟器、重新安装或调用真实网络API。

此前核对的12组submission图片与同名JSON保留原时点；报告图3、图5、图6明确标注改版前画面，不能用旧网络截图证明新版布局或按钮已经实际验收。当前HDC没有连接设备，本次未接管现有IDE预览图像通道；新版正常、设置、空态、失败与恢复截图仍待补拍。API来源与离线固定案例继续分开记录，界面标签不等同真实鉴权通过。

本次以正式工程为准更新报告和配套文档，OneDrive外部副本需另行同步并比对，不沿用此前版本的哈希或同步结论。课程学期、选题登记仍由本人确认；早期Git历史不补造，真实在线生成、重启恢复、剪贴板与卡片宿主未独立复验的边界保留。下文为历史记录，按其原时点理解。

---

## 一、项目定位

移动应用开发课程的期末作业，做一个 HarmonyOS 原生待办清单应用。

设计思路是在一个较小的功能闭环里，把课程要求的全部技术点一次性覆盖：列表展示、表单新增、状态切换、网络取数、多页跳转。这样代码量可控，每个考核点都有明确落点，报告也好写。

| 项目 | 内容 |
| --- | --- |
| 应用名 | 待办清单 TodoApp |
| 包名 | com.example.todoapp |
| 开发平台 | HarmonyOS / DevEco Studio 26.0.0 Release |
| 开发语言 | ArkTS（Stage 模型） |
| SDK 版本 | HarmonyOS 26.0.0 / API 26（build 26.0.0.105） |
| 状态管理 | V2（`@ObservedV2` / `@Trace` / `@Local` / `@Param` / `@Event`） |
| 路由方案 | Navigation + NavPathStack |
| 网络层 | `@kit.NetworkKit` 的 http 模块 |

---

## 二、交付物位置

| 位置 | 说明 |
| --- | --- |
| `D:\DevEcoStudioProjects\TodoApp` | **正式工程**，IDE 当前打开的就是这一份 |
| `D:\OneDrive\文档\deepseek-harness\default-workspace\TodoApp` | 同源代码备份，只作留档 |
| `docs/移动应用开发课程报告_待办事项App.md` | 工程内报告内容稿 |
| `docs/移动应用开发课程报告_TodoApp_提交版.docx` | 最终报告，已完成逐页渲染；修复版和DeepSeek版保留历史含义 |
| `D:\OneDrive\文档\deepseek-harness\default-workspace\移动应用开发课程报告_待办事项App.md` | 外部报告同步目标，内容以正式工程为准 |

### 为什么会有两份

hvigor 对工程路径有硬性约束：只接受字母、数字、连字符、下划线、点、英文括号、空格和 `@`。

OneDrive 那份路径里带"文档"两个中文字，hvigor 直接判违规，报：

```
00306003 Specification Limit Violation
Invalid project path. Current path does not match:
D:\OneDrive\文档\deepseek-harness\default-workspace\TodoApp
```

所以正式工程搬到了纯英文目录，OneDrive 那份留作源码备份。

---

## 三、代码结构

当前结构已扩展到独立网络页、持久化、回收站、统计、导入导出与桌面卡片；不再使用初版“9 个文件、554 行”的规模统计。

```
entry/src/main/ets/
├── entryability/
│   └── EntryAbility.ets             应用生命周期、恢复本地库、加载入口
├── entryformability/
│   └── EntryFormAbility.ets         桌面卡片生命周期
├── pages/
│   ├── Index.ets                    @Entry、Navigation、目标页映射
│   ├── HomePage.ets                 待办、搜索筛选、统计、回收站、导入导出
│   ├── AddTodoPage.ets              新增/编辑表单、截止日期时分、返回确认
│   └── NetworkPage.ets              独立远端列表、三态容错、原生圆环
├── components/
│   └── TodoItem.ets                 复用行组件，完成/编辑/删除事件
├── model/
│   └── Todo.ets                     @ObservedV2、字段级 @Trace
├── viewmodel/
│   ├── TodoStore.ets                个人数据、提交保存、搜索排序、回收站、统计
│   └── NetworkStore.ets             远端加载、失败/空态、图表、会话代理设置
├── common/
│   ├── ApiService.ets               HTTP 请求、响应校验、finally 释放连接
│   ├── FormService.ets              卡片快照、磁盘读取与已发布实例更新
│   ├── TodoDate.ets                 日期与时分组合及显示
│   ├── Theme.ets                    主题值
│   └── Sym.ets                      系统符号
└── widget/pages/WidgetCard.ets      2×2 桌面卡片
```

分层为 model / viewmodel / components / common / pages，与报告里"按功能分层、职责清晰"的表述一致。

---

## 四、技术考核点对应关系

| 课程要求 | 代码落点 | 具体实现 |
| --- | --- | --- |
| 容器组件 | `HomePage.ets` / `AddTodoPage.ets` / `NetworkPage.ets` | `Stack`、`Column`、`Row`、`List`、`ListItem`、`Scroll` 和原生 `Refresh` 组织内容与交互 |
| 自定义组件 | `TodoItem.ets` | `@ComponentV2`、`@Require @Param todo` 接收数据，`@Event onToggle / onEdit / onDelete` 向外抛事件 |
| 状态管理 V2 | `Todo.ets` / `TodoStore.ets` | `Todo` 用 `@ObservedV2` + 字段级 `@Trace`；仓库用静态单例 `TodoStore.instance`；页面用 `@Local` 持本地状态 |
| Navigation 路由 | `Index.ets` / `HomePage.ets` / `AddTodoPage.ets` / `NetworkPage.ets` | `pushPathByName` 入栈、`pop` 返回，新增/编辑与网络业务均为独立 `NavDestination` |
| 网络交互 | `ApiService.ets` / `NetworkStore.ets` / `NetworkPage.ets` | 独立页面直接 GET JSONPlaceholder 远端固定路径，校验状态码、JSON 结构和字段，`finally` 调用 `destroy()` |
| 三态容错 | `NetworkPage.ets` | 加载提示、失败与重试、空数据、正常列表；刷新重新发请求，失败保留上次成功数据 |
| 数据可视化 | `NetworkPage.ets` / `NetworkStore.ets` | 原生 `DataPanel` 圆环与列表共用远端状态；正常场景可重新请求并取响应中两组五条数据，显示已完成、未完成及比例 |

### 状态管理的细化说明

当前写操作由仓库统一处理。组件勾选触发 `onToggle`，首页调用 `TodoStore.toggle(id)`；仓库克隆目标对象，修改副本的 `done` 与 `doneAt`，生成新数组后交给 `commit`。有 Ability context 时先同步写入 Preferences，成功后才替换可观察数组并推送卡片；失败保留既有状态与表单。`@ObservedV2`、`@Trace` 支持响应式状态，但不能据此断言当前实现“直接改 todo.done、只重绘一行”。Previewer 无完整 Ability context 时只保存当次预览内存数据。

---

## 五、调试实录：踩过的 7 个坑

这一部分是整个过程中真正消耗时间的部分，逐条记下来。

| # | 现象 | 根因 | 解决方法 |
| --- | --- | --- | --- |
| 1 | `ohpm install` 直接失败，报 `NOTFOUND package '@ohos/hamock@1.0.1-rc2'` | 模板自带 `@ohos/hamock@1.0.1-rc2`，该版本在官方仓库中不存在 | 从 `oh-package.json5` 的 `devDependencies` 中删掉 hamock，只保留 `@ohos/hypium@1.0.18` |
| 2 | ohpm 报 `EPERM: operation not permitted, mkdir 'C:\Users\30357\.ohpm\cache\...'` | ohpm 缓存默认写在 C 盘用户目录，受执行环境限制 | 命令行加 `--cache <工程内目录>`；或交由 IDE 执行（IDE 进程有完整权限） |
| 3 | 同步报 `compileSdkVersion、compatibleSdkVersion 或 targetSdkVersion 的值不正确` | 模板沿用旧格式 `"5.0.0(12)"`，而本机 SDK 是 API 26 | API 26 起版本号改为纯三段式 SemVer，把 `compatibleSdkVersion` 改为 `"26.0.0"`，并补 `targetSdkVersion: "26.0.0"` |
| 4 | 配置全部改对，同步依然失败 | hvigor 只接受纯英文工程路径，`D:\OneDrive\文档\...` 中的"文档"触发路径校验 | 整个工程迁移到 `D:\DevEcoStudioProjects\TodoApp` |
| 5 | `HvigorRunConfiguration - Launch failed. null` | 全局缓存 `C:\Users\30357\.hvigor\project_caches\<hash>\workspace\node_modules\@ohos\hvigor\bin\hvigor.js` 缺失 | 删除该 `project_caches` 子目录，让 hvigor 重新生成（重建后为指向 IDE 自带 hvigor 的符号链接） |
| 6 | IDE 弹出"文件缓存冲突 / 加载文件系统更改" | 在 IDE 外部用工具修改了 `build-profile.json5`，IDE 内存中仍是旧版本 | 点击"加载文件系统更改"，以磁盘版本为准；之后统一让 IDE 自己保存 |
| 7 | 桌面点击被全屏保护或 host 窗口拦截 | 桌面输入守卫 | 改用 UIA 元素触发、键盘输入、或重新激活目标窗口后再操作 |

本轮另修复首页筛选数字停留在初始值的问题。原构建器的普通数字参数保存了创建时快照，数字节点未在更新表达式中读取仓库；改为在数字 `Text` 内直接读取当前 `todoCount`、`doneCount`。回归检查在已挂载筛选项上执行新增、完成、删除与恢复，验证依赖更新；不能只验证仓库计数正确就认定页面数字会变。

### 关键教训

第 4 条是最致命的一条，且出现得最晚。

在此之前，SDK 版本号、依赖缺失、缓存损坏这三类问题被逐个修掉后，同步依然失败，很容易怀疑方向错了。真正的原因与代码、依赖、SDK 全无关系，只是路径里有两个汉字。

结论：**先确认工程路径是纯英文，再排查其他问题。** 这一步放在最前，能省掉大量弯路。

---

## 六、此前阶段验证状态

本节保留2026年11月26日网络功能补齐阶段的历史记录，不能替代文首本轮复核摘要。原同步依据为 `docs/课程补齐验收_2026-11-26.md` 与当时日志 `docs/evidence/course-fix-verification-2026-11-26.txt`：

- 本轮修复后 `verify.ps1` 六组检查按统一口径合计 84 项通过：store 38、forms 6、pages 8、date 1 个汇总检查（含 5 组断言，不另累加）、reactivity 6、network 25。此前日志保留旧版 75 项结果。
- `assembleHap` 为 `BUILD SUCCESSFUL`，已生成 `entry/build/default/outputs/default/entry-default-unsigned.hap`。未签名不等于已安装，也不阻碍本课程 Previewer 演示。
- 本轮最终修复通过 hdc 在已有 HarmonyOS 模拟器更新 HAP 后复核；已观察启动、首页与表单导航、空标题拦截、未保存返回确认、新增、编辑、完成/取消完成、筛选、软删除与恢复。新增后 3/3/0、完成后 3/2/1、软删后 2/2/0、恢复后 3/3/0，列表与计数一致。
- 网络页已实测加载、系统直连超时与会话代理成功；第 1 组五条、完成一条、20%，第 2 组五条、完成两条、40%。空结果不画图，404 重试仍为预期 404；切回正常恢复，已有成功后失败保留第 2 组 40% 与来源标记。按钮刷新和下拉刷新均已完成。
- 本轮最终报告使用 `docs/evidence/course-fix-*.png` 与同名 JSON 界面树；此前 Previewer 与旧表单图只保留历史含义。新增证据不冒称 Previewer，布局仅实测本机模拟器屏幅。

课程可使用 Previewer，本轮另在已有模拟器复核修复后页面。设备重启持久化、系统剪贴板权限与桌面卡片宿主仍需独立验证，不能用构建或一次启动替代。

---

## 七、此前阶段后续安排

以下为此前阶段记录，本轮尚待处理的模拟器恢复、剩余取证与报告渲染以文首摘要为准。

1. 本轮核心 UI 与网络复核已完成，提交前按 `docs/课程提交清单.md` 核对源码、报告和 `course-fix-*` 证据一致。
2. 在其他电脑演示时按实际网络条件配置当前会话代理，复现两组图表变化、空态和 404 恢复；不提交本机代理地址或把固定数组冒充远端数据。
3. 后续若再次修改代码，重新执行 `scripts/verify.ps1`、`assembleHap` 与受影响 UI 检查；现有最终 84 项与构建日志保留原验证时点。

### 已知的潜在风险点

| 风险 | 说明 |
| --- | --- |
| 条件渲染与筛选 | 需实际验证状态变更后的计数、过滤结果、趋势和布局，不能只依据装饰器存在判断 UI 正确 |
| 原生刷新 | 当前使用 `Refresh({ refreshing: $$this.refreshing })` 与 `onRefreshing`，旧版 `Refresher` / `state.finish(...)` 叙述不适用；需观察刷新结束与请求结果 |
| 网络环境 | Previewer 可能受网络与代理条件影响。网络页提供当前会话代理设置；失败提示之外，还需保留成功、空态、错误与恢复的分别观察 |

---

## 八、报告提交前的待办

1. 已填写向骞、202440210325、计科24-3、人工智能学院；仍需本人核实课程学期、选题登记及独立完成程度。
2. 模板 Word 修复稿已生成，已嵌入真实 Gitk 历史图。基线前历史缺失仍是客观缺口，不能补造过去的分阶段开发；当前评分截图未要求必须公开托管。
3. 核对正式源码、README、内容稿、模板 Word 与当前证据一致，旧历史验收只保留原时点含义。
4. 原模板版被 WPS 占用时保留独立修复稿，关闭占用后核对最终提交文件名与版式。
5. 根据实际完成情况附 Previewer 演示截图；录屏可选。OneDrive 同步仅在实际完成后写为已同步。
