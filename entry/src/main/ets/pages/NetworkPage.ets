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
  @Local proxyOpen: boolean = false;
  @Local proxyHostInput: string = '';
  @Local proxyPortInput: string = '';

  aboutToAppear(): void {
    this.store.load();
  }

  private refresh(): void {
    this.store.load().finally(() => {
      this.refreshing = false;
    });
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

  private scenarioLabel(mode: string): string {
    if (mode === 'empty') {
      return '空列表';
    }
    if (mode === 'error') {
      return 'HTTP 错误';
    }
    return '正常列表';
  }

  private updatedLabel(): string {
    if (this.store.lastUpdatedAt === 0) {
      return '尚无成功结果';
    }
    const d = new Date(this.store.lastUpdatedAt);
    return `上次成功：${d.toLocaleTimeString()} · ${this.scenarioLabel(this.store.lastSuccessfulMode)}`;
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
          .onClick(() => { this.navPathStack.pop(); })
          Text('网络示例')
            .fontSize(Theme.tTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.fg)
            .layoutWeight(1)
          Button(this.store.loading ? '请求中' : '刷新')
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
              this.scenarios()
              this.previewNetworkSettings()

              if (this.store.loading) {
                Row({ space: 10 }) {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .color(Theme.accent)
                  Text('正在请求远端数据…')
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
                  Text('远端返回空列表')
                    .fontSize(Theme.tBody)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.fg)
                  Text('请求已成功，本次没有待办数据。可切回“正常”场景再次请求。')
                    .fontSize(Theme.tSub)
                    .fontColor(Theme.fgDim)
                    .textAlign(TextAlign.Center)
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
              Text('数据来源：JSONPlaceholder 公开测试服务。这里只展示远端示例，不会导入或覆盖个人待办。成功列表支持下拉刷新。')
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
  scenarios() {
    Column({ space: 10 }) {
      Text('远端请求场景')
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
      Text('正常：GET /todos，校验后取前 5 条；空列表：GET /todos?userId=0；错误：GET /this-route-does-not-exist，预期远端返回 404。三种场景都实际联网，返回结果以服务端为准。')
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
  failure() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph(Sym.cloudOff)
          .fontSize(22)
          .fontColor([Theme.danger])
        Text('远端请求失败')
          .fontSize(Theme.tBody)
          .fontColor(Theme.fg)
      }
      Text(this.store.error)
        .id('network-error-message')
        .fontSize(Theme.tSub)
        .fontColor(Theme.danger)
      Text(this.store.loaded ? '以下仍为上次成功结果，并非本次请求的新数据。' : '还没有成功结果，请重试或切换到正常场景。')
        .fontSize(Theme.tSub)
        .fontColor(Theme.fgDim)
      Button('重试本场景')
        .id('network-retry')
        .fontSize(Theme.tSub)
        .fontColor(Theme.onAccent)
        .backgroundColor(Theme.accent)
        .enabled(!this.store.loading)
        .onClick(() => this.refresh())
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .borderRadius(Theme.rCard)
    .backgroundColor(Theme.card)
  }

  @Builder
  chart() {
    Column({ space: 12 }) {
      Text('远端列表完成比例')
        .fontSize(Theme.tBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.fg)
      Stack() {
        DataPanel({
          values: this.store.chartValues,
          max: this.store.items.length,
          type: DataPanelType.Circle
        })
          .id('network-chart')
          .width(152)
          .height(152)
          .valueColors([Theme.accent, Theme.fgFaint])
          .trackBackgroundColor(Theme.cardHi)
          .strokeWidth(12)
          .closeEffect(true)
        Column({ space: 4 }) {
          Text(`${Math.round(this.store.doneCount / this.store.items.length * 100)}%`)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.fg)
          Text('已完成')
            .fontSize(Theme.tMicro)
            .fontColor(Theme.fgDim)
        }
      }
      .width('100%')
      Row({ space: 20 }) {
        Row({ space: 6 }) {
          Circle().width(8).height(8).fill(Theme.accent)
          Text(`已完成 ${this.store.doneCount}`)
            .fontSize(Theme.tSub)
            .fontColor(Theme.fg)
        }
        Row({ space: 6 }) {
          Circle().width(8).height(8).fill(Theme.fgFaint)
          Text(`未完成 ${this.store.pendingCount}`)
            .fontSize(Theme.tSub)
            .fontColor(Theme.fg)
        }
      }
      Text(`合计 ${this.store.items.length} 条 · 随每次成功请求更新`)
        .fontSize(Theme.tMicro)
        .fontColor(Theme.fgDim)
    }
    .padding(16)
    .width('100%')
    .borderRadius(Theme.rCard)
    .backgroundColor(Theme.card)
  }

  @Builder
  remoteList() {
    Column({ space: 10 }) {
      Text(`远端待办 · ${this.store.items.length} 条`)
        .fontSize(Theme.tBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.fg)
      ForEach(this.store.items, (todo: Todo) => {
        Row({ space: 10 }) {
          SymbolGlyph(todo.done ? Sym.checkCircleFill : Sym.circleDashed)
            .fontSize(22)
            .fontColor([todo.done ? Theme.accent : Theme.fgFaint])
          Column({ space: 4 }) {
            Text(todo.title)
              .fontSize(Theme.tBody)
              .fontColor(Theme.fg)
            Text(`#${todo.id} · ${todo.done ? '已完成' : '未完成'}`)
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
