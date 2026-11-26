<script setup lang="ts">
import { computed } from "vue";
import { ApMenuButton, ApMenuItem } from "@/ui";
import { resumeOffer } from "./grant-suspended.ts";
import { LEGACY_NARROW } from "./grant-words.ts";
import { identityName, type Grant } from "./grants.ts";

/**
 * An active or suspended grant's acts (U105): Resume… (suspended, #499), Narrow… and Revoke….
 * Resume and Narrow follow the server's flags only (never a check of the console's own): Resume is
 * disabled with its reason; a grant made before #283 shows Narrow disabled with its. Revoke stays.
 */
const props = defineProps<{ grant: Grant }>();
defineEmits<{ resume: []; narrow: []; revoke: [] }>();
const resume = computed(() => resumeOffer(props.grant));
const narrowBlocked = computed(() =>
  props.grant.viewer_can_narrow === true
    ? undefined
    : props.grant.issued_before_two_person_approval === true
      ? LEGACY_NARROW
      : null,
);
</script>

<template>
  <ApMenuButton
    v-if="grant.state === 'active' || grant.state === 'suspended'"
    :label="`Actions for ${identityName(grant)}'s grant`"
  >
    <ApMenuItem
      v-if="resume.kind === 'act'"
      :disabled="resume.blocked?.text"
      @select="$emit('resume')"
      >Resume…</ApMenuItem
    >
    <ApMenuItem v-if="narrowBlocked !== null" :disabled="narrowBlocked" @select="$emit('narrow')"
      >Narrow…</ApMenuItem
    >
    <ApMenuItem @select="$emit('revoke')">Revoke…</ApMenuItem>
  </ApMenuButton>
</template>
