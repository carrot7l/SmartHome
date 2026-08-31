import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { ApiClient, MessageItem, MessagesResponse } from '../common/ApiClient';
import { StorageUtil } from '../common/StorageUtil';
import { CarVoiceAssistant } from '../common/CarVoiceAssistant';

interface MessageWithColor {
  message: MessageItem;
  bgColor: string;
  senderColor: string;
}

@Entry
@Component
struct MessagePage {
  @State messagesWithColor: MessageWithColor[] = [];
  @State selectedIndex: number = 0;
  @State isLoading: boolean = true;
  private homeId: number = 0;

  aboutToAppear(): void {
    this.homeId = StorageUtil.getHomeId();
    if (this.homeId === 0) {
      promptAction.showToast({ message: '未获取到家庭信息' });
      router.back();
      return;
    }
    this.loadMessages();
  }

  async loadMessages(): Promise<void> {
    this.isLoading = true;
    const token = StorageUtil.getToken();
    if (!token) {
      promptAction.showToast({ message: '未登录' });
      router.back();
      return;
    }

    const resp = await ApiClient.get(`/home/${this.homeId}/messages?page=1&page_size=50`, token);
    if (resp.code === 200 && resp.data) {
      const data = resp.data as MessagesResponse;
      const messages = data.messages || [];
      const temp: MessageWithColor[] = [];
      for (let i = 0; i < messages.length; i++) {
        const remainder = i % 3;
        let bgColor: string;
        let senderColor: string;
        if (remainder === 0) {
          bgColor = '#EFDBD4';
          senderColor = '#E29C9B';
        } else if (remainder === 1) {
          bgColor = '#E6DBDF';
          senderColor = '#9B7BB0';
        } else {
          bgColor = '#DBDFD9';
          senderColor = '#7A9F9E';
        }
        temp.push({ message: messages[i], bgColor: bgColor, senderColor: senderColor });
      }
      this.messagesWithColor = temp;
      const pendingSender: string = AppStorage.get<string>('pendingMessageSender') || '';
      if (pendingSender) {
        AppStorage.delete('pendingMessageSender');
        for (let i = 0; i < temp.length; i++) {
          const senderName: string = temp[i].message.senderName || '';
          if (senderName.includes(pendingSender) || pendingSender.includes(senderName)) {
            this.selectedIndex = i;
            break;
          }
        }
      }
    } else {
      promptAction.showToast({ message: resp.message || '加载失败' });
    }
    this.isLoading = false;
  }

  formatTime(timestamp: string): string {
    if (!timestamp) return '';
    return timestamp.substring(5, 16).replace('T', ' ');
  }

  formatFullTime(timestamp: string): string {
    if (!timestamp) return '';
    return timestamp.replace('T', ' ').substring(0, 19);
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
        Text('消息')
          .fontSize(22)
          .fontColor('#5D4E37')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(48)
      }
      .width('100%')
      .height(56)
      .padding({ top: 16 })

      if (this.isLoading) {
        LoadingProgress().width(48).height(48).margin({ top: 80 })
      } else if (this.messagesWithColor.length === 0) {
        Text('暂无消息')
          .fontSize(18)
          .fontColor('#9E9189')
          .margin({ top: 80 })
      } else {
        Row() {
          Scroll() {
            Column() {
              ForEach(this.messagesWithColor, (item: MessageWithColor, index: number) => {
                this.MessageItemBuilder(item, index);
              }, (item: MessageWithColor) => item.message.id.toString())
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
          .scrollBar(BarState.Auto)
          .scrollable(ScrollDirection.Vertical)
          .width('45%')
          .height('100%')
          .padding({ left: 16, right: 8 })

          Column() {
            this.MessageDetailBuilder()
          }
          .width('55%')
          .height('100%')
          .padding({ left: 8, right: 24, top: 8, bottom: 8 })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0E9E2')

    CarVoiceAssistant()
      .margin({ bottom: 24, right: 24 })
    }
  }

  @Builder
  MessageItemBuilder(item: MessageWithColor, index: number) {
    Column() {
      Row() {
        Text(item.message.senderName || '系统')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(item.senderColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(this.formatTime(item.message.createdAt))
          .fontSize(10)
          .fontColor('#D4CBCF')
      }
      .width('100%')
      .margin({ bottom: 4 })

      Text(item.message.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#5E5C5C')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 2 })

      Text(item.message.content)
        .fontSize(12)
        .fontColor('#C2B8BC')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .backgroundColor(index === this.selectedIndex ? '#D5CEC8' : item.bgColor)
    .borderRadius(12)
    .padding(12)
    .margin({ bottom: 8 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.selectedIndex = index;
    })
  }

  @Builder
  MessageDetailBuilder() {
    if (this.messagesWithColor.length > 0 && this.selectedIndex < this.messagesWithColor.length) {
      Column() {
        Row() {
          Text(this.messagesWithColor[this.selectedIndex].message.senderName || '系统')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#738D89')
          Text(this.formatFullTime(this.messagesWithColor[this.selectedIndex].message.createdAt))
            .fontSize(14)
            .fontColor('#BBB9B4')
            .margin({ left: 16 })
        }
        .width('100%')
        .margin({ bottom: 16 })

        Text(this.messagesWithColor[this.selectedIndex].message.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#738D89')
          .margin({ bottom: 20 })
          .width('100%')

        Scroll() {
          Text(this.messagesWithColor[this.selectedIndex].message.content)
            .fontSize(16)
            .fontColor('#5D4E37')
            .width('100%')
            .textAlign(TextAlign.Start)
            .lineHeight(26)
        }
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#E6DFD6')
      .borderRadius(16)
      .padding(24)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    } else {
      Column() {
        Text('请选择一条消息')
          .fontSize(18)
          .fontColor('#9E9189')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#E6DFD6')
      .borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
