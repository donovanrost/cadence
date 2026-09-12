import PacketBindingsSurface from "./PacketBindingsSurface.vue";
export const packetBindingsContribution = {
  id: "telemetry-decom.packet-bindings",
  version: 1,
  applicationKey: "telemetry_decom",
  surfaceId: "packet_bindings",
  query: { id: "cadence.packet_bindings.manage", version: 1 },
  component: PacketBindingsSurface,
  actionId: "save_packet_bindings",
} as const;
