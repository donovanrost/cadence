// Settings ownership and compiled host contribution; legacy delivery only links here.
export { default as DashboardSettings } from "./features/settings/DashboardSettings.vue";
export { default as SettingsLegacyRedirect } from "./features/settings/SettingsLegacyRedirect.vue";
export { settingsContribution } from "./features/settings/contribution";
export { readSettingsModel, readSettingsState } from "./features/settings/validation";
export type { SettingsModel, SettingsState } from "./features/settings/contracts";
