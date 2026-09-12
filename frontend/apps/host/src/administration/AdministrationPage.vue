<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import OrganizationHomePanel from "./features/organization-home/OrganizationHomePanel.vue";
import { readOrganizationHome } from "./features/organization-home/contracts";
const props = defineProps<{
  page: string;
  snapshot: unknown;
  organizationId: unknown;
  refresh: () => Promise<void>;
}>();
const crashed = ref(false);
watch(
  () => [props.snapshot, props.organizationId, props.page],
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const admitted = computed(() => {
  const value = props.snapshot as Record<string, unknown> | null;
  if (
    props.page !== "organization_home" ||
    !value ||
    Array.isArray(value) ||
    value.page !== props.page ||
    value.version !== 1 ||
    value.status !== "ready" ||
    value.organization_id !== props.organizationId
  )
    return null;
  try {
    return readOrganizationHome(value.data, props.organizationId);
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="core-administration-page">
    <div
      v-if="crashed || !admitted"
      id="core-administration-error"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This organization page is unavailable.</p>
      <button id="core-administration-retry" type="button" class="btn btn-sm mt-4" @click="refresh">
        Retry
      </button>
    </div>
    <OrganizationHomePanel v-else :model="admitted" />
  </section>
</template>
