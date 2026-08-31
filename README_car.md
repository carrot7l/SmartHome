# 鸿居智联 - HarmonyOS 智能家居车载端

## 项目概述

**项目名称**：鸿居智联（车载端）  
**项目类型**：HarmonyOS 智能家居车载应用  
**开发语言**：ArkTS (.ets 文件)  
**目标设备**：car（智能座舱）  
**核心特性**：AI 语音助手 + 场景联动（回家/离家） + 习惯智能 + GPS 定位 + 防重放安全传输

---

## 目录结构

```
SmartHomeCar/entry/
├── src/main/
│   ├── ets/
│   │   ├── pages/                    # UI 页面（8 个页面）
│   │   │   ├── Index.ets             # 入口页
│   │   │   ├── LoginPage.ets         # 登录页
│   │   │   ├── HomePage.ets          # 首页
│   │   │   ├── DevicePage.ets        # 设备控制页（灯+空调+门三栏布局）
│   │   │   ├── AiPage.ets            # AI 页面
│   │   │   ├── FamilyPage.ets        # 家庭管理页
│   │   │   ├── MessagePage.ets       # 消息页
│   │   │   └── ProfilePage.ets       # 个人中心页
│   │   ├── common/                   # 公共模块
│   │   │   ├── CarVoiceAssistant.ets # 车载语音助手核心组件
│   │   │   ├── IntentService.ets     # 意图识别服务（LLM+关键词+场景意图）
│   │   │   ├── ApiClient.ets         # API 客户端（CA证书+安全头）
│   │   │   ├── RequestSecurityUtil.ets # 防重放安全头生成
│   │   │   ├── LocationUtil.ets      # GPS 定位 + 逆地理编码
│   │   │   └── StorageUtil.ets       # 本地存储工具
│   │   ├── entryability/
│   │   │   └── EntryAbility.ets
│   │   └── entrybackupability/
│   │       └── EntryBackupAbility.ets
│   ├── resources/
│   │   └── rawfile/
│   │       └── rootCA.crt            # 自签名 CA 证书
│   └── module.json5
└── build-profile.json5
```

---

## 核心功能模块

### 1. 车载语音助手（CarVoiceAssistant）

#### 1.1 架构概览

```text
┌─────────────────────────────────────────────────────────────┐
│                  CarVoiceAssistant 悬浮组件                    │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ 原生ASR  │  │ 唤醒检测  │  │ 语音识别  │  │ 意图识别  │    │
│  │(SpeechKit)│  │ ("小华")  │  │(SpeechKit)│  │(LLM+规则  │    │
│  │          │  │          │  │          │  │ +场景)    │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│       │                                          │          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ 消息轮询  │  │ 场景联动  │  │ 习惯智能  │  │ TTS 语音  │    │
│  │ (4s)     │  │(回家/离家)│  │(空调习惯) │  │(SpeechKit)│    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└─────────────────────────────────────────────────────────────┘
```

#### 1.2 核心流程

```text
待机(sleep) ──"小华"──> 激活态(smile) ──5s无输入──> 回到待机
                           │
                           └──识别到语音──> 处理流程 ──5s──> 回到待机
```

**完整链路**：

1. **待机监听**：原生 `speechRecognizer` 持续监听，识别结果回调里检测"小华"唤醒词
2. **唤醒**：表情切换为 `smile`，进入激活态
3. **语音识别**：激活态下继续原生 ASR 监听，回调拿到指令文本
4. **意图识别**：调用 `IntentService.processText()`，LLM 优先 + 关键词兜底 + 场景意图
5. **意图执行**：根据 `action` 分发到对应处理函数
6. **TTS 播报**：原生 `textToSpeech` 直接合成并播放
7. **回到待机**：执行完毕后自动回到待机状态

#### 1.3 意图执行分发

| action | 处理方式 | 说明 |
|--------|---------|------|
| `control_device` | `executeDeviceControl()` | 调用 API 控制设备 + 乐观更新 |
| `navigate` | `router.pushUrl()` | 页面跳转 |
| `query` | `executeQuery()` | 查询温湿度传感器 |
| `query_device_status` | `executeDeviceStatusQuery()` | 查询设备状态 + LLM 润色 |
| `query_time` | Toast 显示 | 当前时间/日期/星期 |
| `query_current_family` | `queryCurrentFamily()` | 查询当前家庭信息 |
| `read_message` | 读取消息 | 最新消息摘要 |
| `read_message_detail` | 读取消息 | 消息完整内容 |
| `multi_command` | `executeMultiCommands()` | 批量执行多设备控制 |
| `switch_family` | 跳转 FamilyPage | 切换家庭 |
| `chat` | 显示回复 | 闲聊/问答 |
| `unknown` | Toast 提示 | 未理解指令 |

