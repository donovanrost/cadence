import "../../../../frontend/apps/host/src/shell/federation-lifecycle.js"
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {getHooks} from "live_vue"
import {withImmediateVueUnmount} from "../../../../frontend/apps/host/src/shell/live-vue-lifecycle"
import {createLiveToastHook} from "../../deps/live_toast"

const Hooks = {
  LiveToast: createLiveToastHook()
}

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

import("../vue.ts").then(({default: liveVueApp}) => {
  const VueHooks = getHooks(liveVueApp)
  VueHooks.VueHook = withImmediateVueUnmount(VueHooks.VueHook)
  const liveSocket = new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: {...Hooks, ...VueHooks}
  })
  liveSocket.connect()
  window.liveSocket = liveSocket
})
