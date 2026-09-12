import type { OrganizationPageContribution } from "@cadence/plugin-sdk/organization-pages";
import ProviderAccountRegistrationPage from "./ProviderAccountRegistrationPage.vue";
import { readRegistration } from "./registration.validation";

export const providerAccountRegistrationContribution: OrganizationPageContribution<
  typeof ProviderAccountRegistrationPage
> = {
  id: "comms.provider-account-registration",
  slot: "organization.page",
  version: 1,
  title: "Register provider account",
  component: ProviderAccountRegistrationPage,
  actions: ["validate", "save"],
  read: (value, context) => ({
    model: readRegistration(value, 1),
    organizationId: context.organizationId,
  }),
};
