<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import { ApButton, ApCallout, ApField, ApPanel, ApSelect } from "@/ui";
import { errorCode, failureOutcome } from "@/features/changes/index.ts";
import { inviteFailure, sendInvitation, type Role } from "./api.ts";

/** U2 Invite: email + role (the real roles, DECISIONS #2). Shown only with org.invite. */
const props = defineProps<{ organizationId: OrganizationId }>();
const emit = defineEmits<{ invited: [] }>();
const email = ref("");
const form = ref<HTMLFormElement | null>(null);
/** `org/people/invite` redirects to People with `?invite=1` (ux §7 #8): start in the email field. */
const route = useRoute();
onMounted(() => {
  if (route.query["invite"]) form.value?.querySelector<HTMLInputElement>("input")?.focus();
});
const role = ref<Role | "">("member");
const busy = ref(false);
const sent = ref<string | null>(null);
const failure = ref<string | null>(null);
const options = [
  { value: "member" as const, label: "Member" },
  { value: "organization_admin" as const, label: "Org admin · also manages people and setup" },
];

async function invite() {
  if (busy.value || role.value === "" || !email.value.includes("@")) return;
  busy.value = true;
  failure.value = null;
  sent.value = null;
  try {
    const result = await sendInvitation(props.organizationId, {
      email: email.value.trim(),
      role: role.value,
    });
    if (result.ok) {
      sent.value =
        result.value.delivery === "submitted"
          ? `Invite sent to ${result.value.invitation.email}.`
          : `Invitation created for ${result.value.invitation.email}, but email delivery isn't set up here. Share the sign-up link with them directly.`;
      email.value = "";
      emit("invited");
    } else {
      const outcome = failureOutcome(result.error, "changed");
      failure.value =
        outcome.changed === null
          ? outcome.sentence
          : inviteFailure(
              errorCode(result.error),
              "message" in result.error ? result.error.message : outcome.sentence,
            );
    }
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="U2" title="Invite">
    <form ref="form" class="flex flex-col gap-3" @submit.prevent="invite">
      <ApField
        v-model="email"
        label="Email"
        type="email"
        autocomplete="off"
        :error="failure"
        required
      />
      <ApSelect v-model="role" label="Role" :options="options" />
      <ApCallout v-if="sent" tone="nominal">{{ sent }}</ApCallout>
      <ApButton
        type="submit"
        variant="primary"
        :disabled="busy || !email.includes('@')"
        :disabled-reason="busy ? 'Sending…' : 'Enter an email address.'"
      >
        {{ busy ? "Sending…" : "Send invite" }}
      </ApButton>
    </form>
  </ApPanel>
</template>
