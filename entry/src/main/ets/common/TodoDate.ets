/** 截止日期与时分分别编辑；新设日期默认当天 18:00。 */
export class TodoDate {
  static withDate(current: number, selected: Date): number {
    const old = current > 0 ? new Date(current) : undefined;
    return new Date(selected.getFullYear(), selected.getMonth(), selected.getDate(),
      old ? old.getHours() : 18, old ? old.getMinutes() : 0, 0, 0).getTime();
  }

  static withTime(current: number, hour: number, minute: number): number {
    const date = current > 0 ? new Date(current) : new Date();
    date.setHours(hour, minute, 0, 0);
    return date.getTime();
  }

  static label(timestamp: number): string {
    if (timestamp === 0) {
      return '未设置';
    }
    const date = new Date(timestamp);
    const hour = date.getHours().toString().padStart(2, '0');
    const minute = date.getMinutes().toString().padStart(2, '0');
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()} ${hour}:${minute}`;
  }
}
