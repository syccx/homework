import { http } from '@kit.NetworkKit';
import { Todo } from '../model/Todo';

// 远端接口返回的单条数据结构
export class RemoteTodo {
  userId: number = 0;
  id: number = 0;
  title: string = '';
  completed: boolean = false;
}

// 网络请求封装：加载远端示例数据并做异常处理
export class ApiService {
  static fetchDefaultTodos(): Promise<Todo[]> {
    return ApiService.fetchRemoteTodos('normal');
  }

  // 仅允许固定公开接口，空列表与错误演示同样发起真实远端请求。
  static async fetchRemoteTodos(mode: string = 'normal'): Promise<Todo[]> {
    let url: string = 'https://jsonplaceholder.typicode.com/todos';
    if (mode === 'empty') {
      url = 'https://jsonplaceholder.typicode.com/todos?userId=0';
    } else if (mode === 'error') {
      url = 'https://jsonplaceholder.typicode.com/this-route-does-not-exist';
    } else if (mode !== 'normal') {
      throw new Error('不支持的远端请求场景');
    }
    // 1. 创建 http 请求
    const httpRequest = http.createHttp();
    try {
      // 2. 发起 GET 请求获取示例数据（jsonplaceholder 公开接口）
      const resp = await httpRequest.request(
        url,
        {
          method: http.RequestMethod.GET,
          connectTimeout: 10000,
          readTimeout: 10000,
          // 遵循系统网络代理；不绑定开发机地址或账号。
          usingProxy: true,
          usingCache: false,
          header: { 'Content-Type': 'application/json' },
        }
      );
      // 3. 校验状态码，非 200 视为异常
      if (resp.responseCode !== 200) {
        throw new Error(`状态码 ${resp.responseCode}`);
      }
      // 4. 解析结果并映射为 Todo 数组，只取前 5 条作示例
      if (typeof resp.result !== 'string') {
        throw new Error('接口返回的数据格式不正确');
      }
      const data = JSON.parse(resp.result) as RemoteTodo[];
      if (!Array.isArray(data)) {
        throw new Error('接口返回的不是待办列表');
      }
      return data.slice(0, 5).map((item, index) => {
        if (item === null || typeof item !== 'object' || !Number.isSafeInteger(item.id) || item.id <= 0 ||
          typeof item.title !== 'string' || item.title.trim() === '' || item.title.length > 200 ||
          typeof item.completed !== 'boolean') {
          throw new Error('接口返回的待办内容不完整');
        }
        return new Todo(item.id, item.title.trim(), index === 0 ? '示例：来自网络接口' : '', item.completed, index % 2);
      });
    } catch (e) {
      // 5. 网络异常透明向上传递，由页面三态处理
      throw (e as Error);
    } finally {
      // 6. 无论如何释放连接，避免资源泄漏
      httpRequest.destroy();
    }
  }
}
