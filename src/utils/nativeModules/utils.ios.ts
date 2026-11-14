import { AppState, Dimensions, NativeModules, Share } from 'react-native'

const screenControl = NativeModules.LXScreenControlModule
const deviceInfo = NativeModules.LXDeviceInfoModule
const notificationModule = NativeModules.LXNotificationModule

// iOS does not allow applications to terminate themselves programmatically.
export const exitApp = () => {}
export const getSupportedAbis = async(): Promise<string[]> => []
export const installApk = async(_filePath: string, _fileProviderAuthority: string): Promise<void> => {
  throw new Error('APK installation is Android-only')
}

export const screenkeepAwake = () => {
  screenControl?.setIdleTimerDisabled?.(true)
}
export const screenUnkeepAwake = () => {
  screenControl?.setIdleTimerDisabled?.(false)
}

export const getWIFIIPV4Address = async(): Promise<string> => {
  return deviceInfo?.getWIFIIPV4Address ? deviceInfo.getWIFIIPV4Address() : ''
}
export const getDeviceName = async(): Promise<string> => {
  return deviceInfo?.getDeviceName ? deviceInfo.getDeviceName() : 'iOS Device'
}

export const isNotificationsEnabled = async(): Promise<boolean> => {
  return notificationModule?.isNotificationsEnabled ? notificationModule.isNotificationsEnabled() : false
}
export const requestNotificationPermission = async(): Promise<boolean> => {
  return notificationModule?.requestNotificationPermission ? notificationModule.requestNotificationPermission() : false
}

export const shareText = async(_shareTitle: string, title: string, text: string): Promise<void> => {
  await Share.share({ title, message: text })
}

export const getSystemLocales = async(): Promise<string> => {
  return Intl.DateTimeFormat().resolvedOptions().locale || 'en'
}

export const onScreenStateChange = (handler: (state: 'ON' | 'OFF') => void): (() => void) => {
  const subscription = AppState.addEventListener('change', state => {
    handler(state === 'active' ? 'ON' : 'OFF')
  })
  return () => {
    subscription.remove()
  }
}

export const getWindowSize = async(): Promise<{ width: number, height: number }> => {
  const { width, height } = Dimensions.get('window')
  return { width, height }
}

export const onWindowSizeChange = (handler: (size: { width: number, height: number }) => void): (() => void) => {
  const subscription = Dimensions.addEventListener('change', ({ window }) => {
    handler({ width: window.width, height: window.height })
  })
  return () => {
    subscription.remove()
  }
}

export const isIgnoringBatteryOptimization = async(): Promise<boolean> => false
export const requestIgnoreBatteryOptimization = async(): Promise<boolean> => false
