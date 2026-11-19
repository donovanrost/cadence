<script setup lang="ts">
import { computed } from "vue";
import type { MissionId } from "@/api/index.ts";
import { ApPanel, useNow } from "@/ui";
import ContactRecordView from "./ContactRecordView.vue";
import { neverLiveLine, type HandStartedContact } from "./handStarted.ts";

/**
 * U78: the drawer for a hand-started contact (no reservation): the A13 record alone, with no
 * reservation section and no pass actions. `contactId` is its realized contact id; `contact`, its
 * row when known, adds the never-went-live line.
 */
const props = defineProps<{
  missionId: MissionId;
  contactId: string;
  contact?: HandStartedContact | null;
}>();
const now = useNow();
const closed = computed(() =>
  props.contact ? neverLiveLine(props.contact, now.value.toISOString().slice(0, 10)) : null,
);
</script>

<template>
  <ApPanel index="D2" title="Contact record" pane flush>
    <div class="flex flex-col gap-2 p-3">
      <p v-if="closed" class="m-0 text-sm text-text-2">{{ closed }}</p>
      <ContactRecordView :mission-id="missionId" :contact-id="contactId" alone />
    </div>
  </ApPanel>
</template>
