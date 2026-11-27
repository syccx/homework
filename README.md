# 待办清单 TodoApp

HarmonyOS 原生待办应用，采用 ArkTS、Stage 模型、ArkUI 状态管理 V2 和 Navigation。项目用于移动应用开发课程，正式工程位于 `D:\DevEcoStudioProjects\TodoApp`。

## 当前交付状态

2026年11月27日完成“示例任务”页面体验调整：原“网络示例”入口改为“示例任务”，默认先显示紧凑完成进度与只读任务列表；“换一组”位于列表旁，接口、空列表、404与会话代理设置收进默认关闭的“演示设置”。普通刷新、重新进入及空态/错误恢复均返回正常任务，课堂演示仍可重试当前场景。2026年11月27日08:29:39—08:29:57（北京时间）重新执行116项本地检查及HAP构建，退出码0，日志为 `docs/evidence/report-sync-verification-2026-11-27.txt`；实际设备画面尚未重新采集，说明见 `docs/示例任务体验更新_2026-11-27.md`。

报告使用 `docs/移动应用开发课程报告_TodoApp_提交版.docx`，内容稿为 `docs/移动应用开发课程报告_待办事项App.md`；正文按2026年11月27日“示例任务”新版界面与116项检查口径同步，沿用学校模板。本轮更新后仍为16页，已完成逐页版式视觉检查，保留5张原生表与11张图片，详见 `docs/报告同步记录_2026-11-27.md`。旧版页面截图明确标为改版前历史，尚未取得新版应用运行截图；报告版式QA不能代替新版应用UI验收。此前112项日志 `docs/evidence/final-report-verification-2026-11-27.txt` 保留原时点含义。本轮已重新执行本地检查和增量构建，构建未签名，不能据此认定安装成功。

前一轮逐张核对的12组 `submission-*.png/.json` 保留为既有证据，其中网络画面展示改版前界面；404补充图为明确标注2026年11月26日的 `deepseek-network-error`。离线固定案例与API来源界面的任务分开描述。新版正常列表、演示设置、空态、失败与恢复仍需实际预览并补拍原始画面及同名界面树，不能用旧图证明新版布局。文件名中的2026-11-26保留为前一轮起始日期，不表示全部操作发生在当天。

此前六组检查共84项和旧 `course-fix-verification-2026-11-26.txt` 属于网络功能补齐阶段；DeepSeek阶段112项、同日较早的116项 `network-ux-verification-2026-11-27.txt` 均保留原时点含义。正常网络演示取两组真实响应，预期分别为1/5、20%和2/5、40%，实际数值须与本次请求结果及截图一致。既有运行证据只覆盖当时本机模拟器屏幅，不据此宣称新版或全部窗口尺寸适配。

课程可按 **DevEco Previewer** 演示，无需将真机作为前置要求。既有页面证据来自前一轮 HarmonyOS 模拟器，不能扩大为2026年11月27日新版界面已经复验。编译和模拟服务的本地检查不能代替实际页面与 HTTP 观察；设备重启持久化、系统剪贴板授权和桌面卡片宿主属于可选扩展验证。

## 已实现功能

本次Git归档保留原有六条提交，并于2026年11月27日追加DeepSeek与待办交互、示例任务体验及报告材料等提交，不重建仓库、不改写旧提交。已普通推送至 `https://github.com/syccx/homework.git` 的main分支，首次发布后实际核对远端与本地提交ID一致。报告附件的“当前六条”和未提交说明记录归档前定稿时点，后续请查看 `git log --graph --oneline --decorate --all`。归档与发布验证见 `docs/Git提交与交付记录_2026-11-27.md`。

- DeepSeek 智能拆解：自行配置 API Key，将目标拆成 3–6 条中文建议，先预览、确认后统一保存，同一份已加入计划不会重复导入；提供明确标注的离线课堂示例。

