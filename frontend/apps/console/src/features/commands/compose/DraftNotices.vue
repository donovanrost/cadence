<script setup lang="ts">
import { ApButton, ApCallout } from "@/ui";
import type { StoredDraft } from "./saved.ts";
import { savedWhen, type DraftNotice, type DraftStatus } from "./useComposeDraft.ts";

/**
 * Compose's draft callouts: a saved draft this request would replace (Resume / Discard), another
 * tab's save (409: load it or keep this one), a failed save, and what a resume left out.
 */
defineProps<{
  status: DraftStatus;
  offered: StoredDraft | null;
  notice: DraftNotice | null;
}>();
defineEmits<{ resume: []; discard: []; keepMine: []; retry: [] }>();
</script>

<template>
  <ApCallout v-if="offered" tone="info">
    You have a draft saved {{ savedWhen(offered.saved_at) }}. This request replaces it once you
    start filling it in.
    <template #action>
      <span class="flex flex-none gap-2">
        <ApButton size="compact" @click="$emit('resume')">Resume draft</ApButton>
        <ApButton size="compact" variant="ghost" @click="$emit('discard')">Discard it</ApButton>
      </span>
    </template>
  </ApCallout>
  <ApCallout v-if="status.kind === 'conflict'" tone="caution">
    This draft was saved from another tab or device{{
      status.theirs ? ` at ${savedWhen(status.theirs.saved_at)}` : ""
    }}. Autosave is paused: load that version (your edits here are dropped) or keep this one (it
    replaces that save).
    <template #action>
      <span class="flex flex-none gap-2">
        <ApButton size="compact" @click="$emit('resume')">Load that version</ApButton>
        <ApButton size="compact" variant="ghost" @click="$emit('keepMine')">Keep this one</ApButton>
      </span>
    </template>
  </ApCallout>
  <ApCallout v-if="status.kind === 'failed'" tone="caution">
    {{ status.message }}
    <template #action>
      <ApButton size="compact" @click="$emit('retry')">Save now</ApButton>
    </template>
  </ApCallout>
  <ApCallout v-if="notice" :tone="notice.tone">{{ notice.text }}</ApCallout>
</template>
