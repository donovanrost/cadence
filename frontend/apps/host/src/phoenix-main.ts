import "@cadence/design-tokens/base.css";
import { bootstrapPhoenixHost } from "./phoenix-bootstrap";

const root = document.querySelector<HTMLElement>("#cadence-federation-root");
if (root) bootstrapPhoenixHost(root);
