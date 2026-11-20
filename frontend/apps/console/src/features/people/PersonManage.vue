<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { isKnown } from "@/api";
import { ApButton, ApCallout, ApField, ApPanel, ApSelect, outcomeRole } from "@/ui";
import { adminErrorText, removeMember, setRole } from "./admin.ts";
import { roleLabel, roles, type Member, type Role } from "./api.ts";

/** People.md person page · Manage: change role, remove (typed confirm). Org admins only. */
const props = defineProps<{ orgId: string; member: Member; self: boolean }>();
const emit = defineEmits<{ changed: [] }>();
const router = useRouter();
/** A role the console doesn't know starts empty: the admin picks one rather than overwriting blind. */
const current = (r: Member["role"]): Role | "" => (isKnown(r) ? r : "");
const role = ref<Role | "">(current(props.member.role));
watch(
  () => props.member.role,
  (r) => (role.value = current(r)),
);
const confirm = ref("");
const busy = ref(false);
const note = ref<{ tone: "nominal" | "caution"; text: string } | null>(null);
const name = computed(() => props.member.display_name ?? props.member.email);
const options = roles.map((r) => ({ value: r, label: roleLabel(r) }));

async function saveRole() {
  if (role.value === "") return;
  busy.value = true;
  note.value = null;
  try {
    const r = await setRole(props.orgId, props.member.user_id, role.value);
    note.value = r.ok
      ? {
          tone: "nominal",
          text: `${name.value} is now ${r.value.role === "organization_admin" ? "an org admin" : "a member"}.`,
        }
      : { tone: "caution", text: adminErrorText(r.error) };
    emit("changed");
  } finally {
    busy.value = false;
  }
}

async function remove() {
  busy.value = true;
  note.value = null;
  try {
    const r = await removeMember(props.orgId, props.member.user_id);
    if (r.ok) return void router.push({ name: "org.people" });
    note.value = { tone: "caution", text: adminErrorText(r.error) };
    emit("changed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="P3" title="Manage">
    <div class="flex flex-col gap-4">
      <div class="flex flex-wrap items-end gap-3">
        <div class="w-[240px]">
          <ApSelect v-model="role" label="Role" :options="options" :disabled="self" />
        </div>
        <ApButton
          :disabled="self || busy || role === '' || role === current(member.role)"
          :disabled-reason="
            self ? 'You can\'t change your own role.' : busy ? 'Saving…' : 'Pick a different role'
          "
          @click="saveRole"
          >Save</ApButton
        >
      </div>
      <ApCallout v-if="note" :tone="note.tone" :role="outcomeRole(note.tone)">{{
        note.text
      }}</ApCallout>
      <div class="flex flex-col gap-2 border-t border-hairline pt-4">
        <p class="m-0 text-md text-text-2">
          Removing {{ name }} ends their access now. Their history stays, and inviting them again
          gives them access with the role you choose.
        </p>
        <div class="flex flex-wrap items-end gap-3">
          <div class="w-[320px]">
            <ApField
              v-model="confirm"
              :label="`Type ${member.email} to confirm`"
              :placeholder="member.email"
              mono
              required
            />
          </div>
          <ApButton
            variant="danger"
            :disabled="busy || confirm.trim() !== member.email"
            :disabled-reason="busy ? 'Removing…' : 'Type their email to confirm'"
            @click="remove"
            >Remove from organization</ApButton
          >
        </div>
      </div>
    </div>
  </ApPanel>
</template>
