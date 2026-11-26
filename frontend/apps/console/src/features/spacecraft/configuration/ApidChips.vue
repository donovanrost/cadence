<script setup lang="ts">
import { computed } from "vue";
import { ApChip, ApSelect } from "@/ui";
import type { PacketChoices } from "./api.ts";
import { apidHex } from "./words.ts";

/**
 * #595a (U40, mms-ux): the handled APIDs as removable mono chips, each × named "Remove APID
 * 0x101" (B7), and an Add select from the catalog revision's packets, "0x101 · EPS_HK", leaving
 * out the ones already chosen. Without packets (none chosen, loading, refused) the select says why.
 */
const props = defineProps<{
  apids: readonly number[];
  packets: PacketChoices | null;
  /** Why the Add select is off (no catalog yet, loading, refused); null when it's on. */
  unavailable: string | null;
  error?: string | undefined;
}>();
const emit = defineEmits<{ change: [apids: readonly number[]] }>();
const options = computed(() =>
  (props.packets?.packets ?? [])
    .filter((p) => !props.apids.includes(p.apid))
    .map((p) => ({ value: String(p.apid), label: `${apidHex(p.apid)} · ${p.name}` })),
);
function add(value: string) {
  const apid = Number(value);
  if (value !== "" && Number.isInteger(apid) && !props.apids.includes(apid))
    emit(
      "change",
      [...props.apids, apid].sort((a, b) => a - b),
    );
}
// A6: the Add select is never off without a reason.
const offReason = computed(
  () =>
    props.unavailable ??
    (options.value.length === 0 ? "Every APID in this catalog revision is already chosen." : null),
);
const remove = (apid: number) =>
  emit(
    "change",
    props.apids.filter((a) => a !== apid),
  );
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="ap-label">Handled APIDs</span>
    <ul
      v-if="apids.length"
      class="m-0 flex list-none flex-wrap gap-1.5 p-0"
      aria-label="Handled APIDs"
    >
      <li v-for="a in apids" :key="a">
        <ApChip removable :remove-label="`Remove APID ${apidHex(a)}`" @remove="remove(a)">{{
          apidHex(a)
        }}</ApChip>
      </li>
    </ul>
    <p v-else class="m-0 text-sm text-text-3">None</p>
    <ApSelect
      model-value=""
      label="Add APID"
      placeholder="Add APID…"
      mono
      :options="options"
      :disabled="offReason !== null"
      :hint="offReason ?? undefined"
      :error="error"
      @update:model-value="add"
    />
  </div>
</template>
