<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { useConsoleScope } from "@/shell";
import {
  ApBreadcrumb,
  ApButton,
  ApCallout,
  ApField,
  ApPageHeader,
  ApPanel,
  ApSegmented,
  ApSelect,
  refocusFirst,
} from "@/ui";
import TokenOnce from "./TokenOnce.vue";
import {
  createServiceIdentity,
  serviceFailure,
  type Issued,
  type ServiceScope,
} from "./services.ts";

/** U3 · New service identity (O6): name + scope; the token is shown once afterwards. */
const scope = useConsoleScope();
const org = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const name = ref("");
const reach = ref<ServiceScope>("mission_admin");
const missionId = ref("");
const errors = ref<Record<string, string>>({});
const failure = ref<string | null>(null);
const busy = ref(false);
const issued = ref<Issued | null>(null);
const reachOptions = [
  { value: "mission_admin", label: "One mission" },
  { value: "organization_admin", label: "Every mission" },
];
const missionOptions = computed(() => [
  { value: "", label: "Choose a mission" },
  ...(org.value?.missions ?? []).map((m) => ({ value: m.id, label: m.name })),
]);
const setReach = (v: string) => {
  if (v === "mission_admin" || v === "organization_admin") reach.value = v;
};

async function create() {
  if (!org.value || busy.value) return;
  const local: Record<string, string> = {};
  if (!name.value.trim()) local["name"] = "Name the identity.";
  if (reach.value === "mission_admin" && !missionId.value)
    local["mission_id"] = "Choose a mission.";
  errors.value = local;
  failure.value = null;
  if (Object.keys(local).length > 0) return;
  busy.value = true;
  try {
    const r = await createServiceIdentity(org.value.id, {
      name: name.value.trim(),
      scope: reach.value,
      missionId: missionId.value || null,
    });
    if (r.ok) {
      issued.value = r.value;
      // a11y A5: the form (and its focused Create) is replaced; land on "Created", then Copy is next.
      await nextTick();
      return refocusFirst(document.querySelector<HTMLElement>("[data-service-created]"));
    }
    const f = serviceFailure(r.error);
    errors.value = { ...f.fields };
    failure.value = f.text;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[760px] flex-col gap-4">
    <ApBreadcrumb
      :crumbs="[
        { label: 'People & access', to: { name: 'org.people', query: { tab: 'services' } } },
        { label: 'New service identity' },
      ]"
    />
    <ApPageHeader label="Service identities" title="New service identity" size="reading" />
    <ApPanel v-if="issued" index="U3" :title="issued.service_identity.name">
      <div class="flex flex-col gap-4">
        <ApCallout data-service-created tone="nominal"
          >Created. Give this token to the pipeline that uses it.</ApCallout
        >
        <TokenOnce :token="issued.api_token" />
        <ApButton
          :to="{ name: 'org.people.service', params: { serviceId: issued.service_identity.id } }"
          >Done</ApButton
        >
      </div>
    </ApPanel>
    <ApPanel v-else index="U3" title="Identity">
      <form class="flex flex-col gap-4" @submit.prevent="create">
        <ApField v-model="name" label="Name" mono :error="errors['name'] ?? null" />
        <ApSegmented
          :model-value="reach"
          label="Reach"
          :options="reachOptions"
          @update:model-value="setReach"
        />
        <ApSelect
          v-if="reach === 'mission_admin'"
          v-model="missionId"
          label="Mission"
          :options="missionOptions"
          :error="errors['mission_id'] ?? null"
        />
        <ApCallout v-if="failure" tone="caution">{{ failure }}</ApCallout>
        <div>
          <ApButton type="submit" variant="primary" :disabled="busy" disabled-reason="Creating…"
            >Create and show the token</ApButton
          >
        </div>
      </form>
    </ApPanel>
  </div>
</template>
