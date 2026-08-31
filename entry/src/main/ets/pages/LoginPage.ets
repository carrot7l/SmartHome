import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { ApiClient, PasswordLoginReq } from '../common/ApiClient';
import { StorageUtil } from '../common/StorageUtil';

@Entry
@Component
struct LoginPage {
  @State username: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;

  build() {
    Row() {
      Column() {
        Text('欢迎回来')
          .fontSize(32)
          .fontColor('#5D4E37')
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 8 })

        Text('登录您的智能家居账号')
          .fontSize(16)
          .fontColor('#9E9189')
          .margin({ bottom: 40 })

        TextInput({ placeholder: '用户名' })
          .onChange((value: string) => { this.username = value; })
          .width(360)
          .height(52)
          .fontSize(18)
          .backgroundColor('#DDDCD7')
          .fontColor('#5D4E37')
          .placeholderColor('#AAAAAA')
          .borderRadius(12)
          .margin({ bottom: 16 })

        TextInput({ placeholder: '密码' })
          .type(InputType.Password)
          .onChange((value: string) => { this.password = value; })
          .width(360)
          .height(52)
          .fontSize(18)
          .backgroundColor('#DDDCD7')
          .fontColor('#5D4E37')
          .placeholderColor('#AAAAAA')
          .borderRadius(12)
          .margin({ bottom: 32 })

        Button(this.isLoading ? '登录中...' : '登 录')
          .width(360)
          .height(52)
          .fontSize(20)
          .enabled(!this.isLoading)
          .onClick(() => {
            if (!this.username.trim() || !this.password.trim()) {
              promptAction.showToast({ message: '请输入用户名和密码' });
              return;
            }
            this.doLogin();
          })
          .backgroundColor('#99ABBC')
          .fontColor('#FFFFFF')
          .borderRadius(26)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EBE6E2')
    .justifyContent(FlexAlign.Center);
  }

  async doLogin() {
    this.isLoading = true;
    const req: PasswordLoginReq = {
      username: this.username.trim(),
      password: this.password.trim()
    };
    const resp = await ApiClient.post('/user/login', req);
    this.isLoading = false;

    if (resp.code === 200 && resp.token) {
      StorageUtil.saveLoginInfo(resp);
      promptAction.showToast({ message: '登录成功' });
      router.replaceUrl({ url: 'pages/HomePage' });
    } else {
      promptAction.showToast({ message: resp.message || '登录失败，请检查账号密码' });
    }
  }
}