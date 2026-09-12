<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { ContactRecordPort } from "./OpsContactRecord.contracts";
import type { ContactPage } from "./contact-workflow";
import type { ContactRecord } from "./OpsContactRecord.contracts";
import OpsContactRecord from "./OpsContactRecord.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: ContactPage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const contactPort: ContactRecordPort = {
  context: {
    ...props.page.model.context,
    contact_id: (props.page.model as ContactRecord).subject.id,
  },
  captured: {
    actorId: props.page.actor_id,
    guardNavigation: (guard) => props.port.guardNavigation?.(guard) ?? (() => {}),
  },
  refresh: () => props.readPort.read(),
};
</script>
<template>
  <section id="contact-record-contribution" class="min-w-0">
    <OpsContactRecord :record="page" :port="contactPort" />
  </section>
</template>
