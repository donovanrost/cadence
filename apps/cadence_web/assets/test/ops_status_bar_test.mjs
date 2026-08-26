import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {stripTypeScriptTypes} from "node:module"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const testDirectory = dirname(fileURLToPath(import.meta.url))
const paths = {
  parent: resolve(testDirectory, "../vue/OpsStatusBar.vue"),
  clock: resolve(testDirectory, "../vue/UtcClock.vue"),
  notifications: resolve(testDirectory, "../vue/NotificationsBell.vue"),
  userMenu: resolve(testDirectory, "../vue/UserMenu.vue"),
  accountDropdown: resolve(testDirectory, "../vue/ui/reka/AccountDropdownMenu.vue"),
  menuItem: resolve(testDirectory, "../vue/ui/reka/CadenceMenuItem.vue"),
  phoenix: resolve(testDirectory, "../../lib/cadence_web/components/ops_shell.ex"),
  ui: resolve(testDirectory, "../../lib/cadence_web/components/ui.ex"),
  phoenixTest: resolve(testDirectory, "../../test/cadence_web/components/ops_shell_test.exs"),
}

const [
  source,
  clockSource,
  notificationsSource,
  userMenuSource,
  accountDropdownSource,
  menuItemSource,
  phoenixSource,
  uiSource,
  phoenixTestSource,
] = await Promise.all(Object.values(paths).map((path) => readFile(path, "utf8")))

const script = source.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "OpsStatusBar.vue must expose one typed script setup block")
assert.ok(template, "OpsStatusBar.vue must expose the complete status-bar template")

const parseableScript = stripTypeScriptTypes(script.replace(/^import .*$/gm, ""), {mode: "strip"})
assert.doesNotThrow(
  () => new Function(parseableScript),
  "the dependency-free Node TypeScript parser must accept the parent script",
)

const directImports = [...script.matchAll(/^import (\w+) from "\.\/(\w+)\.vue"$/gm)].map(
  ([, localName, fileName]) => [localName, fileName],
)

assert.deepEqual(
  directImports,
  [
    ["UtcClock", "UtcClock"],
    ["NotificationsBell", "NotificationsBell"],
    ["UserMenu", "UserMenu"],
  ],
  "the parent must directly import exactly the established timer and dropdown children",
)

for (const component of ["UtcClock", "NotificationsBell", "UserMenu"]) {
  assert.equal(
    template.match(new RegExp(`<${component}\\b`, "g"))?.length,
    1,
    `${component} must be directly composed exactly once`,
  )
}

assert.ok(template.indexOf("<UtcClock") < template.indexOf("<NotificationsBell"))
assert.ok(template.indexOf("<NotificationsBell") < template.indexOf("<UserMenu"))

const orderedChildren = [
  '<a :class="presentation.mission.class"',
  '<div :id="presentation.posture.id"',
  '<div :id="presentation.clock.id"',
  ':id="presentation.connection.ok.id"',
  ':id="presentation.connection.lost.id"',
  ':id="presentation.account.notifications_bell.id"',
  ':id="presentation.account.user_menu.id"',
]

for (let index = 1; index < orderedChildren.length; index += 1) {
  assert.ok(
    template.indexOf(orderedChildren[index - 1]) < template.indexOf(orderedChildren[index]),
    `status-bar child order changed between ${orderedChildren[index - 1]} and ${orderedChildren[index]}`,
  )
}

assert.match(template, /<header :class="presentation\.header\.class">/)
assert.match(template, /<a :class="presentation\.mission\.class" v-bind="presentation\.mission\.attrs">/)
assert.match(template, /:id="presentation\.posture\.id" :class="presentation\.posture\.root_class"/)
assert.match(template, /:id="presentation\.clock\.id" :class="presentation\.clock\.class"/)
assert.match(template, /<UtcClock \/>/)
assert.match(
  template,
  /v-if="presentation\.posture\.kind === 'critical' \|\| presentation\.posture\.kind === 'warning'"[\s\S]*?<span :class="presentation\.posture\.dot_class"><\/span>[\s\S]*?<span :class="presentation\.posture\.count\.class">\{\{ presentation\.posture\.count\.text \}\}<\/span>[\s\S]*?<span :class="presentation\.posture\.label\.class">\{\{ presentation\.posture\.label\.text \}\}<\/span>/,
  "critical and warning branches must retain dot, count, and label span topology",
)
assert.match(
  template,
  /<span\s+:id="presentation\.connection\.ok\.id"\s+:class="presentation\.connection\.ok\.class"\s+:title="presentation\.connection\.ok\.title"\s+v-bind="presentation\.connection\.ok\.attrs"\s*><\/span>/,
  "the connected indicator must render every stable DOM contract from its server DTO",
)
assert.match(
  template,
  /<span\s+:id="presentation\.connection\.lost\.id"\s+:class="presentation\.connection\.lost\.class"\s+:title="presentation\.connection\.lost\.title"\s+v-bind="presentation\.connection\.lost\.attrs"\s*><\/span>/,
  "the disconnected indicator must render every stable DOM contract from its server DTO",
)
assert.match(
  template,
  /<div\s+v-if="presentation\.account\?\.notifications_bell"\s+:id="presentation\.account\.notifications_bell\.id"\s+:class="presentation\.account\.notifications_bell\.class"\s*>\s*<NotificationsBell :presentation="presentation\.account\.notifications_bell\.presentation" \/>\s*<\/div>/,
  "the notification wrapper must independently render its server-owned host and child DTO",
)
assert.match(
  template,
  /<div\s+v-if="presentation\.account\?\.user_menu"\s+:id="presentation\.account\.user_menu\.id"\s+:class="presentation\.account\.user_menu\.class"\s*>\s*<UserMenu :presentation="presentation\.account\.user_menu\.presentation" \/>\s*<\/div>/,
  "the user-menu wrapper must independently render its server-owned host and child DTO",
)
assert.doesNotMatch(template, /<template v-if="presentation\.account">/)

