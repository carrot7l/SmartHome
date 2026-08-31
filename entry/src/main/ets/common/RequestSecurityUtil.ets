import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export class RequestSecurityUtil {
  private static SECURITY_VERSION: string = '1';
  private static KEY_ID: string = 'app-session-v1';
  private static fallbackCounter: number = 0;

  static buildHeaders(headers: Record<string, string>, token: string): Record<string, string> {
    if (token.trim() !== '') {
      headers['Authorization'] = 'Bearer ' + token.trim();
    }
    headers['X-Request-ID'] = RequestSecurityUtil.createRequestId();
    headers['X-Timestamp'] = String(Date.now());
    headers['X-Nonce'] = RequestSecurityUtil.createRandomHex(16);
    headers['X-Security-Version'] = RequestSecurityUtil.SECURITY_VERSION;
    headers['X-Key-ID'] = RequestSecurityUtil.KEY_ID;
    headers['Cache-Control'] = 'no-store';
    headers['Pragma'] = 'no-cache';
    return headers;
  }

  static createRequestId(): string {
    return String(Date.now()) + '-' + RequestSecurityUtil.createRandomHex(12);
  }

  static createRandomHex(byteLength: number): string {
    try {
      const random: cryptoFramework.Random = cryptoFramework.createRandom();
      const data: cryptoFramework.DataBlob = random.generateRandomSync(byteLength);
      return RequestSecurityUtil.bytesToHex(data.data);
    } catch (err) {
      RequestSecurityUtil.fallbackCounter += 1;
      return String(Date.now()) + '-' + String(RequestSecurityUtil.fallbackCounter);
    }
  }

  private static bytesToHex(bytes: Uint8Array): string {
    const hexChars: string[] = [];
    for (let i: number = 0; i < bytes.length; i++) {
      const byte: number = bytes[i];
      const hex: string = byte.toString(16).padStart(2, '0');
      hexChars.push(hex);
    }
    return hexChars.join('');
  }
}