// ApiClient.ets
import http from '@ohos.net.http';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { RequestSecurityUtil } from './RequestSecurityUtil';

// ==================== 基础配置 ====================
/** 后端服务器基础地址（请替换为你的后端地址） */
export const BASE_URL: string = 'http://YOUR_BACKEND_HOST:5001/api';

/** 自签名CA证书在沙箱中的路径（应用启动时从rawfile复制） */
let caCertPath: string = '';
let caCertReady: boolean = false;

/** 初始化CA证书：从rawfile复制到沙箱目录（同步版本） */
export function initCaCertSync(context: common.UIAbilityContext): void {
  try {
    const destPath: string = `${context.filesDir}/rootCA.crt`;
    try {
      const stat = fs.statSync(destPath);
      if (stat.size > 0) {
        caCertPath = destPath;
        caCertReady = true;
        console.info('[ApiClient] CA cert already exists: ' + destPath);
        return;
      }
    } catch (_e) {
      // file not exist, need to copy
    }
    const content: Uint8Array = context.resourceManager.getRawFileContentSync('rootCA.crt');
    const file = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    fs.writeSync(file.fd, content.buffer);
    fs.closeSync(file);
    caCertPath = destPath;
    caCertReady = true;
    console.info('[ApiClient] CA cert copied to: ' + destPath);
  } catch (err) {
    console.error('[ApiClient] initCaCert error: ' + JSON.stringify(err));
  }
}

/** 初始化CA证书：从rawfile复制到沙箱目录（异步版本） */
export async function initCaCert(): Promise<void> {
  try {
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('abilityContext') || undefined;
    if (!context) {
      console.error('[ApiClient] no abilityContext for CA cert init');
      return;
    }
    const destPath: string = `${context.filesDir}/rootCA.crt`;
    try {
      const stat = fs.statSync(destPath);
      if (stat.size > 0) {
        caCertPath = destPath;
        caCertReady = true;
        console.info('[ApiClient] CA cert already exists: ' + destPath);
        return;
      }
    } catch (_e) {
      // file not exist, need to copy
    }
    const content: Uint8Array = await context.resourceManager.getRawFileContent('rootCA.crt');
    const file = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    fs.writeSync(file.fd, content.buffer);
    fs.closeSync(file);
    caCertPath = destPath;
    caCertReady = true;
    console.info('[ApiClient] CA cert copied to: ' + destPath);
  } catch (err) {
    console.error('[ApiClient] initCaCert error: ' + JSON.stringify(err));
  }
}

/** 构建通用HTTP请求选项 */
function buildRequestOptions(method: http.RequestMethod, headers: Record<string, string>,
  extraData?: string, timeout: number = 10000): http.HttpRequestOptions {
  const opts: http.HttpRequestOptions = {
    method,
    header: headers,
    extraData: extraData,
    connectTimeout: timeout,
    readTimeout: timeout,
    expectDataType: http.HttpDataType.STRING,
  };
  return opts;
}

/** 获取CA证书路径，未就绪时返回系统默认CA路径 */
export function getCaPath(): string {
  return caCertReady ? caCertPath : '/system/etc/security/certificates';
}

// ==================== 通用响应结构 ====================
/** 后端统一响应格式 */
export interface ApiResponse {
  code?: number;               // 业务状态码，200表示成功
  message?: string;            // 提示信息
  token?: string;              // JWT令牌（登录成功时返回）
  userId?: number | string;    // 用户ID
  homeId?: number | string;    // 家庭ID（创建/加入时返回）
  currentHomeId?: number | string; // 当前选中的家庭ID
  userInfo?: ApiUserInfo;      // 用户基本信息对象
  homes?: ApiHomeInfo[];       // 家庭列表
  data?: object | Array<object>; // 其他业务数据（具体类型见下方各接口）
  needRegister?: boolean;      // 华为账号登录时是否需要注册
  unionId?: string;            // 华为账号唯一标识（需要注册时返回）
  inviteCode?: string;         // 家庭邀请码（创建家庭时返回）
}

// ==================== 用户相关类型 ====================
/** 用户基本信息（后端返回格式） */
export interface ApiUserInfo {
  userId?: string | number;    // 用户ID
  username?: string;           // 用户名
  nickname?: string;           // 昵称
  phone?: string;              // 手机号
  avatarUrl?: string | null;   // 头像URL
  role?: string;               // 在家庭中的角色：'owner' 或 'member'
  mode?: string;               // 家庭模式：'single' 或 'family'
}

