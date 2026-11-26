import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { Todo } from '../model/Todo';

export class FormSnapshot {
  count: string = '0';
  latest: string = '暂无待办';
}

/** 卡片读已保存的快照；通过系统查询实例，进程重启后仍能主动更新。 */
export class FormService {
  private static pending: FormSnapshot | undefined = undefined;
  private static syncing: boolean = false;

  static snapshot(todos: Todo[]): FormSnapshot {
    const data = new FormSnapshot();
    const active = todos.filter((todo: Todo) => {
      return todo !== null && typeof todo.title === 'string' && !todo.deleted && !todo.done;
    }).sort((a: Todo, b: Todo) => (b.createdAt || 0) - (a.createdAt || 0));
    data.count = active.length.toString();
    data.latest = active.length > 0 ? active[0].title : (todos.length > 0 ? '全部完成' : '暂无待办');
    return data;
  }

  static readSaved(context: Context): FormSnapshot {
    try {
      // FormExtension 可能长期驻留，清缓存后读取主应用 flushSync 后的最新磁盘内容。
      // 这里只读，不在卡片进程写 todo_store，避免多进程写同一份 Preferences。
      preferences.removePreferencesFromCacheSync(context, 'todo_store');
      const pref = preferences.getPreferencesSync(context, { name: 'todo_store' });
      const raw = JSON.parse(pref.getSync('todos_json', '[]') as string) as Todo[];
      if (!Array.isArray(raw)) {
        throw new Error('Invalid saved tasks');
      }
      return FormService.snapshot(raw);
    } catch (e) {
      const fallback = new FormSnapshot();
      fallback.count = '--';
      fallback.latest = '打开应用查看';
      return fallback;
    }
  }

  static async updateFromDisk(context: Context, formId: string): Promise<void> {
    try {
      const snapshot = FormService.readSaved(context);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(snapshot));
    } catch (e) {
      // 系统会在后续可见/定时刷新时重试；被用户移除的卡片无须继续维护。
    }
  }

  static push(todos: Todo[]): void {
    // 合并密集写操作并串行提交，避免较旧异步调用最后返回而覆盖新状态。
    FormService.pending = FormService.snapshot(todos);
    if (!FormService.syncing) {
      FormService.drain();
    }
  }

  private static async drain(): Promise<void> {
    FormService.syncing = true;
    try {
      while (FormService.pending !== undefined) {
        const snapshot = FormService.pending;
        FormService.pending = undefined;
        try {
          const forms = await formProvider.getPublishedRunningFormInfos();
          const ownForms = forms.filter((form: formInfo.RunningFormInfo) => {
            return form.bundleName === 'com.example.todoapp' && form.moduleName === 'entry' &&
              form.abilityName === 'EntryFormAbility' && form.formName === 'widget';
          });
          const binding = formBindingData.createFormBindingData(snapshot);
          await Promise.all(ownForms.map(async (form: formInfo.RunningFormInfo) => {
            try {
              await formProvider.updateForm(form.formId, binding);
            } catch (e) {
              // 单张卡被移除不影响其他卡片更新。
            }
          }));
        } catch (e) {
          // 预览器不提供卡片管理服务，运行时仍可依靠系统定时读取已保存数据。
        }
      }
    } finally {
      FormService.syncing = false;
    }
  }
}
