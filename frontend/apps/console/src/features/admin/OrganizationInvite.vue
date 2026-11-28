<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApSelect, ApSheet } from "@/ui";
import { inviteInto } from "./api.ts";

/** `Invite into Acme Space` (Admin.md): the cross-org invite; the org's People sees it too. */
const props = defineProps<{ orgId: OrganizationId; orgName: string }>();
const emit = defineEmits<{ changed: [note: { tone: "nominal" | "caution"; text: string }] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const email = ref("");
const role = ref<"member" | "organization_admin">("member");
const failure = ref<string | null>(null);
const busy = ref(false);
const roles = [
  { value: "member", label: "Member" },
  { value: "organization_admin", label: "Org admin" },
];
const setRole = (v: string) => {
  if (v === "member" || v === "organization_admin") role.value = v;
};
const blocked = computed(() =>
  !email.value.includes("@") ? "Enter an email address." : busy.value ? "Sending…" : null,
);
async function send() {
  if (blocked.value) return;
  busy.value = true;
  try {
    const r = await inviteInto(props.orgId, { email: email.value.trim(), role: role.value });
    if (!r.ok) return void (failure.value = failureOutcome(r.error, "changed").sentence);
    sheet.value?.close();
    emit(
      "changed",
      r.value.delivery === "submitted"
        ? { tone: "nominal", text: `Invitation sent to ${r.value.email}.` }
        : {
            tone: "caution",
            text: `The invitation to ${r.value.email} exists, but no email went out.`,
          },
    );
  } finally {
    busy.value = false;
  }
}
function open() {
  email.value = "";
  failure.value = null;
  sheet.value?.open();
}
</script>

<template>
  <ApButton variant="primary" @click="open">Invite into {{ orgName }}</ApButton>
  <ApSheet ref="sheet" :title="`Invite into ${orgName}`" initial-focus="input">
    <form class="flex flex-col gap-3" @submit.prevent="send">
      <ApField v-model="email" label="Email" type="email" />
      <ApSelect :model-value="role" label="Role" :options="roles" @update:model-value="setRole" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="send"
        >Send invite</ApButton
      >
    </template>
  </ApSheet>
</template>
