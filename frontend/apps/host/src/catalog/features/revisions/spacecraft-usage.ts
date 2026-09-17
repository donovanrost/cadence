import { array, bool, id, invalid, object, text } from "../../../shared/readers.ts";
const fields = object({
  mission_id: id,
  usage: array(object({ id, name: text, active: bool, saved: bool, href: text })),
});
export function readSpacecraftUsage(value: unknown) {
  const result = fields(value);
  if (
    result.usage.some(
      (item) =>
        item.href !== `/missions/${result.mission_id}/spacecraft/${item.id}?section=changes`,
    )
  )
    return invalid();
  return result;
}
