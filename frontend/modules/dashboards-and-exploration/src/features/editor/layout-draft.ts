import type { EditorPlacement } from "./contracts";
export type LayoutEdit = { placement_id: string; x: number; y: number; w: number; h: number };
/** Only admitted authored placements and bounded integer coordinates can become drafts. */
export function layoutEdits(nodes: any[], placements: EditorPlacement[]): LayoutEdit[] {
  if (nodes.length !== placements.length) throw Error("Incomplete layout");
  const seen = new Set<string>();
  return nodes.map((node) => {
    const placement = placements.find((p) => p.id === node.id);
    if (!placement || seen.has(node.id)) throw Error("Unknown layout identity");
    seen.add(node.id);
    const { min_w, min_h, max_w, max_h, max_y } = placement.constraints;
    const { x, y, w, h } = node;
    if (
      ![x, y, w, h].every(Number.isSafeInteger) ||
      x < 0 ||
      y < 0 ||
      y > max_y ||
      w < min_w ||
      w > max_w ||
      h < min_h ||
      h > max_h ||
      x + w > max_w
    )
      throw Error("Layout exceeds its bounds");
    return { placement_id: placement.id, x, y, w, h };
  });
}
export function mergeLayoutEdits(current: LayoutEdit[], next: LayoutEdit[]): LayoutEdit[] {
  const edits = new Map(current.map((item) => [item.placement_id, item]));
  for (const item of next) edits.set(item.placement_id, item);
  return [...edits.values()].sort((a, b) => a.placement_id.localeCompare(b.placement_id));
}
