import http from '@ohos.net.http';
import { ApiClient, SwitchCurrentHomeReq } from './ApiClient';

export interface IntentResult {
  action: string;
  page?: string;
  deviceType?: string;
  room?: string;
  operation?: string;
  queryType?: string;
  editField?: string;
  editValue?: string;
  deviceName?: string;
  acParams?: Record<string, Object>;
  timeQueryType?: string;
  familyName?: string;
  messageSender?: string;
  multiCommands?: IntentResult[];
  chatReply?: string;
  reply: string;
}

interface LLMMessage {
  role: string;
  content: string;
}

interface LLMRequest {
  model: string;
  messages: LLMMessage[];
  temperature: number;
  max_tokens: number;
}

interface LLMIntentResult {
  intent_type: string;
  action_type: string;
  target_page: string;
  device_type: string;
  room: string;
  operation: string;
  query_type: string;
  edit_field: string;
  device_name: string;
  ac_temp: number;
  ac_mode: string;
  ac_fan_speed: string;
  ac_wind_direction: string;
  ac_swing: boolean;
  ac_sleep_mode: boolean;
  ac_eco_mode: boolean;
  family_name: string;
  message_sender: string;
  time_query_type: string;
  reasoning: string;
  confidence: number;
}

const LLM_API_KEY: string = 'YOUR_DASHSCOPE_API_KEY';
const LLM_BASE_URL: string = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
const LLM_MODEL: string = 'qwen-turbo';

export class IntentService {
  private static lastLLMRequestTime: number = 0;

  static async processText(text: string): Promise<IntentResult> {
    const now: number = Date.now();
    if (now - IntentService.lastLLMRequestTime < 500) {
      const intent: IntentResult = IntentService.parseIntent(text);
      await IntentService.enrichQueryResult(intent, text);
      return intent;
    }
    IntentService.lastLLMRequestTime = now;

    const parts: string[] = IntentService.splitMultiCommand(text);
    if (parts.length > 1) {
      return await IntentService.processMultiCommands(parts);
    }

    try {
      const llmResult: LLMIntentResult | null = await IntentService.callLLMForIntent(text);
      if (llmResult && llmResult.confidence >= 0.5) {
        const intent: IntentResult = IntentService.convertLLMToIntent(llmResult, text);
        const overrideIntent: IntentResult | null = IntentService.overrideAllDevices(text, intent);
        if (overrideIntent) {
          await IntentService.enrichQueryResult(overrideIntent, text);
          return overrideIntent;
        }
        await IntentService.enrichQueryResult(intent, text);
        return intent;
      }
    } catch (err) {
      console.error('LLM调用失败，使用关键词匹配', JSON.stringify(err));
    }

    const intent: IntentResult = IntentService.parseIntent(text);
    const overrideIntent: IntentResult | null = IntentService.overrideAllDevices(text, intent);
    if (overrideIntent) {
      await IntentService.enrichQueryResult(overrideIntent, text);
      return overrideIntent;
    }
    await IntentService.enrichQueryResult(intent, text);
    return intent;
  }

  static overrideAllDevices(text: string, intent: IntentResult): IntentResult | null {
    const t: string = text.toLowerCase();
    const hasAllDevices: boolean = t.includes('所有设备') || t.includes('全部设备') || t.includes('所有设备都') || t.includes('设备都关') || t.includes('设备都开') || t.includes('设备全关') || t.includes('设备全开');
    if (!hasAllDevices) return null;
    if (intent.action !== 'control_device' && intent.action !== 'multi_command') return null;

    const isQuery: boolean = t.includes('关了吗') || t.includes('开了吗') || t.includes('吗') || t.includes('有没有') || t.includes('是不是') || t.includes('？') || t.includes('?');
    if (isQuery) return null;

    const isOn: boolean = t.includes('打开') || t.includes('开启') || t.includes('开灯') || t.includes('开空调') || t.includes('开门') || t.includes('解锁') || t.includes('都开');
    const isOff: boolean = t.includes('关闭') || t.includes('关掉') || t.includes('关灯') || t.includes('关空调') || t.includes('关门') || t.includes('锁门') || t.includes('关上') || t.includes('都关');
    if (!isOn && !isOff) return null;

    const room: string = IntentService.extractRoom(t);
    const op: string = isOn ? 'on' : 'off';
    const cmds: IntentResult[] = [
      { action: 'control_device', deviceType: 'light', room: room, operation: op, reply: room ? `已${isOn ? '开启' : '关闭'}${room}灯光` : `已${isOn ? '开启' : '关闭'}全部灯光` },
      { action: 'control_device', deviceType: 'ac', room: room, operation: op, reply: room ? `已${isOn ? '开启' : '关闭'}${room}空调` : `已${isOn ? '开启' : '关闭'}全部空调` },
      { action: 'control_device', deviceType: 'door', room: room, operation: op === 'on' ? 'open' : 'close', reply: room ? `已${op === 'on' ? '打开' : '关闭'}${room}门锁` : `已${op === 'on' ? '打开' : '关闭'}全部门锁` }
    ];
    return { action: 'multi_command', multiCommands: cmds, reply: `已为您${isOn ? '开启' : '关闭'}所有设备` };
  }

  static splitMultiCommand(text: string): string[] {
    const separators: string[] = ['然后', '接着', '再'];
    let result: string[] = [text];
    for (let si = 0; si < separators.length; si++) {
      const sep: string = separators[si];
      const newParts: string[] = [];
      for (let ri = 0; ri < result.length; ri++) {
        const part: string = result[ri];
        const split: string[] = part.split(sep);
        for (let sj = 0; sj < split.length; sj++) {
          const trimmed: string = split[sj].trim();
          if (trimmed) newParts.push(trimmed);
        }
      }
      result = newParts;
    }

    const deviceKeywords: string[] = ['灯', '空调', '门', '灯光', '门锁'];
    const newResult: string[] = [];
    for (let i = 0; i < result.length; i++) {
      const part: string = result[i];
      const andSplit: string[] = part.split('和');
      if (andSplit.length > 1) {
        let allHaveDevice: boolean = true;
        for (let j = 0; j < andSplit.length; j++) {
          const trimmed: string = andSplit[j].trim();
          let hasDevice: boolean = false;
          for (let k = 0; k < deviceKeywords.length; k++) {
            if (trimmed.includes(deviceKeywords[k])) { hasDevice = true; break; }
          }
          if (!hasDevice) { allHaveDevice = false; break; }
        }
        if (allHaveDevice) {
          for (let j = 0; j < andSplit.length; j++) {
            const trimmed: string = andSplit[j].trim();
            if (trimmed) newResult.push(trimmed);
          }
        } else {
          newResult.push(part);
        }
      } else {
        newResult.push(part);
      }
    }
    result = newResult;

    return result.length > 1 ? result : [text];
  }

