export const developmentPorts = Object.freeze({
  host: 5173,
  "telemetry-decom": 4174,
  "contract-probe": 4175,
  "comms-overview": 4176,
  "mission-catalog": 4177,
  "organization-admin": 4178,
  spacecraft: 4179,
  "ops-console": 4180,
});
export type DevelopmentService = keyof typeof developmentPorts;
export function developmentOrigin(service: DevelopmentService) {
  return `http://127.0.0.1:${developmentPorts[service]}`;
}
export function developmentServer(service: DevelopmentService) {
  return {
    host: "127.0.0.1",
    port: developmentPorts[service],
    strictPort: true,
    origin: developmentOrigin(service),
  };
}
export function developmentPreview(service: DevelopmentService) {
  const { host, port, strictPort } = developmentServer(service);
  return { host, port, strictPort };
}
