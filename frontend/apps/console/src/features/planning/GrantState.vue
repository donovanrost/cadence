<script setup lang="ts">
import { computed } from "vue";
import { ApTag } from "@/ui";
import { LEGACY_LINE, stateLine } from "./grant-words.ts";
import { grantTag, type Grant } from "./grants.ts";

/** The State cell (U105): mark + word (B2), the state's line, and a pre-#283 grant's line. */
const props = defineProps<{ grant: Grant }>();
const tag = computed(() => grantTag(props.grant));
const line = computed(() => stateLine(props.grant));
</script>

<template>
  <span class="flex flex-col items-start gap-1">
    <ApTag :state="tag.state" :label="tag.label" />
    <span v-if="line" class="text-sm text-text-2">{{ line }}</span>
    <span v-if="grant.issued_before_two_person_approval" class="text-sm text-text-3">{{
      LEGACY_LINE
    }}</span>
  </span>
</template>