- 新建、编辑、完成与取消完成；标题必填，标题最多 200 字符、描述最多 5000 字符。
- 截止日期和具体时分分别选择；新设日期默认 18:00，可清除截止时间，列表标识逾期事项。
- 按全部、进行中、已完成筛选；按标题或描述搜索。排序依次考虑完成状态、截止时间、优先级、创建时间。
- 软删除、回收站恢复、单条彻底删除、清空回收站和批量将已完成事项移入回收站；不可恢复操作带确认。
- 近 7 天完成趋势、连续完成天数；主列表进度排除回收站事项。软删除保留完成历史，彻底删除或取消完成后不再计入。
- 导出完整 JSON 到剪贴板；粘贴 JSON 合并导入。整批校验后保存，冲突编号重新分配；一次最多导入 1000 条，JSON 字符串长度限 2×1024×1024（代码按 length 判断）。
- 本地 Preferences 持久化；先同步落盘，再提交界面状态。保存失败保留已保存内容与表单，便于重试。
- 首次无本地库时尝试获取 5 条网络示例。离线仍可新建，迟到的示例响应不会覆盖用户操作，手动清空后的数据库不会再次被自动灌入示例。
- 独立“示例任务”页：默认加载正常示例，紧凑DataPanel圆环显示完成进度，列表旁可“换一组”。顶部和下拉刷新恢复正常请求并保持当前分组；进入页面会等待旧演示请求完成后恢复正常。空态和失败提供“重新加载示例”，失败保留旧数据并明确说明。课堂用的空列表、404、接口说明及会话代理都位于默认收起的“演示设置”；不读写个人任务库。
- 已保存 JSON 异常时保留原始内容并阻止意外覆盖；可先导出，再通过有效 JSON 显式恢复，原始异常内容另留恢复副本。
- 2×2 桌面卡片显示未完成数量和最新待办，点击打开应用。主动推送通过系统查询已发布实例，不依赖进程内卡片 ID 注册表；卡片新增、重新可见及定时刷新会读取已保存数据。
- 新增/编辑页可滚动；返回时对未保存修改做确认，保存后回到可见的全部待办列表。

首页下拉刷新用于重算本地状态和刷新卡片；独立网络示例页的刷新用于重复 HTTP 请求，两者互不覆盖。通知提醒、云同步、账号系统和跨设备同步尚未实现。

## 开发环境

| 项目 | 当前配置 |
| --- | --- |
| IDE | DevEco Studio 26.0.0 Release |
| SDK | HarmonyOS API 26，版本配置 `26.0.0` |
| 包名 | `com.example.todoapp` |
| 正式工程 | `D:\DevEcoStudioProjects\TodoApp` |
| IDE 安装 | `D:\DevEco Studio` |
| 源码备份目标 | `D:\OneDrive\文档\deepseek-harness\default-workspace\TodoApp` |
| 本轮课程补齐前备份 | `D:\DevEcoStudioProjects\TodoApp_backups\before_course_20261126_185644` |

构建使用正式工程目录，避免 OneDrive 中文路径带来的现有工具链兼容问题。备份目录不作为构建目录；备份同步结果以验收记录为准。

## 构建与本地检查

在 PowerShell 执行。工程没有独立 `hvigorw.bat`，以下命令使用已安装的 IDE 工具链：

