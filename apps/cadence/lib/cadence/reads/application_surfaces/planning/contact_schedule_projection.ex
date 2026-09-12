defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactScheduleProjection do
  @moduledoc false
  alias Cadence.Auth.Policy
  alias Cadence.Contacts.ProviderScheduling

  def project(scope, mission, q, data) do
    start = DateTime.utc_now() |> DateTime.add(900) |> DateTime.truncate(:second)

    %{
      contract_version: 1,
      permissions: %{
        operate:
          Policy.authorize(scope, :operate_mission, %{
            organization_id: scope.organization_id,
            mission_id: mission
          }) == :ok,
        cancel:
          Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id}) ==
            :ok
      },
      context: %{organization_id: scope.organization_id, mission_id: mission},
      query: q,
      initial_window: %{starts_at: iso(start), ends_at: iso(DateTime.add(start, 3600))},
      spacecraft: %{
        page: q["spacecraft_page"],
        more: q["spacecraft_page"] * 25 < data.spacecraft.total_count,
        entries: Enum.map(data.spacecraft.items, &craft/1)
      },
      selected_spacecraft: if(data.selected, do: craft(data.selected)),
      routes: page(data.ready.routes, q["routes_page"], &route/1),
      findings: page(data.ready.findings, q["findings_page"], &finding/1),
      scheduled: project_page(data.scheduled, &scheduled/1),
      realized: project_page(data.realized, &realized/1),
      reservations: project_page(data.reservations, &reservation/1)
    }
  end

  def route(r), do: ProviderScheduling.route_summary(r)
  defp craft(s), do: %{id: s.spacecraft_id, name: label(s.display_name)}

  defp finding(f),
    do: %{code: to_string(f.code), message: label(f.message), resource_id: f[:resource_id]}

  defp scheduled(s),
    do: %{
      id: s.scheduled_contact_id,
      lifecycle_state: to_string(s.lifecycle_state),
      starts_at: iso(s.starts_at),
      ends_at: iso(s.ends_at),
      revision: s.current_revision,
      realized_id: s.realized_contact_id
    }

  defp realized(r),
    do: %{
      id: r.realized_contact_id,
      lifecycle_state: to_string(r.lifecycle_state),
      realized_at: iso(r.realized_at),
      clock_mode: to_string(r.clock_mode),
      scheduled_id: r.scheduled_contact_id
    }

  defp reservation(r),
    do: %{
      id: r.provider_reservation_id,
      lifecycle_state: to_string(r.lifecycle_state),
      provider_revision: r.provider_revision,
      provider_contact_ref: r.provider_contact_ref,
      provider_id: r.provider_id,
      provider_version: r.provider_version,
      transport_id: r.transport_id,
      transport_version: r.transport_version,
      service_profile: r.service_profile_ref,
      delivery_profile: r.delivery_profile_ref,
      starts_at: iso(r.starts_at),
      ends_at: iso(r.ends_at),
      scheduled_id: r.scheduled_contact_id,
      last_reconciled_at: iso(r.last_reconciled_at)
    }

  defp page(rows, n, project) do
    rows = rows |> Enum.drop((n - 1) * 25) |> Enum.take(26)
    %{page: n, more: length(rows) > 25, entries: rows |> Enum.take(25) |> Enum.map(project)}
  end

  defp project_page(p, project), do: Map.put(p, :entries, Enum.map(p.entries, project))
  defp iso(nil), do: nil
  defp iso(time), do: DateTime.to_iso8601(time)
  defp label(v) when is_binary(v), do: String.slice(v, 0, 120)
  defp label(_), do: "Unavailable label"
end
