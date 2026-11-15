import { Platform, SafeAreaView } from 'react-native'
import Content from './Content'
import PlayerBar from '@/components/player/PlayerBar'

export default () => {
  return (
    <>
      <Content />
      {Platform.OS === 'ios'
        ? <SafeAreaView><PlayerBar isHome /></SafeAreaView>
        : <PlayerBar isHome />
      }
    </>
  )
}
