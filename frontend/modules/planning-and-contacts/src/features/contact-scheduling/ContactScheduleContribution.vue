<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { ContactSchedulePort } from "./OpsContactSchedule.contracts";
import type { ContactPage } from "./contact-workflow";
import OpsContactSchedule from "./OpsContactSchedule.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: ContactPage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const contactPort: ContactSchedulePort = {
  context: { ...props.page.model.context },
  captured: {
    actorId: props.page.actor_id,
    guardNavigation: (guard) => props.port.guardNavigation?.(guard) ?? (() => {}),
  },
  execute: (action, input) => props.port.execute(action, input),
  refresh: () => props.readPort.read(),
};
</script>
<template>
  <section id="contact-schedule-contribution" class="min-w-0">
    <OpsContactSchedule :schedule="page" :port="contactPort" />
  </section>
</template>
