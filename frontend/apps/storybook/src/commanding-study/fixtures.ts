// Development-only design fixtures. These are not mission observations or command contracts.
export type CommandId =
  | "NOOP"
  | "SET_TLM_RATE"
  | "SET_ATTITUDE"
  | "CAPTURE_IMAGE"
  | "RESET_COMPUTER";
export type Command = {
  id: CommandId;
  title: string;
  subsystem: string;
  icon: string;
  description: string;
  effect: string;
  choices: string[];
  defaultValue: string;
  setting: string;
  hazardous: boolean;
};
export type Spacecraft = {
  id: string;
  endpoint: string;
  plane: string;
  health: "normal" | "caution" | "unknown";
  condition: string;
  contact: boolean;
  battery: number | null;
  model: string;
  supports: CommandId[];
};
const standard: CommandId[] = [
  "NOOP",
  "SET_TLM_RATE",
  "SET_ATTITUDE",
  "CAPTURE_IMAGE",
  "RESET_COMPUTER",
];
export const fleet: Spacecraft[] = [
  {
    id: "KESTREL-01",
    endpoint: "obc-01",
    plane: "A",
    health: "normal",
    condition: "Nominal",
    contact: true,
    battery: 92,
    model: "3.2",
    supports: standard,
  },
  {
    id: "KESTREL-02",
    endpoint: "obc-02",
    plane: "A",
    health: "normal",
    condition: "Nominal",
    contact: true,
    battery: 87,
    model: "3.2",
    supports: standard,
  },
  {
    id: "KESTREL-03",
    endpoint: "obc-03",
    plane: "A",
    health: "caution",
    condition: "Battery caution",
    contact: true,
    battery: 28,
    model: "3.2",
    supports: standard,
  },
  {
    id: "KESTREL-04",
    endpoint: "obc-04",
    plane: "A",
    health: "normal",
    condition: "Nominal",
    contact: false,
    battery: 84,
    model: "3.2",
    supports: standard,
  },
  {
    id: "KESTREL-05",
    endpoint: "obc-05",
    plane: "B",
    health: "normal",
    condition: "Nominal",
    contact: true,
    battery: 96,
    model: "3.2",
    supports: standard,
  },
  {
    id: "KESTREL-06",
    endpoint: "obc-06",
    plane: "B",
    health: "normal",
    condition: "Nominal",
    contact: false,
    battery: 78,
    model: "3.2",
    supports: standard,
  },
  {
    id: "KESTREL-07",
    endpoint: "obc-07",
    plane: "B",
    health: "normal",
    condition: "Nominal",
    contact: true,
    battery: 89,
    model: "3.1",
    supports: ["NOOP", "SET_TLM_RATE", "SET_ATTITUDE", "RESET_COMPUTER"],
  },
  {
    id: "KESTREL-08",
    endpoint: "obc-08",
    plane: "B",
    health: "unknown",
    condition: "Telemetry stale",
    contact: false,
    battery: null,
    model: "3.1",
    supports: ["NOOP", "SET_TLM_RATE", "SET_ATTITUDE", "RESET_COMPUTER"],
  },
];
export const commands: Command[] = [
  {
    id: "NOOP",
    title: "Check command path",
    subsystem: "C&DH",
    icon: "hero-signal",
    description: "Verify the command path with a no-operation command.",
    effect: "Returns a command acknowledgement. Spacecraft configuration is unchanged.",
    choices: [],
    defaultValue: "",
    setting: "",
    hazardous: false,
  },
  {
    id: "SET_TLM_RATE",
    title: "Set telemetry interval",
    subsystem: "C&DH",
    icon: "hero-chart-bar",
    description: "Change the interval between housekeeping packets.",
    effect: "Housekeeping telemetry uses the selected interval after execution.",
    choices: ["1 s", "5 s", "10 s", "30 s"],
    defaultValue: "5 s",
    setting: "Packet interval",
    hazardous: false,
  },
  {
    id: "SET_ATTITUDE",
    title: "Set attitude mode",
    subsystem: "ADCS",
    icon: "hero-arrows-pointing-out",
    description: "Select the spacecraft's attitude control mode.",
    effect: "The attitude controller transitions to the selected mode.",
    choices: ["Sun pointing", "Nadir pointing", "Safe hold"],
    defaultValue: "Sun pointing",
    setting: "Attitude mode",
    hazardous: false,
  },
  {
    id: "CAPTURE_IMAGE",
    title: "Capture an image",
    subsystem: "Payload",
    icon: "hero-camera",
    description: "Acquire one image with the primary optical payload.",
    effect: "Captures one frame per spacecraft and writes it to onboard storage.",
    choices: ["10 ms", "25 ms", "50 ms", "100 ms"],
    defaultValue: "25 ms",
    setting: "Exposure",
    hazardous: false,
  },
  {
    id: "RESET_COMPUTER",
    title: "Restart flight computer",
    subsystem: "C&DH",
    icon: "hero-arrow-path",
    description: "Restart the primary onboard flight computer.",
    effect:
      "Interrupts onboard processing and telemetry during the restart. Requires separate approval before release.",
    choices: [],
    defaultValue: "",
    setting: "",
    hazardous: true,
  },
];
export type Draft = { value: string; overrides: Record<string, string> };
export type StagedItem = { id: number; target: Spacecraft; command: Command; value: string };
export type Execution = StagedItem & {
  status:
    | "Queued"
    | "Waiting for contact"
    | "Awaiting approval"
    | "Awaiting verification"
    | "Verified";
};
