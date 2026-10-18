export type DiffLine =
  | { kind: "same" | "added" | "removed"; text: string; left: number | null; right: number | null }
  | { kind: "gap"; hidden: number };

const MAX_CELLS = 4_000_000;

/**
 * Line diff of two texts (longest common subsequence), with unchanged runs
 * longer than `2 * context` collapsed into gaps, like a unified diff.
 */
export function lineDiff(before: string, after: string, context = 3): DiffLine[] {
  const a = before.split("\n"),
    b = after.split("\n");
  if (a.length * b.length > MAX_CELLS) return coarse(a, b);
  const width = b.length + 1;
  const lcs = new Uint32Array((a.length + 1) * width);
  for (let i = a.length - 1; i >= 0; i--)
    for (let j = b.length - 1; j >= 0; j--)
      lcs[i * width + j] =
        a[i] === b[j]
          ? (lcs[(i + 1) * width + j + 1] ?? 0) + 1
          : Math.max(lcs[(i + 1) * width + j] ?? 0, lcs[i * width + j + 1] ?? 0);
  const lines: Exclude<DiffLine, { kind: "gap" }>[] = [];
  let i = 0,
    j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) {
      lines.push({ kind: "same", text: a[i] ?? "", left: i + 1, right: j + 1 });
      i++;
      j++;
    } else if (
      j < b.length &&
      (i >= a.length || (lcs[i * width + j + 1] ?? 0) >= (lcs[(i + 1) * width + j] ?? 0))
    ) {
      lines.push({ kind: "added", text: b[j] ?? "", left: null, right: j + 1 });
      j++;
    } else {
      lines.push({ kind: "removed", text: a[i] ?? "", left: i + 1, right: null });
      i++;
    }
  }
  return collapse(lines, context);
}

function coarse(a: string[], b: string[]): DiffLine[] {
  return [
    ...a.map((text, i) => ({ kind: "removed" as const, text, left: i + 1, right: null })),
    ...b.map((text, j) => ({ kind: "added" as const, text, left: null, right: j + 1 })),
  ];
}

function collapse(lines: Exclude<DiffLine, { kind: "gap" }>[], context: number): DiffLine[] {
  const changed = lines.map((line) => line.kind !== "same");
  const near = (index: number) => {
    for (
      let k = Math.max(0, index - context);
      k <= Math.min(lines.length - 1, index + context);
      k++
    )
      if (changed[k]) return true;
    return false;
  };
  const result: DiffLine[] = [];
  let hidden = 0;
  lines.forEach((line, index) => {
    if (line.kind === "same" && !near(index)) {
      hidden++;
      return;
    }
    if (hidden) result.push({ kind: "gap", hidden });
    hidden = 0;
    result.push(line);
  });
  if (hidden) result.push({ kind: "gap", hidden });
  return result;
}
