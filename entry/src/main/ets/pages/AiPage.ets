import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { common } from '@kit.AbilityKit';
import { ApiClient } from '../common/ApiClient';
import { StorageUtil } from '../common/StorageUtil';
import { IntentService, IntentResult } from '../common/IntentService';
import { speechRecognizer } from '@kit.SpeechKit';
import { textToSpeech } from '@kit.SpeechKit';

interface ChatMessage {
  role: string;
  text: string;
  time: string;
}

@Entry
@Component
struct AiPage {
  @State inputText: string = '';
  @State isRecording: boolean = false;
  @State statusText: string = '小华在线';
  @State aiExpression: string = 'normal';
  @State chatHistory: ChatMessage[] = [];
  @State chatStarted: boolean = false;

  private sleepTimer: number = -1;
  private isSpeaking: boolean = false;

  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private ttsEngine: textToSpeech.TextToSpeechEngine | null = null;
  private isListening: boolean = false;

  aboutToAppear() {
    this.resetSleepTimer();
  }

  aboutToDisappear() {
    if (this.sleepTimer !== -1) clearTimeout(this.sleepTimer);
    this.releaseAsrEngine();
    this.releaseTtsEngine();
  }

  addChatMessage(role: string, text: string) {
    const now = new Date();
    const time = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
    const msg: ChatMessage = { role: role, text: text, time: time };
    this.chatHistory = [...this.chatHistory, msg];
    this.statusText = '小华在线';
  }

  async processVoiceText(text: string) {
    this.statusText = '思考中...';
    try {
      const intent: IntentResult = await IntentService.processText(text);
      this.handleIntentResult(intent);
    } catch (err) {
      this.addChatMessage('ai', '意图识别失败');
      this.statusText = '小华在线';
    }
  }

