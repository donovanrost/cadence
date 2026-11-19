<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery, type ApiResult } from "@/api";
import { useMissionScope } from "@/shell";
import { isEditableKind, opFields, opHead } from "./change-ops-words.ts";
import { fetchKindSchema, type EditableKind, type KindSchema } from "./kindSchema.ts";
import type { Change } from "./shapes.ts";

/**
 * A staged change's ops, expanded, in words (#308): "Changed transport · Name and 2 other
 * settings". Field labels come from the kind's schema; no raw action, kind, id or path is shown.
 */
const props = defineProps<{ change: Change }>();
const scope = useMissionScope();
const kinds = computed(() => [
  ...new Set(props.change.ops.flatMap((o) => (isEditableKind(o.kind) ? [o.kind] : []))),
]);
type Schemas = ReadonlyMap<EditableKind, KindSchema>;
async function fetchSchemas(
  key: Readonly<{ missionId: MissionId; kinds: readonly EditableKind[] }>,
  signal: AbortSignal,
): Promise<ApiResult<Schemas>> {
  const results = await Promise.all(
    key.kinds.map(async (kind) => [kind, await fetchKindSchema({ ...key, kind }, signal)] as const),
  );
  const map = new Map<EditableKind, KindSchema>();
  for (const [kind, r] of results) if (r.ok) map.set(kind, r.value);
  return { ok: true, value: map };
}
const schemas = useRemoteQuery(
  () => (kinds.value.length > 0 ? { missionId: scope.value.mission.id, kinds: kinds.value } : null),
  fetchSchemas,
);
const schemaOf = (op: Change["ops"][number]): KindSchema | null =>
  schemas.state.value.status === "ready" && isEditableKind(op.kind)
    ? (schemas.state.value.value.get(op.kind) ?? null)
    : null;
</script>

<template>
  <ul class="m-0 list-none border-t border-hairline-faint bg-vacuum px-4 py-2.5 text-sm">
    <li v-for="op in change.ops" :key="op.id" class="py-0.5 text-text-2">
      <span class="text-text-3">{{ opHead(op) }}</span
      ><template v-if="opFields(op, schemaOf(op))"> · {{ opFields(op, schemaOf(op)) }}</template>
    </li>
  </ul>
</template>
