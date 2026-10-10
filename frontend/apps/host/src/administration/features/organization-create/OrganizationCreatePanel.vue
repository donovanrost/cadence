<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import { organizationHref, type Organization } from "../../shared/platform-contract";
import { readResult, type Act, type OrganizationCreate } from "./contracts";
const props = defineProps<{ model: OrganizationCreate; act: Act; refresh: () => Promise<void> }>();
const form = reactive({ display_name: "", slug: "" });
const errors = ref<Record<string, string>>({});
const pending = ref(false);
const uncertain = ref(false);
const message = ref("");
const receipt = ref<Organization | null>(null);
const created = computed(() => props.model.created ?? receipt.value);
const disabled = computed(() => pending.value || uncertain.value || !!created.value);
async function save() {
  if (disabled.value) return;
  pending.value = true;
  errors.value = {};
  message.value = "";
  try {
    const result = readResult(await props.act("create", { ...form }));
    if (result.status === "created") receipt.value = result.organization;
    else if (result.status === "invalid") errors.value = result.errors;
    else message.value = "Organization creation is unavailable. Your values have been kept.";
  } catch {
    uncertain.value = true;
    message.value =
      "The creation outcome is unknown. Check the organization directory before starting another form.";
  } finally {
    pending.value = false;
  }
}
useManagementHeader("/admin/organizations/new", {
  description: "Add an organization to the platform.",
});
</script>
<template>
  <div id="admin-organization-new" class="max-w-2xl space-y-6">
    <section
      v-if="created"
      id="admin-organization-created"
      role="status"
      class="card border border-success/40 bg-base-200 p-6 space-y-4"
    >
      <h2 class="font-semibold">Organization created</h2>
      <p class="break-words">{{ created.name }}</p>
      <a
        id="admin-organization-created-link"
        :href="organizationHref(created.id)"
        class="btn btn-primary btn-sm"
        >Open organization</a
      >
      <a href="/admin/organizations" class="link">All organizations</a>
    </section>
    <form
      v-else
      id="org-form"
      class="card border border-base-300 bg-base-200 p-6 space-y-4"
      @submit.prevent="save"
    >
      <CadenceTextField
        id="organization_display_name"
        v-model="form.display_name"
        name="organization[display_name]"
        label="Display name"
        required
        :disabled="disabled"
        :error="errors.display_name ?? ''"
      />
      <CadenceTextField
        id="organization_slug"
        v-model="form.slug"
        name="organization[slug]"
        label="Slug"
        required
        :disabled="disabled"
        :error="errors.slug ?? ''"
        hint="A unique label used to identify the organization."
      />
      <p v-if="errors.form" role="alert">{{ errors.form }}</p>
      <p v-if="message" id="admin-organization-create-message" role="alert">{{ message }}</p>
      <div class="flex flex-wrap gap-3">
        <button
          id="admin-organization-create-submit"
          type="submit"
          class="btn btn-primary btn-sm"
          :disabled="disabled"
        >
          {{ pending ? "Creating…" : "Create organization" }}
        </button>
        <a href="/admin/organizations" class="btn btn-ghost btn-sm">{{
          uncertain ? "Check directory" : "Cancel"
        }}</a>
        <button
          v-if="uncertain"
          id="admin-organization-create-refresh"
          type="button"
          class="btn btn-sm"
          @click="refresh"
        >
          Refresh status
        </button>
      </div>
    </form>
  </div>
</template>
