let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('count') count: string = '0';
  @LocalStorageProp('latest') latest: string = '暂无待办';

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text('待办清单')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#EDEDF0')
        Blank()
        // 未完成数：emerald 大数字
        Text(this.count)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#34D399')
      }
      .width('100%')

      Blank()

      Text(this.latest)
        .fontSize(11)
        .fontColor('#A1A1AA')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding(14)
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A20')
    .borderRadius(16)
    .onClick(() => {
      // 点卡片拉起应用（静态卡用 router 事件）
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility'
      });
    })
  }
}