/** 家庭信息（后端返回的单个家庭） */
export interface ApiHomeInfo {
  homeId?: number | string;    // 家庭ID
  homeName?: string;           // 家庭名称（字段名兼容 name）
  name?: string;               // 部分接口使用 name 字段
  role?: string;               // 当前用户在该家庭的角色
  mode?: string;               // 家庭模式
  inviteCode?: string;         // 邀请码
  memberCount?: number;        // 成员数量
  isCurrent?: boolean;         // 是否为当前选中的家庭
}

// ==================== 登录/注册请求体 ====================
/** 用户名密码登录请求 */
export interface PasswordLoginReq {
  username: string;
  password: string;
}

/** 华为账号登录请求（仅需 unionId） */
export interface HuaweiLoginReq {
  unionId: string;
}

/** 注册请求（根据模式不同，部分字段可选） */
export interface RegisterReq {
  unionId: string;             // 华为账号标识
  mode: string;                // 'single' 或 'family'
  identity?: string;           // 家庭模式下 'owner' 或 'member'
  username?: string;           // 可选，不提供则自动生成
  nickname: string;
  password: string;
  homeName?: string;           // 创建家庭时需要
  homePassword?: string;       // 家庭密码（创建或加入时）
  inviteCode?: string;         // 成员通过邀请码加入时提供
  homeId?: number;             // 成员通过家庭ID+密码加入时提供
}

// ==================== 家庭管理接口类型 ====================
/** 家庭列表项（/api/user/homes 返回的 data 数组元素） */
export interface HomeItem {
  homeId: number;              // 家庭ID
  homeName: string;            // 家庭名称
  role: string;                // 用户在家庭中的角色：'owner' 或 'member'
  mode: string;                // 家庭模式：'single' 或 'family'
  memberCount: number;         // 家庭成员数量
  inviteCode: string;          // 邀请码
  isCurrent: boolean;          // 是否为当前家庭
  createdAt?: string;          // 创建时间
}

/** 当前家庭响应数据（/api/user/current-home 返回的 data） */
export interface CurrentHomeData {
  homeId: number;              // 当前家庭ID
  homeName: string;            // 当前家庭名称
  mode: string;                // 家庭模式
  inviteCode: string;          // 邀请码
}

/** 切换当前家庭请求体 */
export interface SwitchCurrentHomeReq {
  homeId: number;              // 要切换到的家庭ID
}

/** 加入家庭请求体（两种方式选一） */
export interface JoinHomeReq {
  inviteCode?: string;         // 方式一：邀请码
  homeId?: number;             // 方式二：家庭ID
  password?: string;           // 方式二：家庭密码
}

/** 业主添加成员请求体（userId / username / phone 三选一） */
export interface AddMemberReq {
  userId?: number;             // 通过用户ID添加
  username?: string;           // 通过用户名添加
  phone?: string;              // 通过手机号添加
}

/** 转让业主请求体 */
export interface TransferOwnerReq {
  newOwnerId: number;          // 新业主的用户ID
}

/** 修改家庭信息请求体 */
export interface UpdateHomeReq {
  name?: string;               // 新家庭名
  oldPassword?: string;        // 旧密码（修改密码时需要）
  newPassword?: string;        // 新密码
}

// ==================== 设备相关接口类型 ====================
/** 设备列表项（/api/device/list 返回的 data 数组元素） */
export interface DeviceItem {
  deviceId: number;            // 设备ID
  name: string;                // 设备名称
  deviceType: string;          // 设备类型：'temp_humi_sensor', 'light', 'air_conditioner', 'door', 'camera' 等
  room: string;                // 所在房间
  status: string;              // 设备状态：'online'（开/在线）或 'offline'（关/离线）
  homeId: number;              // 所属家庭ID
  createdAt: string;           // 创建时间
}

