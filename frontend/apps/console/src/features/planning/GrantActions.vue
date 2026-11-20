<script setup lang="ts">
import { computed } from "vue";
import { ApMenuButton, ApMenuItem } from "@/ui";
import { LEGACY_NARROW } from "./grant-words.ts";
import { identityName, type Grant } from "./grants.ts";

/**
 * An active grant's acts (U105): Narrow… and Revoke…. Narrow follows the server's
 * viewer_can_narrow only (never a check of the console's own); a grant made before #283 shows it
 * disabled with its reason. Revoke stays.
 */
const props = defineProps<{ grant: Grant }>();
defineEmits<{ narrow: []; revoke: [] }>();
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
    v-if="grant.state === 'active'"
    :label="`Actions for ${identityName(grant)}'s grant`"
  >
    <ApMenuItem v-if="narrowBlocked !== null" :disabled="narrowBlocked" @select="$emit('narrow')"
      >Narrow…</ApMenuItem
    >
    <ApMenuItem @select="$emit('revoke')">Revoke…</ApMenuItem>
  </ApMenuButton>
</template>
