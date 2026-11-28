import { createPageRegistry } from "../../../shell/module-pages/lazy-pages";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import type { Component } from "vue";
export const opsPages = createPageRegistry<OpsPageContribution<Component>>("ops.page", {});
