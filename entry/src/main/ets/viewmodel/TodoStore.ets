import { Todo } from '../model/Todo';
import { ApiService } from '../common/ApiService';
import { FormService } from '../common/FormService';
import { preferences } from '@kit.ArkData';

/** 持久化/导入数据使用显式 DTO，兼容早期未包含可选字段的导出。 */
class TodoDTO {
  id: number = 0;
  title: string = '';
  description: string = '';
  done: boolean = false;
  priority: number = 0;
  createdAt: number = 0;
  dueAt: number = 0;
  deleted: boolean = false;
  doneAt: number = 0;
}

export class DayPoint {
  label: string = '';
  count: number = 0;
}

/** 本地数据为准：写入成功后提交界面状态，示例网络数据不覆盖用户操作。 */
@ObservedV2
export class TodoStore {
  private static singleton: TodoStore | undefined = undefined;

  // 必须在 @ObservedV2 完成类包装后再构造，避免静态初始化生成未观察的实例。
  static get instance(): TodoStore {
    if (TodoStore.singleton === undefined) {
      TodoStore.singleton = new TodoStore();
    }
    return TodoStore.singleton;
  }
  @Trace todos: Todo[] = [];
  @Trace loading: boolean = false;
  @Trace errorMsg: string = '';
  @Trace storageError: string = '';
  @Trace notice: string = '';
  @Trace filter: string = 'all';
  @Trace keyword: string = '';
  @Trace inTrash: boolean = false;
  @Trace nowAt: number = Date.now();

  private static readonly PREF_NAME: string = 'todo_store';
  private static readonly KEY_TODOS: string = 'todos_json';
  private static readonly KEY_SEEDED: string = 'seeded';
  private context: Context | undefined = undefined;
  private started: boolean = false;
  private initialized: boolean = false;
  private storageBlocked: boolean = false;
  private protectedJson: string = '';
  private revision: number = 0;
  private fetchTask: Promise<void> | undefined = undefined;
  private pendingBootstrap: boolean = false;

  /** 区分损坏数据保护与可重试的临时落盘错误，供安全批量导入入口只读查询。 */
  get isStorageProtected(): boolean {
    return this.storageBlocked;
  }

  async init(context: Context): Promise<void> {
    // Previewer 没有 Ability context；若正式初始化晚于首次操作，已接受的草稿也不能丢。
    const drafts: Todo[] = this.context === undefined ? [...this.todos] : [];
    this.context = context;
    if (this.notice === '当前为预览模式，改动仅在本次预览中保留。') {
      this.notice = '';
    }
    if (this.started) {
      if (this.fetchTask) {
        await this.fetchTask;
      }
      return;
    }
    this.started = true;
    try {
      const pref = preferences.getPreferencesSync(context, { name: TodoStore.PREF_NAME });
      const seeded = pref.getSync(TodoStore.KEY_SEEDED, false) as boolean;
      // 兼容旧版：有本地 JSON 就恢复，不能仅凭 seeded 判断，否则离线新增会丢失。
      if (pref.hasSync(TodoStore.KEY_TODOS) || seeded) {
        const json = pref.getSync(TodoStore.KEY_TODOS, '[]');
        if (typeof json !== 'string') {
          throw new Error('本地数据类型异常');
        }
        this.protectedJson = json;
        const restored = this.deserialize(json);
        this.protectedJson = '';
        this.initialized = true;
        this.todos = restored;
        if (drafts.length > 0) {
          const merged = this.merge(drafts, restored);
          if (!this.commit(merged)) {
            // 这些草稿此前已经被预览界面接受：保留在内存并标记未保存，允许刷新重试。
            this.todos = merged;
            this.pendingBootstrap = true;
          }
        } else {
          FormService.push(this.todos);
        }
        return;
      }
    } catch (e) {
      this.storageBlocked = true;
      this.storageError = '本地数据无法读取，原始内容已保留。请先导出备份，再导入有效 JSON 恢复。';
      return;
    }
    if (drafts.length > 0) {
      if (!this.commit(drafts)) {
        this.pendingBootstrap = true;
      }
      return;
    }
    await this.reload();
  }

