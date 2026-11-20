<script setup lang="ts">
import { computed } from "vue";
import { ApTag } from "@/ui";
import { resumeOffer, suspendedLine } from "./grant-suspended.ts";
import { LEGACY_LINE, stateLine } from "./grant-words.ts";
import { grantTag, type Grant, type Grants } from "./grants.ts";

/**
 * The State cell (U105): mark + word (B2), the state's line (a suspended grant's by the setting in
 * force, #499), and a pre-#283 grant's line. A resume reason the console doesn't word keeps its
 * code in Technical details here, since a menu item can't hold them (U20).
 */
const props = defineProps<{ grant: Grant; setting: Grants["approval_setting"] }>();
const tag = computed(() => grantTag(props.grant));
const line = computed(() => stateLine(props.grant) ?? suspendedLine(props.grant, props.setting));
const code = computed(() => {
  const o = resumeOffer(props.grant);
  return o.kind === "act" ? (o.blocked?.code ?? null) : null;
});
</script>

<template>
  <span class="flex flex-col items-start gap-1">
    <ApTag :state="tag.state" :label="tag.label" />
    <span v-if="line" class="text-sm text-text-2">{{ line }}</span>
    <span v-if="grant.issued_before_two_person_approval" class="text-sm text-text-3">{{
      LEGACY_LINE
    }}</span>
    <details v-if="code" class="text-sm">
      <summary class="ap-label cursor-pointer">Technical details</summary>
      <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ code }}</p>
    </details>
  </span>
</template>
