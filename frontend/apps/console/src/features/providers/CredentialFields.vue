<script setup lang="ts">
import { computed, useId } from "vue";
import { ApField, ApSegmented, ApTag } from "@/ui";

/**
 * Credential = where the secret lives + a reference to it. Never a secret value, never a password
 * input (ux SettingsAuditProviders.md, api: Cadence never receives secrets).
 */
const props = defineProps<{
  orgSlug: string;
  errors: Readonly<Record<string, string>>;
}>();
const backend = defineModel<string>("backend", { required: true });
const key = defineModel<string>("reference", { required: true });
const options = [
  { value: "external", label: "Secret manager" },
  { value: "env", label: "Environment variable" },
];
// a11y A6: the backend error is wired to its group (aria-describedby, aria-invalid), not only shown.
const backendError = useId();
const placeholder = computed(() =>
  backend.value === "env" ? "NORTHLIGHT_API_KEY" : `providers/${props.orgSlug}/northlight-prod`,
);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-col gap-1.5">
      <span class="ap-label">Where the secret lives</span>
      <div class="flex flex-wrap items-center gap-2">
        <ApSegmented
          v-model="backend"
          :options="options"
          label="Where the secret lives"
          :aria-describedby="errors['credential.backend'] ? backendError : undefined"
          :aria-invalid="errors['credential.backend'] ? 'true' : undefined"
        />
        <ApTag v-if="backend === 'env'" state="caution" label="Dev only" />
      </div>
      <span v-if="errors['credential.backend']" :id="backendError" class="text-sm text-crit-text">{{
        errors["credential.backend"]
      }}</span>
    </div>
    <ApField
      v-model="key"
      label="Reference"
      mono
      :placeholder="placeholder"
      hint="Cadence reads the secret from there when it calls the provider. The secret itself is never sent to or stored in Cadence."
      :error="errors['credential.key'] ?? null"
    />
  </div>
</template>
