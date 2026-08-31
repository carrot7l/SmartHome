import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { ApiClient } from '../common/ApiClient';
import { StorageUtil } from '../common/StorageUtil';
import { CarVoiceAssistant } from '../common/CarVoiceAssistant';

interface UpdateNicknameReq {
  nickname: string;
}

interface BindPhoneReq {
  phone: string;
}

@Entry
@Component
struct ProfilePage {
  @State nickname: string = '';
  @State username: string = '';
  @State phone: string = '';
  @State currentHomeName: string = '';

  aboutToAppear(): void {
    this.loadUserInfo();
    this.checkPendingEditField();
  }

  checkPendingEditField(): void {
    const editField: string = AppStorage.get<string>('pendingEditField') || '';
    if (!editField) return;
    AppStorage.setOrCreate('pendingEditField', '');

    const editValue: string = AppStorage.get<string>('pendingEditValue') || '';
    AppStorage.setOrCreate('pendingEditValue', '');

    setTimeout(() => {
      if (editField === 'nickname') {
        this.editNickname(editValue);
      } else if (editField === 'phone') {
        this.editPhone(editValue);
      }
    }, 800);
  }

  async loadUserInfo(): Promise<void> {
    const token = StorageUtil.getToken();
    if (!token) return;

    this.nickname = StorageUtil.getNickname() || '用户';
    this.username = StorageUtil.getUsername() || '';
    this.phone = StorageUtil.getPhone() || '';
    this.currentHomeName = StorageUtil.getCurrentHomeName() || '我的家';

    const resp = await ApiClient.get('/user/profile', token);
    if (resp.code === 200 && resp.data) {
      const data = resp.data as Record<string, string>;
      this.nickname = data.nickname || this.nickname;
      this.username = data.username || this.username;
      this.phone = data.phone || this.phone;
      StorageUtil.setNickname(this.nickname);
      if (data.phone) StorageUtil.setPhone(this.phone);
    }
  }

  editNickname(presetValue: string = ''): void {
    const dialogController = new CustomDialogController({
      builder: NicknameEditDialog({
        currentNickname: this.nickname,
        presetValue: presetValue,
        onConfirm: async (newNickname: string) => {
          if (!newNickname) {
            promptAction.showToast({ message: '昵称不能为空' });
            return;
          }
          const token = StorageUtil.getToken();
          const reqBody: UpdateNicknameReq = { nickname: newNickname };
          const resp = await ApiClient.put('/user/profile', reqBody, token);
          if (resp.code === 200) {
            this.nickname = newNickname;
            StorageUtil.setNickname(newNickname);
            promptAction.showToast({ message: '修改成功' });
          } else {
            promptAction.showToast({ message: resp.message || '修改失败' });
          }
          dialogController.close();
        }
      })
    });
    dialogController.open();
  }

