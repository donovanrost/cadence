# Test-only compatibility renderer preserving the pre-LiveVue component contract.
defmodule CadenceWeb.TestSupport.CardComponents do
  @moduledoc false

  use Phoenix.Component

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :patch, :string, default: nil
  attr :active, :boolean, default: false
  attr :class, :string, default: nil

  def stat_tile(assigns) do
    ~H"""
    <%= if @patch do %>
      <.link
        id={@id}
        patch={@patch}
        aria-current={@active && "true"}
        class={[
          "block border bg-base-200 px-3 py-2 transition-colors",
          if(@active, do: "border-primary/60", else: "border-base-300 hover:border-primary/40"),
          @class
        ]}
      >
        <.stat_tile_body label={@label} value={@value} active={@active} />
      </.link>
    <% else %>
      <div id={@id} class={["border border-base-300 bg-base-200 px-3 py-2", @class]}>
        <.stat_tile_body label={@label} value={@value} active={false} />
      </div>
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :active, :boolean, required: true

  defp stat_tile_body(assigns) do
    ~H"""
    <p class={["hud-label", @active && "text-primary!"]}>{@label}</p>
    <p class="mt-1 font-mono text-xl text-base-content">{@value}</p>
    """
  end
end
