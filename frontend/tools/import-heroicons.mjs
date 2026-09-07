import { readFile, readdir, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
const source = process.argv[2];
if (!source)
  throw new Error("Supply the optimized directory of an explicitly selected Heroicons checkout.");
const icons = {};
for (const [suffix, directory] of [
  ["", "24/outline"],
  ["-solid", "24/solid"],
  ["-mini", "20/solid"],
  ["-micro", "16/solid"],
]) {
  const root = resolve(source, directory);
  for (const name of (await readdir(root)).filter((name) => name.endsWith(".svg")).sort()) {
    icons[name.slice(0, -4) + suffix] = (await readFile(join(root, name), "utf8")).replaceAll(
      /\r?\n/g,
      "",
    );
  }
}
await writeFile(
  new URL("../packages/ui/vendor/heroicons.json", import.meta.url),
  `${JSON.stringify(icons, null, 2)}\n`,
);
