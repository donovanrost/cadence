import { array, bool, count, id, invalid, object, text } from "../../../shared/readers.ts";
const fields = object({
  mission_id: id,
  total_count: count,
  usage: array(object({ id, name: text, active: bool, saved: bool, href: text })),
});
export function readSpacecraftUsage(value: unknown) {
  const result = fields(value);
  if (
    result.usage.length !== Math.min(result.total_count, 100) ||
    new Set(result.usage.map((item) => item.id)).size !== result.usage.length ||
    result.usage.some(
      (item) =>
        (!item.active && !item.saved) ||
        item.href !== `/missions/${result.mission_id}/spacecraft/${item.id}?section=changes`,
    )
  )
    return invalid();
  return result;
}
