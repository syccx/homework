# 待办清单 TodoApp

HarmonyOS 原生待办应用，采用 ArkTS、Stage 模型、ArkUI 状态管理 V2 和 Navigation。项目用于移动应用开发课程，正式工程位于 `D:\DevEcoStudioProjects\TodoApp`。

## 当前交付状态

2026 年 11 月 26 日，本轮完善后的 `assembleHap` 已成功，产物为未签名的 `entry-default-unsigned.hap`。数据层、卡片服务、页面逻辑和日期处理的本地回归检查已通过。DevEco Previewer 的实际交互仍在复验，不能将编译和本地测试等同于真机验收。

当前 `hdc list targets` 返回空列表；本机模拟器配置所指向的 `C:\Users\30357\AppData\Local\Huawei\Sdk` 镜像未就绪，尚未启动可安装应用的设备。签名配置也仍为空。真机持久化、真实网络和桌面卡片全流程均需设备验证，详情见 `docs/验收记录_2026-11-26.md`。

## 已实现功能

- 新建、编辑、完成与取消完成；标题必填，标题最多 200 字符、描述最多 5000 字符。
- 截止日期和具体时分分别选择；新设日期默认 18:00，可清除截止时间，列表标识逾期事项。
- 按全部、进行中、已完成筛选；按标题或描述搜索。排序依次考虑完成状态、截止时间、优先级、创建时间。
- 软删除、回收站恢复、单条彻底删除、清空回收站和批量移入已完成事项；不可恢复操作带确认。
- 近 7 天完成趋势、连续完成天数；主列表进度排除回收站事项。软删除保留完成历史，彻底删除或取消完成后不再计入。
- 导出完整 JSON 到剪贴板；粘贴 JSON 合并导入。整批校验后保存，冲突编号重新分配；一次最多导入 1000 条，JSON 内容限 2 MB。
- 本地 Preferences 持久化；先同步落盘，再提交界面状态。保存失败保留已保存内容与表单，便于重试。
- 首次无本地库时尝试获取 5 条网络示例。离线仍可新建，迟到的示例响应不会覆盖用户操作，手动清空后的数据库不会再次被自动灌入示例。
- 已保存 JSON 异常时保留原始内容并阻止意外覆盖；可先导出，再通过有效 JSON 显式恢复，原始异常内容另留恢复副本。
- 2×2 桌面卡片显示未完成数量和最新待办，点击打开应用。主动推送通过系统查询已发布实例，不依赖进程内卡片 ID 注册表；卡片新增、重新可见及定时刷新会读取已保存数据。
- 新增/编辑页可滚动；返回时对未保存修改做确认，保存后回到可见的全部待办列表。

下拉刷新用于重算本地状态和刷新卡片，不会用远端示例覆盖个人事项。通知提醒、云同步、账号系统和跨设备同步尚未实现。

## 开发环境

| 项目 | 当前配置 |
| --- | --- |
| IDE | DevEco Studio 26.0.0 Release |
| SDK | HarmonyOS API 26，版本配置 `26.0.0` |
| 包名 | `com.example.todoapp` |
| 正式工程 | `D:\DevEcoStudioProjects\TodoApp` |
| IDE 安装 | `D:\DevEco Studio` |
| 源码备份目标 | `D:\OneDrive\文档\deepseek-harness\default-workspace\TodoApp` |
| 本轮改动前备份 | `D:\DevEcoStudioProjects\TodoApp_backups\before_20261126_1700` |

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

四项本地检查分别执行，任意脚本退出码非 0 都应先处理失败项：

```powershell
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-store.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-forms.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-pages.cjs
& 'D:\DevEco Studio\tools\node\node.exe' scripts/test-date.cjs
```

本轮结果为数据/网络 24 个用例、卡片 6 个用例、页面逻辑 8 个用例通过，日期脚本 5 组断言通过。这些脚本读取真实 `.ets` 源码，使用本机 SDK 的 TypeScript 转译器执行可独立测试的逻辑，并模拟系统服务；它们不覆盖 ArkUI 实际布局、真实设备 Preferences、系统剪贴板授权或桌面宿主行为。脚本当前依赖上述本机 SDK 安装路径，移机时需相应调整。

## DevEco Studio 中运行

1. 打开正式工程目录，等待同步完成；外部文件修改后在 IDE 中重新加载磁盘内容。
2. 使用 Previewer 复验页面。Previewer 不执行正常的 `EntryAbility` 启动流程，预览中通过表单产生的数据仅在当次预览中保留，页面会提示该限制。
3. 如需安装，先准备可用的鸿蒙真机或完整的匹配模拟器镜像，并检查设备连接：

   ```powershell
   & 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' list targets
   ```

4. 在 IDE 的 Project Structure → Signing Configs 配置调试签名，必要时由本人登录华为账号。当前尚无签名配置。
5. 重新构建并通过 IDE 安装运行，按验收记录补做重启恢复、真实网络、剪贴板和桌面卡片测试。

## 代码入口

| 位置 | 职责 |
| --- | --- |
| `entry/src/main/ets/pages/Index.ets` | Navigation 入口 |
| `entry/src/main/ets/pages/HomePage.ets` | 主列表、筛选搜索、统计、回收站、导入导出 |
| `entry/src/main/ets/pages/AddTodoPage.ets` | NavDestination 新增/编辑表单及返回确认 |
| `entry/src/main/ets/components/TodoItem.ets` | 行展示、完成事件、左滑删除 |
| `entry/src/main/ets/model/Todo.ets` | `@ObservedV2` 数据模型 |
| `entry/src/main/ets/viewmodel/TodoStore.ets` | 校验、持久化提交、筛选排序、统计、导入恢复 |
| `entry/src/main/ets/common/ApiService.ets` | 示例 HTTP 请求、响应校验、连接释放 |
| `entry/src/main/ets/common/FormService.ets` | 卡片快照、磁盘读取、已发布实例查询与串行推送 |
| `entry/src/main/ets/common/TodoDate.ets` | 截止日期/时分组合与显示 |
| `entry/src/main/ets/common/Theme.ets`、`Sym.ets` | 主题值与系统符号 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 应用启动与本地数据恢复 |
| `entry/src/main/ets/entryformability/EntryFormAbility.ets` | 卡片生命周期 |
| `entry/src/main/ets/widget/pages/WidgetCard.ets` | 2×2 卡片界面 |

## 数据与课程材料

主要本地数据位于应用沙箱的 `todo_store` Preferences：`todos_json` 存储完整任务数组，`seeded` 标识已建立本地库。JSON 导出包含回收站事项；同一份备份再次导入会合并并分配冲突编号，不会自动去重。

提交课程材料前，应自行填写真实姓名、学号与班级，提供实际的运行截图或录屏。如果课程要求版本管理记录，需要先建立并使用真实仓库；当前正式工程不是 Git 仓库，本文不提供虚构的提交历史。
