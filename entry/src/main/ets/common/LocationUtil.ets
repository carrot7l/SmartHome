import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';
import http from '@ohos.net.http';

export interface LocationInfo {
  latitude: number;
  longitude: number;
  address: string;
}

export class LocationUtil {
  private static cachedLocation: LocationInfo | null = null;
  private static cacheTime: number = 0;
  private static readonly CACHE_TTL: number = 60000;

  static async requestPermission(): Promise<boolean> {
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('abilityContext') || undefined;
    if (!context) return false;
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(context, [
          'ohos.permission.APPROXIMATELY_LOCATION',
          'ohos.permission.LOCATION'
        ]);
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) return false;
      }
      return true;
    } catch (err) {
      console.error('[Location] 权限请求失败: ' + JSON.stringify(err));
      return false;
    }
  }

  static async getCurrentLocation(): Promise<LocationInfo | null> {
    const now: number = Date.now();
    if (LocationUtil.cachedLocation && (now - LocationUtil.cacheTime) < LocationUtil.CACHE_TTL) {
      return LocationUtil.cachedLocation;
    }

    const hasPermission: boolean = await LocationUtil.requestPermission();
    if (!hasPermission) {
      console.info('[Location] 无定位权限');
      return LocationUtil.cachedLocation;
    }

    try {
      const requestInfo: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.UNSET,
        maxAccuracy: 100
      };
      const location: geoLocationManager.Location =
        await geoLocationManager.getCurrentLocation(requestInfo);

      const latitude: number = location.latitude;
      const longitude: number = location.longitude;
      const address: string = await LocationUtil.reverseGeocode(latitude, longitude);

      const info: LocationInfo = { latitude: latitude, longitude: longitude, address: address };
      LocationUtil.cachedLocation = info;
      LocationUtil.cacheTime = now;
      return info;
    } catch (err) {
      console.error('[Location] 获取定位失败: ' + JSON.stringify(err));
      return LocationUtil.cachedLocation;
    }
  }

  static async reverseGeocode(latitude: number, longitude: number): Promise<string> {
    try {
      const requestInfo: geoLocationManager.ReverseGeoCodeRequest = {
        latitude: latitude,
        longitude: longitude,
        maxItems: 1,
        locale: 'zh'
      };
      const geoAddresses: geoLocationManager.GeoAddress[] =
        await geoLocationManager.getAddressesFromLocation(requestInfo);
      if (geoAddresses && geoAddresses.length > 0) {
        const geoAddress: geoLocationManager.GeoAddress = geoAddresses[0];
        if (geoAddress.placeName) {
          return geoAddress.placeName;
        }
        let addr: string = '';
        if (geoAddress.locality) addr += geoAddress.locality;
        if (geoAddress.subLocality) addr += geoAddress.subLocality;
        if (geoAddress.roadName) addr += geoAddress.roadName;
        if (addr) return addr;
      }
    } catch (err) {
      console.error('[Location] 逆地理编码失败: ' + JSON.stringify(err));
    }
    return `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`;
  }
}