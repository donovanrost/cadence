import {
  ORGANIZATION_PAGE_SLOT,
  type OrganizationPageContribution,
} from "@cadence/plugin-sdk/organization-pages";
import type { Component } from "vue";
import ProviderAccountListPage from "./ProviderAccountListPage.vue";
import { readAccountDirectory } from "./list.validation";

export const providerAccountDirectoryContribution: OrganizationPageContribution<Component> =
  Object.freeze({
    id: "comms.provider-account-directory",
    slot: ORGANIZATION_PAGE_SLOT,
    version: 1,
    title: "Provider accounts",
    component: ProviderAccountListPage,
    read: (value, context) => readAccountDirectory(value, context.organizationId),
  });
