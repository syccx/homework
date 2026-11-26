import { TodoStore } from '../viewmodel/TodoStore';
import { Todo } from '../model/Todo';
import { Theme } from '../common/Theme';
import { Sym } from '../common/Sym';
import { TodoDate } from '../common/TodoDate';

/**
 * 新增 / 编辑页（双模式）
 * - 路由参数带 todo → 编辑态：预填字段，保存调用 store.edit
 * - 无参数 → 新增态：保存调用 store.add
 * 支持：标题、描述、优先级、截止时间（DatePickerDialog，可选）
 */
@ComponentV2
export struct AddTodoPage {
  @Param navPathStack: NavPathStack = new NavPathStack();
  @Local store: TodoStore = TodoStore.instance;

  // 编辑目标 id（null = 新增模式）
  @Local private editingId: number | null = null;
  // 本地表单状态
  @Local title: string = '';
  @Local desc: string = '';
  @Local priority: number = 0;
  // 截止时间（毫秒），0 = 未设置
  @Local dueAt: number = 0;
  // 提交拦截提示（真实语义才显示）
  @Local showTitleError: boolean = false;
  @Local saveError: string = '';
  private original: string = '';

  aboutToAppear(): void {
    // 读取路由参数：编辑模式预填
    const params = this.navPathStack.getParamByName('Add') as Array<Todo | undefined>;
    const param = params[params.length - 1] as Todo | undefined;
    if (param && param.id !== undefined) {
      const current = this.store.byId(param.id) ?? param;
      this.editingId = param.id;
      this.title = current.title;
      this.desc = current.description;
      this.priority = current.priority;
      this.dueAt = current.dueAt ?? 0;
    }
    this.original = this.snapshot();
  }

  private snapshot(): string {
    return JSON.stringify([this.title, this.desc, this.priority.toString(), this.dueAt.toString()]);
  }

