<script setup lang="ts">
import { ref } from "vue";
import { ApButton } from "@/ui";
import type { VerifierGroup } from "./api.ts";
import { DIFFER_LEAD, groupMeta, groupTargetsText, groupVerifierText } from "./verifierGroups.ts";

/**
 * U51 grouped block (Compose B, Approve C2): when a command's verifiers differ across targets,
 * one row per verifier set, largest first, with its targets and revision. Above 3 targets a row
 * gives a count and Show.
 */
const props = defineProps<{
  groups: readonly VerifierGroup[];
  nameOf: (spacecraftId: string) => string;
}>();
const shown = ref<ReadonlySet<number>>(new Set());
const show = (i: number) => (shown.value = new Set([...shown.value, i]));
const names = (g: VerifierGroup) => g.spacecraft_ids.map(props.nameOf).join(", ");
</script>

<template>
  <div class="flex flex-col gap-1">
    <p class="m-0 text-sm text-text-2">{{ DIFFER_LEAD }}</p>
    <ul class="m-0 flex list-none flex-col gap-1 p-0">
      <li
        v-for="(g, i) in groups"
        :key="i"
        class="flex flex-wrap items-baseline gap-x-2 font-mono text-xs uppercase"
      >
        <span :class="groupVerifierText(g).verifiable ? 'text-text-2' : 'text-stale-text'">{{
          groupVerifierText(g).text
        }}</span>
        <span class="text-text-4">·</span>
        <span class="text-text-3">{{ groupMeta(g, nameOf) }}</span>
        <ApButton
          v-if="groupTargetsText(g, nameOf).more && !shown.has(i)"
          size="compact"
          variant="ghost"
          @click="show(i)"
          >Show</ApButton
        >
        <span v-if="shown.has(i)" class="basis-full text-text-3 normal-case">{{ names(g) }}</span>
      </li>
    </ul>
  </div>
</template>
