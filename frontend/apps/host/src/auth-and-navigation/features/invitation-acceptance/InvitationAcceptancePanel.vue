<script setup lang="ts">
import { computed } from "vue";
import { readPage } from "./contracts";
import CadenceField from "@cadence/ui/CadenceField.vue";
const props = defineProps<{ page: unknown }>();
const fields = [
  { name: "display_name", label: "Display Name", type: "text", autocomplete: "name" },
  { name: "password", label: "Password", type: "password", autocomplete: "new-password" },
  {
    name: "password_confirmation",
    label: "Confirm Password",
    type: "password",
    autocomplete: "new-password",
  },
];
const model = computed(() => readPage(props.page));
</script>
<template>
  <section v-if="model" id="organization-invitation" class="space-y-6">
    <header>
      <p class="hud-label">Cadence Invitation</p>
      <h1 class="text-2xl font-bold">
        {{
          model.available
            ? "Accept your invitation and establish durable operator access."
            : "This invitation is no longer available."
        }}
      </h1>
      <p class="mt-2 text-sm text-base-content/70">
        {{
          model.available
            ? "Accepting establishes your organization membership and signs you in."
            : "Ask a Cadence platform administrator for a new invitation."
        }}
      </p>
    </header>
    <p v-if="model.error" id="organization-invitation-error" role="alert" class="alert alert-error">
      {{ model.error }}
    </p>
    <div class="grid gap-4">
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <p class="hud-label">Organization</p>
          <p class="font-semibold">{{ model.organization?.display_name || "Unavailable" }}</p>
          <p v-if="model.organization" class="text-sm text-base-content/60">
            Slug: {{ model.organization.slug }}
          </p>
        </div>
      </div>
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <p class="hud-label">Email</p>
          <p class="font-semibold">{{ model.invitation?.email || "Unavailable" }}</p>
        </div>
      </div>
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <p class="hud-label">Access</p>
          <p class="font-semibold capitalize">
            {{ model.invitation?.membership_role.replaceAll("_", " ") || "Pending new invitation" }}
          </p>
          <p v-if="model.invitation" class="text-sm text-base-content/60">
            Platform admin eligibility: {{ model.invitation.grant_platform_admin ? "Yes" : "No" }}
          </p>
        </div>
      </div>
    </div>
    <form
      v-if="model.available"
      id="organization-invitation-acceptance-form"
      :action="`/invitations/${encodeURIComponent(model.token)}`"
      method="post"
      class="space-y-4"
    >
      <input type="hidden" name="_csrf_token" :value="model.csrf_token" />
      <CadenceField
        v-for="field in fields"
        :key="field.name"
        :label="field.label"
        :control-id="`organization_invitation_acceptance_${field.name}`"
        ><input
          :id="`organization_invitation_acceptance_${field.name}`"
          :name="`organization_invitation_acceptance[${field.name}]`"
          :type="field.type"
          :autocomplete="field.autocomplete"
          :value="field.name === 'display_name' ? model.display_name : undefined"
          required
          class="w-full input"
      /></CadenceField>
      <button type="submit" class="btn btn-primary">Accept Invitation</button>
      <p class="text-sm text-base-content/70">
        Passwords must be at least 12 characters. Accepting this invitation signs you in
        immediately.
      </p>
    </form>
  </section>
  <p v-else id="invitation-acceptance-unavailable" role="alert" class="alert alert-warning">
    This page is unavailable. <a href="/sign-in" class="link">Return to sign in</a>.
  </p>
</template>
