import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {stripTypeScriptTypes} from "node:module"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarios = [
  "the auth brand is one non-SSR LiveVue presentation island",
  "the existing text-center wrapper remains the LiveVue host",
  "Phoenix retains the arbitrary auth inner_content patch surface",
  "Phoenix retains the shared LiveToast host",
  "Phoenix retains the home route, classes, label, and tagline presentation",
  "the router auth LiveSession and controller-rendered pages retain the auth layout",
]

assert.equal(process.versions.node, "24.16.0", "auth layout contracts use pinned Node 24.16.0")
assert.equal(scenarios.length, 6)

const __dirname = dirname(fileURLToPath(import.meta.url))
const webRoot = resolve(__dirname, "../..")

const [template, layouts, component, router, invitationController, adminController, noOrgController] =
  await Promise.all([
    readFile(resolve(webRoot, "lib/cadence_web/components/layouts/auth.html.heex"), "utf8"),
    readFile(resolve(webRoot, "lib/cadence_web/components/layouts.ex"), "utf8"),
    readFile(resolve(webRoot, "assets/vue/AuthLayoutBrand.vue"), "utf8"),
    readFile(resolve(webRoot, "lib/cadence_web/router.ex"), "utf8"),
    readFile(resolve(webRoot, "lib/cadence_web/controllers/organization_invitation_controller.ex"), "utf8"),
    readFile(resolve(webRoot, "lib/cadence_web/controllers/admin_mode_controller.ex"), "utf8"),
    readFile(resolve(webRoot, "lib/cadence_web/controllers/no_organization_controller.ex"), "utf8"),
  ])

assert.equal(template.match(/<\.vue\b/g)?.length, 1)
assert.match(template, /id="auth-layout-brand"/)
assert.match(template, /v-component="AuthLayoutBrand"/)
assert.match(template, /presentation=\{auth_layout_brand_presentation\(\)\}/)
assert.match(template, /v-ssr=\{false\}/)
assert.match(template, /class="text-center"/)
assert.match(template, /\{@inner_content\}/)
assert.match(template, /<LiveToast\.toast_group/)
assert.doesNotMatch(template, /phx-update="ignore"/)

const brandHostEnd = template.indexOf("    />")
const innerContentStart = template.indexOf("    {@inner_content}")

assert.ok(brandHostEnd >= 0)
assert.ok(innerContentStart > brandHostEnd, "inner_content remains outside the LiveVue host")

for (const contract of [
  '"href" => ~p"/"',
  '"inline-block font-mono text-sm tracking-[0.28em] uppercase text-primary"',
  '"label" => "Cadence"',
  '"class" => "mt-1 text-xs text-base-content/50"',
  '"text" => "Ground data control plane"',
]) {
  assert.ok(layouts.includes(contract), `${contract} remains Phoenix-authored`)
}

assert.match(component, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.match(component, /<a :class="presentation\.link\.class" v-bind="presentation\.link\.attrs">/)
assert.match(component, /\{\{ presentation\.link\.label \}\}/)
assert.match(component, /<p :class="presentation\.tagline\.class">/)
assert.match(component, /\{\{ presentation\.tagline\.text \}\}/)
assert.doesNotMatch(component, /Cadence|Ground data control plane|href="\/"|phx-|defineEmits/)

assert.match(router, /live_session :auth, layout: \{CadenceWeb\.Layouts, :auth\} do/)

const script = component.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const componentTemplate = component.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "AuthLayoutBrand keeps an auditable TypeScript setup block")
assert.ok(componentTemplate, "AuthLayoutBrand keeps an auditable template block")
assert.doesNotThrow(
  () => new Function(stripTypeScriptTypes(script, {mode: "strip"})),
  "the dependency-free Node TypeScript parser accepts the brand component",
)

const stack = []

for (const match of componentTemplate.matchAll(/<\/?([a-z][\w-]*)(?:\s[^<>]*?)?>/gs)) {
  const [token, name] = match

  if (token.startsWith("</")) {
    assert.equal(stack.pop(), name, `${name} closes the current element`)
  } else {
    stack.push(name)
  }
}

assert.deepEqual(stack, [], "AuthLayoutBrand template tags are balanced")

for (const controller of [invitationController, adminController, noOrgController]) {
  assert.match(controller, /put_layout\(html: \{CadenceWeb\.Layouts, :auth\}\)/)
}

console.log("auth_layout_brand_test passed")