  editPhone(presetValue: string = ''): void {
    const dialogController = new CustomDialogController({
      builder: PhoneEditDialog({
        currentPhone: this.phone,
        presetValue: presetValue,
        onConfirm: async (newPhone: string) => {
          if (!newPhone || newPhone.length !== 11 || !/^\d+$/.test(newPhone)) {
            promptAction.showToast({ message: '请输入11位数字手机号' });
            return;
          }
          const token = StorageUtil.getToken();
          const reqBody: BindPhoneReq = { phone: newPhone };
          const resp = await ApiClient.post('/user/bind-phone', reqBody, token);
          if (resp.code === 200) {
            this.phone = newPhone;
            StorageUtil.setPhone(newPhone);
            promptAction.showToast({ message: '绑定成功' });
          } else {
            promptAction.showToast({ message: resp.message || '绑定失败' });
          }
          dialogController.close();
        }
      })
    });
    dialogController.open();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
      Row() {
        Text('<')
          .fontSize(24)
          .fontColor('#5D4E37')
          .onClick(() => router.back())
          .margin({ left: 32 })
        Text('个人信息')
          .fontSize(22)
          .fontColor('#5D4E37')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(48)
      }
      .width('100%')
      .height(56)
      .padding({ top: 16 })

      Column() {
        Stack() {
          Circle({ width: 80, height: 80 }).fill('#A1B2AB')
          Text(this.nickname.charAt(0))
            .fontSize(36)
            .fontColor('#FFFFFF')
        }
        .width(80)
        .height(80)
        .borderRadius(40)
        .backgroundColor('#A1B2AB')
        .clip(true)
      }
      .margin({ top: 24, bottom: 24 })

      Column() {
        Row() {
          Text('用户名').fontSize(16).fontColor('#9E9189').width(80)
          Text(this.username).fontSize(16).fontColor('#5D4E37').layoutWeight(1)
        }
        .width('80%')
        .height(52)
        .padding({ left: 16, right: 16 })

        Divider().width('80%').color('#D5CEC8')

        Row() {
          Text('昵称').fontSize(16).fontColor('#9E9189').width(80)
          Text(this.nickname).fontSize(16).fontColor('#5D4E37').layoutWeight(1)
          Text('双击编辑').fontSize(12).fontColor('#BBA0E9')
        }
        .width('80%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .gesture(
          TapGesture({ count: 2 }).onAction(() => {
            this.editNickname();
          })
        )

        Divider().width('80%').color('#D5CEC8')

        Row() {
          Text('手机号').fontSize(16).fontColor('#9E9189').width(80)
          Text(this.phone || '未绑定').fontSize(16).fontColor('#5D4E37').layoutWeight(1)
          Text('双击编辑').fontSize(12).fontColor('#BBA0E9')
        }
        .width('80%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .gesture(
          TapGesture({ count: 2 }).onAction(() => {
            this.editPhone();
          })
        )
      }
      .width('60%')
      .backgroundColor('#E6DFD6')
      .borderRadius(20)
      .padding({ top: 8, bottom: 8 })
      .alignItems(HorizontalAlign.Center)

      Blank()

      Button('退出登录')
        .backgroundColor('#C0392B')
        .fontColor('#FFFFFF')
        .fontSize(18)
        .borderRadius(24)
        .width(200)
        .height(48)
        .margin({ bottom: 40 })
        .onClick(() => {
          StorageUtil.clear();
          router.replaceUrl({ url: 'pages/Index' });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0E9E2')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)

    CarVoiceAssistant()
      .margin({ bottom: 24, right: 24 })
    }
  }
}

@CustomDialog
struct NicknameEditDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: () => {} });
  currentNickname: string = '';
  presetValue: string = '';
  onConfirm: (newNickname: string) => void = () => {};
  @State inputValue: string = '';

  aboutToAppear() {
    this.inputValue = this.presetValue || this.currentNickname;
  }

  build() {
    Column() {
      Text('修改昵称')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })
        .fontColor('#5D4E37');

      TextInput({ placeholder: '请输入新昵称', text: this.inputValue })
        .width('100%')
        .height(48)
        .fontSize(16)
        .backgroundColor('#E6DFD6')
        .fontColor('#5D4E37')
        .onChange((value: string) => { this.inputValue = value; })
        .margin({ bottom: 24 });

      Row() {
        Button('取消')
          .fontSize(16)
          .height(40)
          .padding({ left: 24, right: 24 })
          .backgroundColor('#9E9189')
          .fontColor('#FFFFFF')
          .borderRadius(20)
          .onClick(() => {
            this.controller?.close();
          });

        Button('确定')
          .fontSize(16)
          .height(40)
          .padding({ left: 24, right: 24 })
          .backgroundColor('#A1B2AB')
          .fontColor('#FFFFFF')
          .borderRadius(20)
          .onClick(() => {
            this.onConfirm(this.inputValue);
            this.controller?.close();
          });
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
    }
    .width(360)
    .padding(24)
    .backgroundColor('#F0E9E2')
    .borderRadius(20)
  }
}

@CustomDialog
struct PhoneEditDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: () => {} });
  currentPhone: string = '';
  presetValue: string = '';
  onConfirm: (newPhone: string) => void = () => {};
  @State inputValue: string = '';

  aboutToAppear() {
    this.inputValue = this.presetValue || (this.currentPhone === '未绑定' ? '' : this.currentPhone);
  }

  build() {
    Column() {
      Text('绑定手机号')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })
        .fontColor('#5D4E37');

      TextInput({ placeholder: '请输入11位手机号', text: this.inputValue })
        .width('100%')
        .height(48)
        .fontSize(16)
        .backgroundColor('#E6DFD6')
        .fontColor('#5D4E37')
        .type(InputType.PhoneNumber)
        .maxLength(11)
        .onChange((value: string) => { this.inputValue = value; })
        .margin({ bottom: 24 });

      Row() {
        Button('取消')
          .fontSize(16)
          .height(40)
          .padding({ left: 24, right: 24 })
          .backgroundColor('#9E9189')
          .fontColor('#FFFFFF')
          .borderRadius(20)
          .onClick(() => {
            this.controller?.close();
          });

        Button('确定')
          .fontSize(16)
          .height(40)
          .padding({ left: 24, right: 24 })
          .backgroundColor('#A1B2AB')
          .fontColor('#FFFFFF')
          .borderRadius(20)
          .onClick(() => {
            this.onConfirm(this.inputValue);
            this.controller?.close();
          });
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
    }
    .width(360)
    .padding(24)
    .backgroundColor('#F0E9E2')
    .borderRadius(20)
  }
}
