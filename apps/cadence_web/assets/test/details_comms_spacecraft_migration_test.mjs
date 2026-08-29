import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {execFileSync} from "node:child_process"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {peelCadencePageTitle} from "./page_title_test_support.mjs"
import {
  expectedNodeVersion,
  installDom,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelCadenceNoticeFrames} from "./notice_frame_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const baseIdentity = "f9f36bb729e9f9abb1a2d01c3924bddf3d7eb99a"
const detailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryDirectory = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")

assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `details migration contracts use pinned Node ${expectedNodeVersion}`,
)

const callers = Object.freeze([
  Object.freeze({
    file: "CommsProviderShow.vue",
    predecessorSha256: "8bc6094cee62b720bae126646b0f576811ff51fadd712b587d1c086e80ea7781",
    nativeOpening: `    <details
      :id="diagnostics.id"
      class="rounded border border-base-300 bg-base-200/60 p-4 text-sm"
    >`,
    closingIndent: "    ",
    excludedSummary:
      '      <summary class="cursor-pointer hud-label hover:text-primary">',
  }),
  Object.freeze({
    file: "ProviderAccountShow.vue",
    predecessorSha256: "46eb0308a54a8f8f5b1018f4965aafad6aad1c625e0f4770b7357965a6a38826",
    nativeOpening: `    <details
      :id="diagnostics.id"
      class="rounded border border-base-300 bg-base-200/60 p-4 text-sm"
    >`,
    closingIndent: "    ",
    excludedSummary:
      '      <summary class="cursor-pointer hud-label hover:text-primary">{{ diagnostics.title }}</summary>',
  }),
  Object.freeze({
    file: "CommsTransportShow.vue",
    predecessorSha256: "2a58e84ef9a54c93fda0d46cec856af69c5705739f68556360912ca4f0207c5b",
    nativeOpening: `          <details
            :id="transport.capability.diagnostics.id"
            class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm"
          >`,
    closingIndent: "          ",
    excludedSummary:
      '            <summary class="cursor-pointer hud-label hover:text-primary">',
  }),
  Object.freeze({
    file: "CommsTransportNew.vue",
    predecessorSha256: "81137d33ce0743b10312b40b8548bcb5e0c5b912dd1fc1dc14d9a6da7ea450cc",
    nativeOpening: `        <details
          :id="form.review.diagnostics.id"
          class="rounded border border-base-300 bg-base-100/40 p-4 text-sm"
        >`,
    closingIndent: "        ",
    excludedSummary:
      '          <summary class="cursor-pointer hud-label hover:text-primary">',
  }),
  Object.freeze({
    file: "CommsRoutingShow.vue",
    predecessorSha256: "4ac7de436f1f881828b63fdf3e87f78474246bbc8ffa27e23cde09aa1c304e48",
    nativeOpening:
      '          <details class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">',
    closingIndent: "          ",
    excludedSummary:
      '            <summary class="cursor-pointer hud-label hover:text-primary">',
  }),
  Object.freeze({
    file: "SpacecraftShow.vue",
    predecessorSha256: "725b976057712738ef2e3ca93e51fdfb215e0912de455d2f9e9ebcf2c2ff7138",
    nativeOpening: '          <details class="text-sm">',
    closingIndent: "          ",
    excludedSummary:
      '            <summary class="cursor-pointer hud-label hover:text-primary">',
  }),
])

const replaceExact = (source, current, predecessor, expectedCount, label) => {
  assert.equal(occurrences(source, current), expectedCount, label)
  return source.split(current).join(predecessor)
}

const dom = installDom('<div id="details-comms-spacecraft-compile"></div>')
let compiledSfcCount = 0
let importCount = 0
let frameCount = 0
let excludedSummaryCount = 0

