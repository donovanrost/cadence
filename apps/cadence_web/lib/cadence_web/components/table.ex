defmodule CadenceWeb.Components.Table do
  @moduledoc """
  The canonical Cadence data table.

  Headers are always `hud-label`. Rows get the standard hover accent
  (`border-l-2` cyan reveal) unless `row_accent={false}`. Columns opt into
  right alignment with `align={:right}` (numeric and action columns) and
  monospace cells with `mono` (identifiers, versions, counts).

  Accepts a plain list or a `Phoenix.LiveView.LiveStream` for `rows`; streams
  render with `phx-update="stream"` and derive row DOM ids automatically.
  The `:col` slot always receives the item itself (never the stream tuple).

  Tables with structural needs beyond this (checkbox selection, expander
  rows, nested tables) should stay hand-rolled — see
  `CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable`.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :rows, :any, required: true
  attr :body_id, :string, default: nil
  attr :row_id, :any, default: nil
  attr :row_accent, :boolean, default: true
  attr :class, :string, default: nil

  slot :col, required: true do
    attr :label, :string
    attr :align, :atom
    attr :mono, :boolean
    attr :class, :string
  end

  slot :empty

  def table(assigns) do
    assigns =
      case assigns.rows do
        %Phoenix.LiveView.LiveStream{} ->
          assigns
          |> assign(:stream?, true)
          |> assign(:row_id, assigns.row_id || fn {id, _item} -> id end)
          |> assign(:row_item, fn {_id, item} -> item end)

        _list ->
          assigns
          |> assign(:stream?, false)
          |> assign(:row_item, &Function.identity/1)
      end

    ~H"""
    <table id={@id} class={["table", @class]}>
      <thead>
        <tr>
          <th :for={col <- @col} class={["hud-label", col[:align] == :right && "text-right"]}>
            {col[:label]}
          </th>
        </tr>
      </thead>
      <tbody id={@body_id || "#{@id}-body"} phx-update={@stream? && "stream"}>
        <tr :if={@empty != [] && @rows == []}>
          <td colspan={length(@col)}>{render_slot(@empty)}</td>
        </tr>
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class={
            @row_accent &&
              "border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
          }
        >
          <td
            :for={col <- @col}
            class={[
              col[:align] == :right && "text-right",
              col[:mono] && "font-mono text-sm",
              col[:class]
            ]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end
end
