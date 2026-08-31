import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { ApiClient, DeviceItem, DeviceControlReq, AcStatusData, AcControlParams } from '../common/ApiClient';
import { StorageUtil } from '../common/StorageUtil';
import { CarVoiceAssistant } from '../common/CarVoiceAssistant';
import { IntentResult } from '../common/IntentService';

interface ModeOption {
  label: string;
  value: string;
  icon: string;
}

interface FanOption {
  label: string;
  value: string;
}

interface WindOption {
  label: string;
  value: string;
}

@Entry
@Component
struct DevicePage {
  @State lightDevices: DeviceItem[] = [];
  @State doorDevices: DeviceItem[] = [];
  @State acDevices: DeviceItem[] = [];
  @State isLoading: boolean = true;

  @State acSelectedIndex: number = -1;
  @State acPower: boolean = false;
  @State acTemp: number = 26;
  @State acMode: string = 'cool';
  @State acFanSpeed: string = 'auto';
  @State acWindDirection: string = 'auto';
  @State acSwing: boolean = false;
  @State acSleepMode: boolean = false;
  @State acEcoMode: boolean = false;
  @State isSending: boolean = false;

  private refreshTimer: number = -1;

  private modeOptions: ModeOption[] = [
    { label: '自动', value: 'auto', icon: '🔄' },
    { label: '制冷', value: 'cool', icon: '❄️' },
    { label: '制热', value: 'heat', icon: '☀️' },
    { label: '除湿', value: 'dry', icon: '💧' },
    { label: '送风', value: 'fan', icon: '🌀' }
  ];

  private fanOptions: FanOption[] = [
    { label: '自动', value: 'auto' },
    { label: '低', value: 'low' },
    { label: '中', value: 'medium' },
    { label: '高', value: 'high' }
  ];

  private windOptions: WindOption[] = [
    { label: '自动', value: 'auto' },
    { label: '上', value: 'up' },
    { label: '中', value: 'middle' },
    { label: '下', value: 'down' }
  ];

