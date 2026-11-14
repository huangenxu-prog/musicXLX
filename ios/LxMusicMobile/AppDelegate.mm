#import "AppDelegate.h"
#import <ReactNativeNavigation/ReactNativeNavigation.h>
#import <React/RCTBundleURLProvider.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <string.h>
#import <React/RCTUtils.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <Security/Security.h>

static NSData *LXBase64Data(NSString *value) {
  return [[NSData alloc] initWithBase64EncodedString:value ?: @"" options:NSDataBase64DecodingIgnoreUnknownCharacters] ?: [NSData data];
}

static NSString *LXBase64String(NSData *data) {
  return [data base64EncodedStringWithOptions:0] ?: @"";
}

static NSString *LXMD5(NSString *value) {
  NSString *source = value ?: @"";
  NSString *decoded = [source stringByRemovingPercentEncoding] ?: source;
  NSData *input = [decoded dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char digest[CC_MD5_DIGEST_LENGTH];
  CC_MD5(input.bytes, (CC_LONG)input.length, digest);
  NSMutableString *result = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
  for (NSUInteger i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [result appendFormat:@"%02x", digest[i]];
  return result;
}

static NSString *LXAES(NSString *data, NSString *key, NSString *iv, NSString *mode) {
  NSData *input = LXBase64Data(data);
  NSData *keyData = LXBase64Data(key);
  NSData *ivData = LXBase64Data(iv);
  BOOL cbc = [mode containsString:@"CBC"];
  // Android's Cipher.getInstance("AES") defaults to ECB with PKCS5 padding.
  // CommonCrypto's PKCS7 padding is byte-compatible with PKCS5 for AES.
  CCOptions options = kCCOptionPKCS7Padding;
  if (!cbc) options |= kCCOptionECBMode;
  unsigned char ivBytes[kCCBlockSizeAES128] = {0};
  if (cbc && ivData.length > 0) memcpy(ivBytes, ivData.bytes, MIN(ivData.length, sizeof(ivBytes)));
  size_t outputCapacity = input.length + kCCBlockSizeAES128;
  NSMutableData *output = [NSMutableData dataWithLength:outputCapacity];
  size_t outputLength = 0;
  CCCryptorStatus status = CCCrypt(kCCEncrypt, kCCAlgorithmAES, options,
    keyData.bytes, keyData.length, cbc ? ivBytes : NULL,
    input.bytes, input.length, output.mutableBytes, outputCapacity, &outputLength);
  if (status != kCCSuccess) return @"";
  output.length = outputLength;
  return LXBase64String(output);
}

static BOOL LXReadASN1Length(const uint8_t *bytes, NSUInteger total, NSUInteger *offset, NSUInteger *length) {
  if (*offset >= total) return NO;
  uint8_t first = bytes[(*offset)++];
  if ((first & 0x80) == 0) { *length = first; return YES; }
  NSUInteger count = first & 0x7f;
  if (count == 0 || count > sizeof(NSUInteger) || *offset + count > total) return NO;
  NSUInteger value = 0;
  for (NSUInteger i = 0; i < count; i++) value = (value << 8) | bytes[(*offset)++];
  *length = value;
  return YES;
}

static NSData *LXRSAPublicKeyFromX509(NSData *x509) {
  const uint8_t *bytes = x509.bytes;
  NSUInteger total = x509.length, offset = 0, length = 0;
  if (total < 8 || bytes[offset++] != 0x30 || !LXReadASN1Length(bytes, total, &offset, &length)) return nil;
  if (offset >= total || bytes[offset++] != 0x30 || !LXReadASN1Length(bytes, total, &offset, &length)) return nil;
  if (offset + length > total) return nil;
  offset += length;
  if (offset >= total || bytes[offset++] != 0x03 || !LXReadASN1Length(bytes, total, &offset, &length)) return nil;
  if (length < 2 || offset + length > total || bytes[offset] != 0x00) return nil;
  offset++;
  return [NSData dataWithBytes:bytes + offset length:length - 1];
}

static NSString *LXRSANoPaddingEncrypt(NSString *data, NSString *publicKeyBase64) {
  NSData *rawKey = LXRSAPublicKeyFromX509(LXBase64Data(publicKeyBase64));
  if (rawKey == nil) return @"";
  NSDictionary *attributes = @{
    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
    (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic
  };
  CFErrorRef keyError = NULL;
  SecKeyRef publicKey = SecKeyCreateWithData((__bridge CFDataRef)rawKey, (__bridge CFDictionaryRef)attributes, &keyError);
  if (publicKey == NULL) {
    if (keyError) CFRelease(keyError);
    return @"";
  }
  NSData *input = LXBase64Data(data);
  CFErrorRef encryptError = NULL;
  CFDataRef encrypted = SecKeyCreateEncryptedData(publicKey, kSecKeyAlgorithmRSAEncryptionRaw, (__bridge CFDataRef)input, &encryptError);
  CFRelease(publicKey);
  if (keyError) CFRelease(keyError);
  if (encrypted == NULL) {
    if (encryptError) CFRelease(encryptError);
    return @"";
  }
  NSString *result = LXBase64String((__bridge_transfer NSData *)encrypted);
  if (encryptError) CFRelease(encryptError);
  return result;
}

@interface LXUserApiModule : RCTEventEmitter <RCTBridgeModule>
@property(nonatomic, strong) JSContext *jsContext;
@property(nonatomic, copy) NSString *runtimeKey;
@property(nonatomic, assign) BOOL didSendInit;
@end

@implementation LXUserApiModule

RCT_EXPORT_MODULE(UserApiModule)

- (NSArray<NSString *> *)supportedEvents {
  return @[@"api-action"];
}

- (dispatch_queue_t)methodQueue {
  static dispatch_queue_t queue;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    queue = dispatch_queue_create("com.lxmusic.userapi", DISPATCH_QUEUE_SERIAL);
  });
  return queue;
}

- (void)emitAction:(NSString *)action data:(NSString *)data {
  if (action.length == 0) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([action isEqualToString:@"init"]) {
      if (self.didSendInit) return;
      self.didSendInit = YES;
    }
    [self sendEventWithName:@"api-action" body:@{@"action": action, @"data": data ?: @""}];
  });
}

