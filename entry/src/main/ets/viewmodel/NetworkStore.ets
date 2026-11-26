import { Todo } from '../model/Todo';
import { ApiService } from '../common/ApiService';
import { http } from '@kit.NetworkKit';

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
  @Trace proxyHost: string = '';
  @Trace proxyPort: number = 0;
  @Trace proxyError: string = '';
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

  // 仅保存在当前进程内；不写入 Preferences、文件或个人待办。
  async applyProxy(host: string, portText: string): Promise<boolean> {
    if (this.loading) {
      this.proxyError = '请求中不能修改代理，请等待本次请求结束';
      return false;
    }
    if (/[\r\n]/.test(host)) {
      this.proxyError = '代理主机不能包含换行';
      return false;
    }
    const cleanHost: string = host.trim();
    const cleanPort: string = portText.trim();
    if (cleanHost === '' && cleanPort === '') {
      this.proxyHost = '';
      this.proxyPort = 0;
    } else {
      if (cleanHost === '' || cleanPort === '') {
        this.proxyError = '请同时填写代理主机和端口，或同时留空使用系统代理';
        return false;
      }
      if (cleanHost.length > 253 ||
        !/^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(cleanHost)) {
        this.proxyError = '主机只填写主机名或 IPv4 地址，不含协议、路径、端口及换行';
        return false;
      }
      const port: number = Number(cleanPort);
      if (!/^[0-9]+$/.test(cleanPort) || !Number.isSafeInteger(port) || port < 1 || port > 65535) {
        this.proxyError = '端口必须为 1 到 65535 的整数';
        return false;
      }
      this.proxyHost = cleanHost;
      this.proxyPort = port;
    }
    this.proxyError = '';
    await this.load();
    return true;
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
      const proxy: http.HttpProxy | undefined = this.proxyHost === '' ? undefined : {
        host: this.proxyHost,
        port: this.proxyPort,
        exclusionList: []
      };
      const items = await ApiService.fetchRemoteTodos(mode, proxy);
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
