<script setup lang="ts">
import type { OrganizationPagePort } from "@cadence/plugin-sdk/organization-pages";
import ProviderAccountRegistration from "./ProviderAccountRegistration.vue";
import { RegistrationActionFailure, type RegistrationPort } from "./registration-port";
import type { RegistrationModel } from "./registration.validation";

const props = defineProps<{
  model: RegistrationModel;
  organizationId: string;
  port: OrganizationPagePort;
}>();
// The host keys this component by the admitted page token. Same-instance refreshes
// must not replace the live draft or clear an uncertain submission lock.
const model = props.model,
  organizationId = props.organizationId,
  transport = props.port;
const featurePort: RegistrationPort = {
  async execute(action, input) {
    const result = await transport.execute(action, input);
    if (!result || typeof result !== "object" || !("status" in result))
      throw new RegistrationActionFailure("unknown");
    if (result.status === "rejected") throw new RegistrationActionFailure("rejected");
    if (result.status !== "ok" || !("data" in result))
      throw new RegistrationActionFailure("unknown");
    return result.data;
  },
  navigate: (href) => transport.navigate(href),
};
</script>
<template>
  <div class="max-w-3xl space-y-6">
    <ProviderAccountRegistration
      :model="model"
      :organization-id="organizationId"
      :port="featurePort"
    />
  </div>
</template>
