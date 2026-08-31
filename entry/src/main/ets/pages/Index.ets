import router from '@ohos.router';

@Entry
@Component
struct Index {
  build() {
    Column() {
      Text('智能家居')
        .fontSize(36)
        .fontColor('#5D4E37')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 40 })

      Button('点击登录')
        .backgroundColor('#BBA0E9')
        .fontColor('#FFFFFF')
        .fontSize(22)
        .borderRadius(28)
        .width(240)
        .height(56)
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0E9E2')
    .justifyContent(FlexAlign.Center);
  }
}
