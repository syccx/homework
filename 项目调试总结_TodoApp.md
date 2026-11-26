# 待办事项 App（TodoApp）项目总结报告

> 生成时间：2026-11-26 15:16
> 工程路径：`D:\DevEcoStudioProjects\TodoApp`
> 源码备份：`D:\OneDrive\文档\deepseek-harness\default-workspace\TodoApp`

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
| `D:\OneDrive\文档\deepseek-harness\default-workspace\移动应用开发课程报告_待办事项App.md` | 课程报告正文（185 行） |

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

共 9 个 `.ets` 文件，554 行。

```
entry/src/main/ets/
├── entryability/
│   └── EntryAbility.ets         41 行   应用生命周期，loadContent('pages/Index')
├── pages/
│   ├── Index.ets                28 行   @Entry 入口，Navigation 导航容器
│   ├── HomePage.ets            154 行   统计卡片 + 三态渲染 + 下拉刷新 + 悬浮新增按钮
│   └── AddTodoPage.ets         114 行   表单：标题 / 描述 / 优先级二选一
├── components/
│   └── TodoItem.ets             67 行   自定义复用组件，勾选 / 删除 / 高优先级标记
├── model/
│   └── Todo.ets                 18 行   @ObservedV2 + 字段级 @Trace
├── viewmodel/
│   └── TodoStore.ets            56 行   全局单例仓库，add / remove / toggle / load
└── common/
    └── ApiService.ets           41 行   http 请求 jsonplaceholder，finally 中 destroy
```

分层为 model / viewmodel / components / common / pages，与报告里"按功能分层、职责清晰"的表述一致。

---

## 四、技术考核点对应关系

| 课程要求 | 代码落点 | 具体实现 |
| --- | --- | --- |
| 容器组件 | `HomePage.ets` | `Stack` 作为最外层铺底，`Column` 纵向组织，`Row` 并排三张统计卡，`List` + `ListItem` 渲染列表，`Blank()` 撑开剩余空间 |
| 自定义组件 | `TodoItem.ets` | `@ComponentV2` + `@Require @Param todo` 接收数据，`@Event onDelete` 向外抛删除事件 |
| 状态管理 V2 | `Todo.ets` / `TodoStore.ets` | `Todo` 用 `@ObservedV2` + 字段级 `@Trace`；仓库用静态单例 `TodoStore.instance`；页面用 `@Local` 持本地状态 |
| Navigation 路由 | `Index.ets` / `HomePage.ets` / `AddTodoPage.ets` | `pushPathByName('Add', null)` 入栈，`navPathStack.pop()` 出栈，`navDestination` 按路由名渲染 |
| 网络交互 | `ApiService.ets` / `HomePage.ets` | `http.createHttp()` 发 GET，校验 `responseCode !== 200` 抛错，`finally` 里 `destroy()` 释放连接 |
| 三态容错 | `HomePage.ets` 的 `@Builder body()` | 加载中转圈 / 异常提示 + 重新加载按钮 / 空数据提示 / 正常列表 + `Refresher` 下拉刷新 |

### 状态管理的细化说明

`TodoStore.todos` 重新赋值时整表刷新；勾选完成时直接改 `todo.done`，由字段级 `@Trace` 触发该行的局部刷新，避免整表重绘。这是 V2 相对 V1 最实用的一个点，报告里可以重点写。

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

### 关键教训

第 4 条是最致命的一条，且出现得最晚。

在此之前，SDK 版本号、依赖缺失、缓存损坏这三类问题被逐个修掉后，同步依然失败，很容易怀疑方向错了。真正的原因与代码、依赖、SDK 全无关系，只是路径里有两个汉字。

结论：**先确认工程路径是纯英文，再排查其他问题。** 这一步放在最前，能省掉大量弯路。

---

## 六、当前状态

### 已经验证通过的

- 工程在新路径下 hvigor 不再报路径违规，`--sync` 执行到 `Finished :entry:init`
- IDE 时间线显示"同步项目完成，耗时 5s 704ms"
- `oh_modules` 依赖安装完成，`.hvigor` 缓存已生成，`oh-package-lock.json5` 已产出
- 554 行源码全部落盘，9 个文件齐全
- `compatibleSdkVersion` / `targetSdkVersion` 与 SDK 26.0.0 对齐
- 入口 `EntryAbility` 正确指向 `pages/Index`

### 尚未完成的部分

- `entry/build/default/outputs/default/` 下还没有 HAP 产物
- Previewer 预览窗口还没有实际拉起

也就是说：**工程骨架完整、依赖齐全、同步通道打通，但界面渲染与打包链路还没有走完最后一步。**

---

## 七、下一步动作

按顺序执行，不要跳步。

1. 在 IDE 中打开 `entry/src/main/ets/pages/Index.ets`，点击编辑器右上角的 Previewer 图标启动预览
2. 观察首页是否正常渲染出三张统计卡与列表；如果报错，按提示行号定位，重点排查 V2 装饰器用法与 `Refresher` 的 API 签名
3. 执行一次 `assembleHap`，确认 HAP 产物生成，这一步通过即代表完整链路贯通

### 已知的潜在风险点

| 风险 | 说明 |
| --- | --- |
| `@Builder` 内的多条件分支 | `body()` 中 `if / else if / else` 链在 V2 下需要正常响应 `@Trace` 变化，预览时重点验证三态切换 |
| `Refresher` 签名 | `onRefreshing` 回调参数为 `RefreshStatus`，`state.finish(RefreshStatus.Faded)` 的写法需要与当前 SDK 版本对齐 |
| 网络请求 | Previewer 环境中 `http` 请求可能受网络策略影响，若拉不到数据会落在异常态，属预期行为，用"重新加载"按钮验证异常分支即可 |

---

## 八、报告提交前的待办

对照课程报告 `移动应用开发课程报告_待办事项App.md` 中的"提交前必改项"：

1. 填写基本信息中的学号 / 姓名 / 班级
2. 粘贴真实的 `git log --oneline` 截图与仓库地址
3. 核对工程内真实文件路径与报告描述一致（现已可核对：`D:\DevEcoStudioProjects\TodoApp`）
4. 如有演示录屏，附录屏链接（可选，推荐）
5. 按课程附带的 docx 模板调整版式（页眉、字体、标题层级）
