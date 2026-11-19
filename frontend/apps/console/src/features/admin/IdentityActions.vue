<script setup lang="ts">
import type { AdminServiceIdentity } from "./api.ts";
import ServiceIdentityRevoke from "./ServiceIdentityRevoke.vue";
import ServiceIdentityRotate from "./ServiceIdentityRotate.vue";

/** A service identity row's actions: Rotate… (new token once) and Revoke… (confirms). */
defineProps<{ identity: AdminServiceIdentity }>();
defineEmits<{ rotated: []; revoke: [] }>();
</script>

<template>
  <span class="inline-flex gap-1">
    <ServiceIdentityRotate
      :id="identity.id"
      :organization-id="identity.organization.id"
      :name="identity.name"
      @rotated="$emit('rotated')"
    />
    <ServiceIdentityRevoke :name="identity.name" @revoke="$emit('revoke')" />
  </span>
</template>