- (void)emitLog:(NSString *)type message:(NSString *)message {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self sendEventWithName:@"api-action" body:@{@"action": @"log", @"type": type ?: @"log", @"log": message ?: @""}];
  });
}

- (void)failInitialization:(NSString *)message {
  NSDictionary *payload = @{@"info": [NSNull null], @"status": @NO, @"errorMessage": message ?: @"Create JavaScript Env Failed"};
  NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  NSString *jsonString = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.didSendInit) {
      self.didSendInit = YES;
      [self sendEventWithName:@"api-action" body:@{@"action": @"init", @"errorMessage": message ?: @"Create JavaScript Env Failed", @"data": jsonString}];
    }
    [self sendEventWithName:@"api-action" body:@{@"action": @"log", @"type": @"error", @"log": message ?: @"Unknown JavaScript error"}];
  });
}

- (void)callJS:(NSString *)action data:(id)data {
  JSContext *context = self.jsContext;
  if (context == nil) return;
  JSValue *function = context[@"__lx_native__"];
  if (function == nil || function.isUndefined) return;
  NSMutableArray *arguments = [NSMutableArray arrayWithObjects:self.runtimeKey ?: @"", action ?: @"", nil];
  if (data != nil && data != [NSNull null]) [arguments addObject:data];
  [function callWithArguments:arguments];
}