/** 温湿度传感器最新数据（/api/device/latest/<deviceId> 返回的 data） */
export interface SensorLatestData {
  temperature?: number;        // 温度（摄氏度）
  humidity?: number;           // 湿度（百分比）
  lux?: number;                // 光照强度（可选）
  light_status?: string;       // 灯光状态（可选）
  motor_status?: string;       // 电机状态（可选）
  timestamp?: string;          // 数据时间戳
  state?: string;              // 某些设备的状态（如门）
  deviceType?: string;         // 设备类型
  deviceName?: string;         // 设备名称
  room?: string;               // 房间
  status?: string;             // 状态描述
  message?: string;            // 附加信息（如无数据时）
}

/** 空调控制参数 */
export interface AcControlParams {
  temp?: number;
  mode?: string;
  fan_speed?: string;
  wind_direction?: string;
  swing?: boolean;
  sleep_mode?: boolean;
  eco_mode?: boolean;
  timer_enabled?: boolean;
  timer_action?: string;
  timer_minutes?: number;
}

/** 空调状态（GET /api/device/{deviceId}/ac-status 返回的 data.settings） */
export interface AcStatusSettings {
  power: boolean;
  temp: number;
  mode: string;
  fanSpeed: string;
  windDirection: string;
  swing: boolean;
  sleepMode: boolean;
  ecoMode: boolean;
  timerEnabled: boolean;
  timerAction: string | null;
  timerMinutes: number;
}

/** 空调状态响应（GET /api/device/{deviceId}/ac-status 返回的 data） */
export interface AcStatusData {
  deviceId: number;
  name: string;
  room: string;
  online: boolean;
  settings: AcStatusSettings;
  updatedAt: string | null;
}

/** 设备控制请求体（统一格式） */
export interface DeviceControlReq {
  deviceId: number | string;
  action: string;
  room?: string;
  params?: AcControlParams;
}

// ==================== 青少年模式接口类型 ====================
/** 青少年模式状态（/api/teen-mode/status 返回的 data） */
export interface TeenModeStatus {
  isEnabled: boolean;          // 是否已开启
  enabledAt?: string;          // 开启时间
  disabledAt?: string;         // 关闭时间
}

/** 青少年模式权限设置请求体 */
export interface TeenModeSettingsReq {
  canControlLight?: boolean;   // 是否允许控制灯
  canControlAc?: boolean;      // 是否允许控制空调
  canControlDoor?: boolean;    // 是否允许控制门
}

/** 业主开启/关闭青少年模式的请求体（具体字段根据后端实现） */
export interface TeenModeEnableReq {
  homeId: number;
}
export interface TeenModeDisableReq {
  homeId: number;
  ownerUsername: string;
  ownerPassword: string;
}

// ==================== 告警设置接口类型 ====================
/** 告警设置（/api/alert/settings 返回的 data） */
export interface AlertSettings {
  homeId: number;
  tempEnabled: boolean;        // 温度告警开关
  tempThreshold: number;       // 温度告警阈值（℃）
  humiEnabled: boolean;        // 湿度告警开关
  humiThreshold: number;       // 湿度告警阈值（%）
  acAutoEnabled: boolean;      // 空调自动控制开关
  acTempThreshold: number;     // 空调自动开启温度阈值
  acHumiThreshold: number;     // 空调自动开启湿度阈值
}

// ==================== 人脸识别与摄像头 ====================
/** 人脸识别结果（/api/face/recognize 返回的 data） */
/** 人脸识别成功时的用户信息 */
export interface FaceRecognizeUser {
  userId: number;
  username: string;
  distance: number;   // 特征距离，越小越相似
}

/** 人脸识别结果（/api/face/recognize 返回的 data） */
export interface FaceRecognizeResult {
  recognized: boolean;         // 是否识别成功
  user?: FaceRecognizeUser;    // 识别成功时的用户信息
  reason?: string;             // 失败原因：'disabled', 'no_faces', 'face_size_too_small', 'no_match'
  attemptCount?: number;       // 当前连续失败次数
  maxAttempts?: number;        // 最大允许失败次数
  alertTriggered?: boolean;    // 是否触发了告警
}

/** 摄像头配置请求/响应 */
export interface CameraConfig {
  deviceId: number;
  faceRecognitionEnabled: number; // 0/1
  faceSizeThreshold: number;      // 人脸占比阈值
  maxAttempts: number;            // 最大尝试次数
  attemptCount: number;           // 当前尝试计数
}

