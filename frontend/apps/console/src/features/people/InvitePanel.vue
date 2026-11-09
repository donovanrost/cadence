<script setup lang="ts">
import { ref } from "vue";
import { describeApiError } from "@/api";
import { ApButton, ApCallout, ApField, ApPanel, ApSelect } from "@/ui";
import { sendInvitation, type Role } from "./api.ts";

/** U2 Invite: email + role (the real roles, DECISIONS #2). Shown only with org.invite. */
const props = defineProps<{ organizationId: string }>();
const emit = defineEmits<{ invited: [] }>();
const email = ref("");
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
      sent.value = result.value.email;
      email.value = "";
      emit("invited");
    } else {
      failure.value =
        result.error.kind === "not_found"
          ? "Inviting from the console isn't available yet."
          : describeApiError(result.error);
    }
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="U2" title="Invite">
    <form class="flex flex-col gap-3" @submit.prevent="invite">
      <ApField v-model="email" label="Email" type="email" autocomplete="off" :error="failure" />
      <ApSelect v-model="role" label="Role" :options="options" />
      <ApCallout v-if="sent" tone="nominal">Invite sent to {{ sent }}.</ApCallout>
      <ApButton
        type="submit"
        variant="primary"
        :disabled="busy || !email.includes('@')"
        disabled-reason="Enter an email address."
      >
        {{ busy ? "Sending…" : "Send invite" }}
      </ApButton>
    </form>
  </ApPanel>
</template>
