module.exports = {
  dependencies: {
    // These packages are Android-only. iOS uses the platform adapters under src/.
    'react-native-file-system': {
      platforms: {
        ios: null,
      },
    },
    'react-native-local-media-metadata': {
      platforms: {
        ios: null,
      },
    },
  },
}
