// StorageUtil.ets
import { ApiResponse, ApiUserInfo, ApiHomeInfo } from './ApiClient';

export class StorageUtil {
  // 登录成功后保存所有信息
  static saveLoginInfo(resp: ApiResponse): void {
    if (resp.token) {
      AppStorage.setOrCreate('token', resp.token);
    }
    if (resp.userId) {
      const uid = Number(resp.userId);
      if (!isNaN(uid) && uid > 0) AppStorage.setOrCreate('userId', uid);
    }
    // 当前家庭ID
    let currentHomeId = 0;
    if (resp.currentHomeId) {
      currentHomeId = Number(resp.currentHomeId);
    } else if (resp.homeId) {
      currentHomeId = Number(resp.homeId);
    }
    if (currentHomeId > 0) {
      AppStorage.setOrCreate('currentHomeId', currentHomeId);
      AppStorage.setOrCreate('homeId', currentHomeId);
    }
    if (resp.userInfo) {
      StorageUtil.saveUserInfo(resp.userInfo);   // 改为类名调用
    }
    if (resp.homes && resp.homes.length > 0) {
      let selected = resp.homes.find(h => h.isCurrent === true);
      if (!selected && currentHomeId > 0) {
        selected = resp.homes.find(h => Number(h.homeId) === currentHomeId);
      }
      if (!selected) selected = resp.homes[0];
      if (selected) StorageUtil.saveCurrentHomeInfo(selected); // 改为类名调用
    }
  }

  static saveUserInfo(userInfo: ApiUserInfo): void {
    if (userInfo.userId) {
      const uid = Number(userInfo.userId);
      if (!isNaN(uid) && uid > 0) AppStorage.setOrCreate('userId', uid);
    }
    if (userInfo.username) AppStorage.setOrCreate('username', userInfo.username);
    if (userInfo.nickname) AppStorage.setOrCreate('nickname', userInfo.nickname);
    if (userInfo.phone) AppStorage.setOrCreate('phone', userInfo.phone);
    if (userInfo.avatarUrl) AppStorage.setOrCreate('avatarUrl', userInfo.avatarUrl);
  }

  static saveCurrentHomeInfo(home: ApiHomeInfo): void {
    if (home.homeId) {
      const hid = Number(home.homeId);
      if (!isNaN(hid) && hid > 0) {
        AppStorage.setOrCreate('currentHomeId', hid);
        AppStorage.setOrCreate('homeId', hid);
      }
    }
    if (home.homeName) AppStorage.setOrCreate('currentHomeName', home.homeName);
    if (home.role) AppStorage.setOrCreate('currentRole', home.role);
    if (home.mode) AppStorage.setOrCreate('currentMode', home.mode);
  }


  //Setter
  static setNickname(nickname: string): void {
    AppStorage.setOrCreate('nickname', nickname);
  }
  static setPhone(phone: string): void {
    AppStorage.setOrCreate('phone', phone);
  }
  static setCurrentHomeId(homeId: number): void {
    AppStorage.setOrCreate('currentHomeId', homeId);
    AppStorage.setOrCreate('homeId', homeId);
  }
  static setCurrentHomeName(homeName: string): void {
    AppStorage.setOrCreate('currentHomeName', homeName);
  }

  // 常用 Getter
  static getToken(): string {
    return AppStorage.get<string>('token') || '';
  }
  static getUserId(): number {
    return AppStorage.get<number>('userId') || 0;
  }
  static getHomeId(): number {
    return AppStorage.get<number>('currentHomeId') || AppStorage.get<number>('homeId') || 0;
  }
  static getNickname(): string {
    return AppStorage.get<string>('nickname') || '';
  }
  static getCurrentHomeName(): string {
    return AppStorage.get<string>('currentHomeName') || '我的家';
  }
  static getPhone(): string {
    return AppStorage.get<string>('phone') || '';
  }
  static getAvatarUrl(): string {
    return AppStorage.get<string>('avatarUrl') || '';
  }
  static getCurrentRole(): string {
    return AppStorage.get<string>('currentRole') || '';
  }
  static getCurrentMode(): string {
    return AppStorage.get<string>('currentMode') || '';
  }

  static getUsername(): string {
    return AppStorage.get<string>('username') || '';
  }

  static clear(): void {
    AppStorage.setOrCreate('token', '');
    AppStorage.setOrCreate('userId', 0);
    AppStorage.setOrCreate('homeId', 0);
    AppStorage.setOrCreate('currentHomeId', 0);
    AppStorage.setOrCreate('currentHomeName', '');
    AppStorage.setOrCreate('currentRole', '');
    AppStorage.setOrCreate('currentMode', '');
    AppStorage.setOrCreate('username', '');
    AppStorage.setOrCreate('nickname', '');
    AppStorage.setOrCreate('phone', '');
    AppStorage.setOrCreate('avatarUrl', '');
  }
}