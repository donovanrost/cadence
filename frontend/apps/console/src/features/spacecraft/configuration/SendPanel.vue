<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApCallout, OutcomeCallout } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import {
  reviewLine,
  sendBlocked,
  sendLabel,
  sourceLine,
  type SendOutcome,
  type SendRefusal,
} from "./send-words.ts";

/**
 * #595c (U94): send the saved draft for activation. The button names the act by the mission's
 * approval setting, with the setting's source and Approval settings beside it; it's off with
 * U94's reason (A6). The request's state, a result and a refusal show here.
 */
const props = defineProps<{
  snapshot: ConfigurationSnapshot;
  dirty: boolean;
  conflict: boolean;
  sending: boolean;
  outcome: SendOutcome | null;
  failure: SendRefusal | null;
}>();
const emit = defineEmits<{ send: [] }>();
const blocked = computed(() =>
  sendBlocked(props.snapshot, {
    dirty: props.dirty,
    conflict: props.conflict,
    sending: props.sending,
  }),
);
const review = computed(() => reviewLine(props.snapshot));
const shown = computed(() =>
  props.outcome ? { tone: props.outcome.tone, text: props.outcome.text } : null,
);
</script>

<template>
  <div class="flex flex-col gap-2" data-send-panel>
    <OutcomeCallout v-if="outcome && shown" :outcome="shown">
      <template v-if="outcome.requestId" #action>
        <ApButton
          size="compact"
          :to="{ name: 'setup.activation', params: { requestId: outcome.requestId } }"
          >Open request</ApButton
        >
      </template>
    </OutcomeCallout>
    <ApCallout v-else-if="failure" tone="crit" role="alert">
      {{ failure.text }}
      <details v-if="failure.code" class="mt-1 text-sm">
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ failure.code }}</p>
      </details>
      <template v-if="failure.openRevision || (failure.openProfile && snapshot.profile)" #action>
        <ApButton
          v-if="failure.openRevision"
          size="compact"
          :to="{
            name: 'setup.catalog.model',
            params: { revisionId: failure.openRevision.revisionId },
          }"
          >Open rev {{ failure.openRevision.number }}</ApButton
        >
        <ApButton
          v-else-if="snapshot.profile"
          size="compact"
          :to="{ name: 'setup.profile', params: { profileId: snapshot.profile.id } }"
          >Open profile</ApButton
        >
      </template>
    </ApCallout>
    <p v-if="review && !outcome" class="m-0 flex flex-wrap items-center gap-2 text-md text-text-2">
      {{ review }}
      <ApButton
        v-if="snapshot.review"
        size="compact"
        variant="ghost"
        :to="{ name: 'setup.activation', params: { requestId: snapshot.review.id } }"
        >Open request</ApButton
      >
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <ApButton
        variant="primary"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="emit('send')"
        >{{ sendLabel(snapshot) }}</ApButton
      >
      <span class="text-sm text-text-3">{{ sourceLine(snapshot) }}</span>
      <ApButton size="compact" variant="ghost" :to="{ name: 'setup.settings' }"
        >Approval settings</ApButton
      >
    </div>
  </div>
</template>
