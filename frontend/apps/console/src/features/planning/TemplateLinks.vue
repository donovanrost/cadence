<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApEmptyState, ApRemote, ApSegmented } from "@/ui";
import { fetchByTemplate, templateCountLine } from "./requirements.ts";

/**
 * P4 "From templates" (ux): requirements grouped by template with a count per UTC day, never one per
 * row (api df98dcd3). Each links to its template.
 */
const props = defineProps<{ missionId: MissionId }>();
const utcDay = (offset: number) =>
  new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);
const days = [
  { value: utcDay(-1), label: "Yesterday" },
  { value: utcDay(0), label: "Today" },
  { value: utcDay(1), label: "Tomorrow" },
];
const day = ref(utcDay(0));
const setDay = (v: string) => (day.value = v);
const counts = useRemoteQuery(
  () => ({ missionId: props.missionId, day: day.value }),
  fetchByTemplate,
);
const label = computed(
  () => days.find((d) => d.value === day.value)?.label.toLowerCase() ?? day.value,
);
</script>

<template>
  <div class="flex flex-col gap-2 px-4 py-3">
    <ApSegmented
      :model-value="day"
      :options="days"
      label="Window opens"
      @update:model-value="setDay"
    />
    <ApRemote :state="counts.state.value" loading-label="Counting…" @retry="counts.refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.templates.length === 0"
          :headline="`No template requirements open ${label}`"
        />
        <ul v-else class="m-0 flex list-none flex-col p-0">
          <li
            v-for="t in value.templates"
            :key="t.template.id"
            class="flex flex-wrap items-baseline gap-2 py-1.5"
          >
            <RouterLink
              :to="{
                name: 'setup.contact-planning.template',
                params: { templateId: t.template.id },
              }"
              class="font-semibold text-readout hover:underline"
              >{{ t.template.name }}</RouterLink
            >
            <span class="font-mono text-sm text-text-2">{{ templateCountLine(t, value.day) }}</span>
          </li>
        </ul>
      </template>
    </ApRemote>
  </div>
</template>
