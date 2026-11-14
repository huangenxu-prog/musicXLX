import RNFS from 'react-native-fs'

const cacheRoot = RNFS.CachesDirectoryPath

const getSize = async(path: string): Promise<number> => {
  const items = await RNFS.readDir(path)
  let size = 0
  for (const item of items) {
    if (item.isDirectory()) size += await getSize(item.path)
    else size += Number(item.size) || 0
  }
  return size
}

export const getAppCacheSize = async(): Promise<number> => getSize(cacheRoot)

export const clearAppCache = async(): Promise<void> => {
  const items = await RNFS.readDir(cacheRoot)
  await Promise.all(items.map(async item => {
    await RNFS.unlink(item.path)
  }))
}
