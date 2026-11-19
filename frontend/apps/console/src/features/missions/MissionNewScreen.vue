<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { slugOf } from "@/features/admin/index.ts";
import { canAdministerOrganization, useConsoleScope, useSession } from "@/shell";
import {
  ApBreadcrumb,
  ApButton,
  ApCallout,
  ApField,
  ApPageHeader,
  ApPanel,
  type ApCrumb,
} from "@/ui";
import { checkMissionSlug, createMission } from "./api.ts";
import { blockedReason, createFailure, takenLine, type CreateFailure } from "./newMission.ts";

/**
 * Org › Missions › New (L4; plans/mission-create.md): a one-step reading-layout form (IA "Mission
 * creation"). After create, a full load into the mission's Setup so the session bootstrap has it.
 */
const router = useRouter();
const scope = useConsoleScope();
const session = useSession();
const organization = computed(() =>
  scope.value.kind === "mission" || scope.value.kind === "organization"
    ? scope.value.organization
    : null,
);
const allowed = computed(() =>
  organization.value ? canAdministerOrganization(session, organization.value) : false,
);
const name = ref("");
const slug = ref("");
const slugEdited = ref(false);
watch(name, (n) => {
  if (!slugEdited.value) slug.value = slugOf(n);
});
const check = useRemoteQuery(
  () =>
    organization.value && slug.value
      ? { organizationId: organization.value.id, slug: slug.value }
      : null,
  checkMissionSlug,
);
const busy = ref(false);
const failure = ref<CreateFailure | null>(null);
watch([name, slug], () => (failure.value = null));
const taken = computed(
  () =>
    failure.value?.slug ??
    takenLine(check.state.value.status === "ready" ? check.state.value.value : null),
);
const blocked = computed(() =>
  blockedReason({ name: name.value, slug: slug.value, taken: taken.value, busy: busy.value }),
);
const crumbs: readonly ApCrumb[] = [
  { label: "Missions", to: { name: "org.missions" } },
  { label: "New mission" },
];

async function submit() {
  const org = organization.value;
  if (!org || blocked.value) return;
  busy.value = true;
  try {
    const r = await createMission(org.id, { name: name.value.trim(), slug: slug.value });
    if (!r.ok) return void (failure.value = createFailure(r.error));
    // A full load, not a push: the session is a boot snapshot and must pick up the new mission.
    const href = router.resolve({
      name: "setup.readiness",
      params: { org: org.slug, mission: r.value.slug },
    }).href;
    window.location.assign(href);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[720px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader
      :label="`${organization?.name ?? ''} · organization`"
      title="New mission"
      size="reading"
    />
    <ApCallout v-if="!allowed" tone="caution"
      >Only organization admins can create missions.</ApCallout
    >
    <ApPanel v-else index="M1" title="Mission">
      <form class="flex flex-col gap-3" @submit.prevent="submit">
        <ApField v-model="name" label="Name" required :error="failure?.name ?? null" />
        <ApField
          :model-value="slug"
          label="Slug"
          mono
          :error="taken"
          :hint="`Used in links: /console/${organization?.slug ?? '…'}/${slug || '…'}`"
          @update:model-value="((slugEdited = true), (slug = $event))"
        />
        <ApCallout v-if="failure?.text" tone="crit">{{ failure.text }}</ApCallout>
        <div class="flex flex-wrap gap-2">
          <ApButton
            variant="primary"
            type="submit"
            :disabled="blocked !== null"
            :disabled-reason="blocked ?? undefined"
            >Create mission</ApButton
          >
          <ApButton variant="ghost" :to="{ name: 'org.missions' }">Cancel</ApButton>
        </div>
      </form>
    </ApPanel>
  </div>
</template>
