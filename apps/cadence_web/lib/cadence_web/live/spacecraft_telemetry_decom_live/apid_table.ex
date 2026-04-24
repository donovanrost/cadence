defmodule CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable do
  @moduledoc false

  use Phoenix.Component

  import CadenceWeb.CoreComponents, only: [status_dot: 1]

  attr :rows, :list, required: true
  attr :selection, :any, required: true
  attr :conflicts, :map, required: true
  attr :expanded_apids, :any, required: true
  attr :expanded_defs, :any, required: true
  attr :expanded_entries, :any, required: true
  attr :filter, :string, default: ""

  def table(assigns) do
    assigns = assign(assigns, :visible_rows, filter_rows(assigns.rows, assigns.filter))

    ~H"""
    <table class="w-full text-sm" id="telemetry-decom-apid-table">
      <thead>
        <tr class="text-base-content/60 text-xs uppercase tracking-wider">
          <th class="py-2 w-8"></th>
          <th class="py-2 w-6"></th>
          <th class="py-2 w-16 text-left">APID</th>
          <th class="py-2 text-left">Packets</th>
          <th class="py-2 w-16 text-left">Defs</th>
          <th class="py-2 w-20 text-left">Rate</th>
          <th class="py-2 w-28 text-left">Conflict</th>
        </tr>
      </thead>
      <tbody>
        <%= for row <- @visible_rows do %>
          <tr id={"apid-row-#{row.apid}"} class="border-t border-base-300/40">
            <td class="py-2">
              <input
                type="checkbox"
                class="checkbox checkbox-sm checkbox-primary"
                checked={MapSet.member?(@selection, row.apid)}
                disabled={Map.has_key?(@conflicts, row.apid)}
                phx-click="toggle_apid"
                phx-value-apid={row.apid}
              />
            </td>
            <td class="py-2">
              <button
                type="button"
                id={"apid-row-#{row.apid}-toggle"}
                class={["text-base-content/50 transition-transform",
                        MapSet.member?(@expanded_apids, row.apid) && "rotate-90 text-primary"]}
                phx-click="toggle_apid_expand"
                phx-value-apid={row.apid}
                aria-label="Toggle row details"
              >›</button>
            </td>
            <td class="py-2 font-mono">{row.apid}</td>
            <td class="py-2">{packets_label(row)}</td>
            <td class="py-2 text-base-content/60">{row.def_count}</td>
            <td class="py-2 text-base-content/60">{rate_label(row.rate_hz)}</td>
            <td class="py-2 text-base-content/60">{conflict_label(@conflicts, row.apid)}</td>
          </tr>
          <tr :if={MapSet.member?(@expanded_apids, row.apid)}>
            <td colspan="7" class="p-0">
              <div
                class="pl-4 pr-2 py-3 border-l-2 border-primary bg-base-300/40"
                id={"apid-row-#{row.apid}-detail"}
              >
                <p :if={row.short_description} class="text-sm text-base-content/80 mb-3">
                  {row.short_description}
                </p>
                <div :for={packet <- row.packets} class="bg-base-200 border border-base-300/60 mb-2">
                  <div class="flex items-center gap-3 px-3 py-2 border-b border-base-300/60">
                    <span class="font-semibold text-base-content">{packet.name}</span>
                    <span class="font-mono text-xs text-base-content/60">
                      apid={packet.apid} · type={packet.packet_type || "—"} · {packet.size_bits || "—"} b
                    </span>
                    <span class="ml-auto text-xs text-base-content/60">
                      {packet_entries_label(packet)}
                    </span>
                  </div>
                </div>
              </div>
            </td>
          </tr>
        <% end %>
        <tr :if={@visible_rows == []}>
          <td colspan="7" class="py-4 text-center text-base-content/60">
            No APIDs match the filter.
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp filter_rows(rows, ""), do: rows

  defp filter_rows(rows, filter) do
    needle = String.downcase(filter)

    Enum.filter(rows, fn row ->
      apid_str = Integer.to_string(row.apid)

      String.contains?(apid_str, needle) or
        Enum.any?(row.packets, fn packet ->
          String.contains?(String.downcase(packet.name || ""), needle)
        end)
    end)
  end

  defp packets_label(%{packets: [single]}), do: single.name

  defp packets_label(%{packets: [first | _], def_count: n}),
    do: "#{first.name} (#{n} defs)"

  defp packets_label(_), do: "—"

  defp rate_label(nil), do: "—"
  defp rate_label(hz) when is_number(hz), do: "#{trim_float(hz)} Hz"

  defp trim_float(hz) when is_integer(hz), do: hz

  defp trim_float(hz) when is_float(hz) do
    if hz == Float.round(hz) do
      trunc(hz) |> Integer.to_string()
    else
      :erlang.float_to_binary(hz, decimals: 2)
    end
  end

  defp conflict_label(conflicts, apid) do
    case Map.get(conflicts, apid) do
      nil -> "—"
      name -> name
    end
  end

  defp packet_entries_label(%{entries: []}), do: "no entries"
  defp packet_entries_label(%{entries: entries}), do: "#{length(entries)} entries"
  defp packet_entries_label(_), do: ""

  # status_dot is imported for use in later tasks (Level 2 expansion).
  _ = &status_dot/1
end
