<script setup lang="ts">
import { nextTick, ref } from "vue";
import { isError } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApEmptyState, ApPanel, ApTable, type ApColumn } from "@/ui";
import { revokeShare, type Share, type SettingsKey } from "./api.ts";
import { byLine, shareStateText, visibilityWord } from "./present.ts";
import ShareCreate from "./ShareCreate.vue";
import ShareRevoke from "./ShareRevoke.vue";

/** Shares: link (copy) · Data · Expires · Created · Revoke (confirms). Primary: Create share link. */
const props = defineProps<{ settingsKey: SettingsKey; shares: readonly Share[] }>();
const emit = defineEmits<{ changed: [] }>();
const creating = ref(false);
const note = ref<{ tone: "nominal" | "crit"; text: string } | null>(null);
/** The row whose Revoke is running, and a refusal read in that row's confirm. */
const revoking = ref<string | null>(null);
const refusal = ref<{ id: string; text: string } | null>(null);
/** A5: the form closes, or a row's Revoke… goes, and focus lands on Create share link. */
const createButton = () => document.querySelector<HTMLElement>("[data-share-create]");
const columns: readonly ApColumn[] = [
  { key: "link", label: "Link" },
  { key: "data", label: "Data" },
  { key: "expires", label: "Expires", mono: true },
  { key: "created", label: "Created" },
  { key: "actions", label: "Actions", hiddenLabel: true, align: "end" },
];
async function copy(s: Share) {
  try {
    await navigator.clipboard.writeText(new URL(s.url, window.location.origin).toString());
    note.value = { tone: "nominal", text: "Link copied." };
  } catch {
    note.value = { tone: "crit", text: "Couldn't copy; select the link and copy it." };
  }
}
async function revoke(id: string) {
  revoking.value = id;
  refusal.value = null;
  try {
    const r = await revokeShare(props.settingsKey, id);
    if (r.ok || isError(r.error, "share_not_active")) {
      note.value = r.ok
        ? { tone: "nominal", text: "Share link revoked. It stops working now." }
        : { tone: "nominal", text: "That link was already revoked." };
      emit("changed");
    } else refusal.value = { id, text: failureOutcome(r.error, "changed").sentence };
  } finally {
    revoking.value = null;
  }
}
async function closeForm(made: boolean) {
  creating.value = false;
  if (made) {
    note.value = { tone: "nominal", text: "Share link created. Copy it from the table." };
    emit("changed");
  }
  await nextTick();
  createButton()?.focus();
}
</script>

<template>
  <ApPanel index="S3" title="Share links" flush>
    <template #header>
      <ApButton
        v-if="!creating"
        size="compact"
        variant="primary"
        data-share-create
        @click="creating = true"
        >Create share link</ApButton
      >
    </template>
    <ShareCreate
      v-if="creating"
      :settings-key="settingsKey"
      @created="closeForm(true)"
      @cancel="closeForm(false)"
    />
    <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
    <ApEmptyState
      v-if="shares.length === 0"
      headline="No share links"
      sentence="A share link opens a live view of the current version."
    />
    <ApTable v-else :columns="columns" :rows="shares" :row-key="(s) => s.id" caption="Share links">
      <template #cell-link="{ row }">
        <ApButton
          size="compact"
          variant="ghost"
          :disabled="row.state !== 'active'"
          disabled-reason="Not active"
          @click="copy(row)"
          >Copy link</ApButton
        >
      </template>
      <template #cell-data="{ row }">{{ visibilityWord(row.data_visibility) }}</template>
      <template #cell-expires="{ row }">{{ shareStateText(row) }}</template>
      <template #cell-created="{ row }"
        ><span class="text-text-2">{{ byLine(row.created_by, row.created_at) }}</span></template
      >
      <template #cell-actions="{ row }">
        <ShareRevoke
          :active="row.state === 'active'"
          :busy="revoking === row.id"
          :refusal="refusal?.id === row.id ? refusal.text : null"
          :return-focus="createButton"
          @revoke="revoke(row.id)"
        />
      </template>
    </ApTable>
  </ApPanel>
</template>