RCT_EXPORT_METHOD(loadScript:(NSDictionary *)info) {
  [self destroyContext];
  self.didSendInit = NO;
  self.runtimeKey = NSUUID.UUID.UUIDString;
  JSContext *context = [[JSContext alloc] init];
  self.jsContext = context;
  __weak typeof(self) weakSelf = self;

  context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
    NSString *message = exception.toString ?: @"JavaScript runtime exception";
    [weakSelf emitLog:@"error" message:message];
    if (!weakSelf.didSendInit) [weakSelf failInitialization:message];
  };

  context[@"__lx_native_call__"] = ^(NSString *key, NSString *action, NSString *data) {
    if (![key isEqualToString:weakSelf.runtimeKey]) return;
    [weakSelf emitAction:action data:data];
  };
  context[@"__lx_native_call__utils_str2b64"] = ^NSString *(NSString *value) {
    NSString *source = value ?: @"";
    return LXBase64String([source dataUsingEncoding:NSUTF8StringEncoding]);
  };
  context[@"__lx_native_call__utils_b642buf"] = ^NSString *(NSString *value) {
    NSData *data = LXBase64Data(value);
    NSMutableArray *bytes = [NSMutableArray arrayWithCapacity:data.length];
    const uint8_t *buffer = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) [bytes addObject:@(buffer[i])];
    NSData *json = [NSJSONSerialization dataWithJSONObject:bytes options:0 error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
  };
  context[@"__lx_native_call__utils_str2md5"] = ^NSString *(NSString *value) {
    return LXMD5(value ?: @"");
  };
  context[@"__lx_native_call__utils_aes_encrypt"] = ^NSString *(NSString *data, NSString *key, NSString *iv, NSString *mode) {
    return LXAES(data ?: @"", key ?: @"", iv ?: @"", mode ?: @"");
  };
  context[@"__lx_native_call__utils_rsa_encrypt"] = ^NSString *(NSString *data, NSString *key, NSString *padding) {
    if ([padding isEqualToString:@"RSA/ECB/NoPadding"]) return LXRSANoPaddingEncrypt(data ?: @"", key ?: @"");
    return @"";
  };
  context[@"__lx_native_call__set_timeout"] = ^(NSNumber *identifier, NSNumber *delay) {
    NSTimeInterval interval = MAX(0, delay.doubleValue) / 1000.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), weakSelf.methodQueue, ^{
      [weakSelf callJS:@"__set_timeout__" data:identifier ?: @0];
    });
  };

  JSValue *console = [JSValue valueWithNewObjectInContext:context];
  console[@"log"] = ^(JSValue *value) { [weakSelf emitLog:@"log" message:value.toString]; };
  console[@"warn"] = ^(JSValue *value) { [weakSelf emitLog:@"warn" message:value.toString]; };
  console[@"error"] = ^(JSValue *value) { [weakSelf emitLog:@"error" message:value.toString]; };
  context[@"console"] = console;

  NSString *preloadPath = [[NSBundle mainBundle] pathForResource:@"user-api-preload" ofType:@"js"];
  NSError *readError = nil;
  NSString *preload = preloadPath ? [NSString stringWithContentsOfFile:preloadPath encoding:NSUTF8StringEncoding error:&readError] : nil;
  if (preload.length == 0) {
    [self failInitialization:readError.localizedDescription ?: @"Cannot load user-api-preload.js"];
    return;
  }

  [context evaluateScript:preload];
  JSValue *setup = context[@"lx_setup"];
  if (setup == nil || setup.isUndefined) {
    [self failInitialization:@"LX preload did not define lx_setup"];
    return;
  }

  NSString *script = [info[@"script"] isKindOfClass:[NSString class]] ? info[@"script"] : @"";
  NSArray *setupArguments = @[
    self.runtimeKey,
    info[@"id"] ?: @"",
    info[@"name"] ?: @"Unknown",
    info[@"description"] ?: @"",
    info[@"version"] ?: @"",
    info[@"author"] ?: @"",
    info[@"homepage"] ?: @"",
    script
  ];
  [setup callWithArguments:setupArguments];
  [context evaluateScript:script];
}

RCT_EXPORT_METHOD(sendAction:(NSString *)action info:(NSString *)info)
{
  [self callJS:action data:info];
}

RCT_EXPORT_METHOD(destroy)
{
  [self destroyContext];
}

- (void)destroyContext {
  if (self.jsContext != nil) {
    self.jsContext[@"__lx_native_call__"] = nil;
    self.jsContext = nil;
  }
  self.runtimeKey = nil;
}

@end


