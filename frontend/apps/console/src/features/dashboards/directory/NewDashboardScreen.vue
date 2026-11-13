<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { decoders as d, detailsOf, type ApiError } from "@/api";
import { useMissionScope } from "@/shell";
import { ApButton, ApCallout, ApField, ApPageHeader, ApPanel, ApTextarea } from "@/ui";
import { createDashboard, type NewSpacecraft } from "./api.ts";
import SpacecraftDefault from "./SpacecraftDefault.vue";

/**
 * New dashboard (ux: a small reading page): name, description, tags and the spacecraft default
 * (D4). Starting from a library template joins with slice 8's endpoints.
 */
const scope = useMissionScope();
const router = useRouter();
const name = ref("");
const description = ref("");
const tags = ref("");
const spacecraft = ref<NewSpacecraft>({ mode: "context" });
const ready = computed(
  () =>
    name.value.trim() !== "" &&
    (spacecraft.value.mode !== "fixed" || spacecraft.value.spacecraft_id !== ""),
);
const busy = ref(false);
const error = ref<ApiError | null>(null);
const tagList = computed(() => [
  ...new Set(
    tags.value
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean),
  ),
]);
const formFields = ["name", "description", "tags", "spacecraft"] as const;
const fieldDetail = d.object({ field: d.knownText(formFields) });
/** 422 details name the field (api-ops a8460210a); its message shows under that field. */
const invalidField = computed(() => {
  const e = error.value;
  if (e?.kind !== "invalid") return null;
  const field = detailsOf(e, fieldDetail)?.field;
  return typeof field === "string" ? { field, message: e.message } : null;
});
function fieldError(field: (typeof formFields)[number]): string | null {
  return invalidField.value?.field === field ? invalidField.value.message : null;
}

async function create() {
  if (busy.value || !ready.value) return;
  busy.value = true;
  error.value = null;
  const result = await createDashboard(scope.value.mission.id, {
    name: name.value.trim(),
    description: description.value.trim(),
    tags: tagList.value,
    spacecraft: spacecraft.value,
  });
  busy.value = false;
  if (!result.ok) {
    error.value = result.error;
    return;
  }
  void router.push({
    name: "ops.dashboard",
    params: { dashboardId: result.value.id },
    query: { edit: "1" },
  });
}
</script>

<template>
  <ApPageHeader
    :label="`${scope.mission.name} · dashboards`"
    title="New dashboard"
    size="reading"
  />
  <ApPanel class="max-w-[640px]">
    <form class="flex flex-col gap-4" @submit.prevent="create">
      <ApField v-model="name" label="Name" required :error="fieldError('name')" />
      <ApTextarea
        v-model="description"
        label="Description (optional)"
        :rows="3"
        :maxlength="500"
        :error="fieldError('description')"
      />
      <ApField
        v-model="tags"
        label="Tags (optional)"
        hint="Separate tags with commas."
        :error="fieldError('tags')"
      />
      <SpacecraftDefault v-model="spacecraft" :error="fieldError('spacecraft')" />
      <ApCallout v-if="error && !invalidField" tone="crit">
        {{ error.kind === "unauthenticated" ? "Signed out." : error.message }}
      </ApCallout>
      <span class="flex gap-2">
        <ApButton
          type="submit"
          variant="primary"
          :disabled="busy || !ready"
          disabled-reason="Give it a name (and pick the spacecraft for One spacecraft)."
          >Create and edit</ApButton
        >
        <ApButton variant="secondary" :to="{ name: 'ops.dashboards' }">Cancel</ApButton>
      </span>
    </form>
  </ApPanel>
</template>
