import { http } from '@kit.NetworkKit';
import { DeepSeekService, DeepSeekTask } from '../common/DeepSeekService';
import { TodoStore } from './TodoStore';

// 不序列化 @ObservedV2 Todo：Trace 访问器的内部字段不是导入协议。
class DeepSeekTodoDTO {
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

/** 密钥和代理仅驻留当前应用进程，不进入任务备份、磁盘或日志。 */
@ObservedV2
export class DeepSeekStore {
  private static singleton: DeepSeekStore | undefined = undefined;
  static get instance(): DeepSeekStore {
    if (DeepSeekStore.singleton === undefined) {
      DeepSeekStore.singleton = new DeepSeekStore();
    }
    return DeepSeekStore.singleton;
  }

  @Trace goal: string = '一周内完成鸿蒙待办应用课程设计';
  @Trace hasKey: boolean = false;
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace notice: string = '';
  @Trace tasks: DeepSeekTask[] = [];
  @Trace source: string = '';
  @Trace resultGoal: string = '';
  @Trace added: boolean = false;
  @Trace proxyHost: string = '';
  @Trace proxyPort: number = 0;
  private credential: string = '';
  private inFlight: Promise<void> | undefined = undefined;

  configureKey(value: string): boolean {
    if (this.loading) {
      this.error = '请求中不能修改密钥，请等待本次请求结束';
      return false;
    }
    try {
      this.credential = DeepSeekService.validateKey(value);
      this.hasKey = true;
      this.error = '';
      this.notice = '密钥已应用，仅本次会话有效';
      return true;
    } catch (e) {
      this.error = (e as Error).message;
      return false;
    }
  }

  clearKey(): void {
    if (this.loading) {
      return;
    }
    this.credential = '';
    this.hasKey = false;
    this.error = '';
    this.notice = '已清除本次会话密钥';
  }

  configureProxy(host: string, portText: string): boolean {
    if (this.loading) {
      this.error = '请求中不能修改代理';
      return false;
    }
    const cleanHost = host.trim();
    const cleanPort = portText.trim();
    if (cleanHost === '' && cleanPort === '') {
      this.proxyHost = '';
      this.proxyPort = 0;
    } else {
      const port = Number(cleanPort);
      if (/[\r\n]/.test(host) || cleanHost.length > 253 ||
        !/^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(cleanHost) ||
        !/^[0-9]+$/.test(cleanPort) || !Number.isSafeInteger(port) || port < 1 || port > 65535) {
        this.error = '请填写有效代理主机与 1–65535 端口；主机不含协议、路径或端口';
        return false;
      }
      this.proxyHost = cleanHost;
      this.proxyPort = port;
    }
    this.error = '';
    this.notice = this.proxyHost === '' ? '已使用系统代理' : '会话代理已应用';
    return true;
  }

  generate(): Promise<void> {
    if (this.inFlight !== undefined) {
      return this.inFlight;
    }
    if (!this.hasKey) {
      this.error = '请先配置 DeepSeek API 密钥，或查看离线示例';
      return Promise.resolve();
    }
    let goal: string;
    try {
      goal = DeepSeekService.validateGoal(this.goal);
    } catch (e) {
      this.error = (e as Error).message;
      return Promise.resolve();
    }
    this.loading = true;
    this.error = '';
    this.notice = '';
    this.inFlight = this.request(goal);
    return this.inFlight;
  }

  private async request(goal: string): Promise<void> {
    try {
      const proxy: http.HttpProxy | undefined = this.proxyHost === '' ? undefined : {
        host: this.proxyHost, port: this.proxyPort, exclusionList: []
      };
      const tasks = await DeepSeekService.generate(this.credential, goal, proxy);
      this.tasks = tasks;
      this.source = 'api';
      this.resultGoal = goal;
      this.added = false;
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.loading = false;
      this.inFlight = undefined;
    }
  }

  // 固定课堂案例，明确标为示例；与在线请求入口分开，不伪装为 API 响应。
  showExample(): void {
    if (this.loading) {
      return;
    }
    this.goal = '一周内完成鸿蒙待办应用课程设计';
    this.resultGoal = this.goal;
    this.tasks = [
      new DeepSeekTask('梳理需求与页面流程', '列出任务增删改查、筛选与本地保存的验收条件，绘制页面跳转图。', 1),
      new DeepSeekTask('完成 ArkUI 核心页面', '实现首页、待办表单与回收站，检查输入校验及列表状态联动。', 1),
      new DeepSeekTask('验证网络与数据持久化', '测试离线、接口异常和重启恢复；确认失败时保留已有任务。', 0),
      new DeepSeekTask('整理截图与课程报告', '用清晰的案例展示完整操作闭环，对照课程模板核对图题和测试结论。', 0)
    ];
    this.source = 'example';
    this.added = false;
    this.error = '';
    this.notice = '';
  }

  addToTodos(): number {
    if (this.loading || this.added || this.tasks.length === 0) {
      return 0;
    }
    const store = TodoStore.instance;
    if (store.isStorageProtected) {
      this.error = '本地数据处于保护状态，请先在首页处理存储异常后再保存';
      return 0;
    }
    const now = Date.now();
    const label = this.source === 'example' ? '离线示例' : 'DeepSeek 建议';
    const todos: DeepSeekTodoDTO[] = this.tasks.map((task: DeepSeekTask, index: number) => {
      const dto = new DeepSeekTodoDTO();
      dto.id = now + index;
      dto.title = task.title;
      dto.description = `[${label}] ${task.description}`;
      dto.priority = task.priority;
      dto.createdAt = now + index;
      return dto;
    });
    try {
      const count = store.importJson(JSON.stringify(todos));
      this.added = true;
      this.error = '';
      this.notice = `已加入 ${count} 条待办，可返回首页查看`;
      store.filter = 'all';
      store.inTrash = false;
      store.keyword = '';
      return count;
    } catch (e) {
      this.error = '计划未保存，请检查本地存储后重试；当前预览已保留';
      return 0;
    }
  }
}