#### 1.4 悬浮助手设计

CarVoiceAssistant 以悬浮组件形式嵌入各页面右下角：

- **可拖拽**：通过 `car_va_offsetX` / `car_va_offsetY` AppStorage 键记录位置
- **表情状态**：`sleep`（待机）→ `smile`（激活）→ `surprise`（告警）
- **非阻塞**：语音助手不遮挡主交互区域

---

### 2. 场景联动系统

车载端独有的场景联动功能，基于用户语音触发的场景意图，自动执行多设备联动操作。

#### 2.1 架构设计

```text
┌──────────────────────────────────────────────────────────┐
│                    场景联动系统                             │
│                                                            │
│  ┌────────────────────┐    ┌────────────────────┐         │
│  │   回家模式          │    │   离家模式          │         │
│  │   arrive_home      │    │   leave_home       │         │
│  │                    │    │                    │         │
│  │  1. 打开所有灯      │    │  1. 关闭所有灯      │         │
│  │  2. 打开所有空调    │    │  2. 关闭所有空调    │         │
│  │  3. 恢复习惯设置    │    │  (仅关闭在线设备)   │         │
│  │    (温度/模式/风速)  │    │                    │         │
│  └────────────────────┘    └────────────────────┘         │
│                                                            │
│  注意：回家/离家模式均不操作门锁                             │
└──────────────────────────────────────────────────────────┘
```

#### 2.2 触发方式

**语音触发**：用户说出场景相关指令，IntentService 识别为 `scene` 意图。

| 触发语句 | 识别场景 |
|---------|---------|
| "我快到家了"、"我回来了"、"帮我设置一下" | `arrive_home`（回家模式） |
| "我要出门了"、"我出门了"、"我走了"、"离开" | `leave_home`（离家模式） |

#### 2.3 回家模式详细流程

```text
"我快到家了"
    ↓
IntentService 识别 → scene 意图 → arrive_home
    ↓
buildSceneCommands('arrive_home')
    ↓
1. GET /device/list → 获取所有灯和空调
    ↓
2. 为每个灯生成 → { deviceType: 'light', operation: 'on' }
    ↓
3. 为每个空调：
   GET /device/ac/{deviceId} → 获取上次设置
   → { deviceType: 'ac', operation: 'on', acParams: { temp, mode, fan_speed, ... } }
    ↓
4. 转为 multi_command → DevicePage 逐条执行
    ↓
5. 回复："根据您的习惯，已为您打开客厅灯光，已为您打开客厅空调，26度，制冷模式，低风速"
```

#### 2.4 离家模式详细流程

```text
"我要出门了"
    ↓
IntentService 识别 → scene 意图 → leave_home
    ↓
buildSceneCommands('leave_home')
    ↓
1. GET /device/list → 获取所有灯和空调
    ↓
2. 筛选 status === 'online' 的设备（避免重复操作已关闭的设备）
    ↓
3. 为每个在线灯 → { deviceType: 'light', operation: 'off' }
   为每个在线空调 → { deviceType: 'ac', operation: 'off' }
    ↓
4. 转为 multi_command → DevicePage 逐条执行
    ↓
5. 回复："已为您关闭所有设备" / "所有设备已处于关闭状态"
```

#### 2.5 习惯实现原理

"习惯"并非真正的 AI 学习，而是读取空调上次使用的设置：

```text
GET /device/ac/{deviceId}
    → response.data.settings: { power, temp, mode, fanSpeed, windDirection, ... }
    → 提取 temp, mode, fanSpeed 等参数
    → 作为 acParams 注入到回家模式的空调指令中
```

---

### 3. 意图识别服务（IntentService）

#### 3.1 三层识别架构

```text
用户文本
    ↓
┌──────────────────────────────────┐
│  LLM 路径（通义千问 qwen-turbo）   │
│  置信度 >= 0.5 → 使用 LLM 结果     │
│  支持 14 种意图类型（含 scene）     │
└──────────────────────────────────┘
    ↓ 置信度 < 0.5 或 LLM 失败
┌──────────────────────────────────┐
│  关键词路径（本地规则匹配）         │
│  50+ 关键词覆盖 95% 指令           │
│  含场景关键词匹配                  │
└──────────────────────────────────┘
    ↓ scene 意图
┌──────────────────────────────────┐
│  enrichQueryResult               │
│  scene → buildSceneCommands()    │
│  → 转为 multi_command            │
└──────────────────────────────────┘
```