  /** 同一时间最多一个请求；已经建立本地库（包括空库）后不再自动灌底。 */
  async reload(): Promise<void> {
    if (this.fetchTask) {
      await this.fetchTask;
      return;
    }
    if (this.initialized || this.storageBlocked || this.todos.length > 0) {
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    const revision = this.revision;
    this.fetchTask = this.seedFromNetwork(revision);
    await this.fetchTask;
    this.fetchTask = undefined;
  }

  private async seedFromNetwork(revision: number): Promise<void> {
    try {
      const list = await ApiService.fetchDefaultTodos();
      // 请求期间的新建、导入和离线建库优先；迟到的响应直接丢弃。
      if (this.revision === revision && !this.initialized && !this.storageBlocked) {
        this.commit(list);
      }
    } catch (e) {
      if (!this.initialized) {
        this.errorMsg = '示例数据暂时无法加载，可重试，也可以直接新建待办。';
        this.notice = '离线也能使用，新建的待办会保存在本机。';
      }
    } finally {
      this.loading = false;
    }
  }

  /** 下拉刷新只重算本地视图和桌面卡片，不覆盖个人事项。 */
  async refresh(): Promise<void> {
    this.nowAt = Date.now();
    if (this.pendingBootstrap) {
      this.commit(this.todos);
      return;
    }
    this.todos = [...this.todos];
    if (!this.storageBlocked && this.storageError === '') {
      FormService.push(this.todos);
    }
  }

  private serialize(list: Todo[] = this.todos): string {
    const data: TodoDTO[] = list.map((t: Todo) => {
      const d = new TodoDTO();
      d.id = t.id;
      d.title = t.title;
      d.description = t.description;
      d.done = t.done;
      d.priority = t.priority;
      d.createdAt = t.createdAt;
      d.dueAt = t.dueAt;
      d.deleted = t.deleted;
      d.doneAt = t.doneAt;
      return d;
    });
    return JSON.stringify(data);
  }

  private validTime(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 8640000000000000;
  }

  /** 逐条校验；任何一条不合法都拒绝整批，避免部分导入和搜索时崩溃。 */
  private deserialize(json: string, importing: boolean = false): Todo[] {
    if (json.length > 2 * 1024 * 1024) {
      throw new Error('JSON 内容过大，请控制在 2 MB 内');
    }
    let raw: TodoDTO[];
    try {
      raw = JSON.parse(json) as TodoDTO[];
    } catch (e) {
      throw new Error('JSON 格式不正确，请粘贴从本应用导出的完整数组');
    }
    if (!Array.isArray(raw) || raw.length > (importing ? 1000 : 10000)) {
      throw new Error(importing ? '请提供不超过 1000 条待办的 JSON 数组' : '本地待办列表格式异常');
    }
    const ids: Set<number> = new Set<number>();
    return raw.map((o: TodoDTO, index: number) => {
      if (o === null || typeof o !== 'object' || !Number.isSafeInteger(o.id) || o.id <= 0 ||
        typeof o.title !== 'string' || o.title.trim() === '' || o.title.length > 200 ||
        typeof o.done !== 'boolean') {
        throw new Error(`第 ${index + 1} 条待办的编号、标题或完成状态不正确`);
      }
      if ((o.description !== undefined && (typeof o.description !== 'string' || o.description.length > 5000)) ||
        (o.priority !== undefined && o.priority !== 0 && o.priority !== 1) ||
        (o.deleted !== undefined && typeof o.deleted !== 'boolean') ||
        (o.createdAt !== undefined && !this.validTime(o.createdAt)) ||
        (o.dueAt !== undefined && !this.validTime(o.dueAt)) ||
        (o.doneAt !== undefined && !this.validTime(o.doneAt))) {
        throw new Error(`第 ${index + 1} 条待办的描述、优先级或日期不正确`);
      }
      if (!importing && ids.has(o.id)) {
        throw new Error('本地数据存在重复编号，请导出后重新导入以修复');
      }
      ids.add(o.id);
      return new Todo(o.id, o.title.trim(), o.description ?? '', o.done, o.priority ?? 0,
        o.createdAt ?? Date.now(), o.dueAt ?? 0, o.deleted ?? false, o.done ? (o.doneAt ?? 0) : 0);
    });
  }

  /** 先保存，成功后才替换内存；失败时表单可原样重试，不产生重复事项。 */
  private commit(next: Todo[], recovering: boolean = false): boolean {
    if (this.storageBlocked && !recovering) {
      return false;
    }
    // 同时约束最终库，而非仅单次导入；任何成功写入都必须能被下次启动完整读取。
    const serialized = this.serialize(next);
    if (next.length > 10000 || serialized.length > 2 * 1024 * 1024) {
      this.storageError = '待办总量已达本机上限（10000 条或 2 MB JSON），请导出备份并精简后重试；原有数据未改动。';
      return false;
    }
    if (this.context) {
      try {
        const pref = preferences.getPreferencesSync(this.context, { name: TodoStore.PREF_NAME });
        const hadJson = pref.hasSync(TodoStore.KEY_TODOS);
        const hadSeeded = pref.hasSync(TodoStore.KEY_SEEDED);
        const oldJson = pref.getSync(TodoStore.KEY_TODOS, '[]');
        const oldSeeded = pref.getSync(TodoStore.KEY_SEEDED, false);
        if (recovering && this.protectedJson !== '') {
          // 独立恢复副本先持久化成功，才允许显式导入替换无法解读的原库。
          pref.putSync('recovery_json_' + Date.now().toString(), this.protectedJson);
          pref.flushSync();
        }
        try {
          pref.putSync(TodoStore.KEY_TODOS, serialized);
          pref.putSync(TodoStore.KEY_SEEDED, true);
          pref.flushSync();
        } catch (e) {
          // 恢复 preferences 的进程内缓存，避免下一次读到未成功落盘的数据。
          if (hadJson) {
            pref.putSync(TodoStore.KEY_TODOS, oldJson);
          } else {
            pref.deleteSync(TodoStore.KEY_TODOS);
          }
          if (hadSeeded) {
            pref.putSync(TodoStore.KEY_SEEDED, oldSeeded);
          } else {
            pref.deleteSync(TodoStore.KEY_SEEDED);
          }
          throw new Error('写入失败');
        }
      } catch (e) {
        this.storageError = '保存失败，请检查本机存储空间后重试；当前已保存的数据未改动。';
        return false;
      }
    } else {
      // IDE Previewer 不运行 EntryAbility；允许演示交互，但明确不宣称已保存到设备。
      this.notice = '当前为预览模式，改动仅在本次预览中保留。';
    }
    this.todos = next;
    this.revision++;
    this.initialized = true;
    this.storageBlocked = false;
    this.pendingBootstrap = false;
    this.protectedJson = '';
    this.storageError = '';
    this.errorMsg = '';
    this.nowAt = Date.now();
    if (this.context) {
      FormService.push(this.todos);
    }
    return true;
  }

  private nextId(used: Set<number>): number {
    let id = Date.now();
    while (used.has(id)) {
      id++;
    }
    return id;
  }

  private clone(todo: Todo): Todo {
    return new Todo(todo.id, todo.title, todo.description, todo.done, todo.priority,
      todo.createdAt, todo.dueAt, todo.deleted, todo.doneAt);
  }

  private merge(incoming: Todo[], existing: Todo[]): Todo[] {
    const used: Set<number> = new Set<number>(existing.map((t: Todo) => t.id));
    const items: Todo[] = incoming.map((t: Todo) => {
      const item = this.clone(t);
      if (used.has(item.id)) {
        item.id = this.nextId(used);
      }
      used.add(item.id);
      return item;
    });
    return [...items, ...existing];
  }

  add(todo: Todo): boolean {
    if (this.storageBlocked) {
      return false;
    }
    const item = this.clone(todo);
    if (typeof item.title !== 'string' || item.title.trim() === '' || item.title.length > 200 ||
      typeof item.description !== 'string' || item.description.length > 5000 ||
      typeof item.done !== 'boolean' || typeof item.deleted !== 'boolean' ||
      (item.priority !== 0 && item.priority !== 1) || !this.validTime(item.createdAt) ||
      !this.validTime(item.dueAt) || !this.validTime(item.doneAt)) {
      this.notice = '请检查标题、描述、优先级和日期；标题限 200 字，描述限 5000 字。';
      return false;
    }
    item.title = item.title.trim();
    const used: Set<number> = new Set<number>(this.todos.map((t: Todo) => t.id));
    if (!Number.isSafeInteger(item.id) || item.id <= 0 || used.has(item.id)) {
      item.id = this.nextId(used);
    }
    return this.commit([item, ...this.todos]);
  }

  remove(id: number): boolean {
    return this.change(id, 'delete');
  }

  restore(id: number): boolean {
    return this.change(id, 'restore');
  }

  toggle(id: number): boolean {
    return this.change(id, 'toggle');
  }

  private change(id: number, operation: string): boolean {
    const target = this.byId(id);
    if (!target || (target.deleted && operation !== 'restore')) {
      return false;
    }
    const item = this.clone(target);
    if (operation === 'delete') {
      item.deleted = true;
    } else if (operation === 'restore') {
      item.deleted = false;
    } else {
      item.done = !item.done;
      item.doneAt = item.done ? Date.now() : 0;
    }
    return this.commit(this.todos.map((t: Todo) => t.id === id ? item : t));
  }

  destroy(id: number): boolean {
    const target = this.byId(id);
    return target !== undefined && target.deleted && this.commit(this.todos.filter((t: Todo) => t.id !== id));
  }

  emptyTrash(): boolean {
    return this.commit(this.todos.filter((t: Todo) => !t.deleted));
  }

  edit(id: number, title: string, description: string, priority: number, dueAt: number): boolean {
    const target = this.byId(id);
    if (!target || target.deleted) {
      this.notice = '这条待办已不存在，请返回列表。';
      return false;
    }
    if (title.trim() === '' || title.length > 200 || description.length > 5000 ||
      (priority !== 0 && priority !== 1) || !this.validTime(dueAt)) {
      this.notice = '请检查标题、描述和截止时间。';
      return false;
    }
    const item = this.clone(target);
    item.title = title.trim();
    item.description = description.trim();
    item.priority = priority;
    item.dueAt = dueAt;
    return this.commit(this.todos.map((t: Todo) => t.id === id ? item : t));
  }

  byId(id: number): Todo | undefined {
    return this.todos.find((item: Todo) => item.id === id);
  }

  clearDone(): boolean {
    const next = this.todos.map((t: Todo) => {
      if (!t.done || t.deleted) {
        return t;
      }
      const item = this.clone(t);
      item.deleted = true;
      return item;
    });
    return this.commit(next);
  }

  /** 合并导入；冲突编号重新分配。失败抛错且不改变现有列表。 */
  importJson(text: string): number {
    const imported = this.deserialize(text, true);
    if (imported.length === 0) {
      throw new Error('导入列表为空，现有数据未改动');
    }
    const recovered = this.storageBlocked;
    if (!this.commit(this.merge(imported, this.todos), recovered)) {
      throw new Error(this.storageError || '导入未保存，请重试');
    }
    this.notice = recovered ? `已恢复 ${imported.length} 条待办，原始异常数据另存为本机恢复副本。`
      : `已合并导入 ${imported.length} 条待办，原有数据已保留。`;
    return imported.length;
  }

  exportJson(): string {
    return this.storageBlocked && this.protectedJson !== '' ? this.protectedJson : this.serialize();
  }

  get viewOf(): Todo[] {
    const kw = this.keyword.trim().toLowerCase();
    const filtered = this.todos.filter((t: Todo) => {
      if (t.deleted || (this.filter === 'active' && t.done) || (this.filter === 'done' && !t.done)) {
        return false;
      }
      return kw === '' || t.title.toLowerCase().includes(kw) || t.description.toLowerCase().includes(kw);
    });
    return filtered.sort((a: Todo, b: Todo) => {
      if (a.done !== b.done) {
        return a.done ? 1 : -1;
      }
      if (!a.done && !b.done) {
        if (a.dueAt > 0 && b.dueAt > 0 && a.dueAt !== b.dueAt) {
          return a.dueAt - b.dueAt;
        }
        if (a.dueAt > 0 && b.dueAt === 0) {
          return -1;
        }
        if (b.dueAt > 0 && a.dueAt === 0) {
          return 1;
        }
      }
      return b.priority - a.priority || b.createdAt - a.createdAt || b.id - a.id;
    });
  }

  get trashOf(): Todo[] {
    return this.todos.filter((t: Todo) => t.deleted).sort((a: Todo, b: Todo) => b.createdAt - a.createdAt);
  }

  get currentView(): Todo[] {
    return this.inTrash ? this.trashOf : this.viewOf;
  }

  /** 删除已完成事项不会抹掉完成历史；彻底删除或取消完成则不再计入。 */
  get weeklyTrend(): DayPoint[] {
    const points: DayPoint[] = [];
    const now = new Date(this.nowAt);
    const weeks: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    for (let i = 6; i >= 0; i--) {
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i).getTime();
      const end = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i + 1).getTime();
      const p = new DayPoint();
      p.label = i === 0 ? '今' : weeks[new Date(start).getDay()];
      p.count = this.todos.filter((t: Todo) => t.done && t.doneAt > 0 && t.doneAt >= start &&
        t.doneAt < end && t.doneAt <= this.nowAt).length;
      points.push(p);
    }
    return points;
  }

  get streakDays(): number {
    const now = new Date(this.nowAt);
    let cursor = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const doneToday = this.todos.some((t: Todo) => t.done && t.doneAt >= cursor.getTime() && t.doneAt <= this.nowAt);
    if (!doneToday) {
      cursor.setDate(cursor.getDate() - 1);
    }
    let streak = 0;
    while (true) {
      const end = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1).getTime();
      if (!this.todos.some((t: Todo) => t.done && t.doneAt > 0 && t.doneAt >= cursor.getTime() && t.doneAt < end)) {
        return streak;
      }
      streak++;
      cursor.setDate(cursor.getDate() - 1);
    }
  }

  get doneCount(): number {
    return this.todos.filter((item: Todo) => item.done && !item.deleted).length;
  }

  get todoCount(): number {
    return this.todos.filter((item: Todo) => !item.done && !item.deleted).length;
  }

  get trashCount(): number {
    return this.todos.filter((item: Todo) => item.deleted).length;
  }
}
