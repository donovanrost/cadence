import type { SelectedCommand } from "./contracts";

export function opcodeLabel(
  command: Pick<SelectedCommand, "opcode_json" | "opcode_size_bits">,
): string | null {
  if (!/^(0|[1-9]\d*)$/.test(command.opcode_json)) return null;
  // Parse the catalog's exact integer text without going through a JavaScript number.
  const hex = BigInt(command.opcode_json).toString(16).toUpperCase().padStart(2, "0");
  return `Opcode 0x${hex}${command.opcode_size_bits === null ? "" : ` · ${command.opcode_size_bits} bits`}`;
}
