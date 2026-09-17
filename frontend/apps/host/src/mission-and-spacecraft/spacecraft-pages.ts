import type { Component } from "vue";
import SpacecraftConfigurationPage from "./features/spacecraft-configuration/SpacecraftConfigurationPage.vue";
import { readConfiguration } from "./features/spacecraft-configuration/contracts";
import SpacecraftShow from "./features/spacecraft-overview/SpacecraftShow.vue";
import { assertSpacecraftOverview } from "./features/spacecraft-overview/validation";
import SpacecraftReadiness from "./features/spacecraft-readiness/SpacecraftReadiness.vue";
import { assertSpacecraftReadiness } from "./features/spacecraft-readiness/validation";
import SpacecraftTypeNew from "./features/profile-creation/SpacecraftTypeNew.vue";
import { assertProfileForm } from "./features/profile-creation/validation";
import SpacecraftIdentityForm from "./features/spacecraft-identity/SpacecraftIdentityForm.vue";
import {
  assertNewIdentityForm,
  assertEditIdentityForm,
} from "./features/spacecraft-identity/validation";
import SpacecraftListPage from "./features/spacecraft-directory/SpacecraftListPage.vue";
import SpacecraftTypeListPage from "./features/spacecraft-profiles/SpacecraftTypeListPage.vue";
import SpacecraftTypeShow from "./features/spacecraft-profiles/SpacecraftTypeShow.vue";
import { assertSpacecraftDirectory } from "./features/spacecraft-directory/validation";
import {
  assertProfileDirectory,
  assertProfileDetail,
} from "./features/spacecraft-profiles/validation";
export const spacecraftPages: Record<
  string,
  { component: Component; validate: (value: unknown) => void }
> = {
  spacecraft_configuration: { component: SpacecraftConfigurationPage, validate: readConfiguration },
  spacecraft_new: { component: SpacecraftIdentityForm, validate: assertNewIdentityForm },
  spacecraft_show: { component: SpacecraftShow, validate: assertSpacecraftOverview },
  spacecraft_readiness: { component: SpacecraftReadiness, validate: assertSpacecraftReadiness },
  spacecraft_edit: { component: SpacecraftIdentityForm, validate: assertEditIdentityForm },
  spacecraft_list: { component: SpacecraftListPage, validate: assertSpacecraftDirectory },
  profile_list: { component: SpacecraftTypeListPage, validate: assertProfileDirectory },
  profile_new: { component: SpacecraftTypeNew, validate: assertProfileForm },
  profile_show: { component: SpacecraftTypeShow, validate: assertProfileDetail },
};