static NSData *LXDERLength(NSUInteger length) {
  if (length < 128) {
    uint8_t singleByte = (uint8_t)length;
    return [NSData dataWithBytes:&singleByte length:1];
  }
  uint8_t bytes[sizeof(NSUInteger)];
  NSUInteger count = 0, value = length;
  while (value > 0) { bytes[sizeof(bytes) - 1 - count++] = (uint8_t)(value & 0xff); value >>= 8; }
  uint8_t lengthHeader = (uint8_t)(0x80 | count);
  NSMutableData *result = [NSMutableData dataWithBytes:&lengthHeader length:1];
  [result appendBytes:bytes + sizeof(bytes) - count length:count];
  return result;
}

static NSData *LXDERWrap(uint8_t tag, NSData *content) {
  NSMutableData *result = [NSMutableData dataWithBytes:&tag length:1];
  [result appendData:LXDERLength(content.length)];
  [result appendData:content];
  return result;
}

static NSData *LXRSAPublicX509FromPKCS1(NSData *raw) {
  const uint8_t oidBytes[] = {0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00};
  NSData *algorithm = LXDERWrap(0x30, [NSData dataWithBytes:oidBytes length:sizeof(oidBytes)]);
  uint8_t unusedBits = 0x00;
  NSMutableData *bitStringContent = [NSMutableData dataWithBytes:&unusedBits length:1];
  [bitStringContent appendData:raw];
  NSData *bitString = LXDERWrap(0x03, bitStringContent);
  NSMutableData *outer = [NSMutableData dataWithData:algorithm];
  [outer appendData:bitString];
  return LXDERWrap(0x30, outer);
}

static NSData *LXRSAPrivatePKCS8FromPKCS1(NSData *raw) {
  const uint8_t versionBytes[] = {0x02,0x01,0x00};
  const uint8_t oidBytes[] = {0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00};
  NSData *version = [NSData dataWithBytes:versionBytes length:sizeof(versionBytes)];
  NSData *algorithm = LXDERWrap(0x30, [NSData dataWithBytes:oidBytes length:sizeof(oidBytes)]);
  NSData *privateKey = LXDERWrap(0x04, raw);
  NSMutableData *outer = [NSMutableData dataWithData:version];
  [outer appendData:algorithm];
  [outer appendData:privateKey];
  return LXDERWrap(0x30, outer);
}

static NSData *LXRSAPrivateKeyFromPKCS8(NSData *pkcs8) {
  const uint8_t *bytes = pkcs8.bytes;
  NSUInteger total = pkcs8.length, offset = 0, length = 0;
  if (total < 16 || bytes[offset++] != 0x30 || !LXReadASN1Length(bytes, total, &offset, &length)) return nil;
  if (offset >= total || bytes[offset++] != 0x02 || !LXReadASN1Length(bytes, total, &offset, &length)) return nil;
  if (offset + length > total) return nil;
  offset += length;
  if (offset >= total || bytes[offset++] != 0x30 || !LXReadASN1Length(bytes, total, &offset, &length)) return nil;
  if (offset + length > total) return nil;
  offset += length;
  if (offset >= total || bytes[offset++] != 0x04 || !LXReadASN1Length(bytes, total, &offset, &length)) return nil;
  if (offset + length > total) return nil;
  return [NSData dataWithBytes:bytes + offset length:length];
}