```powershell
Set-Location -LiteralPath 'D:\DevEcoStudioProjects\TodoApp'
$env:DEVECO_SDK_HOME = 'D:\DevEco Studio\sdk'
$env:NODE_HOME = 'D:\DevEco Studio\tools\node'
$env:PATH = "$env:NODE_HOME;$env:PATH"
& "$env:NODE_HOME\node.exe" 'D:\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

产物：`entry\build\default\outputs\default\entry-default-unsigned.hap`。当前产物未签名，不能把打包成功解释为安装成功。

本地检查分别执行，任意脚本退出码非 0 都应先处理失败项：

```powershell
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-store.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-forms.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-pages.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-reactivity.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-date.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-network.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-components.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-deepseek.cjs
```

当前检查口径：store38、forms6、pages8、date1个汇总检查（含5组日期断言）、reactivity6、network29、components4、deepseek24，合计116项；本轮完整日志为 `docs/evidence/report-sync-verification-2026-11-27.txt`，退出码0。构建为增量，33个任务中15个执行、18个已是最新。新增4项执行真实页面AST构建树和回调，检查默认折叠、设置展开、刷新、空态/错误恢复及在途演示请求。旧75、84、112项与较早network-ux日志保留历史含义，日期内部断言不重复计数。这些检查模拟系统服务，不代替实际设备布局、真实HTTP、Preferences、剪贴板授权或桌面宿主验收。脚本依赖本机SDK安装路径，移机时需相应调整。

## DevEco Studio 中运行

最新统一检查口径为 store 38 + forms 6 + pages 8 + date 1 + reactivity 6 + network 29 + components 4 + deepseek 24 = **116项**。DeepSeek24项包含真实SDK装饰器及真实TodoStore集成，HTTP和磁盘为可控替身，不据此宣称真实密钥鉴权或付费模型响应通过。

1. 打开正式工程目录，等待同步完成；外部文件修改后在 IDE 中重新加载磁盘内容。
2. 使用 Previewer 复验页面。Previewer 不执行正常的 `EntryAbility` 启动流程，预览中通过表单产生的数据仅在当次预览中保留，页面会提示该限制。
3. 从首页“示例任务”进入，默认浏览公开任务、进度和“换一组”。需要课堂演示时展开“演示设置”，再选择空列表、HTTP错误或“预览网络设置”。代理主机不含协议/路径/端口，端口为1–65535；设置仅当前会话有效。顶部刷新和“重新加载示例”返回正常列表，展开状态下的“重试此演示”保留当前场景。旧报告截图记录优化前页面，不作为本次视觉复验结果。

以下步骤仅用于可选设备验证：

4. 如需安装，先准备可用的鸿蒙真机或完整的匹配模拟器镜像，并检查设备连接：

   ```powershell
   & 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' list targets
   ```

5. 在 IDE 的 Project Structure → Signing Configs 配置调试签名，必要时由本人登录华为账号。当前构建配置尚无签名，不影响 Previewer 演示。
6. 重新构建并通过 IDE 安装运行，另行记录重启恢复、设备网络、剪贴板和桌面卡片结果。

## 代码入口

| 位置 | 职责 |
| --- | --- |
| `entry/src/main/ets/pages/Index.ets` | Navigation 入口 |
| `entry/src/main/ets/pages/HomePage.ets` | 主列表、筛选搜索、统计、回收站、导入导出 |
| `entry/src/main/ets/pages/AddTodoPage.ets` | NavDestination 新增/编辑表单及返回确认 |
| `entry/src/main/ets/pages/NetworkPage.ets` | 独立示例任务页、折叠演示设置、正常恢复及 DataPanel |
| `entry/src/main/ets/pages/DeepSeekPage.ets` | 密钥配置、目标输入、计划预览及导入确认 |
| `entry/src/main/ets/viewmodel/DeepSeekStore.ets` | 会话密钥、请求状态、示例来源及原子批量导入 |
| `entry/src/main/ets/common/DeepSeekService.ets` | 固定官方 HTTPS 请求、Bearer 鉴权及完整 JSON 校验 |
| `entry/src/main/ets/components/TodoItem.ets` | 行展示、完成事件、左滑删除 |
| `entry/src/main/ets/model/Todo.ets` | `@ObservedV2` 数据模型 |
| `entry/src/main/ets/viewmodel/TodoStore.ets` | 校验、持久化提交、筛选排序、统计、导入恢复 |
| `entry/src/main/ets/viewmodel/NetworkStore.ets` | 远端列表、加载/失败/空态、完成比例及会话代理校验 |
| `entry/src/main/ets/common/ApiService.ets` | 示例 HTTP 请求、响应校验、连接释放 |
| `entry/src/main/ets/common/FormService.ets` | 卡片快照、磁盘读取、已发布实例查询与串行推送 |
| `entry/src/main/ets/common/TodoDate.ets` | 截止日期/时分组合与显示 |
| `entry/src/main/ets/common/Theme.ets`、`Sym.ets` | 主题值与系统符号 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 应用启动与本地数据恢复 |
| `entry/src/main/ets/entryformability/EntryFormAbility.ets` | 卡片生命周期 |
| `entry/src/main/ets/widget/pages/WidgetCard.ets` | 2×2 卡片界面 |

## 数据与课程材料

本轮报告使用 `docs/移动应用开发课程报告_TodoApp_提交版.docx`；模板版、修复版和 DeepSeek 版保留作历史稿。既有 `docs/evidence/submission-*.png` 与同名 JSON 记录前一轮状态，网络图注明确标为改版前历史；新版截图尚待采集。补拍时另存原始画面和同名界面树，核对来源、状态、数值与图注，避免覆盖历史证据。离线规划示例须保留来源标识。OneDrive报告副本需在正式工程文档更新完成后另行同步并比对，不沿用旧版本哈希声明为本次同步结果。

### DeepSeek 使用步骤

1. 首页点击“DeepSeek 智能拆解”，在密码框填写本人 API Key，点击“应用密钥”。密钥仅当前应用进程有效，可点击“清除密钥”，不写文件、Preferences、日志或任务备份。
2. 输入 1–1000 字目标，点击“DeepSeek 生成”。只发送目标与固定规划提示，不自动上传个人待办。使用官方 `https://api.deepseek.com/chat/completions`、`deepseek-flash`、JSON 输出和非思考模式。
3. 核对建议后点击“确认加入”，二次确认后整批保存，可继续编辑、设置截止和完成。鉴权、余额、限流和网络异常会提示，失败不导入部分任务。
4. 可在“配置 → 可选网络代理”填写会话代理，留空恢复系统代理；与网络示例页的代理分别管理。
5. 没有密钥可点击“查看离线示例”，页面明确标注固定课堂案例。已核对离线示例、API来源预览及导入反馈等既有界面，二者分开记录；本次未重新使用有效密钥调用接口，真实鉴权与在线成功响应仍需独立请求证据。

