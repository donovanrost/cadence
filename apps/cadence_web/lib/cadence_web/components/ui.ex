defmodule CadenceWeb.UI do
  @moduledoc """
  Cadence browser primitive component set.

  HEEx function components that capture the Cadence HUD aesthetic using
  Tailwind v4 utilities internally. Start small — only the primitives
  that a concrete page actually needs should be added here.
  """

  use Phoenix.Component

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