static NSString *LXRSACrypt(NSString *dataBase64, NSString *keyBase64, NSString *padding, BOOL encrypt) {
  NSData *encodedKey = LXBase64Data(keyBase64);
  NSData *rawKey = encrypt ? LXRSAPublicKeyFromX509(encodedKey) : LXRSAPrivateKeyFromPKCS8(encodedKey);
  if (rawKey == nil) return @"";
  NSDictionary *attributes = @{
    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
    (__bridge id)kSecAttrKeyClass: (__bridge id)(encrypt ? kSecAttrKeyClassPublic : kSecAttrKeyClassPrivate)
  };
  CFErrorRef keyError = NULL;
  SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)rawKey, (__bridge CFDictionaryRef)attributes, &keyError);
  if (key == NULL) {
    if (keyError) CFRelease(keyError);
    return @"";
  }
  SecKeyAlgorithm algorithm = [padding isEqualToString:@"RSA/ECB/OAEPWithSHA1AndMGF1Padding"]
    ? kSecKeyAlgorithmRSAEncryptionOAEPSHA1
    : kSecKeyAlgorithmRSAEncryptionRaw;
  SecKeyOperationType operation = encrypt ? kSecKeyOperationTypeEncrypt : kSecKeyOperationTypeDecrypt;
  if (!SecKeyIsAlgorithmSupported(key, operation, algorithm)) {
    CFRelease(key);
    if (keyError) CFRelease(keyError);
    return @"";
  }
  NSData *input = LXBase64Data(dataBase64);
  CFErrorRef operationError = NULL;
  CFDataRef output = encrypt
    ? SecKeyCreateEncryptedData(key, algorithm, (__bridge CFDataRef)input, &operationError)
    : SecKeyCreateDecryptedData(key, algorithm, (__bridge CFDataRef)input, &operationError);
  CFRelease(key);
  if (keyError) CFRelease(keyError);
  if (output == NULL) {
    if (operationError) CFRelease(operationError);
    return @"";
  }
  NSData *resultData = (__bridge_transfer NSData *)output;
  if (operationError) CFRelease(operationError);
  return encrypt ? LXBase64String(resultData) : ([[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding] ?: @"");
}

