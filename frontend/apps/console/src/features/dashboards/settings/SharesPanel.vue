<script setup lang="ts">
import { ref } from "vue";
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
  const r = await revokeShare(props.settingsKey, id);
  note.value = r.ok
    ? { tone: "nominal", text: "Share link revoked. It stops working now." }
    : isError(r.error, "share_not_active")
      ? { tone: "nominal", text: "That link was already revoked." }
      : { tone: "crit", text: failureOutcome(r.error, "changed").sentence };
  emit("changed");
}
function created() {
  creating.value = false;
  note.value = { tone: "nominal", text: "Share link created. Copy it from the table." };
  emit("changed");
}
</script>

<template>
  <ApPanel index="S3" title="Share links" flush>
    <template #header>
      <ApButton v-if="!creating" size="compact" variant="primary" @click="creating = true"
        >Create share link</ApButton
      >
    </template>
    <ShareCreate
      v-if="creating"
      :settings-key="settingsKey"
      @created="created"
      @cancel="creating = false"
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
        <ShareRevoke :active="row.state === 'active'" @revoke="revoke(row.id)" />
      </template>
    </ApTable>
  </ApPanel>
</template>