主要本地数据位于应用沙箱的 `todo_store` Preferences：`todos_json` 存储完整任务数组，`seeded` 标识已建立本地库。JSON 导出包含回收站事项；同一份备份再次导入会合并并分配冲突编号，不会自动去重。

课程报告内容稿位于 `docs/移动应用开发课程报告_待办事项App.md`，最终Word使用上述提交版。报告保留学校模板的A4版面、封面、字体行距、自动多级标题编号与三线表；本轮16页逐页视觉QA已完成，243段、5张原生表、11张图片完整。仅31段文本变化，原有段落与文字格式属性、其余包部件保持。原有学生信息保持不变，选题登记仍需本人核实；教师评阅、成绩和签名栏按模板留空。页面演示步骤见 `docs/课程提交清单.md`，评分映射见 `docs/评分项核对_2026-11-26.md`；本轮报告QA和文件一致性见 `docs/报告同步记录_2026-11-27.md`，此前证据及历史边界见 `docs/升级复核与截图验收_2026-11-26.md`。

真实 Git 记录自 2026 年 11 月 26 日建立：`3ee526b` 为既有工程基线，`176af14` 为补齐计划，`4f59075` 为独立网络功能，`1c03dbf` 为网络设置及布局修正，`a3533f3` 为首页计数修复，`3d8e66b` 为远端样本切组与图表动态演示；后续以实际日志为准。此前开发没有可核验的 Git 历史，不补造过去的分阶段提交，也不声称全程版本管理要求已经满足。本轮维护提交使用 Codex 工具身份。当前评分截图要求保留分阶段、完整且真实的 Git 历史，未要求必须公开托管；如老师另有仓库链接要求，再按本人实际账号及地址办理。
