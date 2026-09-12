import { defineComponent, h } from "vue";

const genericCatalogUrl = "/api/cadence/application-host/v1/catalog";

export type FederatedHostScope = "organization" | "user" | "admin" | "mission" | "spacecraft";

export function catalogUrlForPlacement(
  hostScope: FederatedHostScope | undefined,
  applicationKey?: string,
  surfaceId?: string,
  missionId?: string,
  spacecraftId?: string,
  organizationId?: string,
  userId?: string,
): string {
  if (!applicationKey || !surfaceId) return genericCatalogUrl;

  const path =
    hostScope === "mission" && missionId
      ? `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog`
      : hostScope === "spacecraft" && missionId && spacecraftId
        ? `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog`
        : genericCatalogUrl;

  const query = new URLSearchParams({ application_key: applicationKey, surface_id: surfaceId });
  if (hostScope === "organization" && organizationId) {
    query.set("scope", "organization");
    query.set("organization_id", organizationId);
  } else if (hostScope === "user" && userId) {
    query.set("scope", "user");
    query.set("user_id", userId);
  } else if (hostScope === "admin") {
    query.set("scope", "admin");
  } else if (hostScope === "mission" && missionId) {
    query.set("scope", "mission");
    query.set("mission_id", missionId);
  } else if (hostScope === "spacecraft" && missionId && spacecraftId) {
    query.set("scope", "spacecraft");
    query.set("mission_id", missionId);
    query.set("spacecraft_id", spacecraftId);
  }
  return `${path}?${query.toString()}`;
}

type SurfaceProps = {
  surfaceId?: string;
  applicationKey?: string;
  hostScope?: FederatedHostScope;
  organizationId?: string;
  userId?: string;
  missionId?: string;
  spacecraftId?: string;
  queryParams?: unknown;
  application_key?: string;
  surface_id?: string;
  host_scope?: FederatedHostScope;
  organization_id?: string;
  user_id?: string;
  mission_id?: string;
  spacecraft_id?: string;
  query_params?: unknown;
};

export const FederatedFullPageSurface = defineComponent({
  name: "FederatedFullPageSurface",
  inheritAttrs: false,
  props: {
    applicationKey: String,
    surfaceId: String,
    hostScope: String,
    organizationId: String,
    userId: String,
    missionId: String,
    spacecraftId: String,
    queryParams: Object,
    application_key: String,
    surface_id: String,
    host_scope: String,
    organization_id: String,
    user_id: String,
    mission_id: String,
    spacecraft_id: String,
    query_params: Object,
  },
  setup(props: SurfaceProps, { attrs }) {
    return () => {
      const applicationKey = props.applicationKey ?? props.application_key;
      const surfaceId = props.surfaceId ?? props.surface_id;
      const hostScope = props.hostScope ?? props.host_scope;
      const organizationId = props.organizationId ?? props.organization_id;
      const userId = props.userId ?? props.user_id;
      const missionId = props.missionId ?? props.mission_id;
      const spacecraftId = props.spacecraftId ?? props.spacecraft_id;
      const queryParams = props.queryParams ?? props.query_params;
      const queryParamsJson = serializeQueryParams(queryParams);
      const safeAttrs = {
        class: typeof attrs.class === "string" ? attrs.class : undefined,
        ...(typeof attrs.style === "string" ? { style: attrs.style } : {}),
      };

      if (!applicationKey || !surfaceId || !hostScope) {
        return h("div", {
          ...safeAttrs,
          id: "cadence-federation-root",
          "data-query-params": queryParamsJson,
        });
      }

      return h("div", {
        ...safeAttrs,
        id: "cadence-federation-root",
        "data-organization-id": organizationId,
        "data-user-id": userId,
        "data-mission-id": missionId,
        "data-spacecraft-id": spacecraftId,
        "data-host-scope": hostScope,
        "data-application-key": applicationKey,
        "data-surface-id": surfaceId,
        "data-catalog-url": catalogUrlForPlacement(
          hostScope,
          applicationKey,
          surfaceId,
          missionId,
          spacecraftId,
          organizationId,
          userId,
        ),
        "data-fallback-href": globalThis.location?.href ?? "/",
        "data-query-params": queryParamsJson,
      });
    };
  },
});

function serializeQueryParams(value: unknown): string {
  if (value === undefined) return "{}";

  if (!isPlainObject(value)) return "null";

  try {
    const serialized = JSON.stringify(value);
    return serialized ?? "null";
  } catch {
    return "null";
  }
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}
