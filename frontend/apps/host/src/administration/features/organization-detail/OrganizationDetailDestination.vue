<script setup lang="ts">
import { computed } from "vue";
import { identifier, organizationHref } from "../../shared/platform-contract";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ organization_id?: unknown }>();
const href = computed(() =>
  identifier(props.organization_id)
    ? organizationHref(props.organization_id) + ""
    : "/admin/organizations",
);
</script>
<template>
  <section id="organization-detail-destination" class="card p-6 space-y-4">
    <h2 class="text-lg font-semibold">Organization</h2>
    <a :href="href" class="btn btn-primary btn-sm">Open organization</a>
  </section>
</template>
