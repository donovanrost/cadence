import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import {readFile} from "node:fs/promises"
import {createRequire} from "node:module"
import {dirname, extname, resolve} from "node:path"

export const expectedNodeVersion = "24.16.0"
export const expectedRekaVersion = "2.10.3"
export const integrationNodeModules =
  "/Users/donovanrost/projects/cadence/cadence-worktrees/livevue-poc/apps/cadence_web/node_modules"

export const integrationRequire = createRequire(
  resolve(integrationNodeModules, "cadence-reka-adapter-oracle.cjs"),
)
const localModuleCache = new Map()

const loadLocalModule = (modulePath) => {
  if (localModuleCache.has(modulePath)) return localModuleCache.get(modulePath).exports

  const loadedModule = {exports: {}}
  localModuleCache.set(modulePath, loadedModule)
  const {transformSync} = integrationRequire("esbuild")
  let moduleSource = readFileSync(modulePath, "utf8")
  let loader = "js"

  if (extname(modulePath) === ".vue") {
    const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
    const parsed = parse(moduleSource, {filename: modulePath})
    if (parsed.errors.length > 0) throw parsed.errors[0]

    moduleSource = compileScript(parsed.descriptor, {
      id: `cadence-adapter-dependency-${modulePath.split("/").at(-1)}`,
      inlineTemplate: true,
    }).content
    loader = "ts"
  }

  const transformed = transformSync(moduleSource, {
    format: "cjs",
    loader,
    platform: "node",
    target: "node24",
  })
  const evaluate = new Function("require", "module", "exports", transformed.code)
  evaluate(moduleRequire(modulePath), loadedModule, loadedModule.exports)
  return loadedModule.exports
}

const moduleRequire = (fromPath) => (specifier) => {
  if (specifier.startsWith(".")) return loadLocalModule(resolve(dirname(fromPath), specifier))
  return integrationRequire(specifier)
}

export async function assertPinnedAdapterRuntime(packageLockPath) {
  assert.equal(
    process.versions.node,
    expectedNodeVersion,
    `Cadence Reka adapter contracts use pinned Node ${expectedNodeVersion}`,
  )

  const [packageLockSource, rekaPackageSource] = await Promise.all([
    readFile(packageLockPath, "utf8"),
    readFile(resolve(integrationNodeModules, "reka-ui/package.json"), "utf8"),
  ])
  const packageLock = JSON.parse(packageLockSource)
  const rekaPackage = JSON.parse(rekaPackageSource)

  assert.equal(packageLock.packages["node_modules/reka-ui"].version, expectedRekaVersion)
  assert.equal(rekaPackage.version, expectedRekaVersion)
}

export async function loadSfc(componentPath) {
  const source = await readFile(componentPath, "utf8")
  const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
  const {transformSync} = integrationRequire("esbuild")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${componentPath} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${componentPath} keeps a setup script`)
  assert.ok(parsed.descriptor.template, `${componentPath} keeps a template`)

  const compiled = compileScript(parsed.descriptor, {
    id: `cadence-adapter-${componentPath.split("/").at(-1)}`,
    inlineTemplate: true,
  })
  const transformed = transformSync(compiled.content, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}
  const evaluate = new Function("require", "module", "exports", transformed.code)
  evaluate(moduleRequire(componentPath), loadedModule, loadedModule.exports)

  return {
    component: loadedModule.exports.default,
    descriptor: parsed.descriptor,
    source,
  }
}

export function installDom(markup = '<div id="app"></div>') {
  const {JSDOM} = integrationRequire("jsdom")
  const dom = new JSDOM(markup, {pretendToBeVisual: true, url: "http://localhost/"})
  const globals = [
    "window",
    "document",
    "navigator",
    "Node",
    "NodeFilter",
    "Element",
    "HTMLElement",
    "HTMLButtonElement",
    "SVGElement",
    "Event",
    "CustomEvent",
    "FocusEvent",
    "KeyboardEvent",
    "MouseEvent",
    "MutationObserver",
    "DOMRect",
    "getComputedStyle",
  ]

  for (const globalName of globals) {
    Object.defineProperty(globalThis, globalName, {
      configurable: true,
      value: dom.window[globalName],
    })
  }

  Object.defineProperty(globalThis, "PointerEvent", {
    configurable: true,
    value: dom.window.PointerEvent ?? dom.window.MouseEvent,
  })
  Object.defineProperty(globalThis, "requestAnimationFrame", {
    configurable: true,
    value: (callback) => dom.window.setTimeout(() => callback(Date.now()), 0),
  })
  Object.defineProperty(globalThis, "cancelAnimationFrame", {
    configurable: true,
    value: (handle) => dom.window.clearTimeout(handle),
  })

  class ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }

  Object.defineProperty(globalThis, "ResizeObserver", {
    configurable: true,
    value: ResizeObserver,
  })

  for (const method of ["hasPointerCapture", "releasePointerCapture", "setPointerCapture"]) {
    if (!dom.window.Element.prototype[method]) {
      Object.defineProperty(dom.window.Element.prototype, method, {
        configurable: true,
        value: () => false,
      })
    }
  }

  if (!dom.window.Element.prototype.scrollIntoView) {
    Object.defineProperty(dom.window.Element.prototype, "scrollIntoView", {
      configurable: true,
      value: () => {},
    })
  }

  return dom
}

export async function flushVue(nextTick) {
  await nextTick()
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 0))
  await nextTick()
}

export const elementAttributes = (element) =>
  Object.fromEntries(
    element.getAttributeNames().sort().map((name) => [name, element.getAttribute(name)]),
  )
