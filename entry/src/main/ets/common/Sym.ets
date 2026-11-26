/**
 * 系统符号注册表
 *
 * SymbolGlyph 需要 SymbolGlyphModifier 资源对象，集中在此创建。
 */
import { SymbolGlyphModifier } from '@kit.ArkUI';

export class Sym {
  static readonly plus: Resource = $r('sys.symbol.plus');
  static readonly trash: Resource = $r('sys.symbol.trash');
  static readonly checkCircleFill: Resource = $r('sys.symbol.checkmark_circle_fill');
  static readonly circleDashed: Resource = $r('sys.symbol.circle_dashed');
  static readonly listCheck: Resource = $r('sys.symbol.list_checkmark');
  static readonly refresh: Resource = $r('sys.symbol.arrow_2_circlepath');
  static readonly warn: Resource = $r('sys.symbol.exclamationmark_circle');
  static readonly chevronLeft: Resource = $r('sys.symbol.chevron_left');
  static readonly flag: Resource = $r('sys.symbol.flag_fill');
  static readonly clock: Resource = $r('sys.symbol.clock');
  static readonly inbox: Resource = $r('sys.symbol.inbox');
  static readonly pencil: Resource = $r('sys.symbol.square_and_pencil_fill');
  static readonly cloudOff: Resource = $r('sys.symbol.exclamationmark_cloud_fill');

  // 需要以 modifier 形式控制颜色的场景，统一在此构造
  static modifier(res: Resource, color: ResourceColor): SymbolGlyphModifier {
    const m = new SymbolGlyphModifier(res);
    m.fontColor([color]);
    return m;
  }
}
