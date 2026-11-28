export const developmentPorts = Object.freeze({
  host: 5173,
  "telemetry-decom": 4174,
  "organization-admin": 4178,
  "ops-console": 4180,
  console: 5181,
});
export type DevelopmentService = keyof typeof developmentPorts;
export function developmentOrigin(service: DevelopmentService) {
  const port =
    service === "console" && process.env.CONSOLE_VITE_PORT
      ? Number(process.env.CONSOLE_VITE_PORT)
      : developmentPorts[service];
  return `http://127.0.0.1:${port}`;
}
export function developmentServer(service: DevelopmentService) {
  return {
    host: "127.0.0.1",
    port: Number(new URL(developmentOrigin(service)).port),
    strictPort: true,
    origin: developmentOrigin(service),
  };
}
export function developmentPreview(service: DevelopmentService) {
  const { host, port, strictPort } = developmentServer(service);
  return { host, port, strictPort };
}