#### 3.2 支持的意图类型（14 种）

| intent_type | action | 说明 | 示例指令 |
|-------------|--------|------|---------|
| `control_device` | `control_device` | 设备控制 | "打开客厅灯"、"空调调到25度" |
| `navigate` | `navigate` | 页面导航 | "打开设备页面"、"回到首页" |
| `query` | `query` | 传感器查询 | "现在多少度"、"当前湿度" |
| `query_time` | `query_time` | 时间查询 | "现在几点"、"今天星期几" |
| `edit_profile` | `navigate` | 修改资料 | "修改昵称" |
| `switch_family` | `switch_family` | 切换家庭 | "切换到幸福家庭" |
| `read_message` | `read_message` | 读取消息 | "最新消息" |
| `read_message_detail` | `read_message_detail` | 消息详情 | "详细内容" |
| `query_current_family` | `query_current_family` | 当前家庭 | "当前在哪个家庭" |
| `query_device_status` | `query_device_status` | 设备状态 | "空调开着吗" |
| `multi_command` | `multi_command` | 多指令 | "打开客厅灯然后关卧室灯" |
| **`scene`** | **`scene` → `multi_command`** | **场景触发** | **"我快到家了"、"我要出门了"** |
| `chat` | `chat` | 闲聊问答 | "你好"、"讲个笑话" |
| `unknown` | `unknown` | 未理解 | — |

#### 3.3 LLM Prompt 设计

车载端 IntentService 的 LLM Prompt 包含 12 条意图规则，其中第 12 条为车载端独有的 `scene` 意图：

```text
12. scene - 场景触发意图
   用户说"我快到家了/我回来了" → arrive_home
   用户说"我要出门了/我走了" → leave_home
```

#### 3.4 设备类型与参数

**设备类型**：`light`（灯）、`ac`（空调）、`door`（门锁）

**空调参数支持**：

| 参数 | 类型 | 取值范围 |
|------|------|---------|
| `temp` | number | 16-30°C |
| `temp_delta` | number | 温度偏移 |
| `mode` | string | auto / cool / heat / dry / fan |
| `fan_speed` | string | auto / low / medium / high |
| `wind_direction` | string | auto / up / middle / down |
| `swing` | boolean | 扫风开关 |
| `sleep_mode` | boolean | 睡眠模式 |
| `eco_mode` | boolean | 节能模式 |

---

### 4. GPS 定位服务（LocationUtil）

#### 4.1 功能概览

| 方法 | 功能 |
|------|------|
| `requestPermission()` | 请求 `APPROXIMATELY_LOCATION` + `LOCATION` 权限 |
| `getCurrentLocation()` | 获取当前位置（经纬度 + 地址），带 60 秒缓存 |
| `reverseGeocode(lat, lng)` | 逆地理编码：坐标 → 中文地址 |

#### 4.2 数据结构

```typescript
interface LocationInfo {
  latitude: number;   // 纬度
  longitude: number;  // 经度
  address: string;    // 逆地理编码后的中文地址
}
```

#### 4.3 缓存机制

- **缓存时长**：60 秒（`CACHE_TTL = 60000`）
- **缓存策略**：60 秒内复用上次定位结果，避免频繁 GPS 请求
- **逆地理编码**：优先返回 `placeName`，其次拼接 `locality + subLocality + roadName`

#### 4.4 使用场景

- 在 `callLLMForChat` 中被调用，将车辆位置注入聊天上下文
- 为场景联动提供位置感知能力（未来可扩展"离家 5 公里自动关灯"等）

---

### 5. 安全模块

#### 5.1 防重放安全头

`RequestSecurityUtil.ets` 为每个出站请求自动注入安全头：

| Header 字段 | 值 | 说明 |
|-------------|----|------|
| `X-Request-ID` | `{timestamp}-{randomHex(12)}` | 请求唯一标识 |
| `X-Timestamp` | `Date.now()` | 请求时间戳（毫秒） |
| `X-Nonce` | `randomHex(16)` | 16 字节随机数，防重放 |
| `X-Security-Version` | `1` | 安全协议版本号 |
| `X-Key-ID` | `app-session-v1` | 密钥标识 |
| `Cache-Control` | `no-store` | 禁止缓存 |
| `Pragma` | `no-cache` | 禁止缓存（HTTP/1.0 兼容） |

