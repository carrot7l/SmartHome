import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { ApiClient } from './ApiClient';
import { StorageUtil } from './StorageUtil';
import { IntentService, IntentResult } from './IntentService';
import { speechRecognizer } from '@kit.SpeechKit';
import { textToSpeech } from '@kit.SpeechKit';

@Component
export struct CarVoiceAssistant {
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State isActive: boolean = false;

  @State statusText: string = '';
  @State inputText: string = '';
  @State isRecording: boolean = false;
  @State showChatDialog: boolean = false;
  @State chatReplyText: string = '';
  @State aiExpression: string = 'normal';
  private chatTimer: number = -1;
  private sleepTimer: number = -1;
  private idleTimer: number = -1;
  private standbyPolling: boolean = false;

  private startX: number = 0;
  private startY: number = 0;
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.All });

  private lastProcessedText: string = '';

  private lastProcessedMessageId: string = '';

  onControlDevice?: (intent: IntentResult) => void;

  private isSpeaking: boolean = false;

  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private ttsEngine: textToSpeech.TextToSpeechEngine | null = null;
  private isListening: boolean = false;
  private messageCheckTimer: number = -1;

  aboutToAppear() {
    this.loadOffset();
    this.enterStandby();
  }

  aboutToDisappear() {
    this.standbyPolling = false;
    if (this.sleepTimer !== -1) clearTimeout(this.sleepTimer);
    if (this.chatTimer !== -1) clearTimeout(this.chatTimer);
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    if (this.messageCheckTimer !== -1) {
      clearInterval(this.messageCheckTimer);
      this.messageCheckTimer = -1;
    }
    this.releaseAsrEngine();
    this.releaseTtsEngine();
  }

  enterStandby() {
    this.standbyPolling = false;
    this.isActive = false;
    this.isRecording = false;
    this.aiExpression = 'sleep';
    this.statusText = '';
    this.clearRecognitionResult();
    this.startStandbyPolling();
  }

  async clearRecognitionResult() {
    // 原生 SpeechKit 不需要清空中转站识别结果，保留方法名避免调用点报错
  }

  async startStandbyPolling() {
    if (this.standbyPolling) return;
    this.standbyPolling = true;
    console.info('[VA] 进入待机监听模式（原生 SpeechKit）');

    // 启动消息轮询定时器（每 4 秒检查一次新消息）
    if (this.messageCheckTimer !== -1) {
      clearInterval(this.messageCheckTimer);
    }
    this.messageCheckTimer = setInterval(() => {
      this.checkNewMessages();
    }, 4000);

    // 创建 ASR 引擎并开始监听唤醒词
    try {
      if (this.asrEngine === null) {
        const asrConfig: speechRecognizer.SpeechRecognitionEngineConfig = {
          language: 'zh-CN',
          extra: {}
        };
        this.asrEngine = await speechRecognizer.createEngine(asrConfig);
        console.info('[VA] ASR 引擎创建成功');

        // 设置识别回调
        const listener: speechRecognizer.SpeechRecognitionListener = {
          onStart: () => {
            console.info('[VA] ASR 开始监听');
            this.isListening = true;
          },
          onRecognitionResultChange: (text: string, isFinal: boolean) => {
            console.info('[VA] ASR 中间结果: ' + text + ', isFinal=' + isFinal);
          },
          onComplete: (result: speechRecognizer.SpeechRecognitionResult) => {
            const text: string = result ? (result.result || '') : '';
            console.info('[VA] ASR 识别完成: ' + text);
            this.isListening = false;
            if (!text || !this.standbyPolling) return;
            if (text === this.lastProcessedText) return;
            if (text.includes('小华')) {
              console.info('[VA] 检测到唤醒词: ' + text);
              this.lastProcessedText = text;
              const afterWake: string = text.replace(/小华/g, '').replace(/[，,、\s]/g, '').trim();
              if (afterWake) {
                this.wakeUpAndExecute(afterWake);
              } else {
                this.wakeUp();
              }
            } else {
              console.info('[VA] 待机中收到非唤醒词: ' + text);
            }
          },
          onError: (error: speechRecognizer.SpeechRecognitionError) => {
            console.error('[VA] ASR 识别错误: ' + JSON.stringify(error));
            this.isListening = false;
            // 出错后尝试重启监听
            if (this.standbyPolling) {
              setTimeout(() => {
                if (this.standbyPolling) {
                  this.restartAsrListening();
                }
              }, 2000);
            }
          },
          onStop: () => {
            console.info('[VA] ASR 停止监听');
            this.isListening = false;
            // 待机态下停止后自动重启监听
            if (this.standbyPolling && !this.isActive) {
              setTimeout(() => {
                if (this.standbyPolling && !this.isActive) {
                  this.restartAsrListening();
                }
              }, 500);
            }
          }
        };
        this.asrEngine.setListener(listener);
      }

      // 开始监听
      const startParams: speechRecognizer.SpeechRecognitionStartParams = {
        sessionId: 'standby_' + Date.now(),
        audioInfo: {
          audioPath: '',
          audioType: 'pcm'
        },
        extra: {}
      };
      await this.asrEngine.startListening(startParams);
      console.info('[VA] 待机监听已启动');
    } catch (err) {
      console.error('[VA] ASR 引擎创建/启动失败: ' + JSON.stringify(err));
    }
  }

  async restartAsrListening() {
    try {
      if (this.asrEngine === null) {
        const asrConfig: speechRecognizer.SpeechRecognitionEngineConfig = {
          language: 'zh-CN',
          extra: {}
        };
        this.asrEngine = await speechRecognizer.createEngine(asrConfig);
        const listener: speechRecognizer.SpeechRecognitionListener = {
          onStart: () => {
            console.info('[VA] ASR 重新开始监听');
            this.isListening = true;
          },
          onRecognitionResultChange: (text: string, isFinal: boolean) => {
            console.info('[VA] ASR 中间结果: ' + text + ', isFinal=' + isFinal);
          },
          onComplete: (result: speechRecognizer.SpeechRecognitionResult) => {
            const text: string = result ? (result.result || '') : '';
            console.info('[VA] ASR 识别完成: ' + text);
            this.isListening = false;
            if (!text || !this.standbyPolling) return;
            if (text === this.lastProcessedText) return;
            if (this.isActive) {
              // 激活态：直接处理指令
              this.lastProcessedText = text;
              this.isRecording = false;
              this.inputText = text;
              this.statusText = '识别完成，处理中...';
              this.processVoiceText(text);
            } else if (text.includes('小华')) {
              console.info('[VA] 检测到唤醒词: ' + text);
              this.lastProcessedText = text;
              const afterWake: string = text.replace(/小华/g, '').replace(/[，,、\s]/g, '').trim();
              if (afterWake) {
                this.wakeUpAndExecute(afterWake);
              } else {
                this.wakeUp();
              }
            } else {
              console.info('[VA] 待机中收到非唤醒词: ' + text);
            }
          },
          onError: (error: speechRecognizer.SpeechRecognitionError) => {
            console.error('[VA] ASR 识别错误: ' + JSON.stringify(error));
            this.isListening = false;
            if (this.standbyPolling) {
              setTimeout(() => {
                if (this.standbyPolling) {
                  this.restartAsrListening();
                }
              }, 2000);
            }
          },
          onStop: () => {
            console.info('[VA] ASR 停止监听');
            this.isListening = false;
            if (this.standbyPolling && !this.isActive) {
              setTimeout(() => {
                if (this.standbyPolling && !this.isActive) {
                  this.restartAsrListening();
                }
              }, 500);
            }
          }
        };
        this.asrEngine.setListener(listener);
      }
      const startParams: speechRecognizer.SpeechRecognitionStartParams = {
        sessionId: 'session_' + Date.now(),
        audioInfo: {
          audioPath: '',
          audioType: 'pcm'
        },
        extra: {}
      };
      await this.asrEngine.startListening(startParams);
      console.info('[VA] ASR 监听已重启');
    } catch (err) {
      console.error('[VA] ASR 重启监听失败: ' + JSON.stringify(err));
    }
  }

  async wakeUp() {

    this.standbyPolling = false;
    this.isActive = true;
    this.isRecording = false;
    this.aiExpression = 'smile';
    this.statusText = '请说指令...';
    await this.clearRecognitionResult();
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => {
      console.info('[VA] 唤醒后5秒无输入，回到待机');
      this.idleTimer = -1;
      this.isActive = false;
      this.showChatDialog = false;
      this.chatReplyText = '';
      this.enterStandby();
    }, 5000);
    this.startActivePolling();
  }

  async wakeUpAndExecute(command: string) {

    this.standbyPolling = false;
    this.isActive = true;
    this.isRecording = false;
    this.aiExpression = 'smile';
    this.statusText = '处理中...';
    await this.clearRecognitionResult();
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.processVoiceText(command);
  }

  async startActivePolling() {
    this.isRecording = true;
    this.statusText = '请说指令...';
    console.info('[VA] 进入激活监听模式（原生 ASR 回调处理指令）');

    // 唤醒后重启 ASR 监听以接收指令
    // onComplete 回调里会根据 isActive 状态走 processVoiceText 分支
    try {
      if (this.asrEngine !== null && this.isListening) {
        // 已在监听，无需重启
        return;
      }
      await this.restartAsrListening();
    } catch (err) {
      console.error('[VA] 激活态重启 ASR 失败: ' + JSON.stringify(err));
    }
  }

  resetIdleTimer() {
    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => {
      console.info('[VA] 15秒无输入，回到待机');
      this.idleTimer = -1;
      this.isActive = false;
      this.showChatDialog = false;
      this.chatReplyText = '';
      this.enterStandby();
    }, 15000);
  }

  async processVoiceText(text: string) {
    this.statusText = '思考中...';
    this.resetIdleTimer();
    try {
      const intent: IntentResult = await IntentService.processText(text);
      await this.handleIntentResult(intent);
    } catch (err) {
      promptAction.showToast({ message: '意图识别失败' });
      this.resetIdleTimer();
    }
  }

  async handleIntentResult(intent: IntentResult) {
    const replyText: string = intent.chatReply || intent.reply || '';

    if (intent.action === 'chat') {
      this.showChatReply(intent.chatReply || intent.reply);
      if (replyText) this.speak(replyText);
      return;
    }

    const selfSpeakActions: string[] = ['read_message', 'read_message_detail', 'query', 'query_current_family', 'query_device_status'];
    let isSelfSpeak: boolean = false;
    for (let i = 0; i < selfSpeakActions.length; i++) {
      if (intent.action === selfSpeakActions[i]) { isSelfSpeak = true; break; }
    }

    if (!isSelfSpeak) {
      if (replyText) this.showChatReply(replyText);
      if (replyText) this.speak(replyText);
    }

    if (intent.action === 'navigate') {
      if (intent.page === 'back') {
        router.back();
      } else if (intent.page) {
        if (intent.editField) AppStorage.setOrCreate('pendingEditField', intent.editField);
        if (intent.editValue) AppStorage.setOrCreate('pendingEditValue', intent.editValue);
        router.pushUrl({ url: `pages/${intent.page}` });
      }
    } else if (intent.action === 'control_device') {
      if (this.onControlDevice) {
        this.onControlDevice(intent);
      } else {
        this.executeDeviceControl(intent);
      }
    } else if (intent.action === 'switch_family') {
      promptAction.showToast({ message: intent.reply });
      if (intent.page) {
        router.pushUrl({ url: `pages/${intent.page}` });
      } else {
        router.pushUrl({ url: 'pages/FamilyPage' });
      }
    } else if (intent.action === 'query') {
      this.executeQuery(intent);
    } else if (intent.action === 'query_device_status') {
      this.showChatReply(intent.reply);
      this.speak(intent.reply);
    } else if (intent.action === 'query_time') {
      promptAction.showToast({ message: intent.reply });
    } else if (intent.action === 'query_current_family') {
      this.queryCurrentFamily();
    } else if (intent.action === 'read_message') {
      this.readMessage(intent.messageSender || '');
    } else if (intent.action === 'read_message_detail') {
      this.readMessageDetail(intent.messageSender || '');
    } else if (intent.action === 'multi_command') {
      this.executeMultiCommands(intent);
    } else if (intent.action === 'unknown') {
      promptAction.showToast({ message: intent.reply });
    }

    if (this.idleTimer !== -1) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => {
      this.idleTimer = -1;
      this.isActive = false;
      this.showChatDialog = false;
      this.chatReplyText = '';
      this.enterStandby();
    }, 5000);
  }

  async executeMultiCommands(intent: IntentResult) {
    const commands: IntentResult[] = intent.multiCommands || [];
    if (commands.length === 0) {
      promptAction.showToast({ message: intent.reply });
      return;
    }

    const controlCmds: IntentResult[] = [];
    const otherCmds: IntentResult[] = [];
    for (let i = 0; i < commands.length; i++) {
      if (commands[i].action === 'control_device') {
        controlCmds.push(commands[i]);
      } else {
        otherCmds.push(commands[i]);
      }
    }

    for (let i = 0; i < otherCmds.length; i++) {
      const cmd: IntentResult = otherCmds[i];
      if (cmd.action === 'navigate') {
        if (cmd.page === 'back') {
          router.back();
        } else if (cmd.page) {
          if (cmd.editField) AppStorage.setOrCreate('pendingEditField', cmd.editField);
          if (cmd.editValue) AppStorage.setOrCreate('pendingEditValue', cmd.editValue);
          router.pushUrl({ url: `pages/${cmd.page}` });
        }
      } else if (cmd.action === 'switch_family') {
        if (cmd.page) {
          router.pushUrl({ url: `pages/${cmd.page}` });
        } else {
          router.pushUrl({ url: 'pages/FamilyPage' });
        }
      } else if (cmd.action === 'query') {
        this.executeQuery(cmd);
      } else if (cmd.action === 'query_device_status') {
        this.showChatReply(cmd.reply);
        this.speak(cmd.reply);
      } else if (cmd.action === 'query_time') {
        promptAction.showToast({ message: cmd.reply });
      } else if (cmd.action === 'query_current_family') {
        this.queryCurrentFamily();
      } else if (cmd.action === 'read_message') {
        this.readMessage(cmd.messageSender || '');
      } else if (cmd.action === 'read_message_detail') {
        this.readMessageDetail(cmd.messageSender || '');
      }
    }

    if (controlCmds.length > 0) {
      const multiData: string[] = controlCmds.map((cmd: IntentResult) => {
        const obj: Record<string, string> = {};
        obj['deviceType'] = cmd.deviceType || '';
        obj['room'] = cmd.room || '';
        obj['operation'] = cmd.operation || '';
        if (cmd.deviceName) obj['deviceName'] = cmd.deviceName;
        if (cmd.acParams) obj['acParams'] = JSON.stringify(cmd.acParams);
        return JSON.stringify(obj);
      });
      AppStorage.setOrCreate('pendingMultiControl', JSON.stringify(multiData));

      if (this.onControlDevice) {
        this.onControlDevice(controlCmds[0]);
      } else {
        router.pushUrl({ url: 'pages/DevicePage' });
      }
    }
  }

  async executeDeviceControl(intent: IntentResult) {
    const pageMap: Record<string, string> = {
      'light': 'DevicePage',
      'ac': 'DevicePage',
      'door': 'DevicePage'
    };
    const page: string = pageMap[intent.deviceType || ''];
    if (page) {
      const pendingObj: Record<string, string> = {};
      pendingObj['deviceType'] = intent.deviceType || '';
      pendingObj['room'] = intent.room || '';
      pendingObj['operation'] = intent.operation || '';
      if (intent.deviceName) pendingObj['deviceName'] = intent.deviceName;
      if (intent.acParams) pendingObj['acParams'] = JSON.stringify(intent.acParams);
      AppStorage.setOrCreate('pendingControl', JSON.stringify(pendingObj));
      router.pushUrl({ url: `pages/${page}` });
    }
  }

  @State lastMessageContent: string = '';
  @State lastMessageSender: string = '';

  async readMessage(sender: string) {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) { promptAction.showToast({ message: '未登录' }); return; }
    const homeId: number = StorageUtil.getHomeId();
    if (!homeId) { promptAction.showToast({ message: '未获取到家庭信息' }); return; }
    try {
      const resp = await ApiClient.get(`/home/${homeId}/messages?page=1&page_size=50`, token);
      if ((resp.code !== 200 && resp.code !== 0) || !resp.data) {
        this.showChatReply('获取消息失败');
        this.speak('获取消息失败');
        return;
      }
      const data: Record<string, Object> = resp.data as Record<string, Object>;
      const messages: Array<Record<string, Object>> = data['messages'] as Array<Record<string, Object>>;
      if (!messages || messages.length === 0) {
        this.showChatReply('暂无消息');
        this.speak('暂无消息');
        return;
      }

      let target: Record<string, Object> | null = null;
      if (sender) {
        for (let i = 0; i < messages.length; i++) {
          const senderName: string = (messages[i]['senderName'] as string) || '';
          if (senderName.includes(sender) || sender.includes(senderName)) { target = messages[i]; break; }
        }
        if (!target) {
          const replyText: string = `未找到${sender}发来的消息`;
          this.showChatReply(replyText);
          this.speak(replyText);
          return;
        }
      } else {
        target = messages[0];
      }

      const senderName: string = (target['senderName'] as string) || '系统';
      const title: string = (target['title'] as string) || '';
      const content: string = (target['content'] as string) || '';
      const createdAt: string = (target['createdAt'] as string) || '';

      this.lastMessageContent = content;
      this.lastMessageSender = senderName;

      let timeDesc: string = '';
      if (createdAt) {
        const datePart: string = createdAt.substring(0, 10);
        const parts: string[] = datePart.split('-');
        if (parts.length === 3) {
          timeDesc = `${parseInt(parts[1])}月${parseInt(parts[2])}号`;
        }
      }

      let summary: string = '';
      if (sender) {
        summary = title ? `${senderName}发来的最新消息是${title}，发送时间是${timeDesc}` : `${senderName}发来的最新消息，发送时间是${timeDesc}`;
      } else {
        summary = title ? `最新一条消息是${senderName}发来的，${title}，发送时间是${timeDesc}` : `最新一条消息是${senderName}发来的，发送时间是${timeDesc}`;
      }
      summary += '，需要为您读取完整内容吗？';

      this.showChatReply(summary);
      this.speak(summary);
      if (sender) AppStorage.setOrCreate('pendingMessageSender', sender);
      router.pushUrl({ url: 'pages/MessagePage' });
    } catch (err) {
      this.showChatReply('读取消息失败');
      this.speak('读取消息失败');
    }
  }

  async readMessageDetail(sender: string) {
    if (this.lastMessageContent && (!sender || !this.lastMessageSender || this.lastMessageSender.includes(sender) || sender.includes(this.lastMessageSender))) {
      this.showChatReply(this.lastMessageContent);
      this.speak(this.lastMessageContent);
      return;
    }
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) { this.showChatReply('未登录'); this.speak('未登录'); return; }
    const homeId: number = StorageUtil.getHomeId();
    if (!homeId) { this.showChatReply('未获取到家庭信息'); this.speak('未获取到家庭信息'); return; }
    try {
      const resp = await ApiClient.get(`/home/${homeId}/messages?page=1&page_size=50`, token);
      if ((resp.code !== 200 && resp.code !== 0) || !resp.data) {
        this.showChatReply('获取消息失败');
        this.speak('获取消息失败');
        return;
      }
      const data: Record<string, Object> = resp.data as Record<string, Object>;
      const messages: Array<Record<string, Object>> = data['messages'] as Array<Record<string, Object>>;
      if (!messages || messages.length === 0) {
        this.showChatReply('暂无消息');
        this.speak('暂无消息');
        return;
      }

      let target: Record<string, Object> | null = null;
      if (sender) {
        for (let i = 0; i < messages.length; i++) {
          const senderName: string = (messages[i]['senderName'] as string) || '';
          if (senderName.includes(sender) || sender.includes(senderName)) { target = messages[i]; break; }
        }
        if (!target) {
          const replyText: string = `未找到${sender}发来的消息`;
          this.showChatReply(replyText);
          this.speak(replyText);
          return;
        }
      } else {
        target = messages[0];
      }

      const content: string = (target['content'] as string) || '暂无内容';
      this.lastMessageContent = content;
      this.lastMessageSender = (target['senderName'] as string) || '系统';
      this.showChatReply(content);
      this.speak(content);
    } catch (err) {
      this.showChatReply('读取消息失败');
      this.speak('读取消息失败');
    }
  }

  async queryCurrentFamily() {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) { this.showChatReply('未登录'); this.speak('未登录'); return; }
    try {
      const resp = await ApiClient.get('/user/current-home', token);
      if (resp.code === 200 && resp.data) {
        const data: Record<string, Object> = resp.data as Record<string, Object>;
        const replyText: string = `当前家庭是${data['homeName'] || data['homeId']}`;
        this.showChatReply(replyText);
        this.speak(replyText);
      } else {
        this.showChatReply('获取当前家庭失败');
        this.speak('获取当前家庭失败');
      }
    } catch (err) {
      this.showChatReply('查询当前家庭失败');
      this.speak('查询当前家庭失败');
    }
  }

  async executeQuery(intent: IntentResult) {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) { this.showChatReply('未登录'); this.speak('未登录'); return; }
    try {
      const deviceResp = await ApiClient.get('/device/list', token);
      if ((deviceResp.code !== 200 && deviceResp.code !== 0) || !deviceResp.data) {
        this.showChatReply('查询设备列表失败'); this.speak('查询设备列表失败');
        return;
      }
      const devices: Array<Record<string, Object>> = deviceResp.data as Array<Record<string, Object>>;
      const sensor: Record<string, Object> | undefined = devices.find((d: Record<string, Object>) => d['deviceType'] === 'temp_humi_sensor');
      if (!sensor) { this.showChatReply('未找到温湿度传感器'); this.speak('未找到温湿度传感器'); return; }
      const sensorId: Object = sensor['deviceId'];
      const latestResp = await ApiClient.get(`/device/latest/${sensorId}`, token);
      if ((latestResp.code !== 200 && latestResp.code !== 0) || !latestResp.data) {
        this.showChatReply('查询传感器数据失败'); this.speak('查询传感器数据失败');
        return;
      }
      const data: Record<string, number> = latestResp.data as Record<string, number>;
      const queryType: string = intent.queryType || 'temperature';
      const parts: string[] = [];
      if ((queryType === 'temperature' || queryType === 'both') && data['temperature'] !== undefined) {
        parts.push(`温度: ${data['temperature']}°C`);
      }
      if ((queryType === 'humidity' || queryType === 'both') && data['humidity'] !== undefined) {
        parts.push(`湿度: ${data['humidity']}%`);
      }
      const replyText: string = parts.length > 0 ? parts.join('，') : '暂无数据';
      this.showChatReply(replyText);
      this.speak(replyText);
    } catch (err) {
      this.showChatReply('查询失败'); this.speak('查询失败');
    }
  }

  async checkNewMessages() {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) return;
    try {
      const resp = await ApiClient.get('/device/messages', token);
      if (resp.code === 200 && resp.data) {
        const messages: Array<Record<string, Object>> = resp.data as Array<Record<string, Object>>;
        if (messages.length > 0) {
          const latest: Record<string, Object> = messages[0];
          const msgId: string = String(latest['message_id'] || '');
          if (msgId && msgId !== this.lastProcessedMessageId) {
            this.lastProcessedMessageId = msgId;
            const msgType: string = String(latest['message_type'] || '');
            // if (msgType === 'auto_close') {
            //   const msgData: Record<string, string> = latest['data'] as Record<string, string>;
            //   const msgText: string = msgData ? (msgData['message'] || '门已自动关闭') : '门已自动关闭';
            //   this.announceMessage(msgText);
            // } else
            if (msgType === 'stranger_alert') {
              const msgData: Record<string, string> = latest['data'] as Record<string, string>;
              const msgText: string = msgData ? (msgData['message'] || '检测到陌生人在门口逗留') : '检测到陌生人在门口逗留';
              this.announceMessage(msgText);
            }
          }
        }
      }
    } catch (err) {
      console.error('[VA] 消息轮询失败: ' + JSON.stringify(err));
    }
  }

  announceMessage(text: string) {
    this.aiExpression = 'surprise';
    this.showChatReply(text);
    this.speak(text);
  }

  async speak(text: string) {
    if (!text) return;
    if (this.isSpeaking) {
      console.info('[TTS] speak skipped, isSpeaking=true');
      return;
    }
    this.showChatReply(text);
    try {
      // 创建 TTS 引擎（懒加载）
      if (this.ttsEngine === null) {
        const ttsConfig: textToSpeech.TextToSpeechEngineConfig = {
          language: 'zh-CN',
          person: 0,
          extra: {}
        };
        this.ttsEngine = await textToSpeech.createEngine(ttsConfig);
        console.info('[TTS] 引擎创建成功');

        // 设置 TTS 回调
        const ttsListener: textToSpeech.TextToSpeechListener = {
          onStart: (requestId: string) => {
            console.info('[TTS] 开始播放, requestId=' + requestId);
            this.isSpeaking = true;
          },
          onComplete: (requestId: string) => {
            console.info('[TTS] 播放完成, requestId=' + requestId);
            this.isSpeaking = false;
          },
          onStop: (requestId: string) => {
            console.info('[TTS] 停止播放, requestId=' + requestId);
            this.isSpeaking = false;
          },
          onError: (requestId: string, error: textToSpeech.TtsError) => {
            console.error('[TTS] 播放错误, requestId=' + requestId + ', err=' + JSON.stringify(error));
            this.isSpeaking = false;
          }
        };
        this.ttsEngine.setListener(ttsListener);
      }

      // 调用原生 TTS 合成并播放
      this.isSpeaking = true;
      const requestId: string = 'tts_' + Date.now();
      const speakParams: textToSpeech.SpeakParams = {
        text: text,
        extra: {}
      };
      this.ttsEngine.speak(requestId, speakParams);
      console.info('[TTS] speak 已调用, requestId=' + requestId);
    } catch (err) {
      console.error('[TTS] speak 失败: ' + JSON.stringify(err));
      this.isSpeaking = false;
    }
  }

  async releaseAsrEngine() {
    if (this.asrEngine) {
      try {
        this.asrEngine.shutdown();
      } catch (e) {
        console.error('[VA] ASR shutdown 失败: ' + JSON.stringify(e));
      }
      this.asrEngine = null;
    }
    this.isListening = false;
  }

  async releaseTtsEngine() {
    if (this.ttsEngine) {
      try {
        this.ttsEngine.shutdown();
      } catch (e) {
        console.error('[TTS] TTS shutdown 失败: ' + JSON.stringify(e));
      }
      this.ttsEngine = null;
    }
    this.isSpeaking = false;
  }

  showChatReply(reply: string) {
    this.chatReplyText = reply;
    this.showChatDialog = true;
    if (this.chatTimer !== -1) clearTimeout(this.chatTimer);
    this.chatTimer = setTimeout(() => {
      this.showChatDialog = false;
      this.chatReplyText = '';
      this.chatTimer = -1;
    }, 15000);
  }

  resetSleepTimer() {
    if (this.sleepTimer !== -1) clearTimeout(this.sleepTimer);
    if (this.aiExpression === 'sleep') this.aiExpression = 'normal';
    this.sleepTimer = setTimeout(() => {
      this.aiExpression = 'sleep';
      this.sleepTimer = -1;
    }, 300000);
  }

  onAiDragStart() {
    const expressions: string[] = ['smile', 'surprise', 'wink', 'embarrassed'];
    const idx: number = Math.floor(Math.random() * expressions.length);
    this.aiExpression = expressions[idx];
  }

  onAiDragEnd() {
    this.aiExpression = 'normal';
  }

  getAiImageResource(): Resource {
    if (this.aiExpression === 'sleep') return $r('app.media.ai_image_sleep');
    if (this.aiExpression === 'smile') return $r('app.media.ai_image_smile');
    if (this.aiExpression === 'surprise') return $r('app.media.ai_image_surprise');
    if (this.aiExpression === 'wink') return $r('app.media.ai_image_wink');
    if (this.aiExpression === 'embarrassed') return $r('app.media.ai_image_embarrassed');
    return $r('app.media.ai_image_normal');
  }

  loadOffset() {
    this.offsetX = AppStorage.get<number>('car_va_offsetX') || 0;
    this.offsetY = AppStorage.get<number>('car_va_offsetY') || 0;
  }

  saveOffset() {
    AppStorage.setOrCreate('car_va_offsetX', this.offsetX);
    AppStorage.setOrCreate('car_va_offsetY', this.offsetY);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isActive) {
        Column() {
          Image(this.getAiImageResource())
            .width(100)
            .height(100)
          Text(this.statusText)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .margin({ top: 4 })
        }
        .width(220)
        .padding(12)
        .backgroundColor('#8CA79C')
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .shadow({ radius: 10, color: '#00000040' })
        .offset({ x: this.offsetX, y: this.offsetY })
        .gesture(
          PanGesture(this.panOption)
            .onActionStart((event: GestureEvent) => {
              this.startX = event.offsetX;
              this.startY = event.offsetY;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.offsetX = this.offsetX + (event.offsetX - this.startX);
              this.offsetY = this.offsetY + (event.offsetY - this.startY);
              this.startX = event.offsetX;
              this.startY = event.offsetY;
            })
            .onActionEnd(() => {
              this.saveOffset();
            })
        )
      }

      if (this.showChatDialog) {
        Column() {
          Scroll() {
            Text(this.chatReplyText)
              .fontSize(14)
              .fontColor('#333333')
              .lineHeight(22)
          }
          .constraintSize({ maxHeight: 160 })
          .width('100%')
          Button('关闭')
            .width(80)
            .height(32)
            .fontSize(14)
            .margin({ top: 8 })
            .backgroundColor('#999999')
            .fontColor('#FFFFFF')
            .borderRadius(16)
            .onClick(() => {
              this.showChatDialog = false;
              this.chatReplyText = '';
              if (this.chatTimer !== -1) {
                clearTimeout(this.chatTimer);
                this.chatTimer = -1;
              }
            })
        }
        .width(220)
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .alignItems(HorizontalAlign.Center)
        .shadow({ radius: 12, color: '#00000050' })
        .zIndex(999)
      }
    }
  }
}
