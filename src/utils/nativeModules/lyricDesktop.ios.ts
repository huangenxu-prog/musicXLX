// iOS does not support Android-style floating desktop lyrics or overlay
// permission management. Keep the shared API available without exposing an
// unsupported native module.
export const setSendLyricTextEvent = async(_isSend: boolean): Promise<void> => {}
export const showDesktopLyricView = async(_options: {
  isShowToggleAnima: boolean
  isSingleLine: boolean
  width: number
  maxLineNum: number
  isLock: boolean
  unplayColor: string
  playedColor: string
  shadowColor: string
  opacity: number
  textSize: number
  positionX: number
  positionY: number
  textPositionX: string
  textPositionY: string
}): Promise<void> => {}
export const hideDesktopLyricView = async(): Promise<void> => {}
export const play = async(_time: number): Promise<void> => {}
export const pause = async(): Promise<void> => {}
export const setLyric = async(_lyric: string, _translation: string, _romalrc: string): Promise<void> => {}
export const setPlaybackRate = async(_rate: number): Promise<void> => {}
export const toggleTranslation = async(_isShowTranslation: boolean): Promise<void> => {}
export const toggleRoma = async(_isShowRoma: boolean): Promise<void> => {}
export const toggleLock = async(_isLock: boolean): Promise<void> => {}
export const setColor = async(_unplayColor: string, _playedColor: string, _shadowColor: string): Promise<void> => {}
export const setAlpha = async(_alpha: number): Promise<void> => {}
export const setTextSize = async(_size: number): Promise<void> => {}
export const setShowToggleAnima = async(_isShowToggleAnima: boolean): Promise<void> => {}
export const setSingleLine = async(_isSingleLine: boolean): Promise<void> => {}
export const setPosition = async(_x: number, _y: number): Promise<void> => {}
export const setMaxLineNum = async(_maxLineNum: number): Promise<void> => {}
export const setWidth = async(_width: number): Promise<void> => {}
export const setLyricTextPosition = async(_textX: string, _textY: string): Promise<void> => {}
export const checkOverlayPermission = async(): Promise<void> => {}
export const openOverlayPermissionActivity = async(): Promise<void> => {}
export const onPositionChange = (_handler: (position: { x: number, y: number }) => void): (() => void) => () => {}
export const onLyricLinePlay = (_handler: (lineInfo: { text: string, extendedLyrics: string[] }) => void): (() => void) => () => {}