**随机数生成**：使用 `cryptoFramework.createRandom()` 生成加密安全随机数，失败时降级为时间戳+计数器。

#### 5.2 CA 证书验证

车载端额外支持 HTTPS CA 证书验证：

```text
应用启动 → initCaCertSync(context)
    → 从 rawfile 复制 rootCA.crt 到沙箱目录
    → ApiClient 请求时设置 caPath
    → 验证服务器证书合法性
```

- **证书路径**：`/data/storage/el1/bundle/entry/resources/resfile/appCaCert/rootCA.crt`
- **沙箱副本**：`{context.filesDir}/rootCA.crt`
- **自动检测**：启动时检查沙箱副本是否已存在，存在则跳过复制

#### 5.3 ApiClient 集成

所有 HTTP 请求均通过 `RequestSecurityUtil.buildHeaders()` 构建安全头：

```typescript
const headers: Record<string, string> = RequestSecurityUtil.buildHeaders(
  { 'Content-Type': 'application/json' }, token ?? ''
);
```

同时使用 `buildRequestOptions()` 统一构建请求选项，包含 CA 证书路径和 `expectDataType`。

---

### 6. UI 页面详细设计

#### 6.1 DevicePage.ets - 设备控制页（核心页面）

```text
┌──────────────────────────────────────────────────────┐
│  ┌──────────┐  ┌──────────────────┐  ┌──────────┐   │
│  │  灯光列表  │  │   空调控制面板    │  │  门锁列表  │   │
│  │          │  │                  │  │          │   │
│  │ 客厅灯 ○  │  │   [-] 25°C [+]  │  │ 大门  ○   │   │
│  │ 卧室灯 ○  │  │                  │  │ 后门  ○   │   │
│  │ 书房灯 ○  │  │  制冷 制热 除湿  │  │          │   │
│  │ ...      │  │  低  中  高  自动 │  │          │   │
│  │          │  │                  │  │          │   │
│  │          │  │  [扫风][睡眠][节能]│  │          │   │
│  └──────────┘  └──────────────────┘  └──────────┘   │
└──────────────────────────────────────────────────────┘
```

**三栏布局**：左栏灯光、中栏空调、右栏门锁，适配车载横屏。

**核心方法**：

| 方法 | 功能 |
|------|------|
| `loadAllDevices()` | 加载设备列表 + 执行待处理指令 |
| `executePendingControl()` | 从 AppStorage 读取 `pendingControl` 执行 |
| `executeLightControl()` | 按房间/设备名筛选灯 → 批量开关 |
| `executeAcControl()` | 按房间/设备名筛选空调 → 开关/参数设置 |
| `executeDoorControl()` | 按房间/设备名筛选门 → 开关（含门禁检测） |
| `handleAssistantControl()` | 语音助手触发的设备控制入口 |
| `toggleLight / toggleDoor` | 单设备开关切换（乐观更新 + 失败回滚） |
| `loadAcStatus()` | 加载空调详细状态 |
| `adjustTemp / setMode / setFanSpeed` | 空调参数调节 |
| `sendAcControl()` | 统一发送空调控制请求 |

**乐观更新机制**：所有设备操作先更新 UI 状态，API 失败则回滚。

#### 6.2 HomePage.ets - 首页

- 环境信息展示（温湿度）
- 设备概览统计
- 快捷设备入口
- 嵌入 CarVoiceAssistant 悬浮助手

#### 6.3 FamilyPage.ets - 家庭管理页

- 当前家庭信息卡片
- 家庭列表，支持切换
- 切换后同步更新 StorageUtil

#### 6.4 其他页面

| 页面 | 功能 |
|------|------|
| LoginPage.ets | 用户名密码登录 + 华为账号登录 |
| ProfilePage.ets | 个人信息管理 |
| MessagePage.ets | 消息列表 |
| AiPage.ets | AI 交互页面 |

---

### 7. 本地存储（StorageUtil）

#### 7.1 AppStorage 键值

| 键名 | 类型 | 用途 |
|------|------|------|
| `token` | string | JWT 登录令牌 |
| `userId` | number | 用户 ID |
| `username` | string | 用户名 |
| `nickname` | string | 昵称 |
| `phone` | string | 手机号 |
| `avatarUrl` | string | 头像 URL |
| `homeId` | number | 家庭 ID（兼容） |
| `currentHomeId` | number | 当前选中的家庭 ID |
| `currentHomeName` | string | 当前家庭名称 |
| `currentRole` | string | 当前家庭角色（owner/member） |
| `currentMode` | string | 家庭模式（single/family） |