  static async processMultiCommands(parts: string[]): Promise<IntentResult> {
    const commands: IntentResult[] = [];
    const replyParts: string[] = [];

    for (let i = 0; i < parts.length; i++) {
      const part: string = parts[i];
      let intent: IntentResult;
      try {
        const llmResult: LLMIntentResult | null = await IntentService.callLLMForIntent(part);
        if (llmResult && llmResult.confidence >= 0.5) {
          intent = IntentService.convertLLMToIntent(llmResult, part);
        } else {
          intent = IntentService.parseIntent(part);
        }
      } catch (err) {
        intent = IntentService.parseIntent(part);
      }

      if (intent.action === 'query') {
        const queryResult: string = await IntentService.fetchSensorData(intent.queryType || 'temperature');
        if (queryResult) intent.reply = queryResult;
      } else if (intent.action === 'query_time') {
        const enriched: string = IntentService.getTimeReply(intent.timeQueryType || 'time');
        if (enriched) intent.reply = enriched;
      } else if (intent.action === 'query_device_status') {
        const rawStatus: string = await IntentService.fetchDeviceStatus(intent.deviceType || '', intent.room || '');
        if (rawStatus) {
          const polished: string = await IntentService.polishDeviceStatusReply(rawStatus, intent.deviceType || '', intent.room || '', part);
          intent.reply = polished;
        }
      }

      commands.push(intent);
      replyParts.push(intent.reply);
    }

    const multiResult: IntentResult = {
      action: 'multi_command',
      multiCommands: commands,
      reply: replyParts.join('，')
    };
    return multiResult;
  }

  static async callLLMForIntent(text: string): Promise<LLMIntentResult | null> {
    const classifyPrompt: string =
      '你是一个智能家居语音助手，需要精确分析用户输入并分类意图。\n' +
      `\n用户输入: "${text}"\n` +
      '\n## 意图类型：\n' +
      '1. control_device: 控制设备（开关、调节参数）\n' +
      '2. navigate: 页面导航（打开某个页面）\n' +
      '3. query: 查询传感器信息（温度、湿度等，如"多少度""几度""家里温度"）\n' +
      '4. query_time: 查询时间/日期（几点了、星期几、几号）\n' +
      '5. edit_profile: 修改个人信息（昵称、手机号等）\n' +
      '6. switch_family: 切换家庭\n' +
      '7. read_message: 读取最新消息（查询最新消息是什么、谁发的）\n' +
      '8. read_message_detail: 读取消息完整内容（用户要求读完整内容、详细内容、全文时使用）\n' +
      '9. query_current_family: 查询当前家庭\n' +
      '10. query_device_status: 查询设备状态（空调关了吗、灯开了吗、门锁状态等）\n' +
      '11. multi_command: 多个设备操作（如"设备都关了""把灯和空调都打开"等涉及多种设备类型的操作）\n' +
      '12. scene: 场景触发（如"出门了""离家了""走了""回来了""到家了"等表示离家/回家场景）\n' +
      '13. chat: 闲聊/问答/通用对话（不属于以上任何智能家居操作的输入，如问天气、讲笑话、问知识等）\n' +
      '14. unknown: 无法理解\n' +
      '\n## 设备类型：\n' +
      '- light: 灯、灯光、灯泡、照明\n' +
      '- ac: 空调、冷气、暖气\n' +
      '- door: 门、门锁、大门\n' +
      '\n## 操作：\n' +
      '- light/ac: on(开/打开/开启), off(关/关闭/关掉/关上)\n' +
      '- door: open(开/打开/解锁), close(关/关闭/锁上/锁门)\n' +
      '\n## 房间：卧室、客厅、厨房、书房、浴室、阳台、主卧、次卧、餐厅\n' +
      '\n## 空调参数（仅device_type为ac时填写）：\n' +
      '- ac_temp: 温度值。"调低到25度""设为26度"填目标温度25/26（正数），"调低一点"填-1，"调高一点"填+1，"调低2度"填-2。注意区分"调低到X度"（绝对值）和"调低X度"（偏移量）\n' +
      '- ac_mode: auto(自动), cool(制冷), heat(制热), dry(除湿), fan(送风)\n' +
      '- ac_fan_speed: auto(自动), low(低), medium(中), high(高)\n' +
      '- ac_wind_direction: auto(自动), up(上), middle(中), down(下)\n' +
      '- ac_swing: 扫风（布尔）\n' +
      '- ac_sleep_mode: 睡眠模式（布尔）\n' +
      '- ac_eco_mode: 节能模式（布尔）\n' +
      '\n## 页面：\n' +
      '- HomePage: 首页、主页\n' +
      '- LightPage: 灯光页面\n' +
      '- AcPage: 空调页面\n' +
      '- DoorPage: 门锁页面\n' +
      '- ProfilePage: 个人中心、我的页面\n' +
      '- MessagePage: 消息页面、通知页面\n' +
      '- FamilyPage: 家庭页面、家庭管理、家庭设置\n' +
      '\n## 查询类型：temperature(温度), humidity(湿度), both(温湿度都查)\n' +
      '\n## 编辑字段：nickname(昵称), phone(手机号)\n' +
      '\n## 设备名称：用户提到具体设备名如"灯4""五号灯"时填入device_name\n' +
      '\n## 家庭名称：用户要切换家庭时填入family_name\n' +
      '\n## 时间查询类型：time(几点了), date(几号/日期), weekday(星期几)\n' +
      '\n请以JSON格式返回：\n' +
      '{"intent_type":"...","action_type":"...","target_page":"...","device_type":"light或ac或door","room":"房间名或空","operation":"on/off/open/close","query_type":"temperature或humidity或both","edit_field":"nickname或phone","device_name":"具体设备名或空","ac_temp":0,"ac_mode":"auto/cool/heat/dry/fan或空","ac_fan_speed":"auto/low/medium/high或空","ac_wind_direction":"auto/up/middle/down或空","ac_swing":false,"ac_sleep_mode":false,"ac_eco_mode":false,"family_name":"家庭名或空","message_sender":"消息发送者名或空","time_query_type":"time或date或weekday或空","reasoning":"分析理由","confidence":0.0-1.0}\n' +
      '\n重要规则：\n' +
      '0. 查询设备状态（如"空调关了吗""灯开了吗""门锁状态"等）用query_device_status意图，device_type填对应设备类型，room填房间（如果有）\n' +
      '0a. 查询所有设备状态（如"设备都关了吗""所有设备状态""家里设备怎么样"等未指定特定设备类型时），device_type留空字符串，不要只填light\n' +
      '1. 门的操作必须用open/close而非on/off\n' +
      '2. 空调参数如果不相关则留空或填默认值\n' +
      '3. "调低一点""调高一点"等相对调节，ac_temp填偏移量（-1/+1等），不要填绝对温度\n' +
      '4. "关闭睡眠模式""取消扫风""关掉节能"等表示关闭对应功能，对应字段填false，operation填on（保持空调运行），绝对不是关闭空调\n' +
      '5. "开启扫风""打开睡眠模式""节能模式"等表示开启对应功能，对应字段填true\n' +
      '6. 问时间/日期/星期几用query_time意图\n' +
      '7. "家庭页面""家庭管理""打开家庭"→target_page=FamilyPage，不是HomePage\n' +
      '8. "当前家庭""现在的家庭"用query_current_family意图\n' +
      '9. 关闭空调快捷功能（扫风/睡眠/节能）时，operation必须是on，不能是off，因为只是关闭功能不是关闭空调\n' +
      '10. 如果用户输入与智能家居操作无关（如闲聊、问知识、讲笑话等），intent_type填chat\n' +
      '11. "读完整内容""详细内容""全文""完整消息"等要求读取消息详情时用read_message_detail，不是read_message\n' +
      '12. "设备都关了""所有设备打开"等涉及多种设备类型时，用multi_command意图，不要只返回一种设备\n' +
      '13. "出门了""离家了""走了""我出门了"等离家场景用scene意图，operation填leave_home；"回来了""到家了""我回来了"等回家场景用scene意图，operation填arrive_home\n' +
      '请直接返回JSON，不要有其他内容。';

    const httpRequest = http.createHttp();
    try {
      const llmMessage: LLMMessage = { role: 'user', content: classifyPrompt };
      const messages: LLMMessage[] = [llmMessage];
      const reqBody: LLMRequest = {
        model: LLM_MODEL,
        messages: messages,
        temperature: 0.3,
        max_tokens: 300
      };
      const response = await httpRequest.request(`${LLM_BASE_URL}/chat/completions`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${LLM_API_KEY}`,
          'Content-Type': 'application/json'
        },
        extraData: JSON.stringify(reqBody),
        connectTimeout: 8000,
        readTimeout: 8000
      });

      const resultText = response.result as string;
      if (resultText) {
        const respObj: Record<string, Object> = JSON.parse(resultText);
        const choices = respObj['choices'] as Array<Record<string, Object>>;
        if (choices && choices.length > 0) {
          const message = choices[0]['message'] as Record<string, string>;
          const content: string = message['content'] || '';
          const jsonMatch: RegExpMatchArray | null = content.match(/\{[\s\S]*\}/);
          if (jsonMatch) {
            return JSON.parse(jsonMatch[0]) as LLMIntentResult;
          }
        }
      }
      return null;
    } catch (err) {
      console.error('LLM请求失败', JSON.stringify(err));
      return null;
    } finally {
      httpRequest.destroy();
    }
  }

  static async callLLMForChat(text: string): Promise<string> {
    const chatPrompt: string =
      '你是小华，一个智能手表上的智能家居助手。你的核心能力：\n' +
      '1. 智能家居控制（帮用户远程开关设备）\n' +
      '2. 日常问答：简单友好的回答\n' +
      '\n回答规则：\n' +
      '- 关于智能家居：简洁告知操作结果\n' +
      '- 其他问题：简洁友好回答，控制在80字以内\n' +
      '- 语气亲切自然，像朋友聊天一样\n' +
      '- 不要编造信息，不确定时坦诚告知' +
      `\n\n用户说: "${text}"\n` +
      '\n请直接回答，不要加前缀或标号。';

    const httpRequest = http.createHttp();
    try {
      const llmMessage: LLMMessage = { role: 'user', content: chatPrompt };
      const messages: LLMMessage[] = [llmMessage];
      const reqBody: LLMRequest = {
        model: LLM_MODEL,
        messages: messages,
        temperature: 0.7,
        max_tokens: 200
      };
      const response = await httpRequest.request(`${LLM_BASE_URL}/chat/completions`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${LLM_API_KEY}`,
          'Content-Type': 'application/json'
        },
        extraData: JSON.stringify(reqBody),
        connectTimeout: 10000,
        readTimeout: 10000
      });

