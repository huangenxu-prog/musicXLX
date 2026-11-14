import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react'
import {
  Animated,
  Easing,
  Modal,
  Pressable,
  StyleSheet,
  View,
  useWindowDimensions,
  type ColorValue,
  type ReactNode,
  type StyleProp,
  type ViewStyle,
} from 'react-native'
import { type COMPONENT_IDS } from '@/config/constant'

interface Props {
  visibleNavNames?: COMPONENT_IDS[]
  widthPercentage: number
  widthPercentageMax?: number
  drawerWidth?: number
  drawerPosition?: 'left' | 'right'
  drawerBackgroundColor?: ColorValue
  renderNavigationView: () => ReactNode
  children?: ReactNode
  style?: StyleProp<ViewStyle>
}

export interface DrawerLayoutFixedType {
  openDrawer: () => void
  closeDrawer: () => void
  fixWidth: () => void
}

const DrawerLayoutFixed = forwardRef<DrawerLayoutFixedType, Props>(({
  widthPercentage,
  widthPercentageMax,
  drawerWidth: requestedWidth,
  drawerPosition = 'left',
  drawerBackgroundColor,
  renderNavigationView,
  children,
  style,
}, ref) => {
  const { width: windowWidth } = useWindowDimensions()
  const [visible, setVisible] = useState(false)
  const progress = useRef(new Animated.Value(0)).current
  const drawerWidth = requestedWidth ?? Math.min(
    Math.floor(windowWidth * widthPercentage),
    widthPercentageMax ?? windowWidth,
  )
  const hiddenOffset = drawerPosition === 'right' ? drawerWidth : -drawerWidth

  const openDrawer = useCallback(() => {
    if (visible) return
    progress.setValue(0)
    setVisible(true)
  }, [progress, visible])

  const closeDrawer = useCallback(() => {
    if (!visible) return
    Animated.timing(progress, {
      toValue: 0,
      duration: 220,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true,
    }).start(({ finished }) => {
      if (finished) setVisible(false)
    })
  }, [progress, visible])

  const fixWidth = useCallback(() => {}, [])

  useImperativeHandle(ref, () => ({
    openDrawer,
    closeDrawer,
    fixWidth,
  }), [openDrawer, closeDrawer, fixWidth])

  useEffect(() => {
    if (!visible) return
    Animated.timing(progress, {
      toValue: 1,
      duration: 240,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true,
    }).start()
  }, [progress, visible])

  const translateX = progress.interpolate({
    inputRange: [0, 1],
    outputRange: [hiddenOffset, 0],
  })
  const backdropOpacity = progress.interpolate({
    inputRange: [0, 1],
    outputRange: [0, 0.42],
  })

  return (
    <View style={[styles.container, style]}>
      {children}
      <Modal
        visible={visible}
        transparent
        animationType="none"
        onRequestClose={closeDrawer}
      >
        <View style={styles.modal}>
          <Pressable style={StyleSheet.absoluteFill} onPress={closeDrawer} />
          <Animated.View
            pointerEvents="none"
            style={[StyleSheet.absoluteFill, styles.backdrop, { opacity: backdropOpacity }]}
          />
          <Animated.View
            style={[
              styles.drawer,
              drawerPosition === 'right' ? styles.right : styles.left,
              {
                width: drawerWidth,
                backgroundColor: drawerBackgroundColor ?? '#FFFFFF',
                transform: [{ translateX }],
              },
            ]}
          >
            {renderNavigationView()}
          </Animated.View>
        </View>
      </Modal>
    </View>
  )
})

const styles = StyleSheet.create({
  container: {
    flex: 1,
    width: '100%',
  },
  modal: {
    flex: 1,
  },
  backdrop: {
    backgroundColor: '#000000',
  },
  drawer: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    elevation: 12,
    shadowColor: '#000000',
    shadowOpacity: 0.2,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 4 },
  },
  left: {
    left: 0,
  },
  right: {
    right: 0,
  },
})

export default DrawerLayoutFixed
