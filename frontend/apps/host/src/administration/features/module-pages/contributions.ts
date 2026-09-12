import { createPageRegistry } from "../../../shell/module-pages/lazy-pages";
import {
  ORGANIZATION_PAGE_SLOT,
  type OrganizationPageContribution,
} from "@cadence/plugin-sdk/organization-pages";
import type { Component } from "vue";

export function admitOrganizationPages(items: readonly OrganizationPageContribution<Component>[]) {
  const entries = new Map<string, OrganizationPageContribution<Component>>();
  for (const item of items) {
    if (
      item.slot !== ORGANIZATION_PAGE_SLOT ||
      item.version !== 1 ||
      !/^[a-z][a-z0-9.-]+$/.test(item.id) ||
      entries.has(item.id) ||
      typeof item.read !== "function" ||
      (item.actions !== undefined &&
        (!isArray(item.actions) ||
          new Set(item.actions).size !== item.actions.length ||
          item.actions.some((action) => !/^[a-z][a-z0-9.-]*$/.test(action))))
    ) {
      throw new Error("Invalid organization page contribution.");
    }
    entries.set(
      item.id,
      Object.freeze({
        ...item,
        ...(item.actions ? { actions: Object.freeze([...item.actions]) } : {}),
      }),
    );
  }
  return Object.freeze(Object.fromEntries(entries));
}
export const organizationModulePages = createPageRegistry<OrganizationPageContribution<Component>>(
  "organization.page",
  {
    "comms.provider-account-directory": () =>
      import("@cadence/communications/provider-accounts").then(
        (module) => module.providerAccountDirectoryContribution,
      ),
    "comms.provider-account-registration": () =>
      import("@cadence/communications/provider-accounts").then(
        (module) => module.providerAccountRegistrationContribution,
      ),
    "comms.provider-account-detail": () =>
      import("@cadence/communications/provider-accounts").then(
        (module) => module.providerAccountDetailContribution,
      ),
  },
  admitOrganizationPages,
);

// Inspect runtime input without widening the already declared readonly action type to any[].
function isArray(value: unknown): boolean {
  return Array.isArray(value);
}
