// import needle from 'needle'
// import progress from 'request-progress'
import BackgroundTimer from 'react-native-background-timer'

const defaultHeaders = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
}
// var proxyUrl = "http://" + user + ":" + password + "@" + host + ":" + port;
// var proxiedRequest = request.defaults({'proxy': proxyUrl});

const handleRequestData = async({
  method = 'get',
  headers = {},
  format = 'json',
  credentials = 'omit',
  cache = 'default',
  ...options
}) => {
  // console.log(url, options)
  headers = Object.assign({
    Accept: 'application/json',
  }, headers)
  const contentTypeEntry = Object.entries(headers).find(([name]) => name.toLowerCase() === 'content-type')
  // User source scripts may provide form fields with or without an explicit
  // Content-Type. Always serialize them before passing the request to fetch.
  if (options.form != null) {
    if (!contentTypeEntry) headers['Content-Type'] = 'application/x-www-form-urlencoded'
    options.body = Object.entries(options.form)
      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value == null ? '' : String(value))}`)
      .join('&')
    delete options.form
  } else if (options.formData != null) {
    // React Native fetch requires an actual FormData instance, not a plain object.
    const formData = new global.FormData()
    for (const [key, value] of Object.entries(options.formData)) {
      if (Array.isArray(value)) {
        for (const entry of value) formData.append(key, entry)
      } else {
        formData.append(key, value)
      }
    }
    options.body = formData
    delete options.formData
    // The native fetch layer must generate the multipart boundary itself.
    for (const name of Object.keys(headers)) {
      if (name.toLowerCase() === 'content-type') delete headers[name]
    }
  } else if (method.toLowerCase() === 'post' && !contentTypeEntry && options.body != null && typeof options.body !== 'string') {
    headers['Content-Type'] = 'application/json'
  }
  const contentType = Object.entries(headers).find(([name]) => name.toLowerCase() === 'content-type')?.[1]
  if (options.formData == null && typeof contentType === 'string' && contentType.toLowerCase().includes('application/json') && options.body != null && typeof options.body !== 'string' && !(options.body instanceof global.FormData)) {
    options.body = JSON.stringify(options.body)
  }

  return {
    ...options,
    method,
    credentials,
    cache,
    headers: Object.assign({}, defaultHeaders, headers),
  }
}

// https://stackoverflow.com/a/64945178
const blobToBuffer = (blob) => {
  return new Promise((resolve, reject) => {
    const reader = new global.FileReader()
    reader.onerror = reject
    reader.onload = () => {
      const data = reader.result.slice(reader.result.indexOf('base64,') + 7)
      resolve(Buffer.from(data, 'base64'))
    }
    reader.readAsDataURL(blob)
  })
}

export const fetchData = (url, { timeout = 13_000, ...options } = {}) => {
  // console.log('---start---', url)

  const controller = new global.AbortController()
  let id = BackgroundTimer.setTimeout(() => {
    id = null
    controller.abort()
  }, timeout)

  return {
    request: handleRequestData(options).then(options => {
      return global.fetch(url, {
        ...options,
        signal: controller.signal,
      }).then(resp => (options.binary ? resp.blob() : resp.text()).then(text => {
        // console.log(options, headers, text)
        return {
          headers: resp.headers?.map ?? Object.fromEntries(resp.headers?.entries?.() ?? []),
          body: text,
          statusCode: resp.status,
          statusMessage: resp.statusText,
          url: resp.url,
          ok: resp.ok,
        }
      })).then(resp => {
        if (options.binary) {
          return blobToBuffer(resp.body).then(buffer => {
            resp.body = buffer
            return resp
          })
        } else {
          try {
            resp.body = JSON.parse(resp.body)
          } catch {}
          return resp
        }
      }).catch(err => {
        // console.log(err, err.code, err.message)
        return Promise.reject(err)
      })
    }).finally(() => {
      if (id == null) return
      BackgroundTimer.clearTimeout(id)
    }),
    abort() {
      controller.abort()
    },
  }
}