#### 7.2 CarVoiceAssistant 专用键

| 键名 | 类型 | 用途 |
|------|------|------|
| `car_va_offsetX` | number | 助手浮动位置 X 偏移 |
| `car_va_offsetY` | number | 助手浮动位置 Y 偏移 |
| `pendingControl` | string | 待执行的设备控制指令（JSON） |
| `pendingMultiControl` | string | 待执行的多设备控制指令（JSON） |
| `pendingEditField` | string | 待编辑的个人字段 |
| `pendingEditValue` | string | 待编辑的字段值 |
| `pendingMessageSender` | string | 待读取消息的发送者 |
| `abilityContext` | object | UIAbilityContext 上下文 |

---

## 项目架构模式

### 整体架构：MVVM + 服务层

```text
┌──────────────────────────────────────────────────────────┐
│                    UI Layer (Pages)                       │
│  HomePage, DevicePage, FamilyPage, ProfilePage...        │
│  - @Component 声明式 UI                                   │
│  - @State 管理组件状态                                     │
│  - @StorageLink 连接全局状态                               │
└──────────────────────────────────────────────────────────┘
                          ↓ 调用
┌──────────────────────────────────────────────────────────┐
│                    Service Layer                          │
│  CarVoiceAssistant  - 语音助手（唤醒+识别+执行+TTS+场景）  │
│  IntentService      - 意图识别（LLM+关键词+场景意图）      │
│  LocationUtil       - GPS 定位 + 逆地理编码               │
│  ApiClient          - HTTP 请求（CA证书+安全头）            │
│  RequestSecurityUtil - 防重放安全头                        │
│  StorageUtil        - 本地存储                             │
└──────────────────────────────────────────────────────────┘
                          ↓ 调用
┌──────────────────────────────────────────────────────────┐
│                    Data Layer                             │
│  AppStorage       - 全局状态共享                           │
│  Flask Backend    - 后端 API（HTTP 5001）                  │
│  GPS Module       - 车辆定位数据                           │
│  SpeechKit        - 原生语音识别 + 语音合成                 │
└──────────────────────────────────────────────────────────┘
```

### 设计特点

1. **场景驱动交互**：车载场景下"我快到家了"一句话触发全屋联动，无需逐个操作
2. **习惯智能**：回家模式自动恢复空调上次设置，离线也能用
3. **横屏三栏布局**：灯/空调/门同屏展示，适配车载横屏
4. **悬浮语音助手**：可拖拽的悬浮组件，不遮挡主交互区域
5. **GPS 位置感知**：车辆位置注入聊天上下文，为场景联动提供位置基础
6. **HTTPS + CA 证书**：车载端额外支持 CA 证书验证，传输更安全
7. **防重放安全传输**：所有请求携带加密安全头，后端验证

---

## 技术栈

| 技术 | 用途 | 说明 |
|------|------|------|
| **ArkTS** | 开发语言 | TypeScript 扩展，HarmonyOS 官方语言 |
| **ArkUI** | UI 框架 | 声明式开发范式，横屏适配 |
| **@ohos.net.http** | 网络请求 | HTTP 客户端 + CA 证书验证 |
| **@kit.CryptoArchitectureKit** | 加密 | 随机数生成（安全头 Nonce） |
| **@kit.SpeechKit** | 语音能力 | speechRecognizer 识别 + textToSpeech 合成 |
| **@ohos.file.fs** | 文件操作 | CA 证书复制 |
| **@ohos.geoLocationManager** | 定位 | GPS 定位 + 逆地理编码 |
| **@ohos.data.preferences** | 本地存储 | 键值对持久化 |

### 权限配置

```json
{
  "requestPermissions": [
    { "name": "ohos.permission.INTERNET", "reason": "网络访问控制智能设备" },
    { "name": "ohos.permission.MICROPHONE", "reason": "语音识别和语音控制" },
    { "name": "ohos.permission.APPROXIMATELY_LOCATION", "reason": "粗略定位获取车辆位置" },
    { "name": "ohos.permission.LOCATION", "reason": "精确定位获取车辆位置" },
    { "name": "ohos.permission.DISTRIBUTED_DATASYNC", "reason": "分布式数据同步" }
  ]
}
```

---

## API 接口文档

### 基础信息

**后端 API**：`http://192.168.43.237:5001/api`  
**认证方式**：Bearer Token（JWT）  
**安全头**：所有请求自动携带防重放安全头  
**CA 证书**：`rawfile/rootCA.crt`（HTTPS 请求验证服务器证书）

