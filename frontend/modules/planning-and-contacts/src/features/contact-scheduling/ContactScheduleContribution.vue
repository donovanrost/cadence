<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import { createPageScheduleService } from "./schedule-page-adapter";
import { onBeforeUnmount } from "vue";
import type { ContactPage } from "./contact-workflow";
import OpsContactSchedule from "./OpsContactSchedule.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  page: Extract<ContactPage, { kind: "schedule" }>;
  port: OpsPagePort;
  readPort: OpsPageReadPort;
}>();
let active = true;
onBeforeUnmount(() => {
  active = false;
});
const contactPort = createPageScheduleService(props.page, props.port, props.readPort, () => active);
</script>
<template>
  <section id="contact-schedule-contribution" class="min-w-0">
    <OpsContactSchedule :schedule="page.model" :port="contactPort" />
  </section>
</template>
