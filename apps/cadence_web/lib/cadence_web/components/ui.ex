defmodule CadenceWeb.UI do
  @moduledoc """
  Cadence browser primitive component set.

  HEEx function components that capture the Cadence HUD aesthetic using
  Tailwind v4 utilities internally. Start small — only the primitives
  that a concrete page actually needs should be added here.
  """

  use Phoenix.Component

  alias Phoenix.HTML.FormField

  @doc """
  Hero panel container.

  A dark glass-lit panel with a subtle border and inner hairline.
  Use `variant={:hero}` for the oversized first-screen panel and
  `variant={:compact}` for tighter secondary panels.
  """
  attr :variant, :atom, values: [:hero, :compact], default: :hero
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section class={[
      "relative overflow-hidden border border-line rounded-[1.5rem] bg-gradient-to-b from-panel-strong to-panel shadow-[0_28px_90px_rgba(0,0,0,0.42)] before:absolute before:inset-0 before:rounded-[inherit] before:border before:border-white/5 before:pointer-events-none",
      panel_variant_class(@variant),
      @class
    ]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp panel_variant_class(:hero), do: "p-8 grid gap-6"
  defp panel_variant_class(:compact), do: "p-5"

  @doc """
  Eyebrow — small uppercase mono label that sits above a hero title.
  """
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <p class="font-mono text-[0.78rem] tracking-[0.18em] uppercase text-accent m-0">
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Oversized hero headline.
  """
  slot :inner_block, required: true

  def hero_title(assigns) do
    ~H"""
    <h1 class="m-0 max-w-[42rem] text-[clamp(2.2rem,4vw,4rem)] leading-[0.94] tracking-[-0.04em] text-base-content">
      {render_slot(@inner_block)}
    </h1>
    """
  end

  @doc """
  Supporting hero prose paragraph.
  """
  slot :inner_block, required: true

  def hero_copy(assigns) do
    ~H"""
    <p class="m-0 max-w-[42rem] text-muted text-[1.05rem] leading-[1.7]">
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Labeled text field wrapping a Phoenix form field.
  """
  attr :field, FormField, required: true
  attr :type, :string, default: "text", values: ~w(text email password)
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil
  attr :required, :boolean, default: false
  attr :rest, :global, include: ~w(autocomplete autofocus)

  def text_field(assigns) do
    assigns =
      assign(assigns, :value, if(assigns.type == "password", do: nil, else: assigns.field.value))

    ~H"""
    <div class="grid gap-[0.55rem]">
      <label
        for={@field.id}
        class="font-mono text-[0.76rem] tracking-[0.16em] uppercase text-muted"
      >
        {@label}
      </label>
      <input
        id={@field.id}
        name={@field.name}
        type={@type}
        value={@value}
        placeholder={@placeholder}
        required={@required}
        class="w-full border border-line rounded-[1rem] px-4 py-[0.95rem] bg-[rgba(5,11,18,0.86)] text-base-content font-sans transition-[border-color,box-shadow,transform] duration-150 focus:outline-none focus:border-primary focus:shadow-[0_0_0_0.2rem_rgba(134,214,255,0.12)] focus:-translate-y-px placeholder:text-[rgba(156,175,197,0.56)]"
        {@rest}
      />
    </div>
    """
  end

  @doc """
  Primary/secondary/ghost button.
  """
  attr :variant, :atom, values: [:primary, :secondary, :ghost], default: :primary
  attr :kind, :atom, values: [:button, :submit], default: :submit
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={Atom.to_string(@kind)}
      class={[
        "border-0 rounded-full px-5 py-[0.85rem] font-mono text-[0.8rem] tracking-[0.12em] uppercase cursor-pointer transition-[transform,box-shadow,opacity] duration-150 hover:-translate-y-px",
        button_variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_variant_class(:primary) do
    "bg-gradient-to-br from-primary to-[#c9ecff] text-primary-content shadow-[0_14px_34px_rgba(134,214,255,0.22)]"
  end

  defp button_variant_class(:secondary) do
    "bg-[rgba(9,17,27,0.72)] text-base-content border border-line-strong"
  end

  defp button_variant_class(:ghost) do
    "bg-transparent text-base-content border border-line"
  end

  @doc """
  Inline form-level error panel. Renders nothing if `message` is nil or blank.
  """
  attr :message, :string, default: nil

  def form_error(assigns) do
    ~H"""
    <p
      :if={@message not in [nil, ""]}
      class="m-0 px-4 py-[0.95rem] border border-[rgba(255,142,133,0.26)] rounded-[1rem] bg-[rgba(77,18,22,0.58)] text-[#ffd0cc]"
    >
      {@message}
    </p>
    """
  end

  @doc """
  Authenticated scope summary — shows who's signed in and which scope they're in.
  Reads the same shape produced by `Cadence.Auth.Scope.new/1`: prefers `user`,
  falls back to `service_identity`, and renders a generic "Authenticated" label
  for either/neither.
  """
  attr :current_scope, :map, required: true

  def scope_summary(assigns) do
    ~H"""
    <aside class="min-w-[15rem] py-[0.95rem] px-4 border border-line rounded-[1rem] bg-[rgba(9,17,27,0.68)] backdrop-blur-[18px] text-right">
      <p class="block mb-[0.4rem] text-accent text-[0.72rem] tracking-[0.18em] uppercase">
        Authenticated Scope
      </p>
      <%= cond do %>
        <% @current_scope.user -> %>
          <strong class="block text-base-content">{@current_scope.user.display_name}</strong>
          <span class="block mt-[0.2rem] text-muted text-[0.92rem]">{@current_scope.user.email}</span>
        <% @current_scope.service_identity -> %>
          <strong class="block text-base-content">{@current_scope.service_identity.display_name}</strong>
          <span class="block mt-[0.2rem] text-muted text-[0.92rem]">{@current_scope.service_identity.service_identity_id}</span>
        <% true -> %>
          <strong class="block text-base-content">Authenticated</strong>
      <% end %>
    </aside>
    """
  end

  @doc """
  Application header — brand, subhead, and optional scope summary.
  When `current_scope` is nil, only the brand is shown (e.g. /sign-in).
  """
  attr :current_scope, :map, default: nil

  def app_header(assigns) do
    ~H"""
    <header class="flex justify-between gap-6 items-start mb-8 max-md:flex-col">
      <div>
        <.link href="/" class="inline-block font-mono text-[0.88rem] tracking-[0.28em] uppercase text-primary">
          Cadence
        </.link>
        <p class="mt-[0.55rem] mb-0 text-muted max-w-[28rem] leading-[1.5]">
          Ground data control plane
        </p>
      </div>
      <.scope_summary :if={@current_scope} current_scope={@current_scope} />
    </header>
    """
  end

  @doc """
  Fixed-position flash stack. Renders :info and :error entries from the
  controller/LiveView flash map. Emits nothing when both are absent.
  """
  attr :flash, :map, required: true

  def flash_stack(assigns) do
    ~H"""
    <div class="fixed top-5 right-5 max-md:top-auto max-md:bottom-3 max-md:left-3 max-md:right-3 z-[3] grid gap-3">
      <p
        :if={info = Phoenix.Flash.get(@flash, :info)}
        class="m-0 min-w-[16rem] max-w-[min(24rem,calc(100vw-2rem))] max-md:min-w-0 py-[0.9rem] px-4 border border-[rgba(147,242,200,0.24)] rounded-[1rem] bg-[rgba(6,12,19,0.92)] shadow-[0_28px_90px_rgba(0,0,0,0.42)]"
      >
        {info}
      </p>
      <p
        :if={error = Phoenix.Flash.get(@flash, :error)}
        class="m-0 min-w-[16rem] max-w-[min(24rem,calc(100vw-2rem))] max-md:min-w-0 py-[0.9rem] px-4 border border-[rgba(255,142,133,0.32)] rounded-[1rem] bg-[rgba(6,12,19,0.92)] shadow-[0_28px_90px_rgba(0,0,0,0.42)]"
      >
        {error}
      </p>
    </div>
    """
  end
end