  private goBack(): void {
    if (this.original === this.snapshot()) {
      this.navPathStack.pop();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '放弃未保存的修改？', message: '返回后，本次修改不会保存。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '放弃修改', action: () => this.navPathStack.pop() }
    });
  }

  private save(): void {
    if (this.title.trim() === '') {
      this.showTitleError = true;
      return;
    }
    let saved: boolean;
    if (this.editingId !== null) {
      saved = this.store.edit(this.editingId, this.title.trim(), this.desc.trim(), this.priority, this.dueAt);
    } else {
      const todo = new Todo(Date.now(), this.title.trim(), this.desc.trim(), false, this.priority,
        Date.now(), this.dueAt);
      saved = this.store.add(todo);
    }
    if (!saved) {
      this.saveError = this.store.storageError || this.store.notice || '保存失败，请重试';
      return;
    }
    this.store.inTrash = false;
    this.store.filter = 'all';
    this.store.keyword = '';
    this.navPathStack.pop();
  }

  // 弹出日期选择
  private pickDate(): void {
    const base = this.dueAt > 0 ? new Date(this.dueAt) : new Date();
    this.getUIContext().showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(2036, 11, 31),
      selected: base,
      onDateAccept: (value: Date) => {
        this.dueAt = TodoDate.withDate(this.dueAt, value);
      }
    });
  }

  private pickTime(): void {
    this.getUIContext().showTimePickerDialog({
      selected: new Date(this.dueAt),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.dueAt = TodoDate.withTime(this.dueAt, value.hour ?? 18, value.minute ?? 0);
      }
    });
  }

  // 截止时间展示文案
  private dueLabel(): string {
    if (this.dueAt === 0) {
      return '未设置';
    }
    return TodoDate.label(this.dueAt);
  }

  build() {
   NavDestination() {
    Column() {
      // 顶栏：返回 + 标题（随模式变化）
      Row() {
        Button() {
          SymbolGlyph(Sym.chevronLeft)
            .fontSize(22)
            .fontColor([Theme.fg])
        }
        .width(38)
        .height(38)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回')
        .onClick(() => this.goBack())

        Text(this.editingId !== null ? '编辑待办' : '新建待办')
          .fontSize(Theme.tTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.fg)
          .margin({ left: 6 })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 20, top: 10, bottom: 6 })

      Scroll() {
       Column({ space: 20 }) {
        // 标题输入
        Column({ space: 8 }) {
          Text('标题')
            .fontSize(Theme.tSub)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.fgDim)
          TextInput({ placeholder: '要做什么？', text: this.title })
            .fontSize(Theme.tBody)
            .fontColor(Theme.fg)
            .placeholderColor(Theme.fgFaint)
            .placeholderFont({ size: Theme.tBody })
            .backgroundColor(Theme.cardHi)
            .borderRadius(Theme.rItem)
            .border({ width: 0.8, color: this.showTitleError ? Theme.danger : Theme.border })
            .height(48)
            .maxLength(200)
            .id('todo-title')
            .onChange((value: string) => {
              this.title = value;
              if (value.trim() !== '' && this.showTitleError) {
                this.showTitleError = false;
              }
            })
          if (this.showTitleError) {
            Text('标题不能为空')
              .fontSize(Theme.tMicro)
              .fontColor(Theme.danger)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 描述输入
        Column({ space: 8 }) {
          Text('描述')
            .fontSize(Theme.tSub)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.fgDim)
          TextArea({ placeholder: '补充细节（可选）', text: this.desc })
            .fontSize(Theme.tSub)
            .fontColor(Theme.fg)
            .placeholderColor(Theme.fgFaint)
            .placeholderFont({ size: Theme.tSub })
            .backgroundColor(Theme.cardHi)
            .borderRadius(Theme.rItem)
            .border({ width: 0.8, color: Theme.border })
            .height(96)
            .maxLength(5000)
            .id('todo-description')
            .onChange((value: string) => {
              this.desc = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 截止时间
        Column({ space: 8 }) {
          Text('截止时间')
            .fontSize(Theme.tSub)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.fgDim)
          Row({ space: 8 }) {
            Row({ space: 6 }) {
              SymbolGlyph(Sym.clock)
                .fontSize(14)
                .fontColor([this.dueAt > 0 ? Theme.accent : Theme.fgFaint])
              Text(this.dueLabel())
                .fontSize(Theme.tSub)
                .fontColor(this.dueAt > 0 ? Theme.fg : Theme.fgFaint)
            }
            .height(42)
            .padding({ left: 14, right: 14 })
            .borderRadius(Theme.rItem)
            .backgroundColor(Theme.cardHi)
            .border({ width: 0.8, color: Theme.border })
            .layoutWeight(1)
            .onClick(() => this.pickDate())

            // 已设置时显示清除按钮
            if (this.dueAt > 0) {
              Button() {
                SymbolGlyph(Sym.trash)
                  .fontSize(15)
                  .fontColor([Theme.danger])
              }
              .width(42)
              .height(42)
              .borderRadius(Theme.rItem)
              .backgroundColor(Theme.card)
              .border({ width: 0.8, color: Theme.border })
              .onClick(() => {
                this.dueAt = 0;
              })
            }
          }
          .width('100%')
          if (this.dueAt > 0) {
            Row() {
              Text('设置具体时分')
                .fontSize(Theme.tSub)
                .fontColor(Theme.accent)
                .onClick(() => this.pickTime())
              Blank()
              if (this.dueAt < Date.now()) {
                Text('所选时间已过期')
                  .fontSize(Theme.tMicro)
                  .fontColor(Theme.danger)
              }
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 优先级：分段选择
        Column({ space: 8 }) {
          Text('优先级')
            .fontSize(Theme.tSub)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.fgDim)
          Row({ space: 8 }) {
            this.segBtn('普通', 0, Sym.clock)
            this.segBtn('重要', 1, Sym.flag)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.saveError !== '') {
          Text(this.saveError)
            .fontSize(Theme.tSub)
            .fontColor(Theme.danger)
        }
        Button(this.editingId !== null ? '保存修改' : '保存')
          .width('100%')
          .height(48)
          .fontSize(Theme.tBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.onAccent)
          .backgroundColor(Theme.accent)
          .borderRadius(Theme.rPill)
          .id('todo-save')
          .onClick(() => this.save())
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
   }
   .hideTitleBar(true)
   .onBackPressed(() => {
     this.goBack();
     return true;
   })
  }

  // 分段选择按钮：选中 accent 描边 + 文字点亮，未选中弱化
  @Builder
  segBtn(label: string, value: number, icon: Resource) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(14)
        .fontColor([this.priority === value ? Theme.accent : Theme.fgFaint])
      Text(label)
        .fontSize(Theme.tSub)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.priority === value ? Theme.fg : Theme.fgDim)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height(42)
    .borderRadius(Theme.rItem)
    .backgroundColor(this.priority === value ? Theme.cardHi : Theme.card)
    .border({
      width: 1,
      color: this.priority === value ? Theme.accent : Theme.border
    })
    .onClick(() => {
      this.priority = value;
    })
  }
}
