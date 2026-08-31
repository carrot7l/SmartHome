import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { ApiClient, HomeItem, CurrentHomeData, SwitchCurrentHomeReq } from '../common/ApiClient';
import { StorageUtil } from '../common/StorageUtil';
import { CarVoiceAssistant } from '../common/CarVoiceAssistant';

@Entry
@Component
struct FamilyPage {
  @State currentHomeName: string = '加载中...';
  @State currentHomeId: number = 0;
  @State currentRole: string = '';
  @State currentMemberCount: number = 0;
  @State otherHomes: HomeItem[] = [];

  aboutToAppear(): void {
    this.loadData();
  }

  async loadData(): Promise<void> {
    const token = StorageUtil.getToken();
    if (!token) {
      promptAction.showToast({ message: '未登录' });
      router.back();
      return;
    }

    const currentResp = await ApiClient.get('/user/current-home', token);
    if (currentResp.code === 200 && currentResp.data) {
      const data = currentResp.data as CurrentHomeData;
      this.currentHomeId = data.homeId;
      this.currentHomeName = data.homeName || `家庭${data.homeId}`;

    } else {
      this.currentHomeName = '获取失败';
    }

    const homesResp = await ApiClient.get('/user/homes', token);
    if (homesResp.code === 200 && homesResp.data && Array.isArray(homesResp.data)) {
      const allHomes = homesResp.data as HomeItem[];
      for (let i = 0; i < allHomes.length; i++) {
        if (allHomes[i].isCurrent) {
          this.currentHomeId = allHomes[i].homeId;
          this.currentHomeName = allHomes[i].homeName;
          this.currentRole = allHomes[i].role === 'owner' ? '业主' : '家庭成员';
          this.currentMemberCount = allHomes[i].memberCount || 0;
          break;
        }
      }
      this.otherHomes = allHomes.filter((home: HomeItem) => !home.isCurrent);
    } else {
      promptAction.showToast({ message: homesResp.message || '获取家庭列表失败' });
    }
  }

  async switchCurrentHome(homeId: number, homeName: string): Promise<void> {
    if (homeId === this.currentHomeId) return;
    const token = StorageUtil.getToken();
    const reqBody: SwitchCurrentHomeReq = { homeId };
    const resp = await ApiClient.put('/user/current-home', reqBody, token);
    if (resp.code === 200) {
      this.currentHomeId = homeId;
      this.currentHomeName = homeName;
      StorageUtil.setCurrentHomeId(homeId);
      StorageUtil.setCurrentHomeName(homeName);
      const homesResp = await ApiClient.get('/user/homes', token);
      if (homesResp.code === 200 && homesResp.data && Array.isArray(homesResp.data)) {
        const allHomes = homesResp.data as HomeItem[];
        for (let i = 0; i < allHomes.length; i++) {
          if (allHomes[i].isCurrent) {
            this.currentRole = allHomes[i].role === 'owner' ? '业主' : '家庭成员';
            this.currentMemberCount = allHomes[i].memberCount || 0;
            break;
          }
        }
        this.otherHomes = allHomes.filter((home: HomeItem) => !home.isCurrent);
      }
      StorageUtil.setCurrentHomeName(homeName);
      promptAction.showToast({ message: `已切换到 ${homeName}` });
    } else {
      promptAction.showToast({ message: resp.message || '切换失败' });
    }
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
        Text('家庭管理')
          .fontSize(22)
          .fontColor('#5D4E37')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(48)
      }
      .width('100%')
      .height(56)
      .padding({ top: 16 })

      Row() {
        Column() {
          Text('当前家庭')
            .fontSize(18)
            .fontColor('#9E9189')
            .margin({ bottom: 16 })

          Column() {
            Row() {
              Text('家庭名称：')
                .fontSize(16)
                .fontColor('#9E9189')
                .width(100)
              Text(this.currentHomeName)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#5D4E37')
                .layoutWeight(1)
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })

            Divider().color('#D5CEC8')

            Row() {
              Text('我的身份：')
                .fontSize(16)
                .fontColor('#9E9189')
                .width(100)
              Text(this.currentRole || '--')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#5D4E37')
                .layoutWeight(1)
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })

            Divider().color('#D5CEC8')

            Row() {
              Text('成员数：')
                .fontSize(16)
                .fontColor('#9E9189')
                .width(100)
              Text(this.currentMemberCount > 0 ? `${this.currentMemberCount}` : '--')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#5D4E37')
                .layoutWeight(1)
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor('#E6DFD6')
          .borderRadius(16)
          .padding({ top: 8, bottom: 8 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('50%')
        .height('100%')
        .padding({ left: 24, right: 8, top: 16 })
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text('我所在的其他家庭')
            .fontSize(18)
            .fontColor('#9E9189')
            .margin({ bottom: 16 })

          if (this.otherHomes.length === 0) {
            Text('暂无其他家庭')
              .fontSize(16)
              .fontColor('#9E9189')
              .margin({ top: 40 })
          } else {
            Scroll() {
              Column() {
                ForEach(this.otherHomes, (home: HomeItem) => {
                  Row() {
                    Text(`家庭号 ${home.homeId}`)
                      .fontSize(14)
                      .fontColor('#7F7E7E')
                      .width('40%')
                    Text(home.homeName)
                      .fontSize(16)
                      .fontColor('#5D4E37')
                      .layoutWeight(1)
                    Text('双击切换')
                      .fontSize(12)
                      .fontColor('#BBA0E9')
                  }
                  .width('100%')
                  .height(52)
                  .padding({ left: 16, right: 16 })
                  .borderRadius(12)
                  .backgroundColor('#E6DFD6')
                  .margin({ bottom: 8 })
                  .gesture(
                    TapGesture({ count: 2 })
                      .onAction(() => {
                        this.switchCurrentHome(home.homeId, home.homeName);
                      })
                  )
                }, (home: HomeItem) => home.homeId.toString())
              }
              .width('100%')
            }
            .scrollable(ScrollDirection.Vertical)
            .layoutWeight(1)
            .align(Alignment.TopStart)
          }
        }
        .width('50%')
        .height('100%')
        .padding({ left: 8, right: 24, top: 16 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0E9E2')

    CarVoiceAssistant()
      .margin({ bottom: 24, right: 24 })
    }
  }
}
