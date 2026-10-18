import { expect, test } from "vite-plus/test";
import { required } from "../../../../../test-support/required";
import { pageFixture } from "../../features/command-authoring/fixtures.test-support";
import { readCatalog } from "./contracts";
import { opcodeLabel } from "./opcode";

test.each([
  ["34", 8, "Opcode 0x22 · 8 bits"],
  ["0", 8, "Opcode 0x00 · 8 bits"],
  ["9007199254740993", 64, "Opcode 0x20000000000001 · 64 bits"],
  ["null", null, null],
  ['"DISABLE_LOAD"', null, null],
  ["-1", 8, null],
] as const)(
  "formats the catalog opcode %s without rounding",
  (opcode_json, opcode_size_bits, label) => {
    expect(opcodeLabel({ opcode_json, opcode_size_bits })).toBe(label);
  },
);

test("the catalog boundary validates opcode metadata and retains exact integers", () => {
  const catalog = pageFixture().catalog;
  const command = required(catalog.selected_command);
  const read = (fields: Record<string, unknown>) =>
    readCatalog({ ...catalog, selected_command: { ...command, ...fields } }, catalog.context);
  expect(
    read({ opcode_json: "9007199254740993", opcode_size_bits: 64 }).selected_command?.opcode_json,
  ).toBe("9007199254740993");
  expect(
    read({ opcode_json: "null", opcode_size_bits: null }).selected_command?.opcode_size_bits,
  ).toBeNull();
  for (const fields of [
    { opcode_json: 34 },
    { opcode_json: "0x22" },
    { opcode_json: undefined },
    { opcode_size_bits: undefined },
    { opcode_size_bits: 0 },
    { opcode_size_bits: -1 },
    { opcode_size_bits: 1.5 },
    { opcode_size_bits: 8388609 },
  ])
    expect(() => read(fields)).toThrow();
});
