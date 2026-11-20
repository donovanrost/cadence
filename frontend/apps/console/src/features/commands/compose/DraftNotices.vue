<script setup lang="ts">
import { ApButton, ApCallout, OutcomeCallout } from "@/ui";
import type { StoredDraft } from "./saved.ts";
import { savedWhen, type DraftNotice, type DraftStatus } from "./useComposeDraft.ts";

/**
 * Compose's draft callouts (ux Command.md States, 601a32f9): a saved draft this request would
 * replace, another tab's save (409), a draft gone elsewhere, a failed save, what a resume left out.
 */
defineProps<{
  status: DraftStatus;
  offered: StoredDraft | null;
  notice: DraftNotice | null;
}>();
defineEmits<{ resume: []; discardOffered: []; keepMine: []; retry: [] }>();
</script>

<template>
  <ApCallout v-if="offered" tone="info">
    You have a draft saved {{ savedWhen(offered.saved_at) }}. This request replaces it once you
    start filling it in.
    <template #action>
      <span class="flex flex-none gap-2">
        <ApButton size="compact" @click="$emit('resume')">Resume draft</ApButton>
        <ApButton size="compact" variant="ghost" @click="$emit('discardOffered')"
          >Discard draft</ApButton
        >
      </span>
    </template>
  </ApCallout>
  <!-- a11y B6 (#243): a failed or conflicting background save is an alert, once, when it appears. -->
  <ApCallout v-if="status.kind === 'conflict' && status.theirs" tone="caution" role="alert">
    This draft was saved from another tab at {{ savedWhen(status.theirs.saved_at) }}. Autosave is
    paused until you choose.
    <template #action>
      <span class="flex flex-none flex-col items-end gap-1">
        <span class="flex gap-2">
          <ApButton size="compact" @click="$emit('resume')"
            >Load the {{ savedWhen(status.theirs.saved_at) }} version</ApButton
          >
          <ApButton size="compact" variant="ghost" @click="$emit('keepMine')">Keep mine</ApButton>
        </span>
        <span class="text-xs text-text-3"
          >Replaces the {{ savedWhen(status.theirs.saved_at) }} save.</span
        >
      </span>
    </template>
  </ApCallout>
  <!-- 409 with {revision: null} (api): submitted or discarded elsewhere; keeping recreates it. -->
  <ApCallout v-else-if="status.kind === 'conflict'" tone="caution" role="alert">
    This draft was submitted or discarded in another tab. Autosave is paused until you choose.
    <template #action>
      <ApButton size="compact" @click="$emit('keepMine')">Keep mine</ApButton>
    </template>
  </ApCallout>
  <ApCallout v-if="status.kind === 'failed'" tone="caution" role="alert">
    Couldn't save the draft{{ status.reason ? `: ${status.reason.replace(/\.$/, "")}` : "" }}.
    {{
      status.lastSaved
        ? `Changes since ${savedWhen(status.lastSaved)} are only in this tab.`
        : "Your changes are only in this tab."
    }}
    <template #action>
      <ApButton size="compact" @click="$emit('retry')">Try again</ApButton>
    </template>
  </ApCallout>
  <!-- The read on opening is a first load (polite); the rest follow the person's act (#276). -->
  <ApCallout v-if="notice?.onLoad" :tone="notice.tone">{{ notice.text }}</ApCallout>
  <OutcomeCallout v-else-if="notice" :outcome="notice" />
</template>