### 公共请求头

```text
Content-Type: application/json
Authorization: Bearer <token>
X-Request-ID: <timestamp>-<randomHex>
X-Timestamp: <毫秒时间戳>
X-Nonce: <16字节随机hex>
X-Security-Version: 1
X-Key-ID: app-session-v1
Cache-Control: no-store
Pragma: no-cache
```

### 语音能力（原生 SpeechKit）

车载端使用鸿蒙原生 `@kit.SpeechKit` 实现语音交互，不再依赖后端中转：

```text
ASR 语音识别：speechRecognizer.createEngine() + startListening()
  → 回调拿到识别文本 → 检测"小华"唤醒词 → 提取指令 → IntentService 处理

TTS 语音合成：textToSpeech.createEngine() + speak(text)
  → 原生直接合成并播放，无需下载音频文件
```

> 后端 Flask 的 `/voice-recognition/*`、`/speech/tts` 等语音中转接口已不再被车载端调用。

### 设备控制接口

#### 控制设备
```text
POST /api/device/control
请求体：{ deviceId: number, action: 'on' | 'off', params?: object }
响应体：{ code: 200, message: "ok" }
```

#### 获取设备列表
```text
GET /api/device/list
响应体：{ code: 200, data: [{ deviceId, name, deviceType, room, status, homeId }] }
```

#### 获取空调状态（习惯数据来源）
```text
GET /api/device/ac/{deviceId}
响应体：{ code: 200, data: { deviceId, name, room, online, settings: { power, temp, mode, fanSpeed, windDirection, swing, sleepMode, ecoMode, ... } } }
```

#### 获取灯光列表
```text
GET /api/device/lights?homeId={homeId}
响应体：{ code: 200, data: [{ deviceId, name, room, status }] }
```

#### 获取消息列表
```text
GET /api/device/messages
响应体：{ messages: [{ id, type, title, content, createdAt }] }
```

---

## 原生语音能力说明

本项目使用鸿蒙原生 `@kit.SpeechKit` 实现语音交互，无需电脑中转：

| 能力 | API | 说明 |
|------|-----|------|
| 语音识别（ASR） | `speechRecognizer` | `createEngine` + `startListening`，回调拿识别文本 |
| 语音合成（TTS） | `textToSpeech` | `createEngine` + `speak`，原生直接合成播放 |
| 唤醒词检测 | 识别结果匹配 | 在 ASR 回调里检测"小华"，提取后续指令 |

> **注意**：原生 SpeechKit 需要设备系统支持，车载端模拟器可能无语音能力，真机可正常使用。

---

## 与手表端的差异对比

| 特性 | 手表端 | 车载端 |
|------|--------|--------|
| **场景联动** | ❌ 不支持 | ✅ 回家/离家模式 |
| **健康关怀** | ✅ 运动/睡眠/压力关怀 | ❌ 不支持 |
| **陌生人告警** | ✅ 实时告警弹窗 | ❌ 不支持 |
| **GPS 定位** | ❌ 不支持 | ✅ 定位 + 逆地理编码 |
| **CA 证书** | ❌ HTTP 明文 | ✅ HTTPS + CA 证书验证 |
| **设备页布局** | 独立页面（AcPage/LightPage/DoorPage） | 三栏同屏（DevicePage） |
| **语音助手** | 嵌入式（右下角固定） | 悬浮式（可拖拽） |
| **习惯智能** | 开空调时加载习惯 | 回家模式自动恢复习惯 |
| **安全头** | ✅ RequestSecurityUtil | ✅ RequestSecurityUtil |

---

## 项目亮点

1. **场景联动一句话回家**："我快到家了"→ 自动开灯+开空调+恢复习惯设置，真正的"一句话控制全屋"
2. **习惯智能无感恢复**：回家模式自动读取空调上次设置，无需重复设定温度/模式/风速
3. **横屏三栏设备控制**：灯/空调/门同屏展示，适配车载横屏场景
4. **GPS 位置感知**：车辆位置注入聊天上下文，为场景联动提供位置基础
5. **HTTPS + CA 证书**：车载端额外支持 CA 证书验证，传输安全性更高
6. **防重放安全传输**：所有请求携带加密安全头，后端验证时间窗口 + Nonce 唯一性
7. **双引擎意图识别**：LLM 保证准确率 + 关键词保证可用性，离线也能用

---

**最后更新时间：2026年7月8日**