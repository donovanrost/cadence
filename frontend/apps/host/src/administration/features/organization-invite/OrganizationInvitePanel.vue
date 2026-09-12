<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import { organizationHref } from "../../shared/platform-contract";
import {
  readInviteResult,
  type Act,
  type Input,
  type InvitationReceipt,
  type OrganizationInvite,
} from "./contracts";
const props = defineProps<{ model: OrganizationInvite; act: Act; refresh: () => Promise<void> }>();
const form = reactive<Input>({
  email: "",
  display_name: "",
  membership_role: "member",
  grant_platform_admin: false,
});
const pending = ref(false),
  uncertain = ref(false),
  message = ref("");
const errors = ref<Record<string, string>>({}),
  receipt = ref<InvitationReceipt | null>(null);
const submitted = computed(() => props.model.submitted ?? receipt.value);
const disabled = computed(() => pending.value || uncertain.value || !!submitted.value);
async function invite() {
  if (disabled.value) return;
  pending.value = true;
  errors.value = {};
  message.value = "";
  try {
    const result = readInviteResult(await props.act("invite", { ...form }));
    if (result.status === "invited") receipt.value = result.invitation;
    else if (result.status === "invalid") errors.value = result.errors;
    else message.value = "Invitation creation is unavailable. Your values have been kept.";
  } catch {
    uncertain.value = true;
    message.value =
      "The invitation outcome is unknown. Check pending invitations before starting another form.";
  } finally {
    pending.value = false;
  }
}
</script>
<template>
  <main id="admin-organization-invite" class="max-w-2xl space-y-6">
    <CadencePageHeading
      :breadcrumbs="[
        { label: 'Platform Admin', href: '/admin' },
        { label: 'Organizations', href: '/admin/organizations' },
        { label: model.organization.name, href: organizationHref(model.organization.id) },
        { label: 'Invite User', href: null },
      ]"
    >
      <template #title>Invite User</template
      ><template #description>Invite a user to {{ model.organization.name }}.</template>
    </CadencePageHeading>
    <section
      v-if="submitted"
      id="organization-invitation-created"
      role="status"
      class="card border border-primary/40 bg-base-200 p-6 space-y-4"
    >
      <h2 class="font-semibold">Invitation created</h2>
      <p class="break-all">{{ submitted.email }}</p>
      <p
        v-if="submitted.delivery === 'submitted'"
        id="organization-invitation-email-submitted"
        class="text-sm"
      >
        The invitation email was submitted for delivery. The recipient must accept to gain access.
      </p>
      <p v-else id="organization-invitation-email-unavailable" class="text-sm">
        The invitation was saved, but email submission is unavailable. It has not been sent again
        automatically.
      </p>
      <a :href="organizationHref(model.organization.id)" class="btn btn-primary btn-sm"
        >Review organization invitations</a
      >
    </section>
    <form
      v-else
      id="invite-form"
      class="card border border-base-300 bg-base-200 p-6 space-y-4"
      @submit.prevent="invite"
    >
      <CadenceTextField
        id="invite_email"
        v-model="form.email"
        name="invite[email]"
        type="email"
        label="Email"
        required
        :disabled="disabled"
        :error="errors.email ?? ''"
      />
      <CadenceTextField
        id="invite_display_name"
        v-model="form.display_name"
        name="invite[display_name]"
        label="Display name"
        hint="Optional."
        :disabled="disabled"
        :error="errors.display_name ?? ''"
      />
      <label for="invite_membership_role" class="fieldset"
        ><span class="hud-label">Membership role</span
        ><select
          id="invite_membership_role"
          v-model="form.membership_role"
          name="invite[membership_role]"
          class="select w-full"
          :disabled="disabled"
          :aria-invalid="errors.membership_role ? 'true' : undefined"
          :aria-describedby="errors.membership_role ? 'invite-role-error' : undefined"
        >
          <option value="member">Member</option>
          <option value="organization_admin">Organization admin</option></select
        ><span
          v-if="errors.membership_role"
          id="invite-role-error"
          role="alert"
          class="text-sm text-error"
          >{{ errors.membership_role }}</span
        ></label
      >
      <label for="invite_grant_platform_admin" class="flex items-start gap-3"
        ><input
          id="invite_grant_platform_admin"
          v-model="form.grant_platform_admin"
          name="invite[grant_platform_admin]"
          type="checkbox"
          class="checkbox"
          :disabled="disabled"
        /><span
          ><span class="font-semibold text-sm">Grant platform administrator eligibility</span
          ><span class="mt-1 block text-xs text-base-content/70"
            >After acceptance, this user can reauthenticate to enter platform admin mode.</span
          ></span
        ></label
      >
      <p class="text-xs text-base-content/60">
        Sending another invitation to this address replaces its pending invitation for this
        organization.
      </p>
      <p v-if="errors.form" role="alert">{{ errors.form }}</p>
      <p v-if="message" id="organization-invitation-message" role="alert">{{ message }}</p>
      <div class="flex flex-wrap gap-3">
        <button
          id="send-organization-invitation"
          type="submit"
          class="btn btn-primary btn-sm"
          :disabled="disabled"
        >
          {{ pending ? "Sending…" : "Send invitation" }}</button
        ><a :href="organizationHref(model.organization.id)" class="btn btn-ghost btn-sm">{{
          uncertain ? "Check invitations" : "Cancel"
        }}</a
        ><button
          v-if="uncertain"
          id="refresh-organization-invitation"
          type="button"
          class="btn btn-sm"
          @click="refresh"
        >
          Refresh status
        </button>
      </div>
    </form>
  </main>
</template>
