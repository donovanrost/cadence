import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import CadenceStatusSymbol from "./CadenceStatusSymbol.vue";
import type { StatusSymbolRole } from "./status-symbol";

interface StatusSymbolArgs {
  label?: string;
  size: 16 | 20 | 24;
  status: StatusSymbolRole;
}

const vocabulary: Array<{
  description: string;
  geometry: string;
  role: StatusSymbolRole;
}> = [
  { role: "off", geometry: "Small circle", description: "Established inactive state" },
  { role: "standby", geometry: "Ring", description: "Ready, available, not active" },
  { role: "normal", geometry: "Large circle", description: "Positively assessed normal" },
  { role: "caution", geometry: "Square", description: "Awareness or monitoring required" },
  { role: "serious", geometry: "Diamond", description: "Prompt intervention required" },
  {
    role: "critical",
    geometry: "Downward triangle",
    description: "Immediate response required",
  },
];

const meta = {
  title: "Foundations/Symbology/Status Symbols",
  component: CadenceStatusSymbol,
  args: {
    label: "Telemetry assessment: caution",
    size: 24,
    status: "caution",
  },
  argTypes: {
    size: { control: "inline-radio", options: [16, 20, 24] },
    status: {
      control: "select",
      options: ["off", "standby", "normal", "caution", "serious", "critical", "unknown"],
    },
  },
  render: (args) => ({
    components: { CadenceStatusSymbol },
    setup: () => ({ args }),
    template: '<CadenceStatusSymbol v-bind="args" />',
  }),
} satisfies Meta<StatusSymbolArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const OperationalVocabulary: Story = {
  parameters: {
    layout: "fullscreen",
    controls: { disable: true },
  },
  render: () => ({
    components: { CadenceStatusSymbol },
    setup: () => ({ vocabulary }),
    template: `
      <main class="story-symbol-reference">
        <header class="story-symbol-reference__header">
          <p class="story-state">Cadence / operational symbology</p>
          <h1>Six shapes. Six learned states.</h1>
          <p>
            Geometry is the invariant. Color reinforces meaning; it never carries the state alone.
          </p>
        </header>

        <section class="story-symbol-grid" aria-label="Operational status vocabulary">
          <article
            v-for="(item, index) in vocabulary"
            :key="item.role"
            class="story-symbol-card"
            :data-status-card="item.role"
          >
            <div class="story-symbol-card__mark">
              <CadenceStatusSymbol
                :status="item.role"
                :size="24"
                :label="item.role + ' status'"
              />
            </div>
            <div class="story-symbol-card__copy">
              <div class="story-symbol-card__title">
                <span>{{ String(index + 1).padStart(2, '0') }}</span>
                <strong>{{ item.role }}</strong>
              </div>
              <p>{{ item.geometry }}</p>
              <small>{{ item.description }}</small>
            </div>
          </article>
        </section>

        <footer class="story-symbol-reference__footer">
          <span>Shape = status role</span>
          <span>Color = reinforcement</span>
          <span>Label = actual condition</span>
        </footer>
      </main>
    `,
  }),
  play: async ({ canvas }) => {
    for (const item of vocabulary) {
      await expect(canvas.getByRole("img", { name: `${item.role} status` })).toBeVisible();
    }
  },
};

export const SizeAndMonochromeVerification: Story = {
  parameters: { controls: { disable: true } },
  render: () => ({
    components: { CadenceStatusSymbol },
    setup: () => ({ sizes: [16, 20, 24], vocabulary }),
    template: `
      <div class="story-symbol-verification">
        <div v-for="size in sizes" :key="size" class="story-symbol-verification__row">
          <span>{{ size }} px</span>
          <CadenceStatusSymbol
            v-for="item in vocabulary"
            :key="item.role"
            :status="item.role"
            :size="size"
            :label="item.role + ' at ' + size + ' pixels'"
          />
        </div>
        <div class="story-symbol-verification__row story-symbol-verification__row--mono">
          <span>Mono</span>
          <CadenceStatusSymbol
            v-for="item in vocabulary"
            :key="item.role"
            :status="item.role"
            :size="24"
            :label="item.role + ' in monochrome'"
          />
        </div>
      </div>
    `,
  }),
};

export const CadenceUnknownExtension: Story = {
  args: {
    label: "Ground link status unknown",
    status: "unknown",
  },
};
