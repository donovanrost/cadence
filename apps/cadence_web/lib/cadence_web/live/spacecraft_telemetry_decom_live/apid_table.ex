defmodule CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable do
  @moduledoc false

  use Phoenix.Component

  attr :rows, :list, required: true
  attr :selection, :any, required: true
  attr :conflicts, :map, required: true
  attr :expanded_apids, :any, required: true
  attr :expanded_entries, :any, required: true
  attr :filter, :string, default: ""
  attr :points_by_id, :map, default: %{}

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
                    <button
                      type="button"
                      id={"telemetry-decom-entries-toggle-#{packet.packet_id}"}
                      class="ml-auto text-xs text-primary hover:underline"
                      phx-click="toggle_entries"
                      phx-value-packet-id={packet.packet_id}
                    >
                      <%= if MapSet.member?(@expanded_entries, packet.packet_id) do %>
                        ▾ hide entries ({length(packet.entries)})
                      <% else %>
                        ▸ show entries ({length(packet.entries)})
                      <% end %>
                    </button>
                  </div>
                  <div
                    :if={MapSet.member?(@expanded_entries, packet.packet_id)}
                    class="px-3 py-2 font-mono text-xs"
                    id={"telemetry-decom-entries-#{packet.packet_id}"}
                  >
                    <table class="w-full">
                      <thead>
                        <tr class="text-base-content/60">
                          <th class="text-left py-1">name</th>
                          <th class="text-left py-1">kind</th>
                          <th class="text-right py-1">offset</th>
                          <th class="text-left py-1 pl-3">notes</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={entry <- Enum.take(packet.entries, 20)} class="border-t border-base-300/40">
                          <td class="py-1 text-primary">{entry_name(entry, @points_by_id)}</td>
                          <td class="py-1 text-base-content/70">{entry.entry_kind}</td>
                          <td class="py-1 text-right text-base-content/60">{entry.bit_offset || "—"}</td>
                          <td class="py-1 pl-3 text-base-content/60">{entry_notes(entry)}</td>
                        </tr>
                      </tbody>
                    </table>
                    <p :if={length(packet.entries) > 20} class="mt-1 text-base-content/60">
                      {length(packet.entries) - 20} more omitted.
                    </p>
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

  defp entry_name(%{point_id: id} = _entry, points_by_id) when is_binary(id) do
    case Map.get(points_by_id, id) do
      %{name: name} when is_binary(name) -> name
      _ -> id
    end
  end

  defp entry_name(%{nested_packet_id: id} = _entry, _points_by_id) when is_binary(id), do: id
  defp entry_name(%{fixed_value: value}, _points_by_id) when is_binary(value), do: "(fixed)"
  defp entry_name(_, _), do: "—"

  defp entry_notes(%{fixed_value: value}) when is_binary(value), do: "fixed=#{value}"
  defp entry_notes(%{array_size: size}) when is_integer(size), do: "array[#{size}]"
  defp entry_notes(_), do: ""
end
