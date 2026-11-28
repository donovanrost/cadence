<script setup lang="ts">
import { computed } from "vue";
import type { Composition } from "@/features/catalog/composition.ts";
import { ApCallout } from "@/ui";
import { withdrawnRecord, withdrawnStateLine, type ApprovalWithdrawn } from "./withdrawn.ts";

/**
 * E2b (#546; U109): the craft's state line while it runs a revision whose approval was withdrawn
 * or rejected. A standing caution (not the person's own act), so a status, not an alert (B6). The
 * decision's record is under Technical details (design-language §8: no raw id leads a line).
 */
const props = defineProps<{
  /** null: approved (or a server before #924); nothing shows. */
  withdrawn: ApprovalWithdrawn | null;
  composition: Composition | null | undefined;
  craft: string | null;
}>();
const line = computed(() =>
  props.withdrawn ? withdrawnStateLine(props.withdrawn, props.composition, props.craft) : null,
);
const record = computed(() => (props.withdrawn ? withdrawnRecord(props.withdrawn) : []));
</script>

<template>
  <ApCallout v-if="line" tone="caution">
    <span class="flex flex-col gap-1">
      <span>{{ line }}</span>
      <details class="text-sm text-text-3">
        <summary class="cursor-pointer">Technical details</summary>
        <dl class="m-0 mt-1 grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 font-mono text-xs">
          <template v-for="[label, value] in record" :key="label">
            <dt class="text-text-4">{{ label }}</dt>
            <dd class="m-0 break-all">{{ value }}</dd>
          </template>
        </dl>
      </details>
    </span>
  </ApCallout>
</template>
