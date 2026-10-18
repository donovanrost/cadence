<script setup lang="ts">
import type { OrganizationPagePort } from "@cadence/plugin-sdk/organization-pages";
import ProviderAccountDetail from "./ProviderAccountDetail.vue";
import { AccountActionFailure, type AccountDetailPort } from "./detail-port";
import type { AccountDetailModel } from "./detail.validation";
const props = defineProps<{
  model: AccountDetailModel;
  sequence: number;
  locked: boolean;
  port: OrganizationPagePort;
}>();
// The host keys the instance by page token; reconnect must not reset drafts or locks.
const model = props.model,
  locked = props.locked,
  transport = props.port;
let sequence = props.sequence;
function unwrap(value: unknown) {
  if (!value || typeof value !== "object" || !("status" in value))
    throw new AccountActionFailure("unknown");
  if (value.status === "rejected") throw new AccountActionFailure("rejected");
  if (value.status !== "ok" || !("data" in value)) throw new AccountActionFailure("unknown");
  return value.data;
}
const featurePort: AccountDetailPort = {
  async execute(action, input) {
    return unwrap(await transport.execute(action, { ...input, sequence: ++sequence }));
  },
  async query() {
    return unwrap(await transport.execute("refresh", {}));
  },
};
</script>
<template>
  <ProviderAccountDetail :model="model" :port="featurePort" :initially-locked="locked" />
</template>