      const resultText = response.result as string;
      if (resultText) {
        const respObj: Record<string, Object> = JSON.parse(resultText);
        const choices = respObj['choices'] as Array<Record<string, Object>>;
        if (choices && choices.length > 0) {
          const message = choices[0]['message'] as Record<string, string>;
          const content: string = (message['content'] || '').trim();
          if (content) return content;
        }
      }
      return '抱歉，我暂时无法回答';
    } catch (err) {
      console.error('聊天LLM请求失败', JSON.stringify(err));
      return '抱歉，我暂时无法回答';
    } finally {
      httpRequest.destroy();
    }
  }

  static convertLLMToIntent(llm: LLMIntentResult, originalText: string): IntentResult {
    const room: string = llm.room || IntentService.extractRoom(originalText);

    if (llm.intent_type === 'control_device') {
      const deviceType: string = llm.device_type || 'light';
      let operation: string = llm.operation || 'on';
      if (deviceType === 'door') {
        if (operation === 'on') operation = 'open';
        else if (operation === 'off') operation = 'close';
      }
      const deviceLabel: string = deviceType === 'ac' ? '空调' : (deviceType === 'door' ? '门锁' : '灯光');
      let replyText: string = '';
      if (deviceType === 'door') {
        const opLabel: string = operation === 'open' ? '打开' : '关闭';
        replyText = room ? `正在为您${opLabel}${room}${deviceLabel}` : `正在为您${opLabel}${deviceLabel}`;
      } else {
        const opLabel: string = operation === 'on' ? '开启' : '关闭';
        replyText = room ? `已为您${opLabel}${room}${deviceLabel}` : `已为您${opLabel}${deviceLabel}`;
      }

      const result: IntentResult = {
        action: 'control_device',
        deviceType: deviceType,
        room: room,
        operation: operation,
        reply: replyText
      };

      if (llm.device_name) result.deviceName = llm.device_name;

      if (deviceType === 'ac') {
        const acParams: Record<string, Object> = {};
        let hasAcParam: boolean = false;
        const detailParts: string[] = [];
        let isCloseFeature: boolean = false;

        if (llm.ac_temp !== 0) {
          const isTargetTemp: boolean = originalText.includes('调低到') || originalText.includes('调高到') || originalText.includes('降到') || originalText.includes('升到') || originalText.includes('设为') || originalText.includes('设置为') || originalText.includes('调到');
          if (isTargetTemp && llm.ac_temp >= 16 && llm.ac_temp <= 30) {
            acParams['temp'] = llm.ac_temp;
            hasAcParam = true;
            detailParts.push(`温度设为${llm.ac_temp}度`);
          } else {
            acParams['temp_delta'] = llm.ac_temp;
            hasAcParam = true;
            if (llm.ac_temp > 0) detailParts.push(`调高${llm.ac_temp}度`);
            else detailParts.push(`调低${Math.abs(llm.ac_temp)}度`);
          }
        }
        if (llm.ac_mode) {
          acParams['mode'] = llm.ac_mode;
          hasAcParam = true;
          const modeMap: Record<string, string> = { 'auto': '自动', 'cool': '制冷', 'heat': '制热', 'dry': '除湿', 'fan': '送风' };
          detailParts.push((modeMap[llm.ac_mode] || llm.ac_mode) + '模式');
        }
        if (llm.ac_fan_speed) {
          acParams['fan_speed'] = llm.ac_fan_speed;
          hasAcParam = true;
          const fanMap: Record<string, string> = { 'auto': '自动', 'low': '低', 'medium': '中', 'high': '高' };
          detailParts.push((fanMap[llm.ac_fan_speed] || llm.ac_fan_speed) + '风速');
        }
        if (llm.ac_wind_direction) {
          acParams['wind_direction'] = llm.ac_wind_direction;
          hasAcParam = true;
          const windMap: Record<string, string> = { 'auto': '自动', 'up': '上', 'middle': '中', 'down': '下' };
          detailParts.push((windMap[llm.ac_wind_direction] || llm.ac_wind_direction) + '风向');
        }

        const origHasClose: boolean = originalText.includes('关闭') || originalText.includes('取消') || originalText.includes('关掉') || originalText.includes('停止');

        if (origHasClose && originalText.includes('扫风')) {
          acParams['swing'] = false;
          hasAcParam = true;
          isCloseFeature = true;
          detailParts.push('关闭扫风');
        } else if (llm.ac_swing === true) {
          acParams['swing'] = true;
          hasAcParam = true;
          detailParts.push('开启扫风');
        }

        if (origHasClose && originalText.includes('睡眠')) {
          acParams['sleep_mode'] = false;
          hasAcParam = true;
          isCloseFeature = true;
          detailParts.push('关闭睡眠模式');
        } else if (llm.ac_sleep_mode === true) {
          acParams['sleep_mode'] = true;
          hasAcParam = true;
          detailParts.push('开启睡眠模式');
        }

        if (origHasClose && (originalText.includes('节能') || originalText.includes('省电'))) {
          acParams['eco_mode'] = false;
          hasAcParam = true;
          isCloseFeature = true;
          detailParts.push('关闭节能模式');
        } else if (llm.ac_eco_mode === true) {
          acParams['eco_mode'] = true;
          hasAcParam = true;
          detailParts.push('开启节能模式');
        }

        if (hasAcParam) {
          result.acParams = acParams;
          if (isCloseFeature) {
            result.operation = 'on';
            result.reply = room ? `已为您设置${room}空调，${detailParts.join('、')}` : `已为您设置空调，${detailParts.join('、')}`;
          } else {
            result.operation = 'update_settings';
            result.reply = room ? `已为您设置${room}空调，${detailParts.join('、')}` : `已为您设置空调，${detailParts.join('、')}`;
          }
        }
      }

      return result;
    }

    if (llm.intent_type === 'navigate') {
      const page: string = llm.target_page || 'HomePage';
      if (originalText.includes('发来的') || (originalText.includes('最新') && originalText.includes('消息'))) {
        const senderMatch: RegExpMatchArray | null = originalText.match(/(.+?)发来的/);
        const sender: string = senderMatch ? senderMatch[1].trim() : '';
        return {
          action: 'read_message',
          messageSender: sender,
          reply: sender ? `正在为您查找${sender}的最新消息` : '正在为您读取最新消息'
        };
      }
      return {
        action: 'navigate',
        page: page,
        reply: `已为您打开${IntentService.getPageFriendlyName(page)}`
      };
    }

    if (llm.intent_type === 'query') {
      const queryType: string = llm.query_type || 'temperature';
      const queryLabel: string = queryType === 'both' ? '温湿度' : (queryType === 'temperature' ? '温度' : '湿度');
      return { action: 'query', queryType: queryType, reply: `正在为您查询${queryLabel}` };
    }

    if (llm.intent_type === 'query_time') {
      const timeQueryType: string = llm.time_query_type || 'time';
      return { action: 'query_time', timeQueryType: timeQueryType, reply: '正在为您查询时间' };
    }

    if (llm.intent_type === 'edit_profile') {
      const editField: string = llm.edit_field || 'nickname';
      let editValue: string = '';
      if (editField === 'nickname') {
        const nicknameMatch: RegExpMatchArray | null = originalText.match(/(?:昵称|名字)(?:改为|改成|修改为|设为|换成|为|叫)\s*(.+)/);
        editValue = nicknameMatch ? nicknameMatch[1].trim() : '';
      } else if (editField === 'phone') {
        const phoneMatch: RegExpMatchArray | null = originalText.match(/(?:手机号|手机号码|电话号码|电话|手机)(?:改为|改成|修改为|设为|换成|绑定为|为)\s*(\d{11})/);
        editValue = phoneMatch ? phoneMatch[1].trim() : '';
      }
      const result: IntentResult = {
        action: 'navigate',
        page: 'ProfilePage',
        editField: editField,
        editValue: editValue,
        reply: editValue ? (editField === 'phone' ? `已为您修改手机号为${editValue}` : `已为您修改昵称为${editValue}`) : (editField === 'phone' ? '已为您打开手机号修改' : '已为您打开昵称修改')
      };
      return result;
    }

    if (llm.intent_type === 'switch_family') {
      const familyName: string = llm.family_name || '';
      return { action: 'switch_family', familyName: familyName, reply: familyName ? `正在为您切换到${familyName}` : '正在为您打开家庭管理' };
    }

    if (llm.intent_type === 'read_message') {
      let sender: string = llm.message_sender || '';
      if (!sender) {
        const senderMatch: RegExpMatchArray | null = originalText.match(/(.+?)发来的/);
        sender = senderMatch ? senderMatch[1].trim() : '';
      }
      return { action: 'read_message', messageSender: sender, reply: sender ? `正在为您查找${sender}的最新消息` : '正在为您读取最新消息' };
    }

    if (llm.intent_type === 'read_message_detail') {
      let sender: string = llm.message_sender || '';
      if (!sender) {
        const senderMatch: RegExpMatchArray | null = originalText.match(/(.+?)发来的/);
        sender = senderMatch ? senderMatch[1].trim() : '';
      }
      return { action: 'read_message_detail', messageSender: sender, reply: '正在为您读取消息完整内容' };
    }

    if (llm.intent_type === 'query_current_family') {
      return { action: 'query_current_family', reply: '正在为您查询当前家庭' };
    }

    if (llm.intent_type === 'query_device_status') {
      const deviceType: string = llm.device_type || '';
      const deviceLabel: string = deviceType === 'ac' ? '空调' : (deviceType === 'door' ? '门锁' : (deviceType === 'light' ? '灯光' : '设备'));
      const roomLabel: string = room ? `${room}的` : '';
      return { action: 'query_device_status', deviceType: deviceType, room: room, reply: `正在为您查询${roomLabel}${deviceLabel}状态` };
    }

    if (llm.intent_type === 'multi_command') {
      const op: string = llm.operation || 'off';
      const cmds: IntentResult[] = [
        { action: 'control_device', deviceType: 'light', room: room, operation: op === 'open' ? 'on' : op, reply: room ? `已${op === 'on' || op === 'open' ? '开启' : '关闭'}${room}灯光` : `已${op === 'on' || op === 'open' ? '开启' : '关闭'}全部灯光` },
        { action: 'control_device', deviceType: 'ac', room: room, operation: op === 'open' ? 'on' : op, reply: room ? `已${op === 'on' || op === 'open' ? '开启' : '关闭'}${room}空调` : `已${op === 'on' || op === 'open' ? '开启' : '关闭'}全部空调` },
        { action: 'control_device', deviceType: 'door', room: room, operation: op === 'on' ? 'open' : (op === 'off' ? 'close' : op), reply: room ? `已${op === 'on' || op === 'open' ? '打开' : '关闭'}${room}门锁` : `已${op === 'on' || op === 'open' ? '打开' : '关闭'}全部门锁` }
      ];
      return { action: 'multi_command', multiCommands: cmds, reply: `已为您${op === 'on' || op === 'open' ? '开启' : '关闭'}所有设备` };
    }

    if (llm.intent_type === 'scene') {
      const sceneOp: string = llm.operation || 'leave_home';
      if (sceneOp === 'arrive_home') {
        const cmds: IntentResult[] = [
          { action: 'control_device', deviceType: 'light', room: '', operation: 'on', reply: '已打开全部灯光' },
          { action: 'control_device', deviceType: 'ac', room: '', operation: 'on', reply: '已打开全部空调' }
        ];
        return { action: 'multi_command', multiCommands: cmds, reply: '欢迎回家，已为您打开灯光和空调' };
      }
      const cmds: IntentResult[] = [
        { action: 'control_device', deviceType: 'light', room: '', operation: 'off', reply: '已关闭全部灯光' },
        { action: 'control_device', deviceType: 'ac', room: '', operation: 'off', reply: '已关闭全部空调' },
        { action: 'control_device', deviceType: 'door', room: '', operation: 'close', reply: '已关闭全部门锁' }
      ];
      return { action: 'multi_command', multiCommands: cmds, reply: '好的，已为您关闭所有设备，注意安全' };
    }

    if (llm.intent_type === 'chat') {
      return { action: 'chat', reply: '正在思考...' };
    }

    return { action: 'unknown', reply: '抱歉，我没有理解您的指令' };
  }

  static async enrichQueryResult(intent: IntentResult, text?: string): Promise<void> {
    if (intent.action === 'query') {
      const queryResult: string = await IntentService.fetchSensorData(intent.queryType || 'temperature');
      if (queryResult) intent.reply = queryResult;
    }

    if (intent.action === 'query_time') {
      const timeQueryType: string = intent.timeQueryType || 'time';
      const reply: string = IntentService.getTimeReply(timeQueryType);
      if (reply) intent.reply = reply;
    }

    if (intent.action === 'switch_family') {
      const switchResult: string = await IntentService.switchFamily(intent.familyName || '');
      if (switchResult) intent.reply = switchResult;
      intent.page = 'FamilyPage';
    }

    if (intent.action === 'chat') {
      const chatReply: string = await IntentService.callLLMForChat(text || '');
      intent.chatReply = chatReply;
      intent.reply = chatReply;
    }

    if (intent.action === 'query_device_status') {
      const rawStatus: string = await IntentService.fetchDeviceStatus(intent.deviceType || '', intent.room || '');
      if (rawStatus) {
        const polished: string = await IntentService.polishDeviceStatusReply(rawStatus, intent.deviceType || '', intent.room || '', text || '');
        intent.reply = polished;
      }
    }
  }

  static getTimeReply(timeQueryType: string): string {
    const now: Date = new Date();
    const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    if (timeQueryType === 'time') {
      const hours: number = now.getHours();
      const minutes: number = now.getMinutes();
      const period: string = hours < 6 ? '凌晨' : (hours < 12 ? '上午' : (hours < 18 ? '下午' : '晚上'));
      const displayHour: number = hours > 12 ? hours - 12 : (hours === 0 ? 12 : hours);
      return `现在是${period}${displayHour}点${minutes > 0 ? minutes + '分' : '整'}`;
    } else if (timeQueryType === 'weekday') {
      return `今天是星期${weekdays[now.getDay()]}`;
    } else if (timeQueryType === 'date') {
      return `今天是${now.getMonth() + 1}月${now.getDate()}日`;
    }
    return '';
  }

  static async switchFamily(familyName: string): Promise<string> {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) return '未登录';
    try {
      const resp = await ApiClient.get('/user/homes', token);
      if (resp.code !== 200 || !resp.data) return '查询家庭列表失败';
      const families: Array<Record<string, Object>> = resp.data as Array<Record<string, Object>>;
      if (!families || families.length === 0) return '暂无可切换的家庭';

      if (familyName) {
        let targetHomeId: number = 0;
        for (let i = 0; i < families.length; i++) {
          const name: string = (families[i]['homeName'] as string) || '';
          if (name && name.includes(familyName)) {
            targetHomeId = families[i]['homeId'] as number;
            break;
          }
        }
        if (targetHomeId > 0) {
          const switchReq: SwitchCurrentHomeReq = { homeId: targetHomeId };
          const switchResp = await ApiClient.put('/user/current-home', switchReq, token);
          if (switchResp.code === 200) return `已切换到${familyName}`;
          return `切换到${familyName}失败`;
        }
        return `未找到名为"${familyName}"的家庭`;
      }

      const familyNames: string[] = [];
      for (let i = 0; i < families.length; i++) {
        const name: string = (families[i]['homeName'] as string) || '';
        if (name) familyNames.push(name);
      }
      return `当前可用家庭：${familyNames.join('、')}`;
    } catch (err) {
      return '查询家庭信息失败';
    }
  }

  static async fetchDeviceStatus(deviceType: string, room: string): Promise<string> {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) return '未登录';
    try {
      const deviceResp = await ApiClient.get('/device/list', token);
      if ((deviceResp.code !== 200 && deviceResp.code !== 0) || !deviceResp.data) return '查询设备列表失败';
      const devices: Array<Record<string, Object>> = deviceResp.data as Array<Record<string, Object>>;

      const typeMap: Record<string, string> = { 'light': 'light', 'ac': 'air_conditioner', 'door': 'door' };
      const targetType: string = typeMap[deviceType] || deviceType;
      const labelMap: Record<string, string> = { 'light': '灯光', 'ac': '空调', 'door': '门锁', 'air_conditioner': '空调' };
      const statusLabelMap: Record<string, Record<string, string>> = {
        'light': { 'online': '开', 'offline': '关' },
        'ac': { 'online': '开', 'offline': '关' },
        'door': { 'online': '开', 'offline': '关' },
        'air_conditioner': { 'online': '开', 'offline': '关' }
      };

      const matched: Array<Record<string, Object>> = [];
      for (let i = 0; i < devices.length; i++) {
        const d: Record<string, Object> = devices[i];
        const dType: string = (d['deviceType'] as string) || '';
        const typeMatch: boolean = !deviceType || dType === targetType || dType === deviceType;
        if (typeMatch) {
          if (room) {
            const dRoom: string = (d['room'] as string) || '';
            if (dRoom.includes(room) || room.includes(dRoom)) {
              matched.push(d);
            }
          } else {
            matched.push(d);
          }
        }
      }

      if (matched.length === 0) {
        const deviceLabel: string = labelMap[deviceType] || '设备';
        return room ? `${room}没有${deviceLabel}` : `没有找到${deviceLabel}`;
      }

      const parts: string[] = [];
      for (let i = 0; i < matched.length; i++) {
        const d: Record<string, Object> = matched[i];
        const dName: string = (d['name'] as string) || '';
        const dRoom: string = (d['room'] as string) || '';
        const dStatus: string = (d['status'] as string) || '';
        const dType: string = (d['deviceType'] as string) || '';
        const dId: number = d['deviceId'] as number;
        const typeLabel: string = labelMap[dType] || dType;
        const label: string = dRoom ? `${dRoom}的${dName || typeLabel}` : (dName || typeLabel);

        if (dType === 'air_conditioner') {
          try {
            const acResp = await ApiClient.get(`/device/ac/${dId}`, token);
            if ((acResp.code === 200 || acResp.code === 0) && acResp.data) {
              const acData: Record<string, Object> = acResp.data as Record<string, Object>;
              const settings: Record<string, Object> = acData['settings'] as Record<string, Object>;
              const powerOn: boolean = settings !== null && (settings['power'] === true || settings['power'] === 1 || settings['power'] === 'true');
              if (powerOn) {
                const temp: number = (settings['temp'] as number) || 26;
                const mode: string = (settings['mode'] as string) || 'cool';
                const modeMap: Record<string, string> = { 'auto': '自动', 'cool': '制冷', 'heat': '制热', 'dry': '除湿', 'fan': '送风' };
                parts.push(`${label}开着，${modeMap[mode] || mode}模式，${temp}度`);
              } else {
                parts.push(`${label}关着`);
              }
            } else {
              parts.push(`${label}开着`);
            }
          } catch (err) {
            parts.push(`${label}开着`);
          }
        } else {
          const statusMap: Record<string, string> = statusLabelMap[dType] || { 'online': '开', 'offline': '关' };
          const statusLabel: string = statusMap[dStatus] || dStatus;
          parts.push(`${label}${statusLabel}`);
        }
      }
      return parts.join('，');
    } catch (err) {
      return '查询设备状态失败';
    }
  }

  static async polishDeviceStatusReply(rawStatus: string, deviceType: string, room: string, userQuestion: string): Promise<string> {
    const labelMap: Record<string, string> = { 'light': '灯', 'ac': '空调', 'door': '门锁' };
    const deviceLabel: string = labelMap[deviceType] || '设备';
    const roomLabel: string = room ? `${room}的` : '';

    const prompt: string =
      '你是小华，一个智能家居语音助手。用户查询了设备状态，以下是系统返回的原始数据：\n' +
      `\n用户问题: ${userQuestion}\n设备类型: ${deviceLabel}\n房间筛选: ${roomLabel || '全部'}\n原始状态数据: ${rawStatus}\n` +
      '\n请根据原始数据，用自然、简洁、人性化的语言总结设备状态。规则：\n' +
      '1. 如果所有设备状态一致（全开/全关），直接说"家里的灯都关了"或"家里的空调都开着"\n' +
      '2. 如果大部分关、少数开，说"除了客厅灯和卧室空调，其他设备都关了，需要为您关闭吗？"\n' +
      '3. 如果大部分开、少数关，说"除了卧室灯，其他灯都开着，需要为您打开卧室灯吗？"\n' +
      '4. 如果开关各半，说"客厅和卧室的灯开着，厨房和浴室的灯关着"\n' +
      '5. 空调如果开着，可以补充温度和模式信息\n' +
      '6. 回复控制在50字以内，简洁自然\n' +
      '7. 主动建议要符合逻辑：开着的问是否关闭，关着的问是否打开，不要反过来\n' +
      '8. 不要列出每个设备的详细状态，要归纳总结\n' +
      '9. 根据用户问题语境：用户问"XX关了吗"，如果已关就直接确认"已关闭"，不要画蛇添足问"需要关闭吗"；如果没关则告知并问是否需要关闭\n' +
      '10. 门锁状态用"开/关"描述，不要用"已解锁/已锁定"，如"大门已关闭""门开着"\n' +
      '11. 必须完整列出所有开着的设备，不能遗漏任何一种设备类型（灯、空调、门锁等都要提到）\n' +
      '12. 根据用户语境判断建议方向：用户说"出门""离开""走了"等表示要离开时，对开着的设备建议关闭而非打开；用户说"回家""回来了"等表示要回来时，对关着的设备建议打开\n' +
      '\n请直接回复总结内容，不要加前缀或标号。';

    const httpRequest = http.createHttp();
    try {
      const llmMessage: LLMMessage = { role: 'user', content: prompt };
      const messages: LLMMessage[] = [llmMessage];
      const reqBody: LLMRequest = {
        model: LLM_MODEL,
        messages: messages,
        temperature: 0.5,
        max_tokens: 150
      };
      const response = await httpRequest.request(`${LLM_BASE_URL}/chat/completions`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${LLM_API_KEY}`,
          'Content-Type': 'application/json'
        },
        extraData: JSON.stringify(reqBody),
        connectTimeout: 8000,
        readTimeout: 8000
      });

      const resultText = response.result as string;
      if (resultText) {
        const respObj: Record<string, Object> = JSON.parse(resultText);
        const choices = respObj['choices'] as Array<Record<string, Object>>;
        if (choices && choices.length > 0) {
          const message = choices[0]['message'] as Record<string, string>;
          const content: string = (message['content'] || '').trim();
          if (content) return content;
        }
      }
      return rawStatus;
    } catch (err) {
      console.error('润色设备状态回复失败', JSON.stringify(err));
      return rawStatus;
    } finally {
      httpRequest.destroy();
    }
  }

  static async fetchSensorData(queryType: string): Promise<string> {
    const token: string = AppStorage.get<string>('token') || '';
    if (!token) return '未登录';
    try {
      const deviceResp = await ApiClient.get('/device/list', token);
      if ((deviceResp.code !== 200 && deviceResp.code !== 0) || !deviceResp.data) return '查询失败';
      const devices: Array<Record<string, Object>> = deviceResp.data as Array<Record<string, Object>>;
      let sensorId: number = 0;
      for (let i = 0; i < devices.length; i++) {
        if (devices[i]['deviceType'] === 'temp_humi_sensor') {
          sensorId = devices[i]['deviceId'] as number;
          break;
        }
      }
      if (sensorId === 0) return '未找到温湿度传感器';

      const latestResp = await ApiClient.get(`/device/latest/${sensorId}`, token);
      if ((latestResp.code !== 200 && latestResp.code !== 0) || !latestResp.data) return '查询传感器数据失败';
      const data: Record<string, number> = latestResp.data as Record<string, number>;
      const parts: string[] = [];
      if ((queryType === 'temperature' || queryType === 'both') && data['temperature'] !== undefined) {
        parts.push(`当前温度是${data['temperature']}度`);
      }
      if ((queryType === 'humidity' || queryType === 'both') && data['humidity'] !== undefined) {
        parts.push(`当前湿度是${data['humidity']}%`);
      }
      return parts.length > 0 ? parts.join('，') : '暂无数据';
    } catch (err) {
      return '查询失败';
    }
  }

  static getPageFriendlyName(page: string): string {
    const nameMap: Record<string, string> = {
      'HomePage': '首页',
      'LightPage': '灯光页面',
      'AcPage': '空调页面',
      'DoorPage': '门锁页面',
      'ProfilePage': '个人中心',
      'MessagePage': '消息页面',
      'FamilyPage': '家庭管理'
    };
    return nameMap[page] || page;
  }

  static extractRoom(text: string): string {
    const rooms: string[] = ['卧室', '客厅', '厨房', '书房', '浴室', '阳台', '主卧', '次卧', '餐厅'];
    for (let i = 0; i < rooms.length; i++) {
      if (text.includes(rooms[i])) return rooms[i];
    }
    return '';
  }

  static extractDeviceName(text: string): string {
    const numMap: Record<string, string> = {
      '一': '1', '二': '2', '三': '3', '四': '4', '五': '5',
      '六': '6', '七': '7', '八': '8', '九': '9', '十': '10'
    };

    let match: RegExpMatchArray | null = null;

    match = text.match(/([一二三四五六七八九十\d]+)号灯/);
    if (match) return numMap[match[1]] || match[1];

    match = text.match(/灯([一二三四五六七八九十\d]+)/);
    if (match) return numMap[match[1]] || match[1];

    match = text.match(/第([一二三四五六七八九十\d]+)个灯/);
    if (match) return numMap[match[1]] || match[1];

    match = text.match(/([一二三四五六七八九十\d]+)号门/);
    if (match) return numMap[match[1]] || match[1];

    match = text.match(/门([一二三四五六七八九十\d]+)/);
    if (match) return numMap[match[1]] || match[1];

    return '';
  }

  static extractFamilyName(text: string): string {
    const match: RegExpMatchArray | null = text.match(/切换(到|为)?(.+?)(家庭|的家)/);
    if (match && match[2]) return match[2].trim();
    return '';
  }

  static parseIntent(text: string): IntentResult {
    const t: string = text.toLowerCase();
    const room: string = IntentService.extractRoom(t);
    const isOn: boolean = t.includes('打开') || t.includes('开启') || t.includes('开灯') || t.includes('开空调') || t.includes('开门') || t.includes('解锁');
    const isOff: boolean = t.includes('关闭') || t.includes('关掉') || t.includes('关灯') || t.includes('关空调') || t.includes('关门') || t.includes('锁门') || t.includes('关上');
    const isQueryStatus: boolean = t.includes('关了吗') || t.includes('开了吗') || t.includes('状态') || t.includes('是不是开') || t.includes('是不是关') || t.includes('有没有开') || t.includes('有没有关') || t.includes('锁了吗') || t.includes('解锁了吗') || ((t.includes('查') && (t.includes('灯') || t.includes('空调') || t.includes('门'))) && !isOn && !isOff);

    const deviceName: string = IntentService.extractDeviceName(t);

    if (t.includes('几点') || t.includes('时间') || t.includes('现在几点') || t.includes('什么时候')) {
      return { action: 'query_time', timeQueryType: 'time', reply: '正在为您查询时间' };
    }
    if (t.includes('星期') || t.includes('周几')) {
      return { action: 'query_time', timeQueryType: 'weekday', reply: '正在为您查询星期' };
    }
    if (t.includes('几号') || t.includes('日期') || t.includes('今天几号')) {
      return { action: 'query_time', timeQueryType: 'date', reply: '正在为您查询日期' };
    }

    const leaveHome: boolean = t.includes('出门') || t.includes('离家') || t.includes('走了') || t.includes('我走了') || t.includes('我出门了') || t.includes('我离开了') || (t.includes('离开') && !t.includes('返回'));
    const arriveHome: boolean = t.includes('回来了') || t.includes('到家了') || t.includes('我回来了') || t.includes('我到家了') || t.includes('回家啦');

    if (leaveHome && !isQueryStatus) {
      const cmds: IntentResult[] = [
        { action: 'control_device', deviceType: 'light', room: '', operation: 'off', reply: '已关闭全部灯光' },
        { action: 'control_device', deviceType: 'ac', room: '', operation: 'off', reply: '已关闭全部空调' },
        { action: 'control_device', deviceType: 'door', room: '', operation: 'close', reply: '已关闭全部门锁' }
      ];
      return { action: 'multi_command', multiCommands: cmds, reply: '好的，已为您关闭所有设备，注意安全' };
    }
    if (arriveHome) {
      const cmds: IntentResult[] = [
        { action: 'control_device', deviceType: 'light', room: '', operation: 'on', reply: '已打开全部灯光' },
        { action: 'control_device', deviceType: 'ac', room: '', operation: 'on', reply: '已打开全部空调' }
      ];
      return { action: 'multi_command', multiCommands: cmds, reply: '欢迎回家，已为您打开灯光和空调' };
    }

    if (t.includes('灯') || t.includes('灯光') || t.includes('灯泡') || t.includes('照明')) {
      if (isQueryStatus) {
        return { action: 'query_device_status', deviceType: 'light', room: room, reply: '正在为您查询灯光状态' };
      }
      if (isOn) {
        const result: IntentResult = { action: 'control_device', deviceType: 'light', room: room, operation: 'on', reply: deviceName ? `已打开${deviceName}` : (room ? `已为您打开${room}灯光` : '已为您打开灯光') };
        if (deviceName) result.deviceName = deviceName;
        return result;
      }
      if (isOff) {
        const result: IntentResult = { action: 'control_device', deviceType: 'light', room: room, operation: 'off', reply: deviceName ? `已关闭${deviceName}` : (room ? `已为您关闭${room}灯光` : '已为您关闭灯光') };
        if (deviceName) result.deviceName = deviceName;
        return result;
      }
      return { action: 'navigate', page: 'LightPage', reply: '已为您打开灯光页面' };
    }

    if (t.includes('空调') || t.includes('冷气') || t.includes('暖气')) {
      if (isQueryStatus) {
        return { action: 'query_device_status', deviceType: 'ac', room: room, reply: '正在为您查询空调状态' };
      }
      const acParams: Record<string, Object> = {};
      let hasAcParam: boolean = false;
      const detailParts: string[] = [];

      const tempTargetMatch: RegExpMatchArray | null = t.match(/(?:调低|调高|降低|升高|设|设置).*?(\d+)\s*[度℃°]/);
      const tempDeltaMatch: RegExpMatchArray | null = t.match(/(?:调低|降低)\s*(\d+)\s*度(?!.*到)/);
      const tempDeltaUpMatch: RegExpMatchArray | null = t.match(/(?:调高|升高)\s*(\d+)\s*度(?!.*到)/);
      const hasTargetTemp: boolean = t.includes('调低到') || t.includes('调高到') || t.includes('降到') || t.includes('升到') || t.includes('设为') || t.includes('设置为') || t.includes('调到');

      if (hasTargetTemp && tempTargetMatch) {
        const temp: number = parseInt(tempTargetMatch[1], 10);
        if (temp >= 16 && temp <= 30) {
          acParams['temp'] = temp;
          hasAcParam = true;
          detailParts.push(`温度设为${temp}度`);
        }
      } else if (tempDeltaMatch) {
        const delta: number = parseInt(tempDeltaMatch[1], 10);
        acParams['temp_delta'] = -delta;
        hasAcParam = true;
        detailParts.push(`调低${delta}度`);
      } else if (tempDeltaUpMatch) {
        const delta: number = parseInt(tempDeltaUpMatch[1], 10);
        acParams['temp_delta'] = delta;
        hasAcParam = true;
        detailParts.push(`调高${delta}度`);
      } else if (t.includes('调低') || t.includes('降低')) {
        acParams['temp_delta'] = -1;
        hasAcParam = true;
        detailParts.push('调低1度');
      } else if (t.includes('调高') || t.includes('升高')) {
        acParams['temp_delta'] = 1;
        hasAcParam = true;
        detailParts.push('调高1度');
      } else {
        const tempMatch: RegExpMatchArray | null = t.match(/(\d+)\s*[度℃°]/);
        if (tempMatch) {
          const temp: number = parseInt(tempMatch[1], 10);
          if (temp >= 16 && temp <= 30) {
            acParams['temp'] = temp;
            hasAcParam = true;
            detailParts.push(`温度${temp}度`);
          }
        }
      }

      if (t.includes('制冷')) { acParams['mode'] = 'cool'; hasAcParam = true; detailParts.push('制冷模式'); }
      else if (t.includes('制热')) { acParams['mode'] = 'heat'; hasAcParam = true; detailParts.push('制热模式'); }
      else if (t.includes('除湿')) { acParams['mode'] = 'dry'; hasAcParam = true; detailParts.push('除湿模式'); }
      else if (t.includes('送风') && !t.includes('风速')) { acParams['mode'] = 'fan'; hasAcParam = true; detailParts.push('送风模式'); }
      else if (t.includes('自动模式')) { acParams['mode'] = 'auto'; hasAcParam = true; detailParts.push('自动模式'); }

      if (t.includes('低风速') || t.includes('风速低')) { acParams['fan_speed'] = 'low'; hasAcParam = true; detailParts.push('低风速'); }
      else if (t.includes('高风速') || t.includes('风速高') || t.includes('风速调高')) { acParams['fan_speed'] = 'high'; hasAcParam = true; detailParts.push('高风速'); }
      else if (t.includes('中风速') || t.includes('风速中')) { acParams['fan_speed'] = 'medium'; hasAcParam = true; detailParts.push('中风速'); }

      if (t.includes('下风向') || t.includes('风向下')) { acParams['wind_direction'] = 'down'; hasAcParam = true; detailParts.push('下风向'); }
      else if (t.includes('上风向') || t.includes('风向朝上')) { acParams['wind_direction'] = 'up'; hasAcParam = true; detailParts.push('上风向'); }

      const hasClose: boolean = t.includes('关闭') || t.includes('取消') || t.includes('关掉') || t.includes('停止');
      const closeSweep: boolean = hasClose && t.includes('扫风');
      if (closeSweep) { acParams['swing'] = false; hasAcParam = true; detailParts.push('关闭扫风'); }
      else if (t.includes('扫风')) { acParams['swing'] = true; hasAcParam = true; detailParts.push('开启扫风'); }

      const closeSleep: boolean = hasClose && t.includes('睡眠');
      if (closeSleep) { acParams['sleep_mode'] = false; hasAcParam = true; detailParts.push('关闭睡眠模式'); }
      else if (t.includes('睡眠')) { acParams['sleep_mode'] = true; hasAcParam = true; detailParts.push('开启睡眠模式'); }

      const closeEco: boolean = (hasClose && (t.includes('节能') || t.includes('省电')));
      if (closeEco) { acParams['eco_mode'] = false; hasAcParam = true; detailParts.push('关闭节能模式'); }
      else if (t.includes('节能') || t.includes('省电')) { acParams['eco_mode'] = true; hasAcParam = true; detailParts.push('开启节能模式'); }

      const isCloseFeature: boolean = closeSweep || closeSleep || closeEco;

      if (isOff && !hasAcParam) {
        return { action: 'control_device', deviceType: 'ac', room: room, operation: 'off', reply: room ? `已为您关闭${room}空调` : '已为您关闭空调' };
      }
      if (isOn && !hasAcParam) {
        return { action: 'control_device', deviceType: 'ac', room: room, operation: 'on', reply: room ? `已为您打开${room}空调` : '已为您打开空调' };
      }
      if (hasAcParam) {
        const result: IntentResult = { action: 'control_device', deviceType: 'ac', room: room, operation: 'update_settings', reply: room ? `已为您设置${room}空调` : '已为您设置空调' };
        result.acParams = acParams;
        result.reply += `，${detailParts.join('、')}`;
        return result;
      }
      return { action: 'navigate', page: 'AcPage', reply: '已为您打开空调页面' };
    }

    if (t.includes('门') || t.includes('门锁') || t.includes('大门')) {
      if (isQueryStatus) {
        return { action: 'query_device_status', deviceType: 'door', room: room, reply: '正在为您查询门锁状态' };
      }
      if (isOn || t.includes('打开') || t.includes('解锁')) {
        return { action: 'control_device', deviceType: 'door', room: room, operation: 'open', reply: room ? `正在为您开${room}门` : '正在为您开门' };
      }
      if (isOff || t.includes('关闭') || t.includes('锁门') || t.includes('锁上')) {
        return { action: 'control_device', deviceType: 'door', room: room, operation: 'close', reply: room ? `正在为您关${room}门` : '正在为您关门' };
      }
      return { action: 'navigate', page: 'DoorPage', reply: '已为您打开门锁页面' };
    }

    if (t.includes('设备') && isQueryStatus) {
      return { action: 'query_device_status', deviceType: '', room: room, reply: '正在为您查询所有设备状态' };
    }

    if (t.includes('设备') && (isOn || isOff)) {
      const op: string = isOn ? 'on' : 'off';
      const cmds: IntentResult[] = [
        { action: 'control_device', deviceType: 'light', room: room, operation: op, reply: room ? `已${isOn ? '开启' : '关闭'}${room}灯光` : `已${isOn ? '开启' : '关闭'}全部灯光` },
        { action: 'control_device', deviceType: 'ac', room: room, operation: op, reply: room ? `已${isOn ? '开启' : '关闭'}${room}空调` : `已${isOn ? '开启' : '关闭'}全部空调` },
        { action: 'control_device', deviceType: 'door', room: room, operation: op === 'on' ? 'open' : 'close', reply: room ? `已${op === 'on' ? '打开' : '关闭'}${room}门锁` : `已${op === 'on' ? '打开' : '关闭'}全部门锁` }
      ];
      return { action: 'multi_command', multiCommands: cmds, reply: `已为您${isOn ? '开启' : '关闭'}所有设备` };
    }

    if (t.includes('昵称') || t.includes('名字') || t.includes('改昵称') || t.includes('修改昵称') || t.includes('改名字')) {
      const nicknameMatch: RegExpMatchArray | null = text.match(/(?:昵称|名字)(?:改为|改成|修改为|设为|换成|为|叫)\s*(.+)/);
      const editValue: string = nicknameMatch ? nicknameMatch[1].trim() : '';
      return { action: 'navigate', page: 'ProfilePage', editField: 'nickname', editValue: editValue, reply: editValue ? `已为您修改昵称为${editValue}` : '已为您打开昵称修改' };
    }

    if (t.includes('手机号') || t.includes('手机号码') || t.includes('电话号码') || t.includes('改手机号') || t.includes('修改手机号') || t.includes('修改电话')) {
      const phoneMatch: RegExpMatchArray | null = text.match(/(?:手机号|手机号码|电话号码|电话|手机)(?:改为|改成|修改为|设为|换成|绑定为|为)\s*(\d{11})/);
      const editValue: string = phoneMatch ? phoneMatch[1].trim() : '';
      return { action: 'navigate', page: 'ProfilePage', editField: 'phone', editValue: editValue, reply: editValue ? `已为您修改手机号为${editValue}` : '已为您打开手机号修改' };
    }

    if (t.includes('我的') || t.includes('个人') || t.includes('用户') || t.includes('个人中心')) {
      return { action: 'navigate', page: 'ProfilePage', reply: '已为您打开个人页面' };
    }

    if (t.includes('设备')) {
      return { action: 'navigate', page: 'HomePage', reply: '已为您打开首页' };
    }

    if (t.includes('消息') || t.includes('通知')) {
      if (t.includes('完整') || t.includes('详细') || t.includes('全文') || t.includes('完整内容') || t.includes('详细内容')) {
        const senderMatch: RegExpMatchArray | null = text.match(/(.+?)发来的/);
        const sender: string = senderMatch ? senderMatch[1].trim() : '';
        return { action: 'read_message_detail', messageSender: sender, reply: '正在为您读取消息完整内容' };
      }
      if (t.includes('最新') || t.includes('什么消息') || t.includes('读') || t.includes('什么') || t.includes('是谁') || t.includes('发了')) {
        const senderMatch: RegExpMatchArray | null = text.match(/(.+?)发来的/);
        const sender: string = senderMatch ? senderMatch[1].trim() : '';
        return { action: 'read_message', messageSender: sender, reply: sender ? `正在为您查找${sender}的最新消息` : '正在为您读取最新消息' };
      }
      return { action: 'navigate', page: 'MessagePage', reply: '已为您打开消息页面' };
    }

    if (t.includes('切换家庭') || t.includes('换家庭')) {
      const familyName: string = IntentService.extractFamilyName(t);
      return { action: 'switch_family', familyName: familyName, reply: familyName ? `正在为您切换到${familyName}` : '正在为您查询家庭信息' };
    }
    if (t.includes('家庭页面') || t.includes('家庭管理') || t.includes('打开家庭')) {
      return { action: 'navigate', page: 'FamilyPage', reply: '已为您打开家庭管理页面' };
    }
    if (t.includes('当前家庭') || t.includes('现在的家庭') || t.includes('哪个家庭')) {
      return { action: 'query_current_family', reply: '正在为您查询当前家庭' };
    }
    if (t.includes('家庭') && !t.includes('智能家居')) {
      return { action: 'navigate', page: 'FamilyPage', reply: '已为您打开家庭管理页面' };
    }

    if (t.includes('返回') || t.includes('回去') || t.includes('返回上一页')) {
      return { action: 'navigate', page: 'back', reply: '已为您返回上一页' };
    }

    if (t.includes('首页') || t.includes('主页') || t.includes('回家')) {
      return { action: 'navigate', page: 'HomePage', reply: '已为您回到首页' };
    }

    const hasTemp: boolean = t.includes('温度') || t.includes('多少度') || t.includes('几度') || t.includes('气温');
    const hasHumi: boolean = t.includes('湿度') || t.includes('潮湿') || t.includes('干燥');
    if (hasTemp && hasHumi) {
      return { action: 'query', queryType: 'both', reply: '正在为您查询温湿度' };
    }
    if (hasTemp) {
      return { action: 'query', queryType: 'temperature', reply: '正在为您查询温度' };
    }
    if (hasHumi) {
      return { action: 'query', queryType: 'humidity', reply: '正在为您查询湿度' };
    }

    return { action: 'unknown', reply: '抱歉，我没有理解您的指令' };
  }
}