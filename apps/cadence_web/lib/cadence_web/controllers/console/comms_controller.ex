defmodule CadenceWeb.Console.CommsController do
  @moduledoc """
  Ground stations (G1), transports (T1) and routing rules (T2). Edits go
  through change sets. Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.Providers.MissionProviderWrites
  alias Cadence.Reads.CommsDirectory
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  # U82: archived rows only on request (?include_archived=true); the default, which every picker
  # reads, stays active-only.
  def stations(conn, params),
    do:
      json(conn, %{
        data: %{
          stations:
            encode(CommsDirectory.stations(org_id(conn), mission_id(conn), archived(params)))
        }
      })

  def transports(conn, params),
    do:
      json(conn, %{
        data: %{
          transports:
            encode(CommsDirectory.transports(org_id(conn), mission_id(conn), archived(params)))
        }
      })

  defp archived(%{"include_archived" => "true"}), do: [include_archived: true]
  defp archived(_params), do: []

  def transport(conn, %{"transport_id" => transport_id}) do
    case CommsDirectory.transport(org_id(conn), mission_id(conn), transport_id) do
      {:ok, transport} -> json(conn, %{data: encode(transport)})
      {:error, :transport_not_found} -> Problem.respond(conn, :transport_not_found)
    end
  end

  def providers(conn, _params),
    do:
      json(conn, %{
        data: %{
          providers:
            encode(CommsDirectory.providers(conn.assigns.current_scope, mission_id(conn))),
          # L12: what the provider writes check (`:manage_mission`).
          permissions:
            MissionProviderWrites.permissions(conn.assigns.current_scope, mission_id(conn))
        }
      })

  def routing_rules(conn, params) do
    case CommsDirectory.routing_rules(org_id(conn), mission_id(conn), params) do
      {:ok, page} -> json(conn, %{data: encode(page)})
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  @doc "Routing rules grouped by transport, direction and role (setup.md)."
  def routing_rule_groups(conn, _params) do
    groups = CommsDirectory.routing_rule_groups(org_id(conn), mission_id(conn))
    json(conn, %{data: encode(%{groups: groups})})
  end

  defp encode(value), do: ConfigJSON.encode(value)
  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
