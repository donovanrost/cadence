import { describe, expect, it } from "vite-plus/test";
import type { DirectoryRow } from "./api.ts";
import { spacecraftText, spacecraftWord, updatedText, updatedWord } from "./row-words.ts";

const row = (over: Partial<DirectoryRow>): DirectoryRow => ({
  id: "dash-1",
  name: "Thermal",
  description: null,
  tags: [],
  archived: false,
  starred: false,
  current_version: 1,
  updated_at: null,
  updated_by: null,
  viewed_at: null,
  spacecraft: undefined,
  ...over,
});

describe("directory row words", () => {
  it("is null when unknown (phone rows drop the part) and '—' in the table", () => {
    const unknown = row({ spacecraft: undefined, updated_at: null });
    expect([spacecraftText(unknown), updatedText(unknown)]).toEqual([null, null]);
    expect([spacecraftWord(unknown), updatedWord(unknown)]).toEqual(["—", "—"]);
    expect(spacecraftText(row({ spacecraft: null }))).toBe("No widgets");
  });
});
