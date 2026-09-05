export { default as FullPageSurface } from "./FullPageSurface.vue";
export {
  createApplicationContributionRegistry,
  type ApplicationContributionRegistry,
} from "./contribution-registry";
export { mountFullPageSurface, type FullPageSurfaceMount } from "./surface-mount";
export { bootstrapHost, type HostAppProps } from "./host-bootstrap";
export {
  APPROVED_FIRST_PARTY_APPLICATIONS,
  assertKnownFirstPartyIdentity,
  createHostContributionBootstrap,
  type HostContributionBootstrap,
  type HostRemoteModule,
} from "./first-party-composition";
