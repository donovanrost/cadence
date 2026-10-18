export type MissionInput = { mission: { display_name: string; slug: string } };
export type CreateMission = (event: "validate" | "save", input: MissionInput) => Promise<unknown>;
