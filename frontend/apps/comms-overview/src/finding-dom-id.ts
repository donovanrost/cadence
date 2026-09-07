// Finding IDs are local to their group; DOM IDs must include that namespace.
export function findingDomId(groupId: string, findingId: unknown, index: number): string {
  const id =
    typeof findingId === "string" && findingId.length > 0 ? findingId : `finding-${index + 1}`;
  return `${groupId}-${id}`;
}
