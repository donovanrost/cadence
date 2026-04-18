defmodule CadenceWeb.UI do
  @moduledoc """
  Cadence browser primitive component set.

  HEEx function components that capture the Cadence HUD aesthetic using
  Tailwind v4 utilities internally. Start small — only the primitives
  that a concrete page actually needs should be added here.
  """

  use Phoenix.Component

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
