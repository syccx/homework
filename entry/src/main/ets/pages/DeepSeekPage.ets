import { DeepSeekStore } from '../viewmodel/DeepSeekStore';
import { DeepSeekTask } from '../common/DeepSeekService';
import { Theme } from '../common/Theme';
import { Sym } from '../common/Sym';

/** DeepSeek 目标拆解：密钥配置、在线生成、可辨识示例、确认后批量加入。 */
@ComponentV2
export struct DeepSeekPage {
  @Param navPathStack: NavPathStack = new NavPathStack();
  @Local store: DeepSeekStore = DeepSeekStore.instance;
  @Local settingsOpen: boolean = true;
  @Local proxyOpen: boolean = false;
  @Local keyInput: string = '';
  @Local proxyHostInput: string = '';
  @Local proxyPortInput: string = '';
  @Local goalExpanded: boolean = false;

  aboutToAppear(): void {
    this.settingsOpen = !this.store.hasKey && this.store.tasks.length === 0;
    this.proxyHostInput = this.store.proxyHost;
    this.proxyPortInput = this.store.proxyPort === 0 ? '' : this.store.proxyPort.toString();
  }

  aboutToDisappear(): void {
    this.keyInput = '';
  }

  private applyKey(): void {
    if (this.store.configureKey(this.keyInput)) {
      this.keyInput = '';
    }
  }

