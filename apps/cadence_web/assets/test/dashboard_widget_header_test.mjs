import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {announceCadencePopoverOpened, preservesPopoverOpenState, subscribeToLegacyOverlayOpen} from "../vue/ui/reka/popover_compatibility.js"

const ledger = ["composition", "toggle-position-panel", "outside-escape-focus", "global-coordination", "identity-update", "teardown"]
assert.equal(ledger.length, 6)
assert.equal(process.versions.node, "24.16.0")
const dir = dirname(fileURLToPath(import.meta.url))
const paths = ["../vue/DashboardWidgetHeader.vue", "../vue/DashboardWidget.vue", "../../lib/cadence_web/live/ops_dashboard_show_live/components.ex", "../vue/ui/reka/CadencePopover.vue"].map((p) => resolve(dir, p))
const [source, parent, host, adapter] = await Promise.all(paths.map((p) => readFile(p, "utf8")))
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
assert.ok(template)
assert.match(source, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.equal(template.match(/<CadencePopover\b/g)?.length, 1)
assert.doesNotMatch(source, /DASHBOARD_WIDGET_HEADER_CONTROLLER|onMounted|onBeforeUpdate|onUpdated|onBeforeUnmount|phx-hook/)
assert.match(template, /:id="props\.presentation\.actions\.details\.overlay\.id"/)
assert.match(template, /:identity="props\.presentation\.actions\.details\.overlay\.id"/)
assert.match(template, /v-bind="props\.presentation\.actions\.details\.overlay\.attrs"/)
assert.match(template, /:id="props\.presentation\.actions\.details\.trigger\.id"/)
assert.match(template, /:id="props\.presentation\.actions\.details\.panel\.id"/)
assert.match(template, /:hidden="!open"/)
assert.match(source, /delete attrs\.hidden/)
assert.match(parent, /<DashboardWidgetHeader :presentation="composition\.header" \/>/)
const widgetHost = host.match(/def widget\(assigns\) do[\s\S]*?def widget_presentation\(assigns\) do/)?.[0]
assert.ok(widgetHost)
assert.equal(widgetHost.match(/<\.vue/g)?.length, 1)
assert.match(widgetHost, /v-component="DashboardWidget"[\s\S]*v-ssr=\{false\}/)
assert.match(adapter, /:modal="false"|modal="false"/)
assert.match(adapter, /position-strategy="fixed"/)
assert.match(adapter, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(adapter, /@interact-outside="handleInteractOutside"/)
assert.match(adapter, /preservesPopoverOpenState\(open\.value, previousIdentity, nextIdentity\)/)
assert.equal(preservesPopoverOpenState(true, "details", "details"), true)
assert.equal(preservesPopoverOpenState(true, "details", "replacement"), false)

class FakeWindow extends EventTarget { CustomEvent = class extends Event { constructor(type, options) { super(type); this.detail = options.detail } } }
const windowObject = new FakeWindow()
const nested = {}
const owner = {contains: (node) => node === nested}
let closes = 0
const remove = subscribeToLegacyOverlayOpen(windowObject, owner, () => (closes += 1))
announceCadencePopoverOpened(windowObject, nested)
assert.equal(closes, 0)
announceCadencePopoverOpened(windowObject, {id: "peer"})
assert.equal(closes, 1)
remove()
announceCadencePopoverOpened(windowObject, {id: "after-teardown"})
assert.equal(closes, 1)
console.log("dashboard_widget_header_test passed")
