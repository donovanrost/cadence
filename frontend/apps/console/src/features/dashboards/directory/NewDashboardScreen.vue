<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { decode, decoders as d, type ApiError } from "@/api";
import { useMissionScope } from "@/shell";
import { ApButton, ApCallout, ApField, ApPageHeader, ApPanel, ApTextarea } from "@/ui";
import { createDashboard } from "./api.ts";

/**
 * New dashboard (ux: a small reading page). D4 v1 takes name, description and tags. The
 * spacecraft default and library templates join when D4 accepts them (api-ops), not before.
 */
const scope = useMissionScope();
const router = useRouter();
const name = ref("");
const description = ref("");
const tags = ref("");
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
const fieldDetail = d.object({ field: d.string });
/** 422 details name the field (console Problem convention); its message shows under that field. */
function fieldError(field: string): string | null {
  const e = error.value;
  if (e?.kind !== "invalid") return null;
  const detail = decode(fieldDetail, e.details);
  return detail.ok && detail.value.field === field ? e.message : null;
}

async function create() {
  if (busy.value || !name.value.trim()) return;
  busy.value = true;
  error.value = null;
  const result = await createDashboard(scope.value.mission.id, {
    name: name.value.trim(),
    description: description.value.trim(),
    tags: tagList.value,
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
      <ApTextarea v-model="description" label="Description (optional)" :rows="3" :maxlength="500" />
      <ApField
        v-model="tags"
        label="Tags (optional)"
        hint="Separate tags with commas."
        :error="fieldError('tags')"
      />
      <ApCallout v-if="error && !fieldError('name') && !fieldError('tags')" tone="crit">
        {{ error.kind === "unauthenticated" ? "Signed out." : error.message }}
      </ApCallout>
      <span class="flex gap-2">
        <ApButton
          type="submit"
          variant="primary"
          :disabled="busy || !name.trim()"
          disabled-reason="Give it a name."
          >Create and edit</ApButton
        >
        <ApButton variant="secondary" :to="{ name: 'ops.dashboards' }">Cancel</ApButton>
      </span>
    </form>
  </ApPanel>
</template>
