<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import { spacecraftPages } from "./spacecraft-pages";
import { record } from "./shared/validation";
import type { NavigateDirectory } from "./features/spacecraft-directory/contracts";
import SpacecraftIdentityPage from "./features/spacecraft-identity/SpacecraftIdentityPage.vue";
import ProfileCreationPage from "./features/profile-creation/ProfileCreationPage.vue";
import type { IdentityAction } from "./features/spacecraft-identity/contracts";
import SpacecraftConfigurationPage from "./features/spacecraft-configuration/SpacecraftConfigurationPage.vue";
import { readConfiguration } from "./features/spacecraft-configuration/contracts";
import type {
  ConfigurationPort,
  ConfigurationIdentity,
  ConfigurationDrafts,
} from "./configuration";
const props = defineProps<{
  page: string;
  snapshot: unknown;
  navigate: NavigateDirectory;
  navigating?: boolean;
  execute?: IdentityAction & import("./features/profile-creation/contracts").ProfileAction;
  refresh: () => Promise<void>;
  configurationPort?: ConfigurationPort;
  configurationIdentity?: ConfigurationIdentity;
  configurationDrafts?: ConfigurationDrafts;
}>();
const crashed = ref(false);
watch(
  () => props.snapshot,
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const admitted = computed(() => {
  const snapshot = props.snapshot;
  if (props.page === "spacecraft_configuration") {
    if (
      !props.configurationPort ||
      !props.configurationIdentity ||
      !props.configurationDrafts ||
      !record(snapshot) ||
      snapshot.page !== props.page ||
      snapshot.version !== 1 ||
      snapshot.status !== "ready"
    )
      return null;
    try {
      return {
        component: SpacecraftConfigurationPage,
        data: readConfiguration(snapshot.data, props.configurationIdentity),
        formToken: null,
      };
    } catch {
      return null;
    }
  }
  if (
    ["spacecraft_new", "spacecraft_edit", "profile_new"].includes(props.page) &&
    (!props.execute ||
      !record(snapshot) ||
      typeof snapshot.form_token !== "string" ||
      !snapshot.form_token)
  )
    return null;
  if (
    !Object.hasOwn(spacecraftPages, props.page) ||
    !record(snapshot) ||
    snapshot.page !== props.page ||
    snapshot.version !== 1 ||
    snapshot.status !== "ready" ||
    !record(snapshot.data)
  )
    return null;
  const registration = spacecraftPages[props.page];
  if (!registration) return null;
  try {
    registration.validate(snapshot.data);
    return {
      ...registration,
      data: snapshot.data,
      formToken: typeof snapshot.form_token === "string" ? snapshot.form_token : null,
    };
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="core-spacecraft-page">
    <div
      v-if="crashed || !admitted"
      id="core-spacecraft-error"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This spacecraft page is unavailable.</p>
      <button id="core-spacecraft-retry" type="button" class="btn btn-sm mt-4" @click="refresh">
        Retry
      </button>
    </div>
    <SpacecraftConfigurationPage
      v-else-if="
        page === 'spacecraft_configuration' &&
        configurationPort &&
        configurationIdentity &&
        configurationDrafts
      "
      :data="admitted.data"
      :port="configurationPort"
      :identity="configurationIdentity"
      :drafts="configurationDrafts"
    />
    <ProfileCreationPage
      v-else-if="page === 'profile_new' && execute"
      :key="admitted.formToken ?? page"
      :data="admitted.data"
      :execute="execute"
    />
    <SpacecraftIdentityPage
      v-else-if="['spacecraft_new', 'spacecraft_edit'].includes(page) && execute"
      :key="admitted.formToken ?? page"
      :data="admitted.data"
      :execute="execute"
    />
    <component
      :is="admitted.component"
      v-else
      v-bind="{
        ...admitted.data,
        ...(page === 'spacecraft_list' ? { navigate, navigating } : {}),
      }"
    />
  </section>
</template>
