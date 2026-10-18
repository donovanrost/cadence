import "./styles.css";
import "./style.css";
import { bootstrapHost } from "./host-bootstrap";

const root = document.querySelector<HTMLElement>("#app");
if (root) bootstrapHost(root);
