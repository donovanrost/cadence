import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {getHooks} from "live_vue"
import liveVueApp from "../vue"
import {createLiveToastHook} from "../../deps/live_toast"

const Hooks = {
  LiveToast: createLiveToastHook()
}

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...Hooks, ...getHooks(liveVueApp)}
})

liveSocket.connect()

window.liveSocket = liveSocket
