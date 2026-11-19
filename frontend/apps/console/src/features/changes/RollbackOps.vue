<script setup lang="ts">
import { computed } from "vue";
import type { DiffEntry } from "./actions.ts";
import { configKindText } from "./shapes.ts";
import { afterText, beforeText } from "./api.ts";
import type { RollbackPreview } from "./rollback.ts";

/**
 * What the rollback stages back, one entity per line with its values ("frame size 1,115 → 900
 * bytes"). Names and labels come from the server when it sends them; raw ids/paths otherwise.
 */
const props = defineProps<{ ops: RollbackPreview["ops"]; diffs: readonly DiffEntry[] }>();
const verb: Readonly<Record<DiffEntry["action"], string>> = {
  create: "Re-create",
  update: "Change back",
  delete: "Remove",
  unrecognized: "Change",
};
/** Prefer the checked diff (values); fall back to the op list when the preview has none. */
const lines = computed((): readonly DiffEntry[] =>
  props.diffs.length > 0
    ? props.diffs
    : props.ops.map((o) => ({
        kind: o.kind,
        entity_id: o.entity_id,
        entity_name: undefined,
        action: o.action,
        fields: undefined,
      })),
);
</script>

<template>
  <ul class="m-0 flex list-none flex-col gap-2 p-0 text-sm">
    <li v-for="(d, i) in lines.slice(0, 20)" :key="i" class="flex flex-col gap-0.5">
      <span>
        <span class="text-text-2">{{ verb[d.action] }}</span>
        {{ " " }}<span class="text-text-3">{{ configKindText(d.kind).toLowerCase() }}</span> {{ " "
        }}<span v-if="d.entity_name" class="text-readout">{{ d.entity_name }}</span>
      </span>
      <span
        v-for="f in d.fields ?? []"
        :key="f.path"
        class="pl-4 font-mono text-xs text-text-3"
        :title="f.path"
        >{{ f.label ?? f.path }} · {{ beforeText(f) }} →
        <span class="text-text-2">{{ afterText(f) }}</span></span
      >
    </li>
    <li v-if="lines.length > 20" class="text-text-3">and {{ lines.length - 20 }} more</li>
  </ul>
</template>
