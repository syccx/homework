import { Todo } from '../model/Todo';
import { Theme } from '../common/Theme';
import { Sym } from '../common/Sym';

/**
 * 单条待办卡片
 * 视觉：暗卡 + 1px 描边，完成态整体降透明（内容仍在，不隐藏信息）
 * 交互：
 *  - 点勾选圆环 → 切换完成
 *  - 点文本区 → 进编辑页
 *  - 左滑 → 露出删除
 * 高优先级用 accent 旗标标记
 */
@ComponentV2
export struct TodoItem {
  @Require @Param todo: Todo;
  @Param nowAt: number = Date.now();
  @Event onDelete: (todo: Todo) => void;
  @Event onEdit: (todo: Todo) => void;
  @Event onToggle: (todo: Todo) => void;

  // 左滑偏移量（由手势实时驱动）
  @Local private offsetX: number = 0;
  private startOffset: number = 0;

  build() {
    Stack({ alignContent: Alignment.End }) {
      // 底层删除按钮：仅在左滑后露出
      Row() {
        SymbolGlyph(Sym.trash)
          .fontSize(22)
          .fontColor([Theme.danger])
        Text('删除')
          .fontSize(Theme.tSub)
          .fontColor(Theme.danger)
          .margin({ left: 6 })
      }
      .justifyContent(FlexAlign.End)
      .padding({ right: 20 })
      .width('100%')
      .height('100%')
      .borderRadius(Theme.rItem)
      .backgroundColor('#2A1518')
      .onClick(() => {
        this.onDelete(this.todo);
      })
      .enabled(this.offsetX < 0)

      // 上层内容行：随 PanGesture 横移
      Row({ space: 12 }) {
        // 勾选圆环（点它切换完成，阻歧行点击穿透）
        Stack() {
          Circle()
            .width(22)
            .height(22)
            .fill(Color.Transparent)
            .stroke(this.todo.done ? Theme.accent : Theme.fgFaint)
            .strokeWidth(1.6)
          if (this.todo.done) {
            SymbolGlyph(Sym.checkCircleFill)
              .fontSize(22)
              .fontColor([Theme.accent])
          }
        }
        .width(40)
        .height(40)
        .accessibilityText(this.todo.done ? '标为未完成' : '标为已完成')
        .onClick(() => {
          this.onToggle(this.todo);
        })

        // 文本区（点击进编辑）
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            if (this.todo.priority === 1) {
              SymbolGlyph(Sym.flag)
                .fontSize(13)
                .fontColor([Theme.accent])
            }
            Text(this.todo.title)
              .fontSize(Theme.tBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.todo.done ? Theme.fgFaint : Theme.fg)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.todo.description !== '') {
            Text(this.todo.description)
              .fontSize(Theme.tSub)
              .fontColor(Theme.fgDim)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Text(this.todo.done ? '已完成' : this.timeLabel())
            .fontSize(Theme.tMicro)
            .fontColor(this.overdue() ? Theme.danger : Theme.fgFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .onClick(() => {
          this.onEdit(this.todo);
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .borderRadius(Theme.rItem)
      .backgroundColor(Theme.card)
      .border({ width: 0.8, color: Theme.border })
      .opacity(this.todo.done ? 0.45 : 1)
      .translate({ x: this.offsetX })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, fingers: 1 })
          .onActionStart(() => {
            this.startOffset = this.offsetX;
          })
          .onActionUpdate((e: GestureEvent) => {
            this.offsetX = Math.max(-96, Math.min(0, this.startOffset + e.offsetX * 0.8));
          })
          .onActionEnd(() => {
            // 滑过 -60 停在露位，否则弹回
            this.offsetX = this.offsetX < -60 ? -96 : 0;
          })
          .onActionCancel(() => {
            this.offsetX = 0;
          })
      )
    }
    .width('100%')
    .height(this.todo.description !== '' ? 96 : 80)
  }

  // 是否逾期（有截止时间、未完成、已过期）
  private overdue(): boolean {
    return !this.todo.done && this.todo.dueAt > 0 && this.todo.dueAt < this.nowAt;
  }

  // 时间行文案：有截止时间显示截止，否则显示创建相对时间
  private timeLabel(): string {
    if (this.todo.dueAt > 0) {
      const d = new Date(this.todo.dueAt);
      const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
      const base = `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
      return this.overdue() ? `已逾期 · ${base}` : `截止 ${base}`;
    }
    return this.relativeTime(this.todo.createdAt);
  }

  // 相对时间：当天显示时刻，更早显示 N 天前
  private relativeTime(ts: number): string {
    const diff = this.nowAt - ts;
    const day = 24 * 60 * 60 * 1000;
    if (diff < day) {
      const d = new Date(ts);
      const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
      return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }
    const days = Math.floor(diff / day);
    return days === 1 ? '昨天' : `${days} 天前`;
  }
}
