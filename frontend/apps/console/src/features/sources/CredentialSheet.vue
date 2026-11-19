<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApField, ApSheet } from "@/ui";
import type { DataSource } from "./api.ts";
import { sourceFailure } from "./present.ts";
import { rotateCredential } from "./writes.ts";

/** L11 W5: point the source at a new secret reference (the reference only, never the secret). */
const props = defineProps<{ missionId: MissionId; source: DataSource }>();
const emit = defineEmits<{ done: [note: { tone: "nominal" | "crit"; text: string }] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const ref_ = ref("");
const failure = ref<string | null>(null);
const busy = ref(false);
const blocked = computed(() =>
  !ref_.value.trim() ? "Enter the new reference." : busy.value ? "Saving…" : null,
);
function open() {
  ref_.value = "";
  failure.value = null;
  sheet.value?.open();
}
async function submit() {
  if (blocked.value) return;
  busy.value = true;
  try {
    const r = await rotateCredential(
      { missionId: props.missionId, sourceId: props.source.id },
      ref_.value.trim(),
    );
    if (!r.ok) return void (failure.value = sourceFailure(r.error));
    sheet.value?.close();
    emit("done", {
      tone: "nominal",
      text: "Credential reference changed. The next probe uses it.",
    });
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Rotate credential" width="narrow" initial-focus="input">
    <form class="flex flex-col gap-3" @submit.prevent="submit">
      <p class="m-0 text-text-2">
        Now: <span class="font-mono">{{ source.credentials_ref ?? "None" }}</span>
      </p>
      <ApField
        v-model="ref_"
        label="New credentials reference"
        mono
        required
        hint="A secret reference such as secret://…, never the secret itself."
      />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="submit"
        >Change reference</ApButton
      >
    </template>
  </ApSheet>
</template>
