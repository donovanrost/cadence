defmodule CadenceWeb.Console.FleetJSON do
  @moduledoc "Wire shape of the console fleet read. Contract: docs/apogee/api/ops.md."

  alias CadenceWeb.Console.WireValue

  @spec fleet(map(), map(), boolean()) :: map()
  def fleet(fleet, commands, limits_configured?),
    do: fleet |> mission(limits_configured?) |> Map.put(:commands, commands)

  @doc """
  The fleet without the viewer's command counts: the part every viewer of the mission shares.
  The live push builds it once per mission (`CadenceWeb.Console.FleetSource`) and each socket
  adds its own `commands`.
  """
  @spec mission(map(), boolean()) :: map()
  def mission(fleet, limits_configured?) do
    %{
      observed_at: fleet.observed_at,
      stale_after_s: fleet.stale_after_s,
      # "degraded": the durable history store didn't answer in time; freshness comes only from
      # live values, so a spacecraft not heard since the last restart can read never heard.
      telemetry: fleet |> Map.get(:telemetry, :ok) |> to_string(),
      last_received_at: fleet.last_received_at,
      # Not tracked yet: limit-transition history.
      counts: Map.put(fleet.counts, :critical_delta_1h, nil),
      limits: %{configured: limits_configured?},
      spacecraft: Enum.map(fleet.spacecraft, &spacecraft/1)
    }
  end

  @doc "One spacecraft row (also the payload unit of the planned `fleet` channel delta)."
  @spec spacecraft(map()) :: map()
  def spacecraft(row) do
    %{
      id: row.id,
      name: row.name,
      scid: row.scid,
      profile: row.profile,
      plane: row.plane,
      slot: row.slot,
      phase_deg: row.phase_deg,
      operational_phase: row.operational_phase,
      state: Atom.to_string(row.state),
      limit_state: Atom.to_string(row.limit_state),
      violating_points: row.violating_points,
      worst_point: worst_point(row.worst_point),
      last_received_at: row.last_received_at,
      stale: row.stale,
      in_contact: row.in_contact,
      next_aos_at: row.next_aos_at,
      last_los_at: row.last_los_at
    }
  end

  defp worst_point(nil), do: nil

  defp worst_point(point) do
    %{
      source: Atom.to_string(point.source),
      point_id: point.point_id,
      point_name: point.point_name,
      value: WireValue.encode(point.value),
      limit_state: Atom.to_string(point.limit_state),
      raw_limit_state: point.raw_limit_state,
      received_at: point.received_at,
      evaluated_at: point.evaluated_at
    }
  end
end
