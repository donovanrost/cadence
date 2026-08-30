import { createApp } from "vue";
import PhoenixHostApp from "./PhoenixHostApp.vue";
import type { PhoenixHostConfig } from "./phoenix-catalog-client";

export function readPhoenixHostConfig(root: HTMLElement): PhoenixHostConfig {
  const missionId = root.dataset.missionId?.trim();
  const catalogUrl = root.dataset.catalogUrl?.trim();

  if (!missionId || !catalogUrl) {
    throw new Error("The Phoenix federation root requires data-mission-id and data-catalog-url.");
  }

  return { missionId, catalogUrl };
}

export function bootstrapPhoenixHost(root: HTMLElement): void {
  const config = readPhoenixHostConfig(root);
  createApp(PhoenixHostApp, config as unknown as Record<string, unknown>).mount(root);
}
