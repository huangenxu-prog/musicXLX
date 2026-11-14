import RNFS from 'react-native-fs'

export interface MusicMetadata {
  albumName: string
  singer: string
  name: string
}

export interface MusicMetadataFull {
  type: 'mp3' | 'flac' | 'ogg' | 'wav'
  bitrate: string
  interval: number
  size: number
  ext: 'mp3' | 'flac' | 'ogg' | 'wav'
  albumName: string
  singer: string
  name: string
}

// The upstream metadata package currently ships Android native code only.
// Return null on iOS so callers use the filename-based local-track fallback.
export const readMetadata = async(_filePath: string): Promise<MusicMetadataFull | null> => null

export const writeMetadata = async(
  _filePath: string,
  _metadata: MusicMetadata,
  _isOverwrite = false,
): Promise<void> => {
  throw new Error('Writing embedded audio metadata is not supported on iOS')
}

export const readPic = async(_filePath: string, _picDir: string): Promise<string> => ''

export const writePic = async(_filePath: string, _picPath: string): Promise<void> => {
  throw new Error('Writing embedded album artwork is not supported on iOS')
}

export const readLyric = async(filePath: string, isReadLrcFile = true): Promise<string> => {
  if (!isReadLrcFile) return ''
  const lyricPath = filePath.replace(/\\.[^./\\]+$/, '') + '.lrc'
  if (!(await RNFS.exists(lyricPath))) return ''
  return RNFS.readFile(lyricPath, 'utf8')
}

export const writeLyric = async(filePath: string, lyric: string): Promise<void> => {
  const lyricPath = filePath.replace(/\\.[^./\\]+$/, '') + '.lrc'
  await RNFS.writeFile(lyricPath, lyric, 'utf8')
}
