/**
 * 设计 token 体系（单一事实源）
 *
 * 设计语言：calm / clean，zinc 中性系 + 单一 emerald accent
 * 规则（taste-skill）：
 *  - 单 accent 锁定全页，不出现第二彩色
 *  - 中性色只用 zinc 族（不混用暖灰冷灰）
 *  - 圆角体系锁定：卡片 16 / 小组件 12 / 控件全圆角
 *  - 无纯黑（#000）无纯白（#fff），一律 off 值
 */
export class Theme {
  // ---------- 背景 ----------
  static readonly bg: string = '#101014';        // 页面底（zinc-950 偏紫黑，非纯黑）
  static readonly card: string = '#1A1A20';      // 卡片面
  static readonly cardHi: string = '#232329';    // 卡片面-高亮（输入框 / hover）

  // ---------- 分隔 ----------
  static readonly border: string = '#2A2A31';    // 1px 描边
  static readonly divider: string = '#222228';   // 行分隔

  // ---------- 文本 ----------
  static readonly fg: string = '#EDEDF0';        // 主文本
  static readonly fgDim: string = '#A1A1AA';     // 次文本（zinc-400）
  static readonly fgFaint: string = '#63636B';   // 弱文本（zinc-500）

  // ---------- 单一 accent ----------
  static readonly accent: string = '#34D399';    // emerald-400
  static readonly accentDeep: string = '#059669'; // emerald-600（按压/进度底）
  static readonly onAccent: string = '#052E16';  // accent 上的文字（emerald-950）

  // ---------- 语义（仅状态真实时使用，非装饰） ----------
  static readonly danger: string = '#F87171';    // 删除类操作专用

  // ---------- 圆角体系 ----------
  static readonly rCard: number = 16;
  static readonly rItem: number = 12;
  static readonly rPill: number = 999;

  // ---------- 字号 ----------
  static readonly tDisplay: number = 34;   // 统计大数字
  static readonly tTitle: number = 20;
  static readonly tBody: number = 15;
  static readonly tSub: number = 13;
  static readonly tMicro: number = 11;
}
