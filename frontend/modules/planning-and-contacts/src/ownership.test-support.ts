import { createHash } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { parse, compileScript } from "vue/compiler-sfc";
import ts from "typescript";
import { expect } from "vite-plus/test";
export function assertOwnershipOracle(
  url: URL,
  expected: { script: string; template: string },
  reconstruct: (source: string) => string = (source) => source,
) {
  const filename = fileURLToPath(url);
  const { descriptor } = parse(reconstruct(readFileSync(filename, "utf8")), { filename });
  const script = compileScript(descriptor, {
    id: "ownership-" + filename.split("/").at(-1)!.replace(".vue", ""),
    fs: { fileExists: existsSync, readFile: (path) => readFileSync(path, "utf8") },
  }).content;
  const runtime = ts.transpileModule(script, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ESNext,
      removeComments: true,
    },
  }).outputText;
  const hash = (value: string) => createHash("sha256").update(value).digest("hex");
  expect(hash(runtime), "compiled executable script").toBe(expected.script);
  expect(hash(descriptor.template!.content), "unchanged template").toBe(expected.template);
}