for (const clientOwnedDomLiteral of [
  'id="ops-utc-clock"',
  'id="ops-conn-ok"',
  'id="ops-conn-lost"',
  'id="notifications-bell-ops"',
  'id="user-menu-ops"',
  'title="Connected"',
  'title="Connection lost"',
  'class="contents"',
  'class="font-mono text-xs text-base-content/70 tabular-nums"',
  'class="h-2 w-2 rounded-full bg-success"',
  'class="hidden h-2 w-2 rounded-full bg-error motion-safe:animate-pulse"',
]) {
  assert.ok(
    !template.includes(clientOwnedDomLiteral),
    `the parent SFC must not own server presentation literal: ${clientOwnedDomLiteral}`,
  )
}

for (const token of [
  'id="ops-status-bar-component"',
  'v-component="OpsStatusBar"',
  'presentation={@presentation}',
  'v-ssr={false}',
  'class="contents"',
  '"id" => "ops-urgent-posture"',
  '"id" => "ops-utc-clock"',
  '"id" => "ops-conn-ok"',
  '"id" => "ops-conn-lost"',
  '"id" => "notifications-bell-ops"',
  '"id" => "user-menu-ops"',
  '"class" => "contents"',
  'UI.notifications_bell_presentation(%{',
  'UI.user_menu_presentation(%{',
  'Jason.encode!(JS.show())',
  'Jason.encode!(JS.hide())',
]) {
  assert.ok(phoenixSource.includes(token), `missing exact server composition contract: ${token}`)
}

assert.match(uiSource, /def notifications_bell_presentation\(assigns\) do/)
assert.match(uiSource, /def user_menu_presentation\(assigns\) do/)
assert.match(
  phoenixTestSource,
  /then\(fn merged_assigns ->\s+render_component\(&OpsShell\.ops_status_bar\/1, merged_assigns\)\s+end\)/,
)
assert.doesNotMatch(phoenixTestSource, /then\(&render_component/)
assert.match(clockSource, /timerId = setInterval\(updateUtcTime, 1000\)/)
assert.match(clockSource, /if \(timerId !== undefined\) clearInterval\(timerId\)/)

for (const dropdownChildSource of [notificationsSource, userMenuSource]) {
  assert.match(
    dropdownChildSource,
    /import AccountDropdownMenu from "\.\/ui\/reka\/AccountDropdownMenu\.vue"/,
  )
  assert.match(
    dropdownChildSource,
    /import CadenceMenuItem from "\.\/ui\/reka\/CadenceMenuItem\.vue"/,
  )
  assert.match(dropdownChildSource, /<AccountDropdownMenu :class="presentation\.root\.class">/)
  assert.match(dropdownChildSource, /:aria-expanded="String\(open\)"/)
  assert.match(dropdownChildSource, /@select="onItemSelect"/)
  assert.doesNotMatch(dropdownChildSource, /dropdown_controller|from "reka-ui"/)
}

assert.match(accountDropdownSource, /from "reka-ui"/)
assert.match(accountDropdownSource, /open\.value && "dropdown-open"/)
assert.match(accountDropdownSource, /@open-auto-focus="handleOpenAutoFocus"/)
assert.match(accountDropdownSource, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(accountDropdownSource, /@escape-key-down="handleEscapeKeyDown"/)
assert.match(accountDropdownSource, /@keydown\.tab="handleTabKeyDown"/)
assert.match(menuItemSource, /import \{DropdownMenuItem\} from "reka-ui"/)

const sha256 = (value) => createHash("sha256").update(value).digest("hex")

assert.equal(
  sha256(clockSource),
  "fb4b3db7f148ac3e18421976fd2e5682795eacefd95ade1f9b9280a392fd8d28",
  "UtcClock.vue must remain byte-unchanged",
)
assert.equal(
  sha256(notificationsSource),
  "6b3f54ca6b0d87517062f640d5a33fe3c04325b94f312778f7dc570ad836804d",
  "NotificationsBell.vue must remain byte-unchanged",
)
assert.equal(
  sha256(userMenuSource),
  "93432a856d1924a17c45de379319b2a6d40dfd9d6d83a5084629f4ceabf50f84",
  "UserMenu.vue must remain byte-unchanged",
)
assert.equal(
  sha256(accountDropdownSource),
  "03e26f4a0e59475b809b68dcd4fbe15c6701bf4519beebe430d04169ea6168ff",
  "the account dropdown Reka adapter must remain byte-unchanged",
)
assert.equal(
  sha256(menuItemSource),
  "eddb15aa1d205acd68fb1874a63c0ecccdae6aafcafbc0d0c86149a376628fdb",
  "the shared Reka menu-item boundary must remain byte-unchanged",
)

console.log("ops_status_bar_test passed")
