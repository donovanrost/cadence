defmodule CadenceWeb.DesignSystemLive.Index do
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto">
      <.header>
        Design System
        <:subtitle>
          Cadence's vaporwave/Tokyo Night inspired design language and component library
        </:subtitle>
      </.header>
      
    <!-- Color Palette -->
      <div class="mt-8">
        <h2 class="text-2xl font-bold mb-4">Color Palette</h2>
        
    <!-- Dark Mode Colors -->
        <div class="mb-6">
          <h3 class="text-lg font-semibold mb-3">Dark Mode (Tokyo Night)</h3>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-primary flex items-center justify-center text-primary-content">
                Primary
              </div>
              <p class="text-sm">Bright Cyan<br />#7dcfff</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-secondary flex items-center justify-center text-secondary-content">
                Secondary
              </div>
              <p class="text-sm">Purple<br />#bb9af7</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-accent flex items-center justify-center text-accent-content">
                Accent
              </div>
              <p class="text-sm">Hot Pink<br />#ff007c</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-neutral flex items-center justify-center text-neutral-content">
                Neutral
              </div>
              <p class="text-sm">Gray-Blue<br />#3b4261</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-info flex items-center justify-center text-info-content">
                Info
              </div>
              <p class="text-sm">Blue<br />#7aa2f7</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-success flex items-center justify-center text-success-content">
                Success
              </div>
              <p class="text-sm">Cyan-Teal<br />#73daca</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-warning flex items-center justify-center text-warning-content">
                Warning
              </div>
              <p class="text-sm">Orange<br />#ff9e64</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-error flex items-center justify-center text-error-content">
                Error
              </div>
              <p class="text-sm">Coral-Red<br />#f7768e</p>
            </div>
          </div>
        </div>
        
    <!-- Base Colors -->
        <div class="mb-6">
          <h3 class="text-lg font-semibold mb-3">Background & Surface Colors</h3>
          <div class="grid grid-cols-3 gap-4">
            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-base-100 border border-base-300 flex items-center justify-center">
                Base 100
              </div>
              <p class="text-sm">Main Background</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-base-200 border border-base-300 flex items-center justify-center">
                Base 200
              </div>
              <p class="text-sm">Cards, Surfaces</p>
            </div>

            <div class="space-y-2">
              <div class="h-20 rounded-lg bg-base-300 border border-base-300 flex items-center justify-center">
                Base 300
              </div>
              <p class="text-sm">Elevated Surfaces</p>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Typography -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Typography</h2>
        <div class="space-y-4">
          <div>
            <h1 class="text-4xl font-bold">Heading 1 - 4xl Bold</h1>
            <code class="text-sm text-base-content/60">text-4xl font-bold</code>
          </div>
          <div>
            <h2 class="text-3xl font-bold">Heading 2 - 3xl Bold</h2>
            <code class="text-sm text-base-content/60">text-3xl font-bold</code>
          </div>
          <div>
            <h3 class="text-2xl font-semibold">Heading 3 - 2xl Semibold</h3>
            <code class="text-sm text-base-content/60">text-2xl font-semibold</code>
          </div>
          <div>
            <h4 class="text-xl font-semibold">Heading 4 - xl Semibold</h4>
            <code class="text-sm text-base-content/60">text-xl font-semibold</code>
          </div>
          <div>
            <p class="text-base">Body text - Base size, regular weight</p>
            <code class="text-sm text-base-content/60">text-base</code>
          </div>
          <div>
            <p class="text-sm">Small text - sm size</p>
            <code class="text-sm text-base-content/60">text-sm</code>
          </div>
          <div>
            <p class="text-xs">Extra small text - xs size</p>
            <code class="text-sm text-base-content/60">text-xs</code>
          </div>
        </div>
      </div>
      
    <!-- Buttons -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Buttons</h2>
        <div class="flex flex-wrap gap-4">
          <.button>Primary Button</.button>
          <.button variant="primary">Explicit Primary</.button>
          <button class="btn">Default Button</button>
          <button class="btn btn-secondary">Secondary Button</button>
          <button class="btn btn-accent">Accent Button</button>
          <button class="btn btn-ghost">Ghost Button</button>
          <button class="btn btn-sm">Small Button</button>
          <button class="btn btn-lg">Large Button</button>
          <button class="btn" disabled>Disabled</button>
        </div>

        <div class="mt-4 p-4 bg-base-200 rounded-lg">
          <pre class="text-sm"><code>&lt;.button&gt;Primary Button&lt;/.button&gt;
          &lt;button class="btn btn-secondary"&gt;Secondary&lt;/button&gt;</code></pre>
        </div>
      </div>
      
    <!-- Badges -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Badges</h2>
        <div class="flex flex-wrap gap-3">
          <.badge>Default</.badge>
          <.badge variant="primary">Primary</.badge>
          <.badge variant="secondary">Secondary</.badge>
          <.badge variant="accent">Accent</.badge>
          <.badge variant="info">Info</.badge>
          <.badge variant="success">Success</.badge>
          <.badge variant="warning">Warning</.badge>
          <.badge variant="error">Error</.badge>
        </div>

        <div class="mt-4 p-4 bg-base-200 rounded-lg">
          <pre class="text-sm"><code>&lt;.badge variant="primary"&gt;Primary&lt;/.badge&gt;</code></pre>
        </div>
      </div>
      
    <!-- Avatars -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Avatars</h2>
        <div class="flex flex-wrap gap-4 items-end">
          <.avatar email="john@example.com" size="sm" />
          <.avatar email="jane@example.com" size="md" />
          <.avatar email="admin@example.com" size="lg" />
          <.avatar email="user@cadence.com" name="Test User" size="md" />
        </div>

        <div class="mt-4 p-4 bg-base-200 rounded-lg">
          <pre class="text-sm"><code>&lt;.avatar email="user@example.com" /&gt;
    &lt;.avatar email="user@example.com" name="Full Name" size="lg" /&gt;</code></pre>
        </div>
      </div>
      
    <!-- Forms -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Form Elements</h2>
        <div class="max-w-md space-y-4">
          <div class="fieldset mb-2">
            <label>
              <span class="label mb-1">Text Input</span>
              <input type="text" placeholder="Enter text..." class="w-full input" />
            </label>
          </div>

          <div class="fieldset mb-2">
            <label>
              <span class="label mb-1">Select</span>
              <select class="w-full select">
                <option>Option 1</option>
                <option>Option 2</option>
                <option>Option 3</option>
              </select>
            </label>
          </div>

          <div class="fieldset mb-2">
            <label>
              <span class="label mb-1">Textarea</span>
              <textarea class="w-full textarea" placeholder="Enter text..."></textarea>
            </label>
          </div>

          <div class="fieldset mb-2">
            <label>
              <span class="label">
                <input type="checkbox" class="checkbox checkbox-sm" /> Checkbox Label
              </span>
            </label>
          </div>
        </div>
      </div>
      
    <!-- Vaporwave Effects -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Vaporwave Effects</h2>

        <h3 class="text-lg font-semibold mb-3">Glow Effects</h3>
        <div class="flex flex-wrap gap-6 mb-6">
          <div class="p-6 bg-base-200 rounded-lg glow-cyan">
            Cyan Glow
          </div>
          <div class="p-6 bg-base-200 rounded-lg glow-purple">
            Purple Glow
          </div>
          <div class="p-6 bg-base-200 rounded-lg glow-pink">
            Pink Glow
          </div>
          <div class="p-6 bg-base-200 rounded-lg hover-glow-cyan">
            Hover for Cyan Glow
          </div>
        </div>

        <div class="p-4 bg-base-200 rounded-lg">
          <pre class="text-sm"><code>class="glow-cyan"
    class="glow-purple"
    class="glow-pink"
    class="hover-glow-cyan"</code></pre>
        </div>

        <h3 class="text-lg font-semibold mb-3 mt-6">Gradients</h3>
        <div class="space-y-4">
          <div class="h-24 rounded-lg gradient-vaporwave flex items-center justify-center text-white font-bold">
            Vaporwave Gradient
          </div>
          <div class="h-24 rounded-lg gradient-vaporwave-subtle flex items-center justify-center">
            Subtle Vaporwave Gradient
          </div>
        </div>

        <div class="mt-4 p-4 bg-base-200 rounded-lg">
          <pre class="text-sm"><code>class="gradient-vaporwave"
    class="gradient-vaporwave-subtle"</code></pre>
        </div>
      </div>
      
    <!-- Alerts -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Alerts</h2>
        <div class="space-y-4">
          <div class="alert alert-info">
            <.icon name="hero-information-circle" class="size-5 shrink-0" />
            <span>This is an info alert</span>
          </div>

          <div class="alert alert-success">
            <.icon name="hero-check-circle" class="size-5 shrink-0" />
            <span>This is a success alert</span>
          </div>

          <div class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
            <span>This is a warning alert</span>
          </div>

          <div class="alert alert-error">
            <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
            <span>This is an error alert</span>
          </div>
        </div>
      </div>
      
    <!-- Cards -->
      <div class="mt-12">
        <h2 class="text-2xl font-bold mb-4">Cards</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="card bg-base-200 p-6">
            <h3 class="font-semibold text-lg mb-2">Simple Card</h3>
            <p class="text-sm text-base-content/70">
              A basic card with background color
            </p>
          </div>

          <div class="card bg-base-200 p-6 border border-primary">
            <h3 class="font-semibold text-lg mb-2">Primary Border</h3>
            <p class="text-sm text-base-content/70">
              Card with primary color border
            </p>
          </div>

          <div class="card bg-base-200 p-6 hover-glow-cyan transition-glow">
            <h3 class="font-semibold text-lg mb-2">Interactive Card</h3>
            <p class="text-sm text-base-content/70">
              Hover to see glow effect
            </p>
          </div>
        </div>
      </div>
      
    <!-- Icons -->
      <div class="mt-12 mb-12">
        <h2 class="text-2xl font-bold mb-4">Icons (Heroicons)</h2>
        <div class="flex flex-wrap gap-6">
          <div class="flex flex-col items-center gap-2">
            <.icon name="hero-home" class="h-6 w-6" />
            <span class="text-xs">home</span>
          </div>
          <div class="flex flex-col items-center gap-2">
            <.icon name="hero-users" class="h-6 w-6" />
            <span class="text-xs">users</span>
          </div>
          <div class="flex flex-col items-center gap-2">
            <.icon name="hero-cog-6-tooth" class="h-6 w-6" />
            <span class="text-xs">cog</span>
          </div>
          <div class="flex flex-col items-center gap-2">
            <.icon name="hero-rocket-launch" class="h-6 w-6" />
            <span class="text-xs">rocket</span>
          </div>
          <div class="flex flex-col items-center gap-2">
            <.icon name="hero-signal" class="h-6 w-6" />
            <span class="text-xs">signal</span>
          </div>
          <div class="flex flex-col items-center gap-2">
            <.icon name="hero-envelope" class="h-6 w-6" />
            <span class="text-xs">envelope</span>
          </div>
        </div>

        <div class="mt-4 p-4 bg-base-200 rounded-lg">
          <pre class="text-sm"><code>&lt;.icon name="hero-home" class="h-6 w-6" /&gt;</code></pre>
          <p class="text-sm mt-2 text-base-content/70">
            Browse all icons at
            <a
              href="https://heroicons.com"
              target="_blank"
              class="link link-primary"
            >
              heroicons.com
            </a>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
