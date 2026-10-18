# Test-only compatibility renderer preserving the pre-LiveVue component contract.
defmodule CadenceWeb.Components.ListControls do
  @moduledoc false

  use Phoenix.Component

  import CadenceWeb.Components.Button, only: [button: 1]
  import CadenceWeb.Components.FormInputs, only: [input: 1]

  attr :id, :string, required: true
  attr :search, :string, default: nil
  attr :placeholder, :string, default: "Search"
  attr :on_search, :string, default: "search"
  attr :debounce, :integer, default: 300
  slot :filters
  slot :actions

  def toolbar(assigns) do
    ~H"""
    <div
      id={@id}
      class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-2"
    >
      <form
        id={"#{@id}-search-form"}
        phx-change={@on_search}
        class="w-64 max-w-full"
        onsubmit="return false"
      >
        <.input
          id={"#{@id}-search"}
          name="q"
          type="search"
          value={@search}
          placeholder={@placeholder}
          class="input-sm"
          compact
          phx-debounce={@debounce}
        />
      </form>
      <div :if={@filters != []} class="flex items-center gap-2">
        {render_slot(@filters)}
      </div>
      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :total_count, :integer, required: true
  attr :on_paginate, :string, default: "paginate"

  def pagination(assigns) do
    assigns = assign(assigns, :last_page, last_page(assigns))

    ~H"""
    <div
      :if={@total_count > @page_size}
      id={@id}
      class="flex items-center justify-between border-t border-base-300 px-4 py-2"
    >
      <span class="font-mono text-xs text-base-content/70">{range_label(assigns)}</span>
      <div class="flex items-center gap-1">
        <.button
          variant={:ghost}
          size={:xs}
          phx-click={@on_paginate}
          phx-value-page={@page - 1}
          disabled={@page <= 1}
        >
          Prev
        </.button>
        <.button
          variant={:ghost}
          size={:xs}
          phx-click={@on_paginate}
          phx-value-page={@page + 1}
          disabled={@page >= @last_page}
        >
          Next
        </.button>
      </div>
    </div>
    """
  end

  defp last_page(%{total_count: total, page_size: size}), do: max(ceil(total / size), 1)

  defp range_label(%{page: page, page_size: size, total_count: total}) do
    first = (page - 1) * size + 1
    last = min(page * size, total)
    "#{first}–#{last} of #{total}"
  end
end
