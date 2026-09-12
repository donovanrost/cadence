import PacketBindingsSurface from "./PacketBindingsSurface.vue";
export const packetBindingsContribution = {
  id: "telemetry-decom.packet-bindings",
  version: 1,
  applicationKey: "telemetry_decom",
  surfaceId: "packet_bindings",
  query: { id: "cadence.packet_bindings.manage", version: 1 },
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: PacketBindingsSurface,
  actionId: "save_packet_bindings",
} as const;