  aboutToAppear(): void {
    this.loadAllDevices();
    this.refreshTimer = setInterval(() => { this.refreshDevices() }, 5000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
  }

  async loadAllDevices(): Promise<void> {
    this.isLoading = true;
    await this.refreshDevices();
    this.isLoading = false;
    const multiStr: string = AppStorage.get<string>('pendingMultiControl') || '';
    if (multiStr) {
      AppStorage.setOrCreate('pendingMultiControl', '');
      try {
        const multiData: string[] = JSON.parse(multiStr) as string[];
        for (let i = 0; i < multiData.length; i++) {
          AppStorage.setOrCreate('pendingControl', multiData[i]);
          await this.executePendingControl();
          if (i < multiData.length - 1) {
            await new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), 800));
          }
        }
      } catch (err) {
        console.error('多指令执行失败', JSON.stringify(err));
      }
    } else {
      this.executePendingControl();
    }
  }

  async executePendingControl(): Promise<void> {
    const pendingStr: string = AppStorage.get<string>('pendingControl') || '';
    if (!pendingStr) return;
    AppStorage.setOrCreate('pendingControl', '');

    try {
      const pending: Record<string, string> = JSON.parse(pendingStr);
      const deviceType: string = pending['deviceType'] || '';
      const operation: string = pending['operation'] || '';
      const room: string = pending['room'] || '';
      const deviceName: string = pending['deviceName'] || '';
      const acParamsStr: string = pending['acParams'] || '';
      const token: string = StorageUtil.getToken();
      if (!token) return;

      if (deviceType === 'light') {
        await this.executeLightControl(operation, room, deviceName, token);
      } else if (deviceType === 'ac') {
        await this.executeAcControl(operation, room, deviceName, acParamsStr, token);
      } else if (deviceType === 'door') {
        await this.executeDoorControl(operation, room, deviceName, token);
      }
    } catch (err) {
      console.error('执行控制失败', JSON.stringify(err));
    }
  }

  async executeLightControl(operation: string, room: string, deviceName: string, token: string): Promise<void> {
    let targets: DeviceItem[] = this.lightDevices;
    if (room) {
      targets = targets.filter((d: DeviceItem) => d.room === room);
    }
    if (deviceName) {
      const nameTargets: DeviceItem[] = targets.filter((d: DeviceItem) =>
        d.name === deviceName || d.name.includes(deviceName) || deviceName.includes(d.name)
      );
      if (nameTargets.length > 0) {
        targets = nameTargets;
      }
    }

    if (targets.length === 0) {
      promptAction.showToast({ message: room ? `未找到${room}的灯设备` : '未找到灯设备' });
      return;
    }

    const newStatus: string = operation === 'on' ? 'online' : 'offline';
    const targetIds: number[] = [];
    for (let i = 0; i < targets.length; i++) {
      targetIds.push(targets[i].deviceId);
    }
    const updated: DeviceItem[] = [];
    for (let i = 0; i < this.lightDevices.length; i++) {
      const old: DeviceItem = this.lightDevices[i];
      if (targetIds.indexOf(old.deviceId) >= 0) {
        updated.push({
          deviceId: old.deviceId, name: old.name, deviceType: old.deviceType,
          room: old.room, status: newStatus, homeId: old.homeId, createdAt: old.createdAt
        });
      } else {
        updated.push(old);
      }
    }
    this.lightDevices = updated;

    for (const device of targets) {
      const reqBody: DeviceControlReq = {
        deviceId: device.deviceId,
        action: operation || 'on',
        room: device.room
      };
      await ApiClient.post('/device/control', reqBody, token);
    }
    promptAction.showToast({ message: room ? `已${operation === 'on' ? '开启' : '关闭'}${room}灯光` : `已${operation === 'on' ? '开启' : '关闭'}全部灯光` });
    await new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), 1500));
    await this.refreshDevices();
  }

  async executeAcControl(operation: string, room: string, deviceName: string, acParamsStr: string, token: string): Promise<void> {
    if (room) {
      const matchIdx: number = this.acDevices.findIndex((d: DeviceItem) => d.room === room);
      if (matchIdx >= 0) {
        this.acSelectedIndex = matchIdx;
        await this.loadAcStatus(this.acDevices[matchIdx].deviceId);
      }
    }

    let targets: DeviceItem[] = this.acDevices;
    if (room) {
      targets = targets.filter((d: DeviceItem) => d.room === room);
    }
    if (deviceName) {
      const nameTargets: DeviceItem[] = targets.filter((d: DeviceItem) =>
        d.name === deviceName || d.name.includes(deviceName) || deviceName.includes(d.name)
      );
      if (nameTargets.length > 0) {
        targets = nameTargets;
      }
    }

    if (targets.length === 0) {
      promptAction.showToast({ message: room ? `未找到${room}的空调设备` : '未找到空调设备' });
      return;
    }

    let acParams: Record<string, Object> | undefined = undefined;
    if (acParamsStr) {
      acParams = JSON.parse(acParamsStr) as Record<string, Object>;
    }

    const isUpdateSettings: boolean = !!(acParams && Object.keys(acParams).length > 0);
    const newStatus: string = (operation === 'on' || isUpdateSettings) ? 'online' : 'offline';
    const targetIds: number[] = [];
    for (let i = 0; i < targets.length; i++) {
      targetIds.push(targets[i].deviceId);
    }
    const updated: DeviceItem[] = [];
    for (let i = 0; i < this.acDevices.length; i++) {
      const old: DeviceItem = this.acDevices[i];
      if (targetIds.indexOf(old.deviceId) >= 0) {
        updated.push({
          deviceId: old.deviceId, name: old.name, deviceType: old.deviceType,
          room: old.room, status: newStatus, homeId: old.homeId, createdAt: old.createdAt
        });
      } else {
        updated.push(old);
      }
    }
    this.acDevices = updated;

    if (!isUpdateSettings) {
      if (operation === 'off') {
        this.acPower = false;
      } else if (operation === 'on') {
        this.acPower = true;
      }
    }

    for (const device of targets) {
      if (isUpdateSettings) {
        const finalParams: Record<string, Object> = {};

        if (device.status === 'offline') {
          const onReq: DeviceControlReq = {
            deviceId: device.deviceId,
            action: 'on',
            room: device.room
          };
          await ApiClient.post('/device/control', onReq, token);
        }

        if (acParams!['temp_delta'] !== undefined) {
          const delta: number = acParams!['temp_delta'] as number;
          await this.loadAcStatus(device.deviceId);
          const newTemp: number = Math.max(16, Math.min(30, this.acTemp + delta));
          finalParams['temp'] = newTemp;
        } else if (acParams!['temp'] !== undefined) {
          finalParams['temp'] = acParams!['temp'];
        }

        if (acParams!['mode'] !== undefined) finalParams['mode'] = acParams!['mode'];
        if (acParams!['fan_speed'] !== undefined) finalParams['fan_speed'] = acParams!['fan_speed'];
        if (acParams!['wind_direction'] !== undefined) finalParams['wind_direction'] = acParams!['wind_direction'];
        if (acParams!['swing'] !== undefined) finalParams['swing'] = acParams!['swing'];
        if (acParams!['sleep_mode'] !== undefined) finalParams['sleep_mode'] = acParams!['sleep_mode'];
        if (acParams!['eco_mode'] !== undefined) finalParams['eco_mode'] = acParams!['eco_mode'];

        const reqBody: DeviceControlReq = {
          deviceId: device.deviceId,
          action: 'update_settings',
          room: device.room,
          params: finalParams as AcControlParams
        };
        await ApiClient.post('/device/control', reqBody, token);
      } else {
        const reqBody: DeviceControlReq = {
          deviceId: device.deviceId,
          action: operation || 'on',
          room: device.room
        };
        await ApiClient.post('/device/control', reqBody, token);
      }
    }

    if (isUpdateSettings) {
      promptAction.showToast({ message: room ? `已设置${room}空调` : '已设置空调' });
    } else {
      promptAction.showToast({ message: room ? `已${operation === 'on' ? '开启' : '关闭'}${room}空调` : `已${operation === 'on' ? '开启' : '关闭'}全部空调` });
    }
    const savedRoom: string = room;
    await new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), 1500));
    await this.refreshDevices();
    if (savedRoom) {
      const matchIdx2: number = this.acDevices.findIndex((d: DeviceItem) => d.room === savedRoom);
      if (matchIdx2 >= 0) {
        this.acSelectedIndex = matchIdx2;
        await this.loadAcStatus(this.acDevices[matchIdx2].deviceId);
      }
    } else if (this.acSelectedIndex >= 0 && this.acSelectedIndex < this.acDevices.length) {
      await this.loadAcStatus(this.acDevices[this.acSelectedIndex].deviceId);
    }
  }

  async executeDoorControl(operation: string, room: string, deviceName: string, token: string): Promise<void> {
    let actualOp: string = operation;
    if (actualOp === 'on') {
      actualOp = 'open';
    } else if (actualOp === 'off') {
      actualOp = 'close';
    }

    let targets: DeviceItem[] = this.doorDevices;
    if (room) {
      targets = targets.filter((d: DeviceItem) => d.room === room);
    }
    if (deviceName) {
      const nameTargets: DeviceItem[] = targets.filter((d: DeviceItem) =>
        d.name === deviceName || d.name.includes(deviceName) || deviceName.includes(d.name)
      );
      if (nameTargets.length > 0) {
        targets = nameTargets;
      }
    }

    if (targets.length === 0) {
      promptAction.showToast({ message: room ? `未找到${room}的门设备` : '未找到门设备' });
      return;
    }

    const newStatus: string = actualOp === 'open' ? 'online' : 'offline';
    const targetIds: number[] = [];
    for (let i = 0; i < targets.length; i++) {
      targetIds.push(targets[i].deviceId);
    }
    const updated: DeviceItem[] = [];
    for (let i = 0; i < this.doorDevices.length; i++) {
      const old: DeviceItem = this.doorDevices[i];
      if (targetIds.indexOf(old.deviceId) >= 0) {
        updated.push({
          deviceId: old.deviceId, name: old.name, deviceType: old.deviceType,
          room: old.room, status: newStatus, homeId: old.homeId, createdAt: old.createdAt
        });
      } else {
        updated.push(old);
      }
    }
    this.doorDevices = updated;

    for (const device of targets) {
      const reqBody: DeviceControlReq = {
        deviceId: device.deviceId,
        action: actualOp || 'open',
        room: device.room
      };
      const resp = await ApiClient.post('/device/control', reqBody, token);
      if (resp.code === 200 && resp.data) {
        const data: Record<string, Object> = resp.data as Record<string, Object>;
        if (data['blocked'] === true) {
          promptAction.showToast({ message: '当前处于门禁状态，无法开门' });
        }
      } else {
        promptAction.showToast({ message: resp.message || '操作失败' });
      }
    }
    promptAction.showToast({ message: room ? `已${actualOp === 'open' ? '打开' : '关闭'}${room}门锁` : `已${actualOp === 'open' ? '打开' : '关闭'}全部门锁` });
    await new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), 1500));
    await this.refreshDevices();
  }

  async handleAssistantControl(intent: IntentResult): Promise<void> {
    const multiStr: string = AppStorage.get<string>('pendingMultiControl') || '';
    if (multiStr) {
      AppStorage.setOrCreate('pendingMultiControl', '');
      try {
        const multiData: string[] = JSON.parse(multiStr) as string[];
        for (let i = 0; i < multiData.length; i++) {
          AppStorage.setOrCreate('pendingControl', multiData[i]);
          await this.executePendingControl();
          if (i < multiData.length - 1) {
            await new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), 800));
          }
        }
      } catch (err) {
        console.error('多指令执行失败', JSON.stringify(err));
      }
      return;
    }
    const pendingObj: Record<string, string> = {};
    pendingObj['deviceType'] = intent.deviceType || '';
    pendingObj['room'] = intent.room || '';
    pendingObj['operation'] = intent.operation || '';
    if (intent.deviceName) pendingObj['deviceName'] = intent.deviceName;
    if (intent.acParams) pendingObj['acParams'] = JSON.stringify(intent.acParams);
    AppStorage.setOrCreate('pendingControl', JSON.stringify(pendingObj));
    await this.executePendingControl();
  }

  async refreshDevices(): Promise<void> {
    const token = StorageUtil.getToken();
    if (!token) return;

    const resp = await ApiClient.get('/device/list', token);
    if (resp.code === 200 && resp.data && Array.isArray(resp.data)) {
      const allDevices = resp.data as DeviceItem[];
      this.lightDevices = allDevices.filter((d: DeviceItem) => d.deviceType === 'light');
      this.doorDevices = allDevices.filter((d: DeviceItem) => d.deviceType === 'door');
      this.acDevices = allDevices.filter((d: DeviceItem) => d.deviceType === 'air_conditioner');
      if (this.acDevices.length > 0 && this.acSelectedIndex < 0) {
        this.acSelectedIndex = 0;
        await this.loadAcStatus(this.acDevices[0].deviceId);
      }
    }
  }

  // ========== 灯控制 ==========
  async toggleLight(device: DeviceItem): Promise<void> {
    const token = StorageUtil.getToken();
    if (!token) return;
    const isCurrentlyOn = device.status === 'online';
    const action = isCurrentlyOn ? 'off' : 'on';
    const newStatus = isCurrentlyOn ? 'offline' : 'online';
    const idx = this.lightDevices.findIndex((d: DeviceItem) => d.deviceId === device.deviceId);
    if (idx >= 0) {
      const updated: DeviceItem[] = [];
      for (let i = 0; i < this.lightDevices.length; i++) {
        if (i === idx) {
          const old = this.lightDevices[i];
          updated.push({
            deviceId: old.deviceId, name: old.name, deviceType: old.deviceType,
            room: old.room, status: newStatus, homeId: old.homeId, createdAt: old.createdAt
          });
        } else {
          updated.push(this.lightDevices[i]);
        }
      }
      this.lightDevices = updated;
    }
    const reqBody: DeviceControlReq = {
      deviceId: device.deviceId,
      action: action,
      room: device.room
    };
    const resp = await ApiClient.post('/device/control', reqBody, token);
    if (resp.code === 200) {
      promptAction.showToast({ message: `${device.name} 已${action === 'on' ? '开启' : '关闭'}` });
      this.refreshDevices();
    } else {
      if (idx >= 0) {
        const reverted: DeviceItem[] = [];
        for (let i = 0; i < this.lightDevices.length; i++) {
          if (i === idx) {
            const old2 = this.lightDevices[i];
            reverted.push({
              deviceId: old2.deviceId, name: old2.name, deviceType: old2.deviceType,
              room: old2.room, status: device.status, homeId: old2.homeId, createdAt: old2.createdAt
            });
          } else {
            reverted.push(this.lightDevices[i]);
          }
        }
        this.lightDevices = reverted;
      }
      promptAction.showToast({ message: resp.message || '操作失败' });
    }
  }

  // ========== 门控制 ==========
  async toggleDoor(device: DeviceItem): Promise<void> {
    const token = StorageUtil.getToken();
    if (!token) return;
    const isCurrentlyOn = device.status === 'online';
    const action = isCurrentlyOn ? 'close' : 'open';
    const newStatus = isCurrentlyOn ? 'offline' : 'online';
    const idx = this.doorDevices.findIndex((d: DeviceItem) => d.deviceId === device.deviceId);
    if (idx >= 0) {
      const updated: DeviceItem[] = [];
      for (let i = 0; i < this.doorDevices.length; i++) {
        if (i === idx) {
          const old = this.doorDevices[i];
          updated.push({
            deviceId: old.deviceId, name: old.name, deviceType: old.deviceType,
            room: old.room, status: newStatus, homeId: old.homeId, createdAt: old.createdAt
          });
        } else {
          updated.push(this.doorDevices[i]);
        }
      }
      this.doorDevices = updated;
    }
    const reqBody: DeviceControlReq = {
      deviceId: device.deviceId,
      action: action,
      room: device.room
    };
    const resp = await ApiClient.post('/device/control', reqBody, token);
    if (resp.code === 200 && resp.data) {
      const data = resp.data as Record<string, Object>;
      if (data['blocked'] === true) {
        if (idx >= 0) {
          const reverted: DeviceItem[] = [];
          for (let i = 0; i < this.doorDevices.length; i++) {
            if (i === idx) {
              const old2 = this.doorDevices[i];
              reverted.push({
                deviceId: old2.deviceId, name: old2.name, deviceType: old2.deviceType,
                room: old2.room, status: device.status, homeId: old2.homeId, createdAt: old2.createdAt
              });
            } else {
              reverted.push(this.doorDevices[i]);
            }
          }
          this.doorDevices = reverted;
        }
        promptAction.showToast({ message: '当前处于门禁状态，无法开门' });
      } else {
        promptAction.showToast({ message: `${device.name} 已${action === 'open' ? '打开' : '关闭'}` });
        this.refreshDevices();
      }
    } else {
      if (idx >= 0) {
        const reverted: DeviceItem[] = [];
        for (let i = 0; i < this.doorDevices.length; i++) {
          if (i === idx) {
            const old3 = this.doorDevices[i];
            reverted.push({
              deviceId: old3.deviceId, name: old3.name, deviceType: old3.deviceType,
              room: old3.room, status: device.status, homeId: old3.homeId, createdAt: old3.createdAt
            });
          } else {
            reverted.push(this.doorDevices[i]);
          }
        }
        this.doorDevices = reverted;
      }
      promptAction.showToast({ message: resp.message || '操作失败' });
    }
  }

  // ========== 空调控制 ==========
  async loadAcStatus(deviceId: number): Promise<void> {
    const token = StorageUtil.getToken();
    if (!token) return;
    const resp = await ApiClient.get(`/device/ac/${deviceId}`, token);
    if (resp.code === 200 && resp.data) {
      const data = resp.data as AcStatusData;
      this.acPower = data.online;
      this.acTemp = data.settings.temp;
      this.acMode = data.settings.mode;
      this.acFanSpeed = data.settings.fanSpeed;
      this.acWindDirection = data.settings.windDirection;
      this.acSwing = data.settings.swing;
      this.acSleepMode = data.settings.sleepMode;
      this.acEcoMode = data.settings.ecoMode;
    }
  }

  async onAcDeviceSelect(index: number): Promise<void> {
    if (this.acSelectedIndex === index) return;
    this.acSelectedIndex = index;
    await this.loadAcStatus(this.acDevices[index].deviceId);
  }

  getAcSelectedDevice(): DeviceItem | null {
    if (this.acSelectedIndex >= 0 && this.acSelectedIndex < this.acDevices.length) {
      return this.acDevices[this.acSelectedIndex];
    }
    return null;
  }

  async toggleAcPower(): Promise<void> {
    const device = this.getAcSelectedDevice();
    if (!device) return;
    this.acPower = !this.acPower;
    await this.sendAcControl(this.acPower ? 'on' : 'off');
  }

  async adjustTemp(delta: number): Promise<void> {
    const newTemp = this.acTemp + delta;
    if (newTemp < 16 || newTemp > 30) return;
    this.acTemp = newTemp;
    await this.sendAcControl('update_settings', { temp: this.acTemp });
  }

  async setMode(mode: string): Promise<void> {
    this.acMode = mode;
    await this.sendAcControl('update_settings', { mode: mode });
  }

  async setFanSpeed(fan: string): Promise<void> {
    this.acFanSpeed = fan;
    await this.sendAcControl('update_settings', { fan_speed: fan });
  }

  async setWindDirection(wind: string): Promise<void> {
    this.acWindDirection = wind;
    await this.sendAcControl('update_settings', { wind_direction: wind });
  }

  async toggleSwing(): Promise<void> {
    this.acSwing = !this.acSwing;
    await this.sendAcControl('update_settings', { swing: this.acSwing });
  }

  async toggleSleepMode(): Promise<void> {
    this.acSleepMode = !this.acSleepMode;
    await this.sendAcControl('update_settings', { sleep_mode: this.acSleepMode });
  }

  async toggleEcoMode(): Promise<void> {
    this.acEcoMode = !this.acEcoMode;
    await this.sendAcControl('update_settings', { eco_mode: this.acEcoMode });
  }

  async sendAcControl(action: string, extraParams?: AcControlParams): Promise<void> {
    const device = this.getAcSelectedDevice();
    if (!device) return;
    if (this.isSending) return;
    const token = StorageUtil.getToken();
    if (!token) return;
    this.isSending = true;
    const reqBody: DeviceControlReq = {
      deviceId: device.deviceId,
      action: action,
      room: device.room
    };
    if (extraParams) {
      reqBody.params = extraParams;
    }
    const resp = await ApiClient.post('/device/control', reqBody, token);
    if (resp.code !== 200) {
      promptAction.showToast({ message: resp.message || '操作失败' });
    }
    this.isSending = false;
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
        Text('设备管理')
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
      } else {
        Row() {
          // 左栏：灯
          Column() {
            Text('灯')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#5D4E37')
              .margin({ bottom: 16 })

            if (this.lightDevices.length === 0) {
              Text('暂无灯设备')
                .fontSize(14)
                .fontColor('#9E9189')
                .margin({ top: 40 })
            } else {
              Scroll() {
                Column() {
                  ForEach(this.lightDevices, (device: DeviceItem) => {
                    this.LightItemBuilder(device);
                  }, (device: DeviceItem) => `${device.deviceId}_${device.status}`)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              .scrollable(ScrollDirection.Vertical)
              .layoutWeight(1)
              .align(Alignment.TopStart)
            }
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ left: 16, right: 8, top: 8, bottom: 8 })
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Start)

          // 中栏：空调
          Column() {
            Text('空调')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#5D4E37')
              .margin({ bottom: 16 })

            if (this.acDevices.length === 0) {
              Text('暂无空调设备')
                .fontSize(14)
                .fontColor('#9E9189')
                .margin({ top: 40 })
            } else {
              Scroll() {
                Column() {
                  if (this.acDevices.length > 1) {
                    Row() {
                      ForEach(this.acDevices, (device: DeviceItem, index: number) => {
                        this.AcTabBuilder(device, index);
                      }, (device: DeviceItem) => `${device.deviceId}_${device.status}`)
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Center)
                    .margin({ bottom: 8 })
                  }

                  Column() {
                    Row() {
                      Text(this.acPower ? '运行中' : '已关闭')
                        .fontSize(14)
                        .fontColor(this.acPower ? '#8BA59B' : '#9E9189')
                      Blank()
                      Button(this.acPower ? '关闭' : '开启')
                        .width(64)
                        .height(32)
                        .fontSize(14)
                        .backgroundColor(this.acPower ? '#EAB1B3' : '#8BA59B')
                        .fontColor('#FFFFFF')
                        .borderRadius(16)
                        .onClick(() => this.toggleAcPower())
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12 })

                    if (this.acPower) {
                      Row() {
                        Text('−')
                          .width(40)
                          .height(40)
                          .fontSize(24)
                          .fontColor('#8BA59B')
                          .backgroundColor('#EBE4DC')
                          .borderRadius(20)
                          .textAlign(TextAlign.Center)
                          .onClick(() => this.adjustTemp(-1))
                        Text(`${this.acTemp}°C`)
                          .fontSize(28)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#8BA59B')
                        Text('+')
                          .width(40)
                          .height(40)
                          .fontSize(24)
                          .fontColor('#8BA59B')
                          .backgroundColor('#EBE4DC')
                          .borderRadius(20)
                          .textAlign(TextAlign.Center)
                          .onClick(() => this.adjustTemp(1))
                      }
                      .width('100%')
                      .justifyContent(FlexAlign.SpaceEvenly)
                      .alignItems(VerticalAlign.Center)
                      .padding({ top: 8, bottom: 8 })

                      Column() {
                        Text('模式').fontSize(12).fontColor('#9E9189').width('100%').padding({ left: 8, top: 4 })
                        Row() {
                          ForEach(this.modeOptions, (opt: ModeOption) => {
                            this.AcModeButtonBuilder(opt);
                          }, (opt: ModeOption) => opt.value)
                        }
                        .width('100%')
                        .justifyContent(FlexAlign.Start)
                        .padding({ left: 2, right: 4, bottom: 4 })
                      }
                      .width('100%')
                      .margin({ top: 4 })

                      Column() {
                        Text('风速').fontSize(12).fontColor('#9E9189').width('100%').padding({ left: 8, top: 4 })
                        Row() {
                          ForEach(this.fanOptions, (opt: FanOption) => {
                            this.AcFanButtonBuilder(opt);
                          }, (opt: FanOption) => opt.value)
                        }
                        .width('100%')
                        .justifyContent(FlexAlign.SpaceEvenly)
                        .padding({ left: 4, right: 4, bottom: 4 })
                      }
                      .width('100%')
                      .margin({ top: 4 })

                      Column() {
                        Text('风向').fontSize(12).fontColor('#9E9189').width('100%').padding({ left: 8, top: 4 })
                        Row() {
                          ForEach(this.windOptions, (opt: WindOption) => {
                            this.AcWindButtonBuilder(opt);
                          }, (opt: WindOption) => opt.value)
                        }
                        .width('100%')
                        .justifyContent(FlexAlign.SpaceEvenly)
                        .padding({ left: 4, right: 4, bottom: 4 })
                      }
                      .width('100%')
                      .margin({ top: 4 })

                      Column() {
                        Text('快捷功能').fontSize(12).fontColor('#9E9189').width('100%').padding({ left: 8, top: 4 })
                        Row() {
                          Column() {
                            Text('扫风')
                              .fontSize(12)
                              .fontColor(this.acSwing ? '#FFFFFF' : '#9E9189')
                          }
                          .width(56)
                          .height(32)
                          .borderRadius(10)
                          .backgroundColor(this.acSwing ? '#8CA79C' : '#E6DFD6')
                          .justifyContent(FlexAlign.Center)
                          .alignItems(HorizontalAlign.Center)
                          .onClick(() => this.toggleSwing())

                          Column() {
                            Text('睡眠')
                              .fontSize(12)
                              .fontColor(this.acSleepMode ? '#FFFFFF' : '#9E9189')
                          }
                          .width(56)
                          .height(32)
                          .borderRadius(10)
                          .backgroundColor(this.acSleepMode ? '#8CA79C' : '#E6DFD6')
                          .justifyContent(FlexAlign.Center)
                          .alignItems(HorizontalAlign.Center)
                          .onClick(() => this.toggleSleepMode())

                          Column() {
                            Text('节能')
                              .fontSize(12)
                              .fontColor(this.acEcoMode ? '#FFFFFF' : '#9E9189')
                          }
                          .width(56)
                          .height(32)
                          .borderRadius(10)
                          .backgroundColor(this.acEcoMode ? '#8CA79C' : '#E6DFD6')
                          .justifyContent(FlexAlign.Center)
                          .alignItems(HorizontalAlign.Center)
                          .onClick(() => this.toggleEcoMode())
                        }
                        .width('100%')
                        .justifyContent(FlexAlign.SpaceEvenly)
                        .padding({ left: 4, right: 4, bottom: 4 })
                      }
                      .width('100%')
                      .margin({ top: 4 })
                    }
                  }
                  .width('100%')
                  .backgroundColor('#E6DFD6')
                  .borderRadius(16)
                  .padding(12)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              .scrollable(ScrollDirection.Vertical)
              .layoutWeight(1)
              .align(Alignment.TopStart)
            }
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Start)

          // 右栏：门
          Column() {
            Text('门')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#5D4E37')
              .margin({ bottom: 16 })

            if (this.doorDevices.length === 0) {
              Text('暂无门设备')
                .fontSize(14)
                .fontColor('#9E9189')
                .margin({ top: 40 })
            } else {
              Scroll() {
                Column() {
                  ForEach(this.doorDevices, (device: DeviceItem) => {
                    this.DoorItemBuilder(device);
                  }, (device: DeviceItem) => `${device.deviceId}_${device.status}`)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              .scrollable(ScrollDirection.Vertical)
              .layoutWeight(1)
              .align(Alignment.TopStart)
            }
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ left: 8, right: 16, top: 8, bottom: 8 })
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0E9E2')

    CarVoiceAssistant({
      onControlDevice: (intent: IntentResult) => {
        this.handleAssistantControl(intent);
      }
    })
      .margin({ bottom: 24, right: 24 })
    }
  }

  // ========== 灯 Builder ==========
  @Builder
  LightItemBuilder(device: DeviceItem) {
    Row() {
      Column() {
        Text(device.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#5D4E37')
        Text(device.room)
          .fontSize(12)
          .fontColor('#9E9189')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(device.status === 'online' ? '开' : '关')
        .width(60)
        .height(32)
        .fontSize(14)
        .backgroundColor(device.status === 'online' ? '#EDD0A8' : '#A6AFA8')
        .fontColor('#FFFFFF')
        .borderRadius(16)
        .onClick(() => this.toggleLight(device))
    }
     .width('100%')
     .backgroundColor('#E6DFD6')
     .borderRadius(12)
     .padding(12)
     .margin({ bottom: 8 })
   }

   // ========== 门 Builder ==========
  @Builder
  DoorItemBuilder(device: DeviceItem) {
    Row() {
      Column() {
        Text(device.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#5D4E37')
        Text(device.room)
          .fontSize(12)
          .fontColor('#9E9189')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(device.status === 'online' ? '开' : '关')
        .width(60)
        .height(32)
        .fontSize(14)
        .backgroundColor(device.status === 'online' ? '#EDD0A8' : '#A6AFA8')
        .fontColor('#FFFFFF')
        .borderRadius(16)
        .onClick(() => this.toggleDoor(device))
    }
    .width('100%')
    .backgroundColor('#E6DFD6')
    .borderRadius(12)
    .padding(12)
    .margin({ bottom: 8 })
  }

  // ========== 空调 Builders ==========
  @Builder
  AcTabBuilder(device: DeviceItem, index: number) {
    Text(device.room || device.name)
      .fontSize(12)
      .fontColor(this.acSelectedIndex === index ? '#FFFFFF' : '#9E9189')
      .backgroundColor(this.acSelectedIndex === index ? '#8CA79C' : '#E6DFD6')
      .borderRadius(12)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .margin({ right: 4 })
      .onClick(() => this.onAcDeviceSelect(index))
  }

  @Builder
  AcModeButtonBuilder(opt: ModeOption) {
    Column() {
      Text(opt.icon).fontSize(14)
      Text(opt.label)
        .fontSize(10)
        .fontColor(this.acMode === opt.value ? '#5A7A6E' : '#9E9189')
        .margin({ top: 1 })
    }
    .width(44)
    .height(44)
    .borderRadius(8)
    .backgroundColor(this.acMode === opt.value ? '#E4EAE5' : '#E6DFD6')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .margin({ right: 4 })
    .onClick(() => this.setMode(opt.value))
  }

  @Builder
  AcFanButtonBuilder(opt: FanOption) {
    Text(opt.label)
      .fontSize(12)
      .fontColor(this.acFanSpeed === opt.value ? '#FFFFFF' : '#9E9189')
      .backgroundColor(this.acFanSpeed === opt.value ? '#8CA79C' : '#E6DFD6')
      .borderRadius(10)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .onClick(() => this.setFanSpeed(opt.value))
  }

  @Builder
  AcWindButtonBuilder(opt: WindOption) {
    Text(opt.label)
      .fontSize(12)
      .fontColor(this.acWindDirection === opt.value ? '#FFFFFF' : '#9E9189')
      .backgroundColor(this.acWindDirection === opt.value ? '#8CA79C' : '#E6DFD6')
      .borderRadius(10)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .onClick(() => this.setWindDirection(opt.value))
  }

  @Builder
  AcQuickToggleBuilder(label: string, isActive: boolean, onTap: () => void) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(isActive ? '#FFFFFF' : '#9E9189')
    }
    .width(56)
    .height(32)
    .borderRadius(10)
    .backgroundColor(isActive ? '#8CA79C' : '#E6DFD6')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }
}
