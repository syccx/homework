import { NetworkStore } from '../viewmodel/NetworkStore';
import { Todo } from '../model/Todo';
import { Theme } from '../common/Theme';
import { Sym } from '../common/Sym';

/** 独立网络业务页：进入即请求，刷新、空态与失败均使用真实远端接口。 */
@ComponentV2
export struct NetworkPage {
  @Param navPathStack: NavPathStack = new NavPathStack();
  @Local store: NetworkStore = NetworkStore.instance;
  @Local refreshing: boolean = false;
  @Local showDemoSettings: boolean = false;
  @Local proxyOpen: boolean = false;
  @Local proxyHostInput: string = '';
  @Local proxyPortInput: string = '';

  aboutToAppear(): void {
    this.showDemoSettings = false;
    this.proxyOpen = false;
    this.loadExamples();
  }

  private async loadExamples(): Promise<void> {
    await this.store.load('normal');
    // 进入页面时可能还有上一次演示请求在途，结束后再恢复普通浏览。
    if (this.store.mode !== 'normal') {
      await this.store.load('normal');
    }
  }

  private refresh(): void {
    this.loadExamples().finally(() => {
      this.refreshing = false;
    });
  }

  private toggleDemoSettings(): void {
    this.showDemoSettings = !this.showDemoSettings;
    if (!this.showDemoSettings) {
      this.proxyOpen = false;
    }
  }

  private toggleProxySettings(): void {
    this.proxyOpen = !this.proxyOpen;
    if (this.proxyOpen) {
      this.proxyHostInput = this.store.proxyHost;
      this.proxyPortInput = this.store.proxyPort === 0 ? '' : this.store.proxyPort.toString();
    }
  }

  private restoreSystemProxy(): void {
    this.store.applyProxy('', '').then((accepted: boolean) => {
      if (accepted) {
        this.proxyHostInput = '';
        this.proxyPortInput = '';
      }
    });
  }

  private scenarioLabel(mode: string, sampleGroup: number = this.store.sampleGroup): string {
    if (mode === 'empty') {
      return '空列表';
    }
    if (mode === 'error') {
      return 'HTTP 错误';
    }
    return `示例任务 · 第 ${sampleGroup} 组`;
  }

