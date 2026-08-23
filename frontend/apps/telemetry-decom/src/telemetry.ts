export interface PacketBinding {
  apid: number;
  description: string;
  fieldCount: number;
  name: string;
  rateHz: number;
  selected: boolean;
}

export interface PacketBindingsData {
  configurationVersion: number;
  packets: PacketBinding[];
  queryVersion: 1;
  revision: {
    id: string;
    importedAt: string;
    label: string;
  };
  sourceEndpoint: {
    id: string;
    label: string;
    status: "connected" | "disconnected";
  };
}

export interface SavePacketBindingsResult {
  configurationVersion: number;
  selectedCount: number;
}

export function filterPackets(
  packets: readonly PacketBinding[],
  search: string,
  selectedOnly: boolean,
  selection: ReadonlySet<number>,
): PacketBinding[] {
  const term = search.trim().toLocaleLowerCase();

  return packets.filter((packet) => {
    if (selectedOnly && !selection.has(packet.apid)) return false;
    if (term.length === 0) return true;

    return (
      packet.name.toLocaleLowerCase().includes(term) ||
      packet.description.toLocaleLowerCase().includes(term) ||
      String(packet.apid).includes(term)
    );
  });
}
