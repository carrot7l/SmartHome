import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import {
  ApiClient,
  HomeItem,
  CurrentHomeData,
  DeviceItem,
  SensorLatestData
} from '../common/ApiClient';
import { StorageUtil } from '../common/StorageUtil';
import { CarVoiceAssistant } from '../common/CarVoiceAssistant';

@Entry
@Component
struct HomePage {
  @State currentHomeId: number = 0;
  @State currentHomeName: string = '加载中...';
  @State homes: HomeItem[] = [];
  @State temperature: string = '--';
  @State humidity: string = '--';
  @State timeDisplay: string = '--:--';
  @State dateDisplay: string = '--';

  private dateTimer: number = -1;
  private pollTimer: number = -1;

  aboutToAppear(): void {
    this.loadCurrentHomeAndHomes();
    this.startDateTimeUpdater();
    this.startPolling();
  }

  aboutToDisappear(): void {
    if (this.dateTimer !== -1) clearInterval(this.dateTimer);
    if (this.pollTimer !== -1) clearInterval(this.pollTimer);
  }

  startDateTimeUpdater(): void {
    this.updateDateTime();
    this.dateTimer = setInterval(() => this.updateDateTime(), 1000);
  }

  updateDateTime(): void {
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    this.timeDisplay = `${hours}:${minutes}`;
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const weekdays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    const weekday = weekdays[now.getDay()];
    this.dateDisplay = `${month}-${day} ${weekday}`;
  }

  startPolling(): void {
    this.pollTimer = setInterval(() => this.loadTemperatureAndHumidity(), 5000);
  }

  async loadCurrentHomeAndHomes(): Promise<void> {
    const token = StorageUtil.getToken();
    if (!token) {
      promptAction.showToast({ message: '未登录，请重新登录' });
      router.replaceUrl({ url: 'pages/LoginPage' });
      return;
    }

    const homesResp = await ApiClient.get('/user/homes', token);
    if (homesResp.code === 200 && homesResp.data && Array.isArray(homesResp.data)) {
      this.homes = homesResp.data as HomeItem[];
    }

    const currentResp = await ApiClient.get('/user/current-home', token);
    if (currentResp.code === 200 && currentResp.data) {
      const data = currentResp.data as CurrentHomeData;
      this.currentHomeId = data.homeId;
      this.currentHomeName = data.homeName || `家庭${data.homeId}`;
      this.homes.forEach((h: HomeItem) => h.isCurrent = (h.homeId === this.currentHomeId));
    } else {
      const savedHomeId = StorageUtil.getHomeId();
      if (savedHomeId > 0) {
        this.currentHomeId = savedHomeId;
        this.currentHomeName = `家庭${savedHomeId}`;
      } else if (this.homes.length > 0) {
        this.currentHomeId = this.homes[0].homeId;
        this.currentHomeName = this.homes[0].homeName;
      }
    }

    await this.loadTemperatureAndHumidity();
  }

  async loadTemperatureAndHumidity(): Promise<void> {
    const token = StorageUtil.getToken();
    if (!token || this.currentHomeId === 0) return;

    const deviceResp = await ApiClient.get('/device/list', token);
    if ((deviceResp.code !== 200 && deviceResp.code !== 0) || !deviceResp.data) return;
    const devices = deviceResp.data as DeviceItem[];
    const sensor = devices.find((d: DeviceItem) => d.deviceType === 'temp_humi_sensor');
    if (!sensor) return;

    const latestResp = await ApiClient.get(`/device/latest/${sensor.deviceId}`, token);
    if (latestResp.code === 200 || latestResp.code === 0) {
      const data = latestResp.data as SensorLatestData;
      if (data.temperature !== undefined && data.temperature !== null)
        this.temperature = `${data.temperature}°C`;
      if (data.humidity !== undefined && data.humidity !== null)
        this.humidity = `${data.humidity}%`;
    }
  }

  build() {
    Stack() {
// 背景图
Image($r('app.media.HomePageBackground'))
  .width('100%')
  .height('100%')
  .objectFit(ImageFit.Fill)

Column() {

  // 上部内容区
  Row() {
    // 左侧
    Column() {
      Text(this.timeDisplay)
        .fontSize(150)
        .fontWeight(FontWeight.Bold)
        .fontColor('#6D7B73')
      Text(this.dateDisplay)
        .fontSize(40)
        .fontColor('#97A29B')
        .margin({ top: 10,left: 20,bottom:10 })
      Row() {
        Text('当前家庭')
          .fontSize(22)
          .fontColor('#A4AEA7')
        Text(this.currentHomeName)
          .fontSize(30)
          .fontWeight(FontWeight.Medium)
          .fontColor('#6D7B73')
          .margin({ left: 10 })
      }
      .margin({ top: 22,left: 80 })
    }
    .width('56.5%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: 60
    })

    // 右侧温湿度
    Row() {
      Column() {
        Text('温度')
          .fontSize(24)
          .fontColor('#A4AEA7')
        Text(this.temperature)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#8FA59A')
          .margin({ top: 15 })
      }
      .margin({right:180})
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text('湿度')
          .fontSize(24)
          .fontColor('#A4AEA7')
        Text(this.humidity)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#C1A4AB')
          .margin({ top: 15 })
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 60 })

    }
    .width('38%')
    .height('100%')
    .alignItems(VerticalAlign.Bottom)
    .justifyContent(FlexAlign.Center)
    .padding({
      right: 60,
      bottom: 80
    })

  }
  .width('100%')
  .layoutWeight(1)

  // 底部导航
  Row() {
    this.NavButton(
      '我的',
      () => router.pushUrl({
        url: 'pages/ProfilePage'
      })
    )
    this.NavButton(
      '设备',
      () => router.pushUrl({
        url: 'pages/DevicePage'
      })
    )
    this.NavButton(
      '家庭',
      () => router.pushUrl({
        url: 'pages/FamilyPage'
      })
    )
    this.NavButton(
      '消息',
      () => router.pushUrl({
        url: 'pages/MessagePage'
      })
    )
    this.NavButton(
      '和小华聊天',
      () => router.pushUrl({
        url: 'pages/AiPage'
      })
    )
  }
  .height(150)
  .padding({
    left: 60,
    right: 65,
    bottom: 15
  })
  .justifyContent(FlexAlign.Center)

}
.width('100%')
.height('100%')

    CarVoiceAssistant()
      .position({ x: '75%', y: '70%' })

    }
    .width('100%')
    .height('100%')
  }

  @Builder
  NavButton(text: string, onClick: () => void) {
    Column() {
      Text(text)
      .fontSize(28)
      .fontWeight(FontWeight.Medium)
     .fontColor('#FFFFFF')
    }
    .layoutWeight(1)
    .height(170)
    .backgroundColor('rgba(0,0,0,0)')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(onClick)
  }
}
