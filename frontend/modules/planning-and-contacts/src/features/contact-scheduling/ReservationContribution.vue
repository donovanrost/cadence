<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { ReservationPort } from "./OpsContactDetail.contracts";
import type { ContactPage } from "./contact-workflow";
import OpsContactDetail from "./OpsContactDetail.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  page: Extract<ContactPage, { kind: "reservation" }>;
  port: OpsPagePort;
  readPort: OpsPageReadPort;
}>();
const contactPort: ReservationPort = {
  context: {
    ...props.page.model.context,
    reservation_id: props.page.model.reservation.id,
  },
  protocol: "page-snapshot",
  actorId: props.page.actor_id,
  guardNavigation: (guard) => props.port.guardNavigation?.(guard) ?? (() => {}),
  execute: (action, input) => props.port.execute(action, input),
  refresh: () => props.readPort.read(),
};
</script>
<template>
  <section id="contact-reservation-contribution" class="min-w-0">
    <OpsContactDetail :detail="page" :port="contactPort" />
  </section>
</template>
