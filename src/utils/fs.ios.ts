import RNFS from 'react-native-fs'
import { Buffer } from '@craftzdog/react-native-buffer'
import pako from 'pako'
import { NativeModules } from 'react-native'
import type { Encoding, FileType, HashAlgorithm, OpenDocumentOptions } from 'react-native-file-system'

export type { FileType }

const documentRoot = RNFS.DocumentDirectoryPath
const cacheRoot = RNFS.CachesDirectoryPath

export const temporaryDirectoryPath = cacheRoot
export const externalStorageDirectoryPath = documentRoot
export const privateStorageDirectoryPath = documentRoot

const getName = (path: string) => path.replace(/\\/+$/, '').split('/').pop() ?? path
const getParent = (path: string) => path.replace(/\\/+$/, '').split('/').slice(0, -1).join('/') || '/'

const toFileType = (item: {
  path: string
  name?: string
  size?: number
  mtime?: Date | null
  isFile?: () => boolean
  isDirectory?: () => boolean
}): FileType => ({
  path: item.path,
  name: item.name ?? getName(item.path),
  size: item.size ?? 0,
  lastModified: item.mtime?.getTime() ?? 0,
  isFile: item.isFile?.() ?? false,
  isDirectory: item.isDirectory?.() ?? false,
  canRead: true,
  data: item.path,
  mimeType: '',
})

export const extname = (name: string) => name.lastIndexOf('.') > 0 ? name.substring(name.lastIndexOf('.') + 1) : ''

// iOS apps have no Android-style shared-storage root. The app's Documents
// directory is the user-visible import/export area exposed by this adapter.
export const getExternalStoragePaths = async(_isRemovable?: boolean): Promise<string[]> => [documentRoot]

export const selectManagedFolder = async(_isPersist: boolean = false): Promise<FileType> => toFileType({
  path: documentRoot,
  name: 'Documents',
  isDirectory: () => true,
})

export const removeManagedFolder = async(_path: string): Promise<void> => {}
export const getManagedFolders = async(): Promise<string[]> => [documentRoot]
export const getPersistedUriList = async(): Promise<string[]> => [documentRoot]

// The Android Storage Access Framework has no direct iOS equivalent. Until the
// native UIDocumentPicker bridge is added, the system picker deliberately
// rejects so the app can fall back to its in-app Documents browser.
export const selectFile = async(_options: OpenDocumentOptions): Promise<FileType> => {
  const picker = NativeModules.LXDocumentPicker
  if (!picker?.pickFile) throw new Error('iOS document picker is not installed yet')
  return picker.pickFile(_options)
}

export const readDir = async(path: string): Promise<FileType[]> => {
  const items = await RNFS.readDir(path)
  return items.map(item => toFileType(item))
}

export const unlink = async(path: string): Promise<boolean> => {
  await RNFS.unlink(path)
  return true
}

export const mkdir = async(path: string): Promise<FileType> => {
  await RNFS.mkdir(path)
  return stat(path)
}

export const stat = async(path: string): Promise<FileType> => {
  const item = await RNFS.stat(path)
  return toFileType({
    path: item.path,
    name: getName(item.path),
    size: Number(item.size),
    mtime: item.mtime,
    isFile: () => item.isFile(),
    isDirectory: () => item.isDirectory(),
  })
}

export const hash = async(path: string, algorithm: HashAlgorithm): Promise<string> => {
  return RNFS.hash(path, algorithm as 'md5' | 'sha1' | 'sha256' | 'sha512')
}

export const readFile = async(path: string, encoding: Encoding = 'utf8'): Promise<string> => {
  return RNFS.readFile(path, encoding)
}

export const moveFile = async(fromPath: string, toPath: string): Promise<boolean> => {
  await RNFS.moveFile(fromPath, toPath)
  return true
}

export const gzipFile = async(fromPath: string, toPath: string): Promise<void> => {
  const source = Buffer.from(await RNFS.readFile(fromPath, 'base64'), 'base64')
  const compressed = pako.gzip(source)
  await RNFS.writeFile(toPath, Buffer.from(compressed).toString('base64'), 'base64')
}

export const unGzipFile = async(fromPath: string, toPath: string): Promise<void> => {
  const source = Buffer.from(await RNFS.readFile(fromPath, 'base64'), 'base64')
  const decompressed = pako.ungzip(source)
  await RNFS.writeFile(toPath, Buffer.from(decompressed).toString('base64'), 'base64')
}

export const gzipString = async(data: string, encoding: Encoding = 'utf8'): Promise<string> => {
  const source = Buffer.from(data, encoding)
  return Buffer.from(pako.gzip(source)).toString('base64')
}

export const unGzipString = async(data: string, encoding: Encoding = 'utf8'): Promise<string> => {
  const source = Buffer.from(data, 'base64')
  const decompressed = Buffer.from(pako.ungzip(source))
  return decompressed.toString(encoding)
}

export const existsFile = async(path: string): Promise<boolean> => RNFS.exists(path)

export const rename = async(path: string, name: string): Promise<boolean> => {
  await RNFS.moveFile(path, `${getParent(path)}/${name}`)
  return true
}

export const writeFile = async(path: string, data: string, encoding: Encoding = 'utf8'): Promise<void> => {
  await RNFS.writeFile(path, data, encoding)
}

export const appendFile = async(path: string, data: string, encoding: Encoding = 'utf8'): Promise<void> => {
  await RNFS.appendFile(path, data, encoding)
}

export const downloadFile = (
  url: string,
  path: string,
  options: Omit<RNFS.DownloadFileOptions, 'fromUrl' | 'toFile'> = {},
) => RNFS.downloadFile({
  fromUrl: url,
  toFile: path,
  ...options,
  headers: options.headers ?? {
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile',
  },
})

export const stopDownload = (jobId: number) => RNFS.stopDownload(jobId)