// ==================== 消息通知 ====================
/** 消息通知项（/api/user/notifications 返回的 data 数组元素） */
export interface NotificationItem {
  notify_id: number;           // 通知ID
  type: string;                // 通知类型
  title: string;               // 标题
  content: string;             // 内容
  extra_data?: string;         // 额外数据（JSON字符串）
  is_read: number;             // 是否已读 0/1
  created_at: string;          // 创建时间
}

// ==================== 消息相关类型 ====================
/** 单条消息项 */
export interface MessageItem {
  id: number;
  type: string;
  title: string;
  content: string;
  isRead: boolean;
  createdAt: string;
  senderId: number;
  senderName: string;
}

/** 分页信息 */
export interface PaginationInfo {
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
}

/** 消息列表响应数据 */
export interface MessagesResponse {
  homeId: number;
  messages: MessageItem[];
  pagination: PaginationInfo;
}

// ==================== ApiClient 类 ====================
/**
 * 后端接口调用客户端
 * 所有方法均为静态方法，无需实例化
 */
export class ApiClient {
  /**
   * GET 请求
   * @param path 接口路径（如 '/user/profile'）
   * @param token 可选的 JWT token（已登录用户需传入）
   * @returns Promise<ApiResponse>
   */
  static async get(path: string, token?: string): Promise<ApiResponse> {
    return ApiClient.request(http.RequestMethod.GET, path, undefined, token);
  }

  /**
   * POST 请求
   * @param path 接口路径
   * @param body 请求体对象
   * @param token 可选的 JWT token
   */
  static async post(path: string, body?: object, token?: string): Promise<ApiResponse> {
    return ApiClient.request(http.RequestMethod.POST, path, body, token);
  }

  /**
   * PUT 请求
   * @param path 接口路径
   * @param body 请求体对象
   * @param token 可选的 JWT token
   */
  static async put(path: string, body?: object, token?: string): Promise<ApiResponse> {
    return ApiClient.request(http.RequestMethod.PUT, path, body, token);
  }

  /**
   * DELETE 请求
   * @param path 接口路径
   * @param token 可选的 JWT token
   */
  static async delete(path: string, token?: string): Promise<ApiResponse> {
    return ApiClient.request(http.RequestMethod.DELETE, path, undefined, token);
  }

  /**
   * 上传头像（multipart/form-data）
   * @param filePath 本地图片文件路径
   * @param token JWT token
   * @returns Promise<ApiResponse>，成功后 data.url 为头像URL
   */
  static async uploadAvatar(filePath: string, token: string): Promise<ApiResponse> {
    const httpRequest = http.createHttp();
    const headers: Record<string, string> = RequestSecurityUtil.buildHeaders({}, token);
    try {
      const formData: Array<http.MultiFormData> = [{
        name: 'file',
        contentType: 'image/jpeg',
        remoteFileName: 'avatar.jpg',
        filePath: filePath
      }];
      const uploadOpts: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        multiFormDataList: formData,
        connectTimeout: 15000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING,
      };
      const response = await httpRequest.request(BASE_URL + '/upload/avatar', uploadOpts);
      const resultText = response.result as string;
      if (!resultText) return { code: -1, message: '服务器无响应' };
      return JSON.parse(resultText) as ApiResponse;
    } catch (err) {
      console.error('uploadAvatar error', JSON.stringify(err));
      return { code: -1, message: '上传失败' };
    } finally {
      httpRequest.destroy();
    }
  }

  // ==================== 私有请求方法 ====================
  private static async request(
    method: http.RequestMethod,
    path: string,
    body?: object,
    token?: string
  ): Promise<ApiResponse> {
    const httpRequest = http.createHttp();
    const headers: Record<string, string> = RequestSecurityUtil.buildHeaders({ 'Content-Type': 'application/json' }, token ?? '');

    try {
      const response = await httpRequest.request(BASE_URL + path,
        buildRequestOptions(method, headers, body ? JSON.stringify(body) : undefined, 10000)
      );
      const resultText = response.result as string;
      if (!resultText) {
        return { code: -1, message: '服务器无响应' };
      }
      return JSON.parse(resultText) as ApiResponse;
    } catch (err) {
      const errObj: Error = err as Error;
      console.error(`ApiClient request error: ${errObj.message}, caPath=${caCertPath}, ready=${caCertReady}`);
      return { code: -1, message: `网络请求失败: ${errObj.message}` };
    } finally {
      httpRequest.destroy();
    }
  }
}