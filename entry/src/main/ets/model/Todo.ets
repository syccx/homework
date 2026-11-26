// 数据模型：单条待办事项，使用状态管理 V2 细粒度追踪
@ObservedV2
export class Todo {
  // 字段级 @Trace：只对该字段建立响应式依赖，变化时触发局部刷新
  @Trace id: number;
  @Trace title: string;
  @Trace description: string;
  @Trace done: boolean = false;
  // 优先级：0 = 普通，1 = 高
  @Trace priority: number = 0;
  // 创建时间（毫秒）
  @Trace createdAt: number;
  // 截止时间（毫秒），0 = 未设置
  @Trace dueAt: number = 0;
  // 软删除标记：true 表示在回收站
  @Trace deleted: boolean = false;
  // 完成时间（毫秒），0 = 未完成；用于近 7 天趋势统计
  @Trace doneAt: number = 0;

  constructor(id: number, title: string, description: string, done: boolean, priority: number,
    createdAt: number = Date.now(), dueAt: number = 0, deleted: boolean = false, doneAt: number = 0) {
    this.id = id;
    this.title = title;
    this.description = description;
    this.done = done;
    this.priority = priority;
    this.createdAt = createdAt;
    this.dueAt = dueAt;
    this.deleted = deleted;
    this.doneAt = doneAt;
  }
}