  private confirmAdd(): void {
    const label = this.store.source === 'example' ? '离线示例' : 'DeepSeek 建议';
    this.getUIContext().showAlertDialog({
      title: `加入 ${this.store.tasks.length} 条待办？`,
      message: `来源：${label}。确认后一次性保存到本地，保留现有任务。建议内容请自行核对。`,
      primaryButton: { value: '再看看', action: () => {} },
      secondaryButton: { value: '确认加入', action: () => { this.store.addToTodos(); } }
    });
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 10 }) {
          Button() {
            SymbolGlyph(Sym.chevronLeft).fontSize(18).fontColor([Theme.fg])
          }
          .id('deepseek-back')
          .width(38).height(38).backgroundColor(Theme.card)
          .accessibilityText('返回首页')
          .onClick(() => { this.navPathStack.pop(); })
          Column({ space: 2 }) {
            Text('DeepSeek 智能拆解').fontSize(Theme.tTitle).fontWeight(FontWeight.Bold).fontColor(Theme.fg)
            Text('目标 → 行动计划 → 个人待办').fontSize(Theme.tMicro).fontColor(Theme.fgDim)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button('配置')
            .id('deepseek-settings')
            .height(34).fontSize(Theme.tSub).fontColor(Theme.accent).backgroundColor(Theme.card)
            .enabled(!this.store.loading)
            .onClick(() => { this.settingsOpen = !this.settingsOpen; })
        }.width('100%').padding({ left: 20, right: 20, top: 14, bottom: 14 })

        Scroll() {
          Column({ space: 14 }) {
            if (this.store.tasks.length === 0) {
              Column({ space: 5 }) {
                Text('把大目标，变成下一步').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Theme.fg)
                Text('生成 3–6 条可执行建议，由你决定是否加入。')
                  .fontSize(Theme.tSub).fontColor(Theme.fgDim)
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 2 })
            }

            if (this.settingsOpen) {
              this.keySettings()
            }
            this.goalCard()

            if (this.store.loading) {
              Row({ space: 10 }) {
                LoadingProgress().width(24).height(24).color(Theme.accent)
                Text('DeepSeek 正在规划，通常需要几秒钟…').fontSize(Theme.tSub).fontColor(Theme.fgDim)
              }.id('deepseek-loading').width('100%').padding(14).backgroundColor(Theme.card).borderRadius(Theme.rItem)
            }
            if (this.store.error !== '') {
              Column({ space: 5 }) {
                Text(this.store.error).fontSize(Theme.tSub).fontColor(Theme.danger)
                if (this.store.tasks.length > 0) {
                  Text('下方保留上次预览，请以来源标记为准。').fontSize(Theme.tMicro).fontColor(Theme.fgDim)
                }
              }.id('deepseek-error').width('100%').alignItems(HorizontalAlign.Start)
                .padding(14).backgroundColor(Theme.card).borderRadius(Theme.rItem)
            }
            if (this.store.notice !== '') {
              Text(this.store.notice).id('deepseek-notice').width('100%').fontSize(Theme.tSub).fontColor(Theme.accent)
            }
            if (this.store.tasks.length > 0) {
              this.planPreview()
            }
          }.width('100%').padding({ left: 20, right: 20, bottom: 24 }).alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)

        if (this.store.tasks.length > 0) {
          Column({ space: 7 }) {
            Button(this.store.added ? '已加入待办 · 返回首页' : `确认加入 ${this.store.tasks.length} 条待办`)
              .id('deepseek-confirm-add')
              .width('100%').height(46).fontSize(Theme.tBody).fontWeight(FontWeight.Medium)
              .fontColor(Theme.onAccent).backgroundColor(Theme.accent).enabled(!this.store.loading)
              .onClick(() => {
                if (this.store.added) { this.navPathStack.pop(); } else { this.confirmAdd(); }
              })
            Text(this.store.added ? '已完成本次导入，不会重复加入。' : '生成和预览不会修改原有待办，确认后才保存。')
              .fontSize(Theme.tMicro).fontColor(Theme.fgDim)
          }.width('100%').padding({ left: 20, right: 20, top: 10, bottom: 12 })
        }
      }.width('100%').height('100%').backgroundColor(Theme.bg)
    }.hideTitleBar(true)
  }

  @Builder
  keySettings() {
    Column({ space: 10 }) {
      Row() {
        Text('API 密钥').fontSize(Theme.tBody).fontWeight(FontWeight.Medium).fontColor(Theme.fg).layoutWeight(1)
        Text(this.store.hasKey ? '本次会话已配置' : '未配置')
          .id('deepseek-key-status').fontSize(Theme.tMicro).fontColor(this.store.hasKey ? Theme.accent : Theme.fgDim)
      }.width('100%')
      TextInput({ placeholder: '输入 sk- 开头的 DeepSeek API Key', text: this.keyInput })
        .id('deepseek-key-input').type(InputType.Password).showPasswordIcon(false)
        .height(44).fontSize(Theme.tSub).fontColor(Theme.fg).placeholderColor(Theme.fgFaint).backgroundColor(Theme.cardHi)
        .enabled(!this.store.loading).onChange((value: string) => { this.keyInput = value; })
      Row({ space: 8 }) {
        Button('应用密钥').id('deepseek-apply-key').height(34).fontSize(Theme.tSub)
          .fontColor(Theme.onAccent).backgroundColor(Theme.accent).enabled(!this.store.loading)
          .onClick(() => this.applyKey())
        if (this.store.hasKey) {
          Button('清除密钥').id('deepseek-clear-key').height(34).fontSize(Theme.tSub)
            .fontColor(Theme.fgDim).backgroundColor(Theme.cardHi).enabled(!this.store.loading)
            .onClick(() => { this.store.clearKey(); this.keyInput = ''; })
        }
      }.width('100%')
      Text('密钥仅在当前应用会话使用，不写入文件、任务备份或日志。退出进程后需重新配置。')
        .fontSize(Theme.tMicro).fontColor(Theme.fgDim).lineHeight(17)
      Text('官方接口 · api.deepseek.com\n模型 · deepseek-flash（非思考模式）')
        .fontSize(Theme.tMicro).fontColor(Theme.fgDim).lineHeight(18)
      Button(this.proxyOpen ? '收起可选代理' : '可选网络代理')
        .id('deepseek-proxy-toggle').height(28).fontSize(Theme.tMicro).fontColor(Theme.accent).backgroundColor(Color.Transparent)
        .onClick(() => { this.proxyOpen = !this.proxyOpen; })
      if (this.proxyOpen) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '主机，如 192.168.1.2', text: this.proxyHostInput })
            .id('deepseek-proxy-host').layoutWeight(2).height(40).fontSize(Theme.tSub)
            .fontColor(Theme.fg).placeholderColor(Theme.fgFaint).backgroundColor(Theme.cardHi).enabled(!this.store.loading)
            .onChange((value: string) => { this.proxyHostInput = value; })
          TextInput({ placeholder: '端口', text: this.proxyPortInput })
            .id('deepseek-proxy-port').type(InputType.Number).layoutWeight(1).height(40).fontSize(Theme.tSub)
            .fontColor(Theme.fg).placeholderColor(Theme.fgFaint).backgroundColor(Theme.cardHi).enabled(!this.store.loading)
            .onChange((value: string) => { this.proxyPortInput = value; })
        }.width('100%')
        Button('应用代理（留空恢复系统代理）').id('deepseek-apply-proxy').height(32)
          .fontSize(Theme.tMicro).fontColor(Theme.accent).backgroundColor(Theme.cardHi).enabled(!this.store.loading)
          .onClick(() => { this.store.configureProxy(this.proxyHostInput, this.proxyPortInput); })
      }
      Text(this.store.proxyHost === '' ? '当前网络：系统代理' : `当前网络：会话代理 ${this.store.proxyHost}:${this.store.proxyPort}`)
        .fontSize(Theme.tMicro).fontColor(Theme.fgFaint)
    }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      .backgroundColor(Theme.card).borderRadius(Theme.rCard)
  }

  @Builder
  goalCard() {
    Column({ space: 10 }) {
      Row() {
        Text('我的目标').fontSize(Theme.tBody).fontWeight(FontWeight.Medium).fontColor(Theme.fg).layoutWeight(1)
        if (this.store.tasks.length > 0 && !this.goalExpanded) {
          Text('修改目标').fontSize(Theme.tMicro).fontColor(Theme.accent)
            .id('deepseek-edit-goal').onClick(() => { this.goalExpanded = true; })
        } else {
          Text(`${this.store.goal.length}/1000`).fontSize(Theme.tMicro).fontColor(Theme.fgFaint)
        }
      }.width('100%')
      if (this.store.tasks.length === 0 || this.goalExpanded) {
        TextArea({ placeholder: '例如：一周内完成鸿蒙待办应用课程设计', text: this.store.goal })
          .id('deepseek-goal').height(76).maxLength(1000).fontSize(Theme.tBody)
          .fontColor(Theme.fg).placeholderColor(Theme.fgFaint).backgroundColor(Theme.cardHi).enabled(!this.store.loading)
          .onChange((value: string) => { this.store.goal = value; })
      } else {
        Text(this.store.goal).fontSize(Theme.tSub).fontColor(Theme.fg).width('100%').maxLines(2)
      }
      Row({ space: 10 }) {
        Button(this.store.loading ? '生成中…' : 'DeepSeek 生成')
          .id('deepseek-generate').layoutWeight(1).height(38).fontSize(Theme.tSub)
          .fontColor(Theme.onAccent).backgroundColor(Theme.accent).enabled(!this.store.loading)
          .onClick(() => { this.store.generate().then(() => {
            if (this.store.error === '') { this.goalExpanded = false; }
          }); })
        Button('查看离线示例')
          .id('deepseek-example').layoutWeight(1).height(38).fontSize(Theme.tSub)
          .fontColor(Theme.fg).backgroundColor(Theme.cardHi).enabled(!this.store.loading)
          .onClick(() => { this.store.showExample(); this.settingsOpen = false; this.goalExpanded = false; this.keyInput = ''; })
      }.width('100%')
      Text('在线仅发送上方目标，不自动上传个人待办；调用将使用你的 API 额度。')
        .fontSize(Theme.tMicro).fontColor(Theme.fgDim).lineHeight(17)
    }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      .backgroundColor(Theme.card).borderRadius(Theme.rCard)
  }

  @Builder
  planPreview() {
    Column({ space: 8 }) {
      Row() {
        Text('行动计划').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.fg).layoutWeight(1)
        Text(`${this.store.tasks.length} 项待确认`).fontSize(Theme.tMicro).fontColor(Theme.accent)
      }.width('100%')
      Column({ space: 4 }) {
        Text(this.store.source === 'example' ? '离线示例 · 固定课堂案例，不是 API 返回' : '来源：DeepSeek API · deepseek-flash')
          .id('deepseek-source').fontSize(Theme.tMicro).fontColor(Theme.accent)
        Text(`本次预览目标：${this.store.resultGoal}`).fontSize(Theme.tMicro).fontColor(Theme.fgDim).lineHeight(17)
      }.width('100%').alignItems(HorizontalAlign.Start)
      ForEach(this.store.tasks, (task: DeepSeekTask, index: number) => {
        Row({ space: 10 }) {
          Text((index + 1).toString().padStart(2, '0')).fontSize(Theme.tSub).fontWeight(FontWeight.Bold)
            .fontColor(Theme.accent).width(28).height(28).textAlign(TextAlign.Center)
            .backgroundColor(Theme.cardHi).borderRadius(8).alignSelf(ItemAlign.Start)
          Column({ space: 5 }) {
            Row({ space: 6 }) {
              Text(task.title).fontSize(Theme.tBody).fontWeight(FontWeight.Medium).fontColor(Theme.fg).layoutWeight(1)
              if (task.priority === 1) {
                Text('高优先').fontSize(9).fontColor(Theme.accent).padding({ left: 5, right: 5, top: 3, bottom: 3 })
                  .backgroundColor(Theme.cardHi).borderRadius(5)
              }
            }.width('100%')
            Text(task.description).fontSize(12).fontColor(Theme.fgDim).lineHeight(18).width('100%')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.id(`deepseek-task-${index}`).width('100%').padding({ top: 4, bottom: 4 }).alignItems(VerticalAlign.Top)
      }, (task: DeepSeekTask) => task.title)
    }.id('deepseek-plan').width('100%').padding(16).alignItems(HorizontalAlign.Start)
      .backgroundColor(Theme.card).borderRadius(Theme.rCard)
  }
}