  handleIntentResult(intent: IntentResult) {
    const replyText: string = intent.chatReply || intent.reply || '';

    if (intent.action === 'chat') {
      this.addChatMessage('ai', intent.chatReply || intent.reply);
      this.aiExpression = 'smile';
      this.resetSleepTimer();
      if (replyText) this.speak(replyText);
      return;
    }

    this.addChatMessage('ai', intent.reply);
    this.aiExpression = 'smile';
    this.resetSleepTimer();

    if (intent.action === 'navigate') {
      if (intent.page === 'back') {
        router.back();
      } else if (intent.page) {
        if (intent.editField) AppStorage.setOrCreate('pendingEditField', intent.editField);
        if (intent.editValue) AppStorage.setOrCreate('pendingEditValue', intent.editValue);
        router.pushUrl({ url: `pages/${intent.page}` });
      }
    } else if (intent.action === 'control_device') {
      this.executeDeviceControl(intent);
    } else if (intent.action === 'switch_family') {
      if (intent.page) {
        router.pushUrl({ url: `pages/${intent.page}` });
      } else {
        router.pushUrl({ url: 'pages/FamilyPage' });
      }
    } else if (intent.action === 'query') {
      this.executeQuery(intent);
    } else if (intent.action === 'query_time') {
      // reply already added
    } else if (intent.action === 'query_current_family') {
      this.queryCurrentFamily();
    } else if (intent.action === 'read_message') {
      this.readMessage(intent.messageSender || '');
    } else if (intent.action === 'multi_command') {
      this.executeMultiCommands(intent);
    }

    if (replyText) this.speak(replyText);
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

  async executeMultiCommands(intent: IntentResult) {
    const commands: IntentResult[] = intent.multiCommands || [];
    for (let i = 0; i < commands.length; i++) {
      const cmd: IntentResult = commands[i];
      if (cmd.action === 'navigate') {
        if (cmd.page === 'back') router.back();
        else if (cmd.page) {
          if (cmd.editField) AppStorage.setOrCreate('pendingEditField', cmd.editField);
          if (cmd.editValue) AppStorage.setOrCreate('pendingEditValue', cmd.editValue);
          router.pushUrl({ url: `pages/${cmd.page}` });
        }
      } else if (cmd.action === 'control_device') {
        this.executeDeviceControl(cmd);
      } else if (cmd.action === 'switch_family') {
        router.pushUrl({ url: cmd.page ? `pages/${cmd.page}` : 'pages/FamilyPage' });
      } else if (cmd.action === 'query') {
        this.executeQuery(cmd);
      } else if (cmd.action === 'query_current_family') {
        this.queryCurrentFamily();
      } else if (cmd.action === 'read_message') {
        this.readMessage(cmd.messageSender || '');
      }
      if (i < commands.length - 1) {
        await new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), 500));
      }
    }
  }

  async readMessage(sender: string) {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) { this.addChatMessage('ai', '未登录'); return; }
    const homeId: number = StorageUtil.getHomeId();
    if (!homeId) { this.addChatMessage('ai', '未获取到家庭信息'); return; }
    try {
      const resp = await ApiClient.get(`/home/${homeId}/messages?page=1&page_size=50`, token);
      if ((resp.code !== 200 && resp.code !== 0) || !resp.data) {
        this.addChatMessage('ai', '获取消息失败');
        return;
      }
      const data: Record<string, Object> = resp.data as Record<string, Object>;
      const messages: Array<Record<string, Object>> = data['messages'] as Array<Record<string, Object>>;
      if (!messages || messages.length === 0) { this.addChatMessage('ai', '暂无消息'); return; }
      let target: Record<string, Object> | null = null;
      if (sender) {
        for (let i = 0; i < messages.length; i++) {
          const senderName: string = (messages[i]['senderName'] as string) || '';
          if (senderName.includes(sender) || sender.includes(senderName)) { target = messages[i]; break; }
        }
        if (!target) { this.addChatMessage('ai', `未找到${sender}发来的消息`); return; }
      } else {
        target = messages[0];
      }
      this.addChatMessage('ai', `来自${target['senderName'] || '系统'}: ${target['content']}`);
    } catch (err) {
      this.addChatMessage('ai', '读取消息失败');
    }
  }

  async queryCurrentFamily() {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) { this.addChatMessage('ai', '未登录'); return; }
    try {
      const resp = await ApiClient.get('/user/current-home', token);
      if (resp.code === 200 && resp.data) {
        const data: Record<string, Object> = resp.data as Record<string, Object>;
        this.addChatMessage('ai', `当前家庭: ${data['homeName'] || data['homeId']}`);
      } else {
        this.addChatMessage('ai', '获取当前家庭失败');
      }
    } catch (err) {
      this.addChatMessage('ai', '查询当前家庭失败');
    }
  }

  async executeQuery(intent: IntentResult) {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) { this.addChatMessage('ai', '未登录'); return; }
    try {
      const deviceResp = await ApiClient.get('/device/list', token);
      if ((deviceResp.code !== 200 && deviceResp.code !== 0) || !deviceResp.data) {
        this.addChatMessage('ai', '查询设备列表失败');
        return;
      }
      const devices: Array<Record<string, Object>> = deviceResp.data as Array<Record<string, Object>>;
      const sensor: Record<string, Object> | undefined = devices.find((d: Record<string, Object>) => d['deviceType'] === 'temp_humi_sensor');
      if (!sensor) { this.addChatMessage('ai', '未找到温湿度传感器'); return; }
      const sensorId: Object = sensor['deviceId'];
      const latestResp = await ApiClient.get(`/device/latest/${sensorId}`, token);
      if ((latestResp.code !== 200 && latestResp.code !== 0) || !latestResp.data) {
        this.addChatMessage('ai', '查询传感器数据失败');
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
      this.addChatMessage('ai', parts.length > 0 ? parts.join('，') : '暂无数据');
    } catch (err) {
      this.addChatMessage('ai', '查询失败');
    }
  }

  async sendVoiceText() {
    if (!this.inputText.trim()) {
      promptAction.showToast({ message: '请输入内容' });
      return;
    }

    this.addChatMessage('user', this.inputText.trim());
    this.aiExpression = 'normal';

    const text: string = this.inputText.trim();
    this.inputText = '';
    this.statusText = '思考中...';
    this.processVoiceText(text);
  }

  async startRecording() {
    if (this.isRecording) return;
    await this.fallbackToWebInput();
  }

  async fallbackToWebInput() {
    this.statusText = '录音中，请说话...';
    try {
      // 创建 ASR 引擎（懒加载）
      if (this.asrEngine === null) {
        const asrConfig: speechRecognizer.SpeechRecognitionEngineConfig = {
          language: 'zh-CN',
          extra: {}
        };
        this.asrEngine = await speechRecognizer.createEngine(asrConfig);
        console.info('[AiPage] ASR 引擎创建成功');

        // 设置识别回调
        const listener: speechRecognizer.SpeechRecognitionListener = {
          onStart: () => {
            console.info('[AiPage] ASR 开始监听');
            this.isListening = true;
          },
          onRecognitionResultChange: (text: string, isFinal: boolean) => {
            console.info('[AiPage] ASR 中间结果: ' + text + ', isFinal=' + isFinal);
          },
          onComplete: (result: speechRecognizer.SpeechRecognitionResult) => {
            const text: string = result ? (result.result || '') : '';
            console.info('[AiPage] ASR 识别完成: ' + text);
            this.isListening = false;
            if (!text || !this.isRecording) return;
            this.isRecording = false;
            this.addChatMessage('user', text);
            this.aiExpression = 'normal';
            this.statusText = '思考中...';
            this.processVoiceText(text);
          },
          onError: (error: speechRecognizer.SpeechRecognitionError) => {
            console.error('[AiPage] ASR 识别错误: ' + JSON.stringify(error));
            this.isListening = false;
            this.isRecording = false;
            this.statusText = '小华在线';
          },
          onStop: () => {
            console.info('[AiPage] ASR 停止监听');
            this.isListening = false;
          }
        };
        this.asrEngine.setListener(listener);
      }

      // 开始监听
      const startParams: speechRecognizer.SpeechRecognitionStartParams = {
        sessionId: 'aipage_' + Date.now(),
        audioInfo: {
          audioPath: '',
          audioType: 'pcm'
        },
        extra: {}
      };
      await this.asrEngine.startListening(startParams);
      console.info('[AiPage] ASR 监听已启动');
      this.isRecording = true;
      this.aiExpression = 'surprise';
    } catch (err) {
      console.error('[AiPage] ASR 引擎创建/启动失败: ' + JSON.stringify(err));
      promptAction.showToast({ message: '启动语音识别失败' });
      this.statusText = '小华在线';
    }
  }

  async fetchWebInput() {
    try {
      if (this.asrEngine !== null && this.isListening) {
        await this.asrEngine.stopListening();
        console.info('[AiPage] ASR 监听已停止');
      }
    } catch (err) {
      console.error('[AiPage] 停止 ASR 监听失败: ' + JSON.stringify(err));
    }
    this.isRecording = false;
    this.isListening = false;
    this.statusText = '小华在线';
  }

  async stopRecording() {
    if (!this.isRecording) return;
    await this.fetchWebInput();
  }

  async releaseAsrEngine() {
    if (this.asrEngine) {
      try {
        this.asrEngine.shutdown();
      } catch (e) {
        console.error('[AiPage] ASR shutdown 失败: ' + JSON.stringify(e));
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

  resetSleepTimer() {
    if (this.sleepTimer !== -1) clearTimeout(this.sleepTimer);
    if (this.aiExpression === 'sleep') this.aiExpression = 'normal';
    this.sleepTimer = setTimeout(() => {
      this.aiExpression = 'sleep';
      this.sleepTimer = -1;
    }, 300000);
  }

  getAiImageResource(): Resource {
    if (this.aiExpression === 'sleep') return $r('app.media.ai_image_sleep');
    if (this.aiExpression === 'smile') return $r('app.media.ai_image_smile');
    if (this.aiExpression === 'surprise') return $r('app.media.ai_image_surprise');
    if (this.aiExpression === 'wink') return $r('app.media.ai_image_wink');
    if (this.aiExpression === 'embarrassed') return $r('app.media.ai_image_embarrassed');
    return $r('app.media.ai_image_normal');
  }

  async speak(text: string) {
    if (!text) {
      console.error('[TTS] speak called with empty text');
      return;
    }
    if (this.isSpeaking) {
      console.info('[TTS] speak skipped, isSpeaking=true');
      return;
    }
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

  startChat() {
    this.chatStarted = true;
    this.aiExpression = 'smile';
    this.resetSleepTimer();
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(24)
          .fontColor('#5D4E37')
          .onClick(() => router.back())
          .margin({ left: 32 })
        Text('和小华聊天')
          .fontSize(22)
          .fontColor('#5D4E37')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(48)
      }
      .width('100%')
      .height(56)
      .padding({ top: 16 })

      if (!this.chatStarted) {
        Column() {
          Image(this.getAiImageResource())
            .width(180)
            .height(180)
            .gesture(
              PanGesture()
                .onActionStart(() => {
                  const expressions: string[] = ['smile', 'surprise', 'wink', 'embarrassed'];
                  const idx: number = Math.floor(Math.random() * expressions.length);
                  this.aiExpression = expressions[idx];
                  this.resetSleepTimer();
                })
                .onActionEnd(() => {
                  this.aiExpression = 'normal';
                })
            )
          Text('我是小华，您的智能家居助手')
            .fontSize(24)
            .fontColor('#5D4E37')
            .margin({ top: 20 })
          Text('点我即可开启对话')
            .fontSize(22)
            .fontColor('#9E9189')
            .margin({ top: 14 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => this.startChat())
      } else {
        Row() {
          Column() {
            Image(this.getAiImageResource())
              .width(120)
              .height(120)
              .gesture(
                PanGesture()
                  .onActionStart(() => {
                    const expressions: string[] = ['smile', 'surprise', 'wink', 'embarrassed'];
                    const idx: number = Math.floor(Math.random() * expressions.length);
                    this.aiExpression = expressions[idx];
                    this.resetSleepTimer();
                  })
                  .onActionEnd(() => {
                    this.aiExpression = 'normal';
                  })
              )
            Text(this.statusText)
              .fontSize(14)
              .fontColor('#9E9189')
              .margin({ top: 8 })
          }
          .width('25%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Column() {
            Scroll() {
              Column() {
                ForEach(this.chatHistory, (msg: ChatMessage, index: number) => {
                  this.ChatBubbleBuilder(msg);
                }, (msg: ChatMessage, index: number) => `${index}`)
              }
              .width('100%')
            }
            .scrollable(ScrollDirection.Vertical)
            .layoutWeight(1)
            .width('100%')
            .padding({ left: 16, right: 40 })
          }
          .width('75%')
          .height('100%')
          .padding({ top: 8, bottom: 8, right: 24 })
        }
        .width('100%')
        .layoutWeight(1)

        Column() {
          Button(this.isRecording ? '⏹ 停止' : '🎤 录音')
            .width(160)
            .height(48)
            .fontSize(18)
            .backgroundColor(this.isRecording ? '#D36347' : '#C8E2CA')
            .fontColor('#FFFFFF')
            .borderRadius(24)
            .onClick(() => {
              if (this.isRecording) this.stopRecording();
              else this.startRecording();
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 24, top: 8 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0E9E2')
  }

  @Builder
  ChatBubbleBuilder(msg: ChatMessage) {
    Column() {
      if (msg.role === 'user') {
        Row() {
          Blank().layoutWeight(1)
          Column() {
            Text(msg.text)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .lineHeight(20)
          }
          .backgroundColor('#8CA79C')
          .borderRadius(12)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .constraintSize({ maxWidth: '50%' })
        }
        .width('100%')
      } else {
        Row() {
          Column() {
            Text(msg.text)
              .fontSize(14)
              .fontColor('#5D4E37')
              .lineHeight(20)
          }
          .backgroundColor('#E6DFD6')
          .borderRadius(12)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .constraintSize({ maxWidth: '70%' })
          Blank().layoutWeight(1)
        }
        .width('100%')
      }
    }
    .margin({ bottom: 8 })
  }
}
