import { configurationContribution } from "./features/configuration/contribution";
import { packetBindingsContribution } from "./features/packet-bindings/contribution";
export const contributions = [configurationContribution, packetBindingsContribution] as const;