  private updatedLabel(): string {
    if (this.store.lastUpdatedAt === 0) {
      return '下拉即可刷新示例';
    }
    const d = new Date(this.store.lastUpdatedAt);
    const time: string = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
    return `更新于 ${time} · ${this.scenarioLabel(this.store.lastSuccessfulMode, this.store.lastSuccessfulGroup)}`;
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 12 }) {
          Button() {
            SymbolGlyph(Sym.chevronLeft)
              .fontSize(18)
              .fontColor([Theme.fg])
          }
          .id('network-back')
          .width(40)
          .height(40)
          .backgroundColor(Theme.card)
          .accessibilityText('返回首页')
          .onClick(() => { this.navPathStack.pop(); })
          Text('示例任务')
            .fontSize(Theme.tTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.fg)
            .layoutWeight(1)
          Button(this.store.loading ? '加载中' : '刷新')
            .id('network-refresh')
            .fontSize(Theme.tSub)
            .fontColor(Theme.onAccent)
            .backgroundColor(Theme.accent)
            .height(36)
            .enabled(!this.store.loading)
            .onClick(() => this.refresh())
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column({ space: 16 }) {
              Row({ space: 12 }) {
                Text('浏览公开任务，看看完成进度')
                  .fontSize(Theme.tSub)
                  .fontColor(Theme.fgDim)
                  .layoutWeight(1)
                Button(this.showDemoSettings ? '收起设置' : '演示设置')
                  .id('network-demo-settings-toggle')
                  .height(36)
                  .padding({ left: 10, right: 10 })
                  .fontSize(Theme.tMicro)
                  .fontColor(Theme.fgDim)
                  .backgroundColor(Color.Transparent)
                  .accessibilityText(this.showDemoSettings ? '收起演示设置' : '展开演示设置')
                  .onClick(() => this.toggleDemoSettings())
              }.width('100%')

              if (this.showDemoSettings) {
                this.demoSettings()
              }

              if (this.store.loading) {
                Row({ space: 10 }) {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .color(Theme.accent)
                  Text(this.store.items.length > 0 ? '正在更新任务…' : '正在加载示例任务…')
                    .fontSize(Theme.tSub)
                    .fontColor(Theme.fgDim)
                }
                .id('network-loading')
                .width('100%')
                .padding(16)
                .backgroundColor(Theme.card)
                .borderRadius(Theme.rCard)
              }

              if (this.store.error !== '') {
                this.failure()
              }

              if (this.store.items.length > 0) {
                this.chart()
                this.remoteList()
              } else if (this.store.loaded && !this.store.loading && this.store.error === '') {
                Column({ space: 12 }) {
                  SymbolGlyph(Sym.inbox)
                    .fontSize(40)
                    .fontColor([Theme.fgFaint])
                  Text('暂时没有示例任务')
                    .fontSize(Theme.tBody)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.fg)
                  Text('这里还没有可展示的内容，重新加载一组试试。')
                    .fontSize(Theme.tSub)
                    .fontColor(Theme.fgDim)
                    .textAlign(TextAlign.Center)
                  this.reloadExamples()
                }
                .id('network-empty-state')
                .padding(24)
                .width('100%')
                .borderRadius(Theme.rCard)
                .backgroundColor(Theme.card)
              }

              Text(this.updatedLabel())
                .id('network-updated')
                .fontSize(Theme.tMicro)
                .fontColor(Theme.fgDim)
                .width('100%')
              Text('公开示例仅供查看，不会改动你的待办。')
                .fontSize(Theme.tMicro)
                .fontColor(Theme.fgFaint)
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 20, right: 20, top: 4, bottom: 32 })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
        .onRefreshing(() => this.refresh())
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg)
    }
    .hideTitleBar(true)
  }

  @Builder
  demoSettings() {
    Column({ space: 12 }) {
      Text('课堂演示')
        .fontSize(Theme.tSub)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.fgDim)
      Text('以下选项用于演示空内容、加载失败和网络配置。日常浏览直接刷新即可。')
        .fontSize(Theme.tMicro)
        .fontColor(Theme.fgDim)
      this.scenarios()
      this.previewNetworkSettings()
      Text('数据来源：JSONPlaceholder 公开测试服务。这里只展示远端示例，不写入个人任务库。')
        .fontSize(Theme.tMicro)
        .fontColor(Theme.fgDim)
    }.id('network-demo-settings').width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  scenarios() {
    Column({ space: 10 }) {
      Text('演示场景')
        .fontSize(Theme.tBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.fg)
      Row({ space: 8 }) {
        Button('正常')
          .id('network-normal')
          .height(36)
          .padding({ left: 8, right: 8 })
          .layoutWeight(1)
          .fontSize(Theme.tSub)
          .fontColor(this.store.mode === 'normal' ? Theme.onAccent : Theme.fg)
          .backgroundColor(this.store.mode === 'normal' ? Theme.accent : Theme.cardHi)
          .enabled(!this.store.loading)
          .onClick(() => { this.store.load('normal'); })
        Button('空列表')
          .id('network-empty')
          .height(36)
          .padding({ left: 8, right: 8 })
          .layoutWeight(1)
          .fontSize(Theme.tSub)
          .fontColor(this.store.mode === 'empty' ? Theme.onAccent : Theme.fg)
          .backgroundColor(this.store.mode === 'empty' ? Theme.accent : Theme.cardHi)
          .enabled(!this.store.loading)
          .onClick(() => { this.store.load('empty'); })
        Button('HTTP 错误')
          .id('network-error')
          .height(36)
          .padding({ left: 8, right: 8 })
          .layoutWeight(1)
          .fontSize(Theme.tSub)
          .fontColor(this.store.mode === 'error' ? Theme.onAccent : Theme.fg)
          .backgroundColor(this.store.mode === 'error' ? Theme.accent : Theme.cardHi)
          .enabled(!this.store.loading)
          .onClick(() => { this.store.load('error'); })
      }
      .width('100%')
      Text('正常：GET /todos，第1组取第1–5条，第2组取第6–10条；空列表：GET /todos?userId=0；HTTP错误：GET /this-route-does-not-exist，预期404。各场景均发出真实请求。顶部刷新恢复正常列表，保留当前分组。')
        .fontSize(Theme.tMicro)
        .fontColor(Theme.fgDim)
      Text(`本次请求：${this.scenarioLabel(this.store.mode)}`)
        .fontSize(Theme.tSub)
        .fontColor(Theme.accent)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .borderRadius(Theme.rCard)
    .backgroundColor(Theme.card)
  }

  @Builder
  previewNetworkSettings() {
    Column({ space: 10 }) {
      Button(this.proxyOpen ? '收起预览网络设置' : '预览网络设置')
        .id('network-proxy-toggle')
        .fontSize(Theme.tSub)
        .fontColor(Theme.accent)
        .backgroundColor(Theme.cardHi)
        .height(36)
        .onClick(() => this.toggleProxySettings())
      Text(this.store.proxyHost === '' ? '当前：系统代理' : `当前：HTTP 代理 ${this.store.proxyHost}:${this.store.proxyPort}`)
        .id('network-proxy-current')
        .fontSize(Theme.tMicro)
        .fontColor(Theme.fgDim)
      if (this.proxyOpen) {
        Text('仅当前预览会话使用，不写入文件或个人待办。若系统代理无法联网，可填写可用的 HTTP 代理；无需代理时恢复系统设置。')
          .fontSize(Theme.tMicro)
          .fontColor(Theme.fgDim)
        TextInput({ placeholder: '代理主机名或 IPv4 地址（不含 http://）', text: this.proxyHostInput })
          .id('network-proxy-host')
          .fontSize(Theme.tSub)
          .fontColor(Theme.fg)
          .placeholderColor(Theme.fgFaint)
          .backgroundColor(Theme.cardHi)
          .height(42)
          .enabled(!this.store.loading)
          .onChange((value: string) => { this.proxyHostInput = value; })
        TextInput({ placeholder: '代理端口（1–65535）', text: this.proxyPortInput })
          .id('network-proxy-port')
          .type(InputType.Number)
          .fontSize(Theme.tSub)
          .fontColor(Theme.fg)
          .placeholderColor(Theme.fgFaint)
          .backgroundColor(Theme.cardHi)
          .height(42)
          .enabled(!this.store.loading)
          .onChange((value: string) => { this.proxyPortInput = value; })
        if (this.store.proxyError !== '') {
          Text(this.store.proxyError)
            .id('network-proxy-validation')
            .fontSize(Theme.tSub)
            .fontColor(Theme.danger)
        }
        Row({ space: 8 }) {
          Button('应用并请求')
            .id('network-proxy-apply')
            .height(36)
            .padding({ left: 12, right: 12 })
            .layoutWeight(1)
            .fontSize(Theme.tSub)
            .fontColor(Theme.onAccent)
            .backgroundColor(Theme.accent)
            .enabled(!this.store.loading)
            .onClick(() => { this.store.applyProxy(this.proxyHostInput, this.proxyPortInput); })
          Button('恢复系统代理')
            .id('network-proxy-system')
            .height(36)
            .padding({ left: 12, right: 12 })
            .layoutWeight(1)
            .fontSize(Theme.tSub)
            .fontColor(Theme.fg)
            .backgroundColor(Theme.cardHi)
            .enabled(!this.store.loading)
            .onClick(() => this.restoreSystemProxy())
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(Theme.rCard)
    .backgroundColor(Theme.card)
  }

  @Builder
  reloadExamples() {
    Button('重新加载示例')
      .id('network-return-normal')
      .height(40)
      .fontSize(Theme.tSub)
      .fontColor(Theme.onAccent)
      .backgroundColor(Theme.accent)
      .enabled(!this.store.loading)
      .onClick(() => this.refresh())
  }

  @Builder
  failure() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph(Sym.cloudOff)
          .fontSize(22)
          .fontColor([Theme.danger])
        Text(this.store.items.length > 0 ? '暂时没能更新任务' : '示例任务加载失败')
          .fontSize(Theme.tBody)
          .fontColor(Theme.fg)
      }
      Text(this.store.items.length > 0 ? '下方显示上次加载的结果，你可以稍后再试。' : '请检查网络连接，然后重新加载。')
        .fontSize(Theme.tSub)
        .fontColor(Theme.fgDim)
      this.reloadExamples()
      if (this.showDemoSettings) {
        Text(this.store.error)
          .id('network-error-message')
          .fontSize(Theme.tMicro)
          .fontColor(Theme.danger)
        Button('重试此演示')
          .id('network-retry')
          .height(36)
          .fontSize(Theme.tSub)
          .fontColor(Theme.accent)
          .backgroundColor(Theme.cardHi)
          .enabled(!this.store.loading)
          .onClick(() => { this.store.load(); })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .borderRadius(Theme.rCard)
    .backgroundColor(Theme.card)
  }

  @Builder
  chart() {
    Row({ space: 18 }) {
      Stack() {
        DataPanel({
          values: this.store.chartValues,
          max: this.store.items.length,
          type: DataPanelType.Circle
        })
          .id('network-chart')
          .width(96)
          .height(96)
          .valueColors([Theme.accent, Theme.fgFaint])
          .trackBackgroundColor(Theme.cardHi)
          .strokeWidth(8)
          .closeEffect(true)
        Column({ space: 4 }) {
          Text(`${Math.round(this.store.doneCount / this.store.items.length * 100)}%`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.fg)
          Text('已完成')
            .fontSize(Theme.tMicro)
            .fontColor(Theme.fgDim)
        }
      }
      .width(96)
      .height(96)
      Column({ space: 8 }) {
        Text('本组任务进度')
          .fontSize(Theme.tBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.fg)
        Text(`已完成 ${this.store.doneCount} 项 · 待完成 ${this.store.pendingCount} 项`)
          .fontSize(Theme.tSub)
          .fontColor(Theme.fgDim)
        Text(this.scenarioLabel(this.store.lastSuccessfulMode, this.store.lastSuccessfulGroup))
          .id('network-chart-source')
          .fontSize(Theme.tMicro)
          .fontColor(Theme.fgDim)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .padding(16)
    .width('100%')
    .borderRadius(Theme.rCard)
    .backgroundColor(Theme.card)
  }

  @Builder
  remoteList() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(`任务列表 · ${this.store.items.length} 项`)
          .fontSize(Theme.tBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.fg)
          .layoutWeight(1)
        Button('换一组')
          .id('network-next-group')
          .height(36)
          .padding({ left: 12, right: 12 })
          .fontSize(Theme.tSub)
          .fontColor(Theme.accent)
          .backgroundColor(Theme.cardHi)
          .enabled(!this.store.loading)
          .onClick(() => { this.store.loadNextGroup(); })
      }.width('100%')
      ForEach(this.store.items, (todo: Todo) => {
        Row({ space: 10 }) {
          SymbolGlyph(todo.done ? Sym.checkCircleFill : Sym.circleDashed)
            .fontSize(22)
            .fontColor([todo.done ? Theme.accent : Theme.fgFaint])
          Column({ space: 4 }) {
            Text(todo.title)
              .fontSize(Theme.tBody)
              .fontColor(Theme.fg)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(todo.done ? '已完成' : '待完成')
              .fontSize(Theme.tMicro)
              .fontColor(Theme.fgDim)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .id(`network-item-${todo.id}`)
        .padding(16)
        .width('100%')
        .borderRadius(Theme.rItem)
        .backgroundColor(Theme.card)
      }, (todo: Todo) => `${todo.id}-${todo.title}-${todo.done}`)
    }
    .id('network-list')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
