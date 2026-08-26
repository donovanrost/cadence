import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import test from "node:test"
import {fileURLToPath} from "node:url"

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const uiPath = resolve(testDirectory, "../../lib/cadence_web/components/ui.ex")

const componentSource = async (name) => readFile(resolve(vueDirectory, name), "utf8")

test("both account dropdown SFCs use only the narrow first-party Reka boundary", async () => {
  for (const name of ["NotificationsBell.vue", "UserMenu.vue"]) {
    const source = await componentSource(name)

    assert.match(source, /import AccountDropdownMenu from "\.\/ui\/reka\/AccountDropdownMenu\.vue"/)
    assert.match(source, /import CadenceMenuItem from "\.\/ui\/reka\/CadenceMenuItem\.vue"/)
    assert.match(source, /<AccountDropdownMenu :class="presentation\.root\.class">/)
    assert.match(source, /#trigger="\{open\}"/)
    assert.match(source, /:aria-expanded="String\(open\)"/)
    assert.match(source, /#content="\{open, onItemSelect\}"/)
    assert.match(source, /:active="open"/)
    assert.match(source, /@select="onItemSelect"/)
    assert.match(source, /<template>/)
    assert.match(source, /v-bind="presentation\./)
    assert.doesNotMatch(source, /phx-hook|dropdown_controller|from "reka-ui"/)
    assert.doesNotMatch(
      source,
      /["']\/(?:session|admin-mode|admin)["']|_csrf_token|_method|platform_admin/,
    )
  }
})

test("notifications renderer preserves server-owned menu and navigation attrs", async () => {
  const source = await componentSource("NotificationsBell.vue")

  assert.match(source, /:id="presentation\.menu\.id"/)
  assert.match(source, /v-bind="presentation\.trigger\.attrs"/)
  assert.match(source, /v-bind="notification\.link\.attrs"/)
  assert.match(source, /v-bind="presentation\.menu\.footer\.attrs"/)
  assert.equal(source.match(/<CadenceMenuItem\b/g)?.length, 2)
  assert.equal(source.match(/<a\b/g)?.length, 2)
  assert.doesNotMatch(source, /9\+|No notifications|See all notifications/)
})

test("user-menu renderer preserves server-owned forms, hidden fields, and actions", async () => {
  const source = await componentSource("UserMenu.vue")

  assert.match(source, /v-bind="organization\.form\.attrs"/)
  assert.match(source, /organization\.form\.hidden_fields/)
  assert.match(source, /v-bind="presentation\.menu\.admin_action\.attrs"/)
  assert.match(source, /presentation\.menu\.leave_admin_mode\.hidden_fields/)
  assert.match(source, /presentation\.menu\.sign_out\.hidden_fields/)
  assert.equal(source.match(/<form\b/g)?.length, 3)
  assert.equal(source.match(/<input\b/g)?.length, 3)
  assert.equal(source.match(/<button\b/g)?.length, 4)
  assert.equal(source.match(/<a\b/g)?.length, 1)
  assert.equal(source.match(/<CadenceMenuItem\b/g)?.length, 4)
  assert.doesNotMatch(
    source,
    /ORGANIZATION|Enter admin mode|System administration|Leave admin mode|Sign out/,
  )
})

test("Phoenix owns both LiveVue hosts and the explicit method, CSRF, link, and raw-attr contracts", async () => {
  const source = await readFile(uiPath, "utf8")

  assert.equal((source.match(/v-component="NotificationsBell"/g) || []).length, 1)
  assert.equal((source.match(/v-component="UserMenu"/g) || []).length, 1)
  assert.equal((source.match(/v-ssr=\{false\}/g) || []).length, 2)
  assert.equal((source.match(/class="contents"/g) || []).length, 2)
  assert.doesNotMatch(source, /phx-hook="DropdownMenu"/)
  assert.match(source, /Plug\.CSRFProtection\.get_csrf_token_for\(action\)/)
  assert.match(source, /"name" => "_method"/)
  assert.match(source, /"name" => "_csrf_token"/)
  assert.match(source, /"data-phx-link" => "redirect"/)
  assert.match(source, /"data-phx-link-state" => "push"/)
  assert.match(source, /value in \[nil, false\]/)
  assert.match(source, /\{name, true\}.*Map\.put\(rendered, name, ""\)/s)
  assert.match(source, /Map\.put\(rendered, name, to_string\(value\)\)/)
})
