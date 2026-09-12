<script setup lang="ts">
import { computed } from "vue";
import { identifier, organizationHref } from "../../shared/platform-contract";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ organization_id?: unknown }>();
const href = computed(() =>
  identifier(props.organization_id)
    ? organizationHref(props.organization_id) + "/invite"
    : "/admin/organizations",
);
</script>
<template>
  <section id="organization-invite-destination" class="card p-6 space-y-4">
    <h1 class="text-lg font-semibold">Invite user</h1>
    <a :href="href" class="btn btn-primary btn-sm">Open invite user</a>
  </section>
</template>
