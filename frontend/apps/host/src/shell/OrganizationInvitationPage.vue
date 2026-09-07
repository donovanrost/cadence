<script setup lang="ts">
import CadenceField from "@cadence/ui/CadenceField.vue";
defineProps<{
  page: {
    csrf_token: string;
    token: string;
    available: boolean;
    error: string | null;
    display_name: string;
    organization: { display_name: string; slug: string } | null;
    invitation: { email: string; membership_role: string; grant_platform_admin: boolean } | null;
  };
}>();
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
</script>
<template>
  <section id="organization-invitation" class="space-y-6">
    <header>
      <p class="hud-label">Cadence Invitation</p>
      <h1 class="text-2xl font-bold">
        {{
          page.available
            ? "Accept your invitation and establish durable operator access."
            : "This invitation is no longer available."
        }}
      </h1>
      <p class="mt-2 text-sm text-base-content/70">
        {{
          page.available
            ? "Accepting creates your account, establishes organization membership, and signs you in."
            : "Ask a Cadence platform administrator for a new invitation."
        }}
      </p>
    </header>
    <p v-if="page.error" id="organization-invitation-error" role="alert" class="alert alert-error">
      {{ page.error }}
    </p>
    <div class="grid gap-4">
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <p class="hud-label">Organization</p>
          <p class="font-semibold">{{ page.organization?.display_name || "Unavailable" }}</p>
          <p v-if="page.organization" class="text-sm text-base-content/60">
            Slug: {{ page.organization.slug }}
          </p>
        </div>
      </div>
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <p class="hud-label">Email</p>
          <p class="font-semibold">{{ page.invitation?.email || "Unavailable" }}</p>
        </div>
      </div>
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <p class="hud-label">Access</p>
          <p class="font-semibold capitalize">
            {{ page.invitation?.membership_role.replaceAll("_", " ") || "Pending new invitation" }}
          </p>
          <p v-if="page.invitation" class="text-sm text-base-content/60">
            Platform Admin: {{ page.invitation.grant_platform_admin ? "Yes" : "No" }}
          </p>
        </div>
      </div>
    </div>
    <form
      v-if="page.available"
      id="organization-invitation-acceptance-form"
      :action="`/invitations/${encodeURIComponent(page.token)}`"
      method="post"
      class="space-y-4"
    >
      <input type="hidden" name="_csrf_token" :value="page.csrf_token" />
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
          :value="field.name === 'display_name' ? page.display_name : undefined"
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
</template>