try {
  for (const caller of callers) {
    const componentPath = resolve(vueDirectory, caller.file)
    const repositoryPath = `apps/cadence_web/assets/vue/${caller.file}`
    const [source, loaded] = await Promise.all([
      readFile(componentPath, "utf8"),
      loadSfc(componentPath),
    ])
    const predecessorSource = execFileSync(
      "git",
      ["show", `${baseIdentity}:${repositoryPath}`],
      {cwd: repositoryDirectory, encoding: "utf8"},
    )
    const migratedOpening = caller.nativeOpening.replace(
      "<details",
      "<CadenceDetailsFrame",
    )
    const nativeClosing = `${caller.closingIndent}</details>`
    const migratedClosing = `${caller.closingIndent}</CadenceDetailsFrame>`

    assert.equal(
      sha256(predecessorSource),
      caller.predecessorSha256,
      `${caller.file} has its frozen ${baseIdentity} SHA-256`,
    )
    assert.equal(
      occurrences(predecessorSource, caller.nativeOpening),
      1,
      `${caller.file} predecessor has exactly one owned native opening`,
    )
    assert.equal(
      occurrences(predecessorSource, nativeClosing),
      1,
      `${caller.file} predecessor has exactly one owned native closing`,
    )
    assert.equal(
      occurrences(predecessorSource, caller.excludedSummary),
      1,
      `${caller.file} predecessor has exactly one excluded caller summary`,
    )

    assert.equal(
      occurrences(source, detailsFrameImport),
      1,
      `${caller.file} imports CadenceDetailsFrame exactly once`,
    )
    assert.equal(
      occurrences(source, migratedOpening),
      1,
      `${caller.file} has exactly one migrated owned opening`,
    )
    assert.equal(
      occurrences(source, migratedClosing),
      1,
      `${caller.file} has exactly one migrated owned closing`,
    )
    assert.equal(
      source.match(/<CadenceDetailsFrame\b/g)?.length ?? 0,
      1,
      `${caller.file} has exactly one CadenceDetailsFrame root`,
    )
    assert.equal(
      occurrences(source, caller.excludedSummary),
      1,
      `${caller.file} keeps its caller-owned summary excluded from migration`,
    )
    assert.doesNotMatch(
      source,
      /<\/?details\b/,
      `${caller.file} has no residual native details target`,
    )

    const migratedBodyStart = source.indexOf(migratedOpening) + migratedOpening.length
    const migratedBodyEnd = source.indexOf(migratedClosing, migratedBodyStart)
    const predecessorBodyStart =
      predecessorSource.indexOf(caller.nativeOpening) + caller.nativeOpening.length
    const predecessorBodyEnd = predecessorSource.indexOf(nativeClosing, predecessorBodyStart)

    assert.notEqual(migratedBodyEnd, -1, `${caller.file} migrated frame closes exactly`)
    assert.notEqual(predecessorBodyEnd, -1, `${caller.file} predecessor details closes exactly`)
    assert.equal(
      source.slice(migratedBodyStart, migratedBodyEnd),
      predecessorSource.slice(predecessorBodyStart, predecessorBodyEnd),
      `${caller.file} summary and every descendant remain byte-for-byte caller-owned`,
    )

    const noticePeeledSource = peelCadenceNoticeFrames(
      peelCadencePageTitle(source, caller.file),
      caller.file,
    )
    const reconstructed = replaceExact(
      replaceExact(
        replaceExact(
          noticePeeledSource,
          detailsFrameImport,
          "",
          1,
          `${caller.file} import peel count`,
        ),
        migratedOpening,
        caller.nativeOpening,
        1,
        `${caller.file} opening peel count`,
      ),
      migratedClosing,
      nativeClosing,
      1,
      `${caller.file} closing peel count`,
    )

    assert.equal(
      reconstructed,
      predecessorSource,
      `${caller.file} reconstructs ${baseIdentity} byte-for-byte by peeling only the newest layer`,
    )
    assert.equal(
      sha256(reconstructed),
      caller.predecessorSha256,
      `${caller.file} reconstruction preserves its frozen SHA-256`,
    )
    assert.ok(loaded.component, `${caller.file} compiles through the actual local SFC resolver`)
    assert.ok(loaded.descriptor.scriptSetup, `${caller.file} keeps its actual setup script`)
    assert.ok(loaded.descriptor.template, `${caller.file} keeps its actual template`)
    assert.equal(loaded.source, source, `${caller.file} compiles the exact audited source`)

    compiledSfcCount += 1
    importCount += occurrences(source, detailsFrameImport)
    frameCount += source.match(/<CadenceDetailsFrame\b/g)?.length ?? 0
    excludedSummaryCount += occurrences(source, caller.excludedSummary)
  }
} finally {
  dom.window.close()
}

assert.equal(callers.length, 6, "the cohort owns exactly six callers")
assert.equal(compiledSfcCount, 6, "all six actual owned SFCs compile")
assert.equal(importCount, 6, "the cohort has exactly six CadenceDetailsFrame imports")
assert.equal(frameCount, 6, "the cohort has exactly six CadenceDetailsFrame roots")
assert.equal(excludedSummaryCount, 6, "the cohort excludes exactly six caller-owned summaries")

console.log(
  "details_comms_spacecraft_migration_test passed (6 roots, 6 actual SFCs, 6 summary exclusions)",
)
