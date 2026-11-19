/**
 * Naming patterns for a generated batch (AddSpacecraft.md step 02).
 * Tokens: `{scid}`, `{n}` (1-based index in the batch), `{n:03}` (zero-padded to 3 digits).
 */

type Part =
  | Readonly<{ kind: "text"; text: string }>
  | Readonly<{ kind: "scid" }>
  | Readonly<{ kind: "n"; width: number }>;

export type NamingPattern = Readonly<{ source: string; parts: readonly Part[]; unique: boolean }>;

export type PatternResult =
  | Readonly<{ ok: true; pattern: NamingPattern }>
  | Readonly<{ ok: false; message: string }>;

const TOKEN = /\{([^{}]*)\}/g;

export function parsePattern(source: string): PatternResult {
  const trimmed = source.trim();
  if (trimmed === "") return { ok: false, message: "Enter a naming pattern." };
  const parts: Part[] = [];
  let last = 0;
  for (const match of trimmed.matchAll(TOKEN)) {
    const index = match.index;
    if (index > last) parts.push({ kind: "text", text: trimmed.slice(last, index) });
    const token = match[1] ?? "";
    if (token === "scid") parts.push({ kind: "scid" });
    else if (token === "n") parts.push({ kind: "n", width: 0 });
    else {
      const padded = /^n:0(\d)$/.exec(token);
      const width = padded?.[1] ? Number(padded[1]) : null;
      if (width === null || width < 2)
        return { ok: false, message: `Unknown token {${token}}. Use {scid}, {n} or {n:03}.` };
      parts.push({ kind: "n", width });
    }
    last = index + match[0].length;
  }
  if (last < trimmed.length) parts.push({ kind: "text", text: trimmed.slice(last) });
  if (/[{}]/.test(parts.map((p) => (p.kind === "text" ? p.text : "")).join("")))
    return { ok: false, message: "Unmatched brace in the pattern." };
  return {
    ok: true,
    pattern: { source: trimmed, parts, unique: parts.some((p) => p.kind !== "text") },
  };
}

export function expandName(pattern: NamingPattern, at: Readonly<{ scid: number; n: number }>) {
  return pattern.parts
    .map((part) => {
      switch (part.kind) {
        case "text":
          return part.text;
        case "scid":
          return String(at.scid);
        case "n":
          return String(at.n).padStart(part.width, "0");
      }
    })
    .join("");
}
