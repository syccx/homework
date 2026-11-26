import { Todo } from '../model/Todo';
import { ApiService } from '../common/ApiService';

/** 远端示例专属状态，不读取或写入个人待办及 Preferences。 */
@ObservedV2
export class NetworkStore {
  private static singleton: NetworkStore | undefined = undefined;

  // 在装饰器安装 Trace 访问器后才构造，避免静态初始化遮蔽响应式字段。
  static get instance(): NetworkStore {
    if (NetworkStore.singleton === undefined) {
      NetworkStore.singleton = new NetworkStore();
    }
    return NetworkStore.singleton;
  }

  @Trace items: Todo[] = [];
  @Trace loading: boolean = false;
  @Trace error: string = '';
  // 至少一次成功（包含远端返回空列表）。失败不会抹去已有成功状态。
  @Trace loaded: boolean = false;
  @Trace lastUpdatedAt: number = 0;
  @Trace mode: string = 'normal';
  @Trace lastSuccessfulMode: string = '';
  private inFlight: Promise<void> | undefined = undefined;

  get doneCount(): number {
    return this.items.filter((item: Todo) => item.done).length;
  }

  get pendingCount(): number {
    return this.items.length - this.doneCount;
  }

  get chartValues(): number[] {
    return [this.doneCount, this.pendingCount];
  }

  // 重复刷新始终重新请求；请求中合并调用，避免慢响应覆盖新状态。
  load(mode: string = this.mode): Promise<void> {
    if (this.inFlight !== undefined) {
      return this.inFlight;
    }
    this.mode = mode;
    this.loading = true;
    this.error = '';
    this.inFlight = this.request(mode);
    return this.inFlight;
  }

  private async request(mode: string): Promise<void> {
    try {
      const items = await ApiService.fetchRemoteTodos(mode);
      this.items = items;
      this.loaded = true;
      this.lastSuccessfulMode = mode;
      this.lastUpdatedAt = Date.now();
    } catch (e) {
      this.error = (e as Error).message || '远端请求失败，请检查网络后重试';
    } finally {
      this.loading = false;
      this.inFlight = undefined;
    }
  }
}
