defmodule CadenceWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def icon(assigns) do
    ~H"""
    <span class={[@name, @class]} {@rest}></span>
    """
  end

  @doc """
  Renders a key-value detail row. Wrap multiple rows in a `divide-y divide-base-300`
  container for dividers between them.

  ## Examples

      <div class="divide-y divide-base-300">
        <.detail_row label="Slug" value={@org.slug} mono />
        <.detail_row label="Status" value="Active" />
      </div>
  """
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :mono, :boolean, default: false
  slot :inner_block

  def detail_row(assigns) do
    ~H"""
    <div class="hud-data-row">
      <span class="hud-data-label">{@label}</span>
      <span class={[
        "hud-data-value",
        @mono && "font-mono text-sm"
      ]}>
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          {@value || "—"}
        <% end %>
      </span>
    </div>
    """
  end

  @doc """
  Renders an inline callout — a contextual in-page message that belongs where
  it appears (a failed import's reason, a warning about dropped selections).
  Not a toast: transient action feedback goes through flash.

  ## Examples

      <.callout variant={:error}>Import failed: unsupported schema version.</.callout>
      <.callout variant={:warning} id="dropped-apids">3 APIDs are not in this revision.</.callout>
  """
  attr :variant, :atom, values: [:info, :warning, :error, :success], default: :info
  attr :id, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def callout(assigns) do
    ~H"""
    <div
      id={@id}
      role="alert"
      class={["border px-4 py-3 text-sm text-base-content", callout_class(@variant), @class]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp callout_class(:info), do: "border-info/40 bg-info/10"
  defp callout_class(:warning), do: "border-warning/40 bg-warning/10"
  defp callout_class(:error), do: "border-error/40 bg-error/10"
  defp callout_class(:success), do: "border-success/40 bg-success/10"
end
