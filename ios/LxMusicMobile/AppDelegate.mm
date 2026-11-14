#import "AppDelegate.h"
#import <ReactNativeNavigation/ReactNativeNavigation.h>
#import <React/RCTBundleURLProvider.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTUtils.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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