static NSString *LXAESDecrypt(NSString *data, NSString *key, NSString *iv, NSString *mode) {
  NSData *input = LXBase64Data(data);
  NSData *keyData = LXBase64Data(key);
  NSData *ivData = LXBase64Data(iv);
  BOOL cbc = [mode containsString:@"CBC"];
  CCOptions options = cbc ? kCCOptionPKCS7Padding : kCCOptionECBMode;
  if (cbc) options |= kCCOptionPKCS7Padding;
  unsigned char ivBytes[kCCBlockSizeAES128] = {0};
  if (cbc && ivData.length > 0) memcpy(ivBytes, ivData.bytes, MIN(ivData.length, sizeof(ivBytes)));
  size_t outputCapacity = input.length + kCCBlockSizeAES128;
  NSMutableData *output = [NSMutableData dataWithLength:outputCapacity];
  size_t outputLength = 0;
  CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES, options,
    keyData.bytes, keyData.length, cbc ? ivBytes : NULL,
    input.bytes, input.length, output.mutableBytes, outputCapacity, &outputLength);
  if (status != kCCSuccess) return @"";
  output.length = outputLength;
  return [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *LXSHA1(NSString *value) {
  NSData *input = [(value ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char digest[CC_SHA1_DIGEST_LENGTH];
  CC_SHA1(input.bytes, (CC_LONG)input.length, digest);
  NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
  for (NSUInteger i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [result appendFormat:@"%02x", digest[i]];
  return result;
}

static NSDictionary *LXGenerateRSAKeyPair(void) {
  NSDictionary *privateAttributes = @{(__bridge id)kSecAttrIsPermanent: @NO};
  NSDictionary *attributes = @{
    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
    (__bridge id)kSecAttrKeySizeInBits: @2048,
    (__bridge id)kSecPrivateKeyAttrs: privateAttributes
  };
  CFErrorRef error = NULL;
  SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
  if (privateKey == NULL) {
    if (error) CFRelease(error);
    return nil;
  }
  SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
  CFErrorRef publicError = NULL, privateError = NULL;
  NSData *publicRaw = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(publicKey, &publicError);
  NSData *privateRaw = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(privateKey, &privateError);
  CFRelease(publicKey);
  CFRelease(privateKey);
  if (error) CFRelease(error);
  if (publicError) CFRelease(publicError);
  if (privateError) CFRelease(privateError);
  if (publicRaw == nil || privateRaw == nil) return nil;
  return @{
    @"publicKey": LXBase64String(LXRSAPublicX509FromPKCS1(publicRaw)),
    @"privateKey": LXBase64String(LXRSAPrivatePKCS8FromPKCS1(privateRaw))
  };
}

@interface LXCryptoModule : NSObject <RCTBridgeModule>
@end

@implementation LXCryptoModule

RCT_EXPORT_MODULE(CryptoModule)

RCT_EXPORT_METHOD(generateRsaKey:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  NSDictionary *keys = LXGenerateRSAKeyPair();
  if (keys == nil) reject(@"E_RSA_KEYGEN", @"Unable to generate RSA key pair", nil);
  else resolve(keys);
}

RCT_EXPORT_METHOD(rsaEncrypt:(NSString *)text key:(NSString *)key padding:(NSString *)padding resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  NSString *result = LXRSACrypt(text, key, padding, YES);
  if (result.length == 0) reject(@"E_RSA_ENCRYPT", @"RSA encryption failed", nil);
  else resolve(result);
}

RCT_EXPORT_METHOD(rsaDecrypt:(NSString *)text key:(NSString *)key padding:(NSString *)padding resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  NSString *result = LXRSACrypt(text, key, padding, NO);
  if (result.length == 0) reject(@"E_RSA_DECRYPT", @"RSA decryption failed", nil);
  else resolve(result);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(rsaEncryptSync:(NSString *)text key:(NSString *)key padding:(NSString *)padding) {
  return LXRSACrypt(text, key, padding, YES);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(rsaDecryptSync:(NSString *)text key:(NSString *)key padding:(NSString *)padding) {
  return LXRSACrypt(text, key, padding, NO);
}

RCT_EXPORT_METHOD(aesEncrypt:(NSString *)text key:(NSString *)key iv:(NSString *)iv mode:(NSString *)mode resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  NSString *result = LXAES(text, key, iv, mode);
  if (result.length == 0) reject(@"E_AES_ENCRYPT", @"AES encryption failed", nil);
  else resolve(result);
}

RCT_EXPORT_METHOD(aesDecrypt:(NSString *)text key:(NSString *)key iv:(NSString *)iv mode:(NSString *)mode resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  NSString *result = LXAESDecrypt(text, key, iv, mode);
  if (result.length == 0) reject(@"E_AES_DECRYPT", @"AES decryption failed", nil);
  else resolve(result);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(aesEncryptSync:(NSString *)text key:(NSString *)key iv:(NSString *)iv mode:(NSString *)mode) {
  return LXAES(text, key, iv, mode);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(aesDecryptSync:(NSString *)text key:(NSString *)key iv:(NSString *)iv mode:(NSString *)mode) {
  return LXAESDecrypt(text, key, iv, mode);
}

RCT_EXPORT_METHOD(sha1:(NSString *)input resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  resolve(LXSHA1(input));
}

@end

@interface LXScreenControlModule : NSObject <RCTBridgeModule>
@end

@implementation LXScreenControlModule

RCT_EXPORT_MODULE(LXScreenControlModule)

RCT_EXPORT_METHOD(setIdleTimerDisabled:(BOOL)disabled)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [UIApplication sharedApplication].idleTimerDisabled = disabled;
  });
}

@end

@interface LXDocumentPickerModule : NSObject <RCTBridgeModule, UIDocumentPickerDelegate>
@property(nonatomic, copy) RCTPromiseResolveBlock resolve;
@property(nonatomic, copy) RCTPromiseRejectBlock reject;
@property(nonatomic, copy) NSString *targetPath;
@end

@implementation LXDocumentPickerModule

RCT_EXPORT_MODULE(LXDocumentPicker)

RCT_REMAP_METHOD(pickFile,
                 pickFileWithOptions:(NSDictionary *)options
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.resolve != nil) {
      reject(@"E_PICKER_BUSY", @"A document selection is already in progress", nil);
      return;
    }

    self.resolve = resolve;
    self.reject = reject;
    self.targetPath = [options[@"toPath"] isKindOfClass:[NSString class]] ? options[@"toPath"] : nil;

    UIDocumentPickerViewController *picker = nil;
    if (@available(iOS 14.0, *)) {
      NSMutableArray<UTType *> *types = [NSMutableArray array];
      NSArray *extensions = [options[@"extTypes"] isKindOfClass:[NSArray class]] ? options[@"extTypes"] : @[];
      for (id extension in extensions) {
        if (![extension isKindOfClass:[NSString class]]) continue;
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if (type != nil) [types addObject:type];
      }
      NSArray *mimeTypes = [options[@"mimeTypes"] isKindOfClass:[NSArray class]] ? options[@"mimeTypes"] : @[];
      for (id mimeType in mimeTypes) {
        if (![mimeType isKindOfClass:[NSString class]]) continue;
        UTType *type = [UTType typeWithMIMEType:mimeType];
        if (type != nil) [types addObject:type];
      }
      if (types.count == 0) [types addObject:UTTypeItem];
      picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    } else {
      picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
    }

    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    UIViewController *presenter = RCTPresentedViewController();
    if (presenter == nil) {
      self.resolve = nil;
      self.reject = nil;
      reject(@"E_PICKER_PRESENT", @"No active view controller is available", nil);
      return;
    }
    [presenter presentViewController:picker animated:YES completion:nil];
  });
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
  NSURL *sourceURL = urls.firstObject;
  if (sourceURL == nil) {
    [self finishWithValue:nil];
    return;
  }

  BOOL accessed = [sourceURL startAccessingSecurityScopedResource];
  NSError *error = nil;
  NSString *destinationPath = nil;

  if (self.targetPath.length > 0) {
    NSString *extension = sourceURL.pathExtension;
    destinationPath = extension.length > 0
      ? [self.targetPath stringByAppendingPathExtension:extension]
      : self.targetPath;
  } else {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importsDirectory = [directory stringByAppendingPathComponent:@"Imports"];
    [[NSFileManager defaultManager] createDirectoryAtPath:importsDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    if (error == nil) destinationPath = [importsDirectory stringByAppendingPathComponent:sourceURL.lastPathComponent];
  }

  if (error == nil && destinationPath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:nil];
    NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
    [[NSFileManager defaultManager] copyItemAtURL:sourceURL toURL:destinationURL error:&error];
  } else if (error == nil) {
    error = [NSError errorWithDomain:@"LXDocumentPicker" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid destination path"}];
  }

  if (accessed) [sourceURL stopAccessingSecurityScopedResource];

  if (error != nil) {
    [self finishWithError:error];
    return;
  }

  NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:destinationPath error:nil];
  NSString *fileName = destinationPath.lastPathComponent ?: sourceURL.lastPathComponent;
  NSDate *modified = attributes[NSFileModificationDate] ?: [NSDate date];
  NSDictionary *result = @{
    @"path": destinationPath,
    @"name": fileName,
    @"size": attributes[NSFileSize] ?: @0,
    @"lastModified": @([modified timeIntervalSince1970] * 1000.0),
    @"isFile": @YES,
    @"isDirectory": @NO,
    @"canRead": @YES,
    @"data": destinationPath,
    @"mimeType": @""
  };
  [self finishWithValue:result];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
  [self finishWithValue:nil];
}

- (void)finishWithValue:(id)value
{
  RCTPromiseResolveBlock resolve = self.resolve;
  self.resolve = nil;
  self.reject = nil;
  self.targetPath = nil;
  if (resolve != nil) resolve(value);
}

- (void)finishWithError:(NSError *)error
{
  RCTPromiseRejectBlock reject = self.reject;
  self.resolve = nil;
  self.reject = nil;
  self.targetPath = nil;
  if (reject != nil) reject(@"E_PICKER_COPY", error.localizedDescription, error);
}

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  RCTBridge *bridge = [[RCTBridge alloc] initWithDelegate:self launchOptions:launchOptions];
  [ReactNativeNavigation bootstrapWithBridge:bridge];
  self.initialProps = @{};
  return YES;
}

- (NSArray<id<RCTBridgeModule>> *)extraModulesForBridge:(RCTBridge *)bridge {
  return [ReactNativeNavigation extraModulesForBridge:bridge];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self getBundleURL];
}
- (NSURL *)getBundleURL
{
#if DEBUG
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

@end
