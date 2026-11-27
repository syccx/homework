import { TodoStore, DayPoint } from '../viewmodel/TodoStore';
import { Todo } from '../model/Todo';
import { TodoItem } from '../components/TodoItem';
import { Theme } from '../common/Theme';
import { Sym } from '../common/Sym';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * 首页：顶栏问候 + 进度总览 + 筛选条 + 列表四态 + 回收站
 * 本版新增：搜索框、统计卡（近 7 天趋势条 + 连续天数 + 导出）、回收站视图
 */
@ComponentV2
export struct HomePage {
  @Param navPathStack: NavPathStack = new NavPathStack();
  @Local store: TodoStore = TodoStore.instance;
  @Local refreshing: boolean = false;
  // 清空确认弹层目标
  @Local confirmKind: string = '';
  // 统计卡展开态（默认收起，点标题展开）
  @Local statOpen: boolean = false;
  @Local pendingDeleteId: number = 0;
  @Local importText: string = '';
  @Local importError: string = '';
  private clockTimer: number = -1;

  aboutToAppear(): void {
    this.clockTimer = setInterval(() => {
      this.store.refresh();
    }, 60000);
  }

  aboutToDisappear(): void {
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  private gotoAdd(): void {
    this.navPathStack.pushPathByName('Add', null);
  }

  private gotoNetwork(): void {
    this.navPathStack.pushPathByName('Network', null);
  }

  private gotoEdit(todo: Todo): void {
    this.navPathStack.pushPathByName('Add', todo);
  }

  // 进度比例 0-1
  private get progress(): number {
    const total = this.store.todoCount + this.store.doneCount;
    if (total === 0) {
      return 0;
    }
    return this.store.doneCount / total;
  }

  // 导出：JSON 写入剪贴板
  private exportData(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.store.exportJson());
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.store.notice = '备份 JSON 已复制，可粘贴保存到文件';
    } catch (e) {
      this.store.notice = '复制失败，请检查剪贴板权限后重试';
    }
  }

  private importData(): void {
    try {
      const count = this.store.importJson(this.importText);
      if (this.store.notice === '') {
        this.store.notice = `已导入 ${count} 条待办`;
      }
      this.store.filter = 'all';
      this.store.keyword = '';
      this.store.inTrash = false;
      this.importText = '';
      this.importError = '';
      this.confirmKind = '';
    } catch (e) {
      this.importError = (e as Error).message || '数据格式错误，未导入任何内容';
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部：问候 + 日期 + 回收站入口
        Row() {
          Column({ space: 2 }) {
            Text(this.greeting())
              .fontSize(Theme.tTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.fg)
            Text(this.dateLabel())
              .fontSize(Theme.tSub)
              .fontColor(Theme.fgDim)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          // 回收站入口（有内容时点亮）
          Button() {
            Row({ space: 4 }) {
              SymbolGlyph(Sym.trash)
                .fontSize(14)
                .fontColor([this.store.trashCount > 0 ? Theme.accent : Theme.fgFaint])
              Text(this.store.trashCount.toString())
                .fontSize(Theme.tMicro)
                .fontColor(this.store.trashCount > 0 ? Theme.accent : Theme.fgFaint)
            }
          }
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(Theme.rPill)
          .backgroundColor(Theme.card)
          .border({ width: 0.8, color: Theme.border })
          .margin({ right: 8 })
          .onClick(() => {
            this.store.inTrash = !this.store.inTrash;
          })

          // 新增按钮
          Button() {
            Row({ space: 5 }) {
              SymbolGlyph(Sym.plus)
                .fontSize(15)
                .fontColor([Theme.onAccent])
              Text('新建')
                .fontSize(Theme.tSub)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.onAccent)
            }
          }
          .backgroundColor(Theme.accent)
          .borderRadius(Theme.rPill)
          .height(36)
          .padding({ left: 14, right: 14 })
          .onClick(() => this.gotoAdd())
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 8 })

        Button() {
          Row({ space: 8 }) {
            SymbolGlyph(Sym.refresh)
              .fontSize(15)
              .fontColor([Theme.accent])
            Text('网络示例')
              .fontSize(Theme.tSub)
              .fontColor(Theme.fg)
            Text('远端列表 · 圆环统计')
              .fontSize(Theme.tMicro)
              .fontColor(Theme.fgDim)
          }
        }
        .id('home-network-entry')
        .height(36)
        .backgroundColor(Theme.card)
        .borderRadius(Theme.rPill)
        .border({ width: 0.8, color: Theme.border })
        .margin({ left: 20, right: 20, top: 2, bottom: 6 })
        .alignSelf(ItemAlign.Start)
        .onClick(() => this.gotoNetwork())

        Button() {
          Row({ space: 8 }) {
            SymbolGlyph(Sym.listCheck).fontSize(16).fontColor([Theme.accent])
            Text('DeepSeek 智能拆解').fontSize(Theme.tSub).fontWeight(FontWeight.Medium).fontColor(Theme.fg)
            Text('目标变计划').fontSize(Theme.tMicro).fontColor(Theme.fgDim)
          }
        }
        .id('home-deepseek-entry')
        .height(38)
        .backgroundColor(Theme.card)
        .borderRadius(Theme.rPill)
        .border({ width: 0.8, color: Theme.border })
        .margin({ left: 20, right: 20, bottom: 6 })
        .alignSelf(ItemAlign.Start)
        .onClick(() => { this.navPathStack.pushPathByName('DeepSeek', null); })

        if (this.store.storageError !== '' || this.store.notice !== '') {
          Row({ space: 8 }) {
            Text(this.store.storageError || this.store.notice)
              .fontSize(Theme.tMicro)
              .fontColor(this.store.storageError !== '' ? Theme.danger : Theme.fgDim)
              .layoutWeight(1)
            if (this.store.storageError === '') {
              Text('关闭')
                .fontSize(Theme.tMicro)
                .fontColor(Theme.accent)
                .onClick(() => { this.store.notice = ''; })
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 6, bottom: 6 })
        }

        // 搜索框（主视图显示）
        if (!this.store.inTrash) {
          Row({ space: 8 }) {
            SymbolGlyph(Sym.pencil)
              .fontSize(0)
              .fontColor([Theme.bg])
            TextInput({ placeholder: '搜索待办…', text: this.store.keyword })
              .fontSize(Theme.tSub)
              .fontColor(Theme.fg)
              .placeholderColor(Theme.fgFaint)
              .placeholderFont({ size: Theme.tSub })
              .backgroundColor(Theme.card)
              .borderRadius(Theme.rPill)
              .border({ width: 0.8, color: Theme.border })
              .height(38)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.store.keyword = value;
              })
            if (this.store.keyword !== '') {
              Text('取消')
                .fontSize(Theme.tMicro)
                .fontColor(Theme.accent)
                .onClick(() => {
                  this.store.keyword = '';
                })
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 4, bottom: 4 })
        }

        // 回收站视图：标题条
        if (this.store.inTrash) {
          Row({ space: 8 }) {
            Text('回收站')
              .fontSize(Theme.tBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.fg)
            Text(`${this.store.trashCount} 条`)
              .fontSize(Theme.tMicro)
              .fontColor(Theme.fgDim)
            Blank()
            if (this.store.trashCount > 0) {
              Text('清空回收站')
                .fontSize(Theme.tMicro)
                .fontColor(Theme.danger)
                .onClick(() => {
                  this.confirmKind = 'trash';
                })
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 6, bottom: 6 })
        } else {
          // 进度总览 + 统计卡
          this.overview()
        }

        Divider()
          .color(Theme.divider)
          .strokeWidth(1)
          .margin({ left: 20, right: 20 })

        // 列表主体
        this.body()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg)

      // 确认弹层
      if (this.confirmKind !== '') {
        if (this.confirmKind === 'import') {
          this.importLayer()
        } else {
          this.confirmLayer()
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  // 进度总览 + 可展开统计卡
  @Builder
  overview() {
    Column({ space: 12 }) {
      Row() {
        Text(this.store.doneCount.toString())
          .fontSize(Theme.tDisplay)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.fg)
        Text(' / ' + this.store.todos.filter((t: Todo) => !t.deleted).length)
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.fgFaint)
          .margin({ bottom: 4 })
        Blank()
        if (this.store.doneCount > 0 && !this.store.inTrash) {
          Text('清空已完成')
            .fontSize(Theme.tMicro)
            .fontColor(Theme.danger)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(Theme.rPill)
            .border({ width: 0.8, color: Theme.border })
            .backgroundColor(Theme.card)
            .onClick(() => {
              this.confirmKind = 'done';
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(4)
          .borderRadius(Theme.rPill)
          .backgroundColor(Theme.accentDeep)
          .opacity(0.35)
        Row()
          .width(this.progress * 100 + '%')
          .height(4)
          .borderRadius(Theme.rPill)
          .backgroundColor(Theme.accent)
      }
      .width('100%')

      // 筛选条
      Row({ space: 8 }) {
        this.filterChip('all', '全部')
        this.filterChip('active', '进行中')
        this.filterChip('done', '已完成')
        Blank()
        // 统计展开开关
        Text(this.statOpen ? '收起统计' : '统计')
          .fontSize(Theme.tMicro)
          .fontColor(Theme.accent)
          .onClick(() => {
            this.statOpen = !this.statOpen;
          })
      }
      .width('100%')

      // 统计卡：连击天数 + 近 7 天趋势条 + 导出
      if (this.statOpen) {
        Column({ space: 14 }) {
          Row({ space: 16 }) {
            Column({ space: 2 }) {
              Text(this.store.streakDays.toString())
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.accent)
              Text('连续天数')
                .fontSize(Theme.tMicro)
                .fontColor(Theme.fgDim)
            }
            .alignItems(HorizontalAlign.Start)

            Divider()
              .vertical(true)
              .color(Theme.divider)
              .strokeWidth(1)
              .height(34)

            // 近 7 天趋势：迷你条形图
            Row({ space: 6 }) {
              ForEach(this.store.weeklyTrend, (p: DayPoint) => {
                Column({ space: 4 }) {
                  // 条形：高度按占比 6-34vp
                  Column()
                    .width(16)
                    .height(p.count === 0 ? 4 : Math.min(34, 6 + p.count * 7))
                    .borderRadius(4)
                    .backgroundColor(p.count === 0 ? Theme.cardHi : Theme.accent)
                  Text(p.label)
                    .fontSize(10)
                    .fontColor(Theme.fgFaint)
                }
                .alignItems(HorizontalAlign.Center)
              })
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Bottom)

          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          Row({ space: 12 }) {
            Text('近 7 天完成情况')
              .fontSize(Theme.tMicro)
              .fontColor(Theme.fgFaint)
              .layoutWeight(1)
            Text('导入')
              .fontSize(Theme.tMicro)
              .fontColor(Theme.accent)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .onClick(() => {
                this.importText = '';
                this.importError = '';
                this.confirmKind = 'import';
              })
            Text('导出备份')
              .fontSize(Theme.tMicro)
              .fontColor(Theme.fgDim)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(Theme.rPill)
              .border({ width: 0.8, color: Theme.border })
              .onClick(() => this.exportData())
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
        .width('100%')
        .padding(14)
        .borderRadius(Theme.rItem)
        .backgroundColor(Theme.card)
        .border({ width: 0.8, color: Theme.border })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 4 })
  }

  @Builder
  body() {
    if (this.store.inTrash) {
      // 回收站列表：恢复 / 彻底删除
      if (this.store.trashOf.length === 0) {
        this.emptyBlock('回收站是空的', '删除的待办会先放到这里')
      } else {
        List({ space: 10 }) {
          ForEach(this.store.trashOf, (todo: Todo) => {
            ListItem() {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(todo.title)
                    .fontSize(Theme.tBody)
                    .fontColor(Theme.fgDim)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)

                Text('恢复')
                  .fontSize(Theme.tMicro)
                  .fontColor(Theme.accent)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .borderRadius(Theme.rPill)
                  .backgroundColor(Theme.cardHi)
                  .onClick(() => this.store.restore(todo.id))

                Text('彻底删除')
                  .fontSize(Theme.tMicro)
                  .fontColor(Theme.danger)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .borderRadius(Theme.rPill)
                  .border({ width: 0.8, color: Theme.danger })
                  .onClick(() => {
                    this.pendingDeleteId = todo.id;
                    this.confirmKind = 'delete';
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 12, top: 10, bottom: 10 })
              .borderRadius(Theme.rItem)
              .backgroundColor(Theme.card)
              .border({ width: 0.8, color: Theme.border })
            }
          }, (todo: Todo) => `${todo.id}`)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
    } else if (this.store.loading && this.store.todos.length === 0) {
      this.skeleton()
    } else if (this.store.errorMsg !== '' && this.store.todos.length === 0) {
      Column({ space: 14 }) {
        SymbolGlyph(Sym.cloudOff)
          .fontSize(44)
          .fontColor([Theme.fgFaint])
        Text('网络不可用')
          .fontSize(Theme.tBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.fg)
        Text('示例数据暂未加载，你仍可直接新建待办')
          .fontSize(Theme.tSub)
          .fontColor(Theme.fgDim)
        Button('重新加载')
          .fontSize(Theme.tSub)
          .fontColor(Theme.onAccent)
          .backgroundColor(Theme.accent)
          .borderRadius(Theme.rPill)
          .height(38)
          .padding({ left: 20, right: 20 })
          .onClick(() => this.store.reload())
        Button('离线新建')
          .fontColor(Theme.accent)
          .backgroundColor(Theme.card)
          .onClick(() => this.gotoAdd())
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.store.viewOf.length === 0) {
      this.emptyBlock(this.emptyTitle(), this.emptyHint())
    } else {
      Refresh({ refreshing: $$this.refreshing }) {
        List({ space: 10 }) {
          ForEach(this.store.viewOf, (todo: Todo) => {
            ListItem() {
              TodoItem({
                todo: todo,
                nowAt: this.store.nowAt,
                onToggle: (t: Todo) => {
                  this.store.toggle(t.id);
                },
                onDelete: (t: Todo) => {
                  this.store.remove(t.id);
                },
                onEdit: (t: Todo) => {
                  this.gotoEdit(t);
                }
              })
            }
          }, (todo: Todo) => JSON.stringify([todo.id, todo.done, todo.priority, todo.dueAt,
            todo.title, todo.description]))
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
        .scrollBar(BarState.Off)
      }
      .onRefreshing(() => {
        this.store.refresh().finally(() => {
          this.refreshing = false;
        });
      })
      .layoutWeight(1)
    }
  }

  @Builder
  emptyBlock(title: string, hint: string) {
    Column({ space: 12 }) {
      SymbolGlyph(Sym.inbox)
        .fontSize(44)
        .fontColor([Theme.fgFaint])
      Text(title)
        .fontSize(Theme.tBody)
        .fontColor(Theme.fg)
      Text(hint)
        .fontSize(Theme.tSub)
        .fontColor(Theme.fgDim)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  // 确认弹层（清空已完成 / 清空回收站）
  @Builder
  confirmLayer() {
    Column() {
      Blank()
        .color(Color.Transparent)
        .onClick(() => this.confirmKind = '')
      Column({ space: 16 }) {
        Text(this.confirmKind === 'trash' ? '清空回收站？' :
          this.confirmKind === 'delete' ? '彻底删除这条待办？' : '清空已完成？')
          .fontSize(Theme.tBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.fg)
        Text(this.confirmKind === 'trash'
          ? `将彻底删除 ${this.store.trashCount} 条，不可恢复`
          : this.confirmKind === 'delete' ? '删除后不可恢复，请确认已不再需要。'
            : `将移入回收站 ${this.store.doneCount} 条已完成事项`)
          .fontSize(Theme.tSub)
          .fontColor(Theme.fgDim)
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .fontSize(Theme.tSub)
            .fontColor(Theme.fg)
            .backgroundColor(Theme.cardHi)
            .borderRadius(Theme.rItem)
            .onClick(() => this.confirmKind = '')
          Button('确认')
            .layoutWeight(1)
            .height(42)
            .fontSize(Theme.tSub)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.danger)
            .backgroundColor('#2A1518')
            .borderRadius(Theme.rItem)
            .onClick(() => {
              if (this.confirmKind === 'trash') {
                this.store.emptyTrash();
              } else if (this.confirmKind === 'delete') {
                this.store.destroy(this.pendingDeleteId);
              } else {
                this.store.clearDone();
              }
              this.confirmKind = '';
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .borderRadius({ topLeft: Theme.rCard, topRight: Theme.rCard })
      .backgroundColor(Theme.card)
      .border({ width: { top: 0.8 }, color: Theme.border })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  importLayer() {
    Column() {
      Blank()
      Scroll() {
      Column({ space: 14 }) {
        Text('导入 JSON 备份')
          .fontSize(Theme.tBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.fg)
        Text('粘贴通过“导出备份”获得的 JSON，校验通过后合并到现有列表。最多 1000 条。')
          .fontSize(Theme.tSub)
          .fontColor(Theme.fgDim)
        TextArea({ placeholder: '粘贴 JSON 数组，例如 [...]', text: this.importText })
          .height(150)
          .fontSize(Theme.tSub)
          .fontColor(Theme.fg)
          .backgroundColor(Theme.cardHi)
          .onChange((value: string) => { this.importText = value; this.importError = ''; })
        if (this.importError !== '') {
          Text(this.importError)
            .fontSize(Theme.tSub)
            .fontColor(Theme.danger)
        }
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .fontColor(Theme.fg)
            .backgroundColor(Theme.cardHi)
            .onClick(() => { this.confirmKind = ''; })
          Button('校验并导入')
            .layoutWeight(1)
            .fontColor(Theme.onAccent)
            .backgroundColor(Theme.accent)
            .onClick(() => this.importData())
        }
        .width('100%')
      }
      .padding(20)
      .width('100%')
      .backgroundColor(Theme.card)
      .borderRadius({ topLeft: Theme.rCard, topRight: Theme.rCard })
      }
      .width('100%')
      .constraintSize({ maxHeight: '85%' })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
  }

  @Builder
  filterChip(key: string, label: string) {
    Row({ space: 5 }) {
      Text(label)
        .fontSize(Theme.tMicro)
        .fontWeight(this.store.filter === key ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.store.filter === key ? Theme.fg : Theme.fgDim)
      // 在 Text 更新回调内读取仓库，避免 @Builder 普通数值参数停留在首次创建时的快照。
      Text((key === 'all' ? this.store.todoCount + this.store.doneCount :
        key === 'active' ? this.store.todoCount : this.store.doneCount).toString())
        .fontSize(Theme.tMicro)
        .fontColor(this.store.filter === key ? Theme.accent : Theme.fgFaint)
    }
    .height(28)
    .padding({ left: 12, right: 12 })
    .borderRadius(Theme.rPill)
    .backgroundColor(this.store.filter === key ? Theme.cardHi : Color.Transparent)
    .border({ width: 0.8, color: this.store.filter === key ? Theme.accent : Theme.border })
    .onClick(() => {
      this.store.filter = key;
    })
  }

  @Builder
  skeleton() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        this.bone(120, 18)
        Blank()
        this.bone(72, 30)
      }
      .width('100%')

      this.bone('100%', 10)

      ForEach([1, 2, 3], () => {
        Row({ space: 12 }) {
          this.bone(24, 24)
          Column({ space: 8 }) {
            this.bone('70%', 14)
            this.bone('45%', 12)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .borderRadius(Theme.rItem)
        .backgroundColor(Theme.card)
        .border({ width: 0.8, color: Theme.border })
      })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 20, right: 20, top: 16 })
  }

  @Builder
  bone(w: Length, h: number) {
    Row()
      .width(w)
      .height(h)
      .borderRadius(6)
      .backgroundColor(Theme.cardHi)
  }

  private emptyTitle(): string {
    if (this.store.keyword !== '') {
      return '没有匹配的待办';
    }
    if (this.store.filter === 'active') {
      return '没有进行中的待办';
    }
    if (this.store.filter === 'done') {
      return '还没有已完成的事项';
    }
    return '今天还没有待办';
  }

  private emptyHint(): string {
    if (this.store.keyword !== '') {
      return '换个关键词试试';
    }
    if (this.store.filter === 'done') {
      return '完成一条待办后会出现在这里';
    }
    return '点击右上角「新建」添加一条';
  }

  private greeting(): string {
    const h = new Date(this.store.nowAt).getHours();
    if (h < 6) {
      return '夜深了';
    }
    if (h < 12) {
      return '早上好';
    }
    if (h < 18) {
      return '下午好';
    }
    return '晚上好';
  }

  private dateLabel(): string {
    const d = new Date(this.store.nowAt);
    const weeks = ['日', '一', '二', '三', '四', '五', '六'];
    return `${d.getMonth() + 1} 月 ${d.getDate()} 日 · 星期${weeks[d.getDay()]}`;
  }
}
