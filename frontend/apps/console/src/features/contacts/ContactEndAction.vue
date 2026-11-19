<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApSheet, ApTextarea } from "@/ui";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { useCommandAccess } from "@/features/commands/index.ts";
import { fetchQueuedCommands, type Pass, type QueuedCommands } from "./api.ts";
import {
  consequenceLines,
  NO_ACCESS_CONTACT,
  REASON_HELP,
  REASON_MAX,
  REASON_PLACEHOLDER,
  refusalWords,
  sheetTitle,
  stopContact,
} from "./contactEnd.ts";

/**
 * U55 on the selected pass: `Cancel contact…` before AOS, `End contact now…` while live (the
 * server says which). A danger sheet with a required reason; `Keep contact` takes the default
 * focus. A refusal says why and re-reads the pass.
 */
const props = defineProps<{ missionId: MissionId; pass: Pass; spacecraft: string; now: Date }>();
const emit = defineEmits<{ changed: [] }>();

const access = useCommandAccess();
const session = useSession();
const scope = useMissionScope();
const mayRelease = computed(() => canAdministerOrganization(session, scope.value.organization));
const action = computed(() => props.pass.contact_action ?? null);
const known = computed(() =>
  action.value === "cancel" || action.value === "end" ? action.value : null,
);

const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const reason = ref("");
const queued = ref<QueuedCommands | null>(null);
const busy = ref(false);
const note = ref<string | null>(null);
const error = ref<string | null>(null);

async function open() {
  reason.value = "";
  error.value = null;
  queued.value = null;
  sheet.value?.open();
  const r = await fetchQueuedCommands(props.missionId, props.pass.id);
  if (r.ok) queued.value = r.value.queued_commands ?? null;
}
async function confirm() {
  const a = known.value;
  const text = reason.value.trim();
  if (!a || busy.value) return;
  if (!text) {
    error.value = "Give a reason first.";
    return;
  }
  busy.value = true;
  try {
    const r = await stopContact(props.missionId, props.pass.id, a, text);
    sheet.value?.close();
    note.value = r.ok ? null : refusalWords(r.error);
    emit("changed");
  } finally {
    busy.value = false;
  }
}
const lines = computed(() =>
  known.value
    ? consequenceLines(
        known.value,
        props.pass,
        props.spacecraft,
        queued.value,
        mayRelease.value,
        props.now,
      )
    : [],
);
</script>

<template>
  <div v-if="known" class="flex flex-col gap-1">
    <ApButton
      v-if="access.abort"
      size="compact"
      variant="danger"
      class="self-start"
      @click="open"
      >{{ known === "cancel" ? "Cancel contact…" : "End contact now…" }}</ApButton
    >
    <p v-else class="m-0 text-sm text-text-3">{{ NO_ACCESS_CONTACT }}</p>
    <!-- a11y B6 (#243): the note is this act's refusal or failure, announced as an alert. -->
    <p v-if="note" role="alert" class="m-0 text-sm text-caution-text">{{ note }}</p>
    <ApSheet ref="sheet" :title="sheetTitle(known, spacecraft, pass, now)" width="narrow">
      <p v-for="line in lines" :key="line" class="m-0 text-md text-text-2">{{ line }}</p>
      <ApTextarea
        v-model="reason"
        label="Reason"
        required
        :hint="REASON_HELP"
        :placeholder="REASON_PLACEHOLDER"
        :maxlength="REASON_MAX"
        :error="error ?? undefined"
      />
      <template #footer>
        <ApButton variant="ghost" @click="sheet?.close()">Keep contact</ApButton>
        <ApButton
          variant="danger"
          :disabled="busy"
          :disabled-reason="known === 'cancel' ? 'Canceling…' : 'Ending…'"
          @click="confirm"
          >{{ known === "cancel" ? "Cancel contact" : "End contact now" }}</ApButton
        >
      </template>
    </ApSheet>
  </div>
</template>
