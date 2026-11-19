<script setup lang="ts">
import { ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApPanel, ApTextarea } from "@/ui";
import ArchiveSection from "./ArchiveSection.vue";
import { saveGeneral, type DashboardSettings, type SettingsKey } from "./api.ts";
import { fromForm, toForm } from "./defaults.ts";
import DefaultsFields from "./DefaultsFields.vue";
import { conflictText, parseTags } from "./present.ts";

/** General (ux § Settings): saving makes a current version (Q1), with a "Saved as v8" line. */
const props = defineProps<{ settingsKey: SettingsKey; settings: DashboardSettings }>();
const emit = defineEmits<{ saved: [] }>();
const d = props.settings.dashboard;
const name = ref(d.name);
const description = ref(d.description);
const tags = ref(d.tags.join(", "));
const defaults = ref(toForm(props.settings.defaults.time, props.settings.defaults.scope));
const errors = ref<Record<string, string>>({});
const note = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
const busy = ref(false);

async function save() {
  const t = parseTags(tags.value, props.settings.limits);
  const dft = fromForm(defaults.value);
  errors.value = {
    ...(name.value.trim() === "" ? { name: "Name the dashboard." } : {}),
    ...(t.ok ? {} : { tags: t.message }),
    ...(dft.ok ? {} : { [dft.field]: dft.message }),
  };
  if (!t.ok || !dft.ok || Object.keys(errors.value).length > 0 || busy.value) return;
  busy.value = true;
  try {
    const r = await saveGeneral(props.settingsKey, {
      name: name.value.trim(),
      description: description.value.trim(),
      tags: t.tags,
      defaults: { time: dft.time, scope: dft.scope },
      expected_version: d.current_version,
    });
    if (r.ok) {
      note.value = { tone: "nominal", text: `Saved as v${r.value.version}.` };
      return void emit("saved");
    }
    note.value = {
      tone: "crit",
      text: conflictText(r.error) ?? failureOutcome(r.error, "changed").sentence,
    };
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="S1" title="General" :meta="`v${d.current_version}`">
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <ApField v-model="name" label="Name" required :error="errors['name'] ?? null" />
      <ApTextarea
        v-model="description"
        label="Description"
        :maxlength="settings.limits.description"
      />
      <ApField
        v-model="tags"
        label="Tags"
        hint="Separated by commas."
        :error="errors['tags'] ?? null"
      />
      <DefaultsFields v-model="defaults" :mission-id="settingsKey.missionId" :errors="errors" />
      <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
      <div>
        <ApButton type="submit" variant="primary" :disabled="busy" disabled-reason="Saving…"
          >Save</ApButton
        >
      </div>
    </form>
  </ApPanel>
  <ArchiveSection :settings-key="settingsKey" :archived="d.lifecycle === 'archived'" />
</template>
