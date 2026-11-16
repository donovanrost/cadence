<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink } from "vue-router";
import { ApButton, ApStatusMark, stateTextClass } from "@/ui";
import type { MissionId } from "@/api/index.ts";
import type { MissionEvent } from "./api.ts";
import { eventDetail } from "./eventDetail.ts";
import { useContactLinks } from "./useContactLinks.ts";

/**
 * A Timeline event's detail (ux decisions U71 A8): the sentence as the title, severity, group and
 * type, when it occurred, its named links and status, then Technical details. Copy link copies
 * the `?event=<id>` permalink. The parent puts it in an aside (≥1100) or a sheet.
 */
const props = defineProps<{ missionId: MissionId; event: MissionEvent }>();
const emit = defineEmits<{ close: [] }>();
const detail = computed(() => eventDetail(props.event));
const contacts = useContactLinks(
  computed(() => props.missionId),
  computed(() => detail.value.technical.filter((r) => r.contact).map((r) => r.value)),
);
const onTechnical = (e: Event) => {
  if (e.target instanceof HTMLDetailsElement && e.target.open) void contacts.probe();
};
const title = ref<HTMLElement | null>(null);
const copied = ref("");
async function copyLink() {
  const url = new URL(window.location.href);
  url.searchParams.set("event", props.event.id);
  try {
    await navigator.clipboard.writeText(url.toString());
    copied.value = "Link copied.";
  } catch {
    copied.value = "Couldn't copy; the link is in the address bar.";
  }
}
defineExpose({ focusTitle: () => title.value?.focus() });
</script>

<template>
  <div class="flex flex-col gap-3 p-4">
    <h2 ref="title" tabindex="-1" class="m-0 text-lg text-readout focus:outline-none">
      {{ detail.title }}
    </h2>
    <p class="m-0 flex items-center gap-2" :class="stateTextClass(detail.state)">
      <ApStatusMark :state="detail.state" />{{ detail.severity }}
    </p>
    <p class="m-0 text-text-2">{{ detail.groupType }}</p>
    <p class="m-0 font-mono text-sm text-text-3">{{ detail.occurred }}</p>
    <ul v-if="detail.links.length" class="m-0 flex list-none flex-wrap gap-x-3 p-0">
      <li v-for="link in detail.links" :key="link.label">
        <RouterLink :to="link.to" class="text-readout underline-offset-2 hover:underline">{{
          link.label
        }}</RouterLink>
      </li>
    </ul>
    <p v-if="detail.status" class="m-0 text-text-2">{{ detail.status }}</p>
    <details @toggle="onTechnical">
      <summary class="cursor-pointer text-sm text-text-3">Technical details</summary>
      <dl class="m-0 mt-2 grid grid-cols-[auto_minmax(0,1fr)] gap-x-3 gap-y-1 text-sm">
        <template v-for="row in detail.technical" :key="row.label">
          <dt class="text-text-4">{{ row.label }}</dt>
          <dd class="m-0 font-mono break-all text-text-2">
            <RouterLink
              v-if="row.contact && contacts.resolved.value.has(row.value)"
              :to="{ name: 'ops.contacts.history', query: { contact: row.value } }"
              class="text-readout underline-offset-2 hover:underline"
              >{{ row.value }}</RouterLink
            >
            <template v-else>{{ row.value }}</template>
          </dd>
        </template>
      </dl>
    </details>
    <div class="flex flex-wrap items-center gap-2">
      <ApButton size="compact" variant="secondary" @click="copyLink">Copy link</ApButton>
      <ApButton size="compact" variant="ghost" @click="emit('close')">Close</ApButton>
      <span class="text-sm text-text-3" aria-live="polite">{{ copied }}</span>
    </div>
  </div>
</template>
