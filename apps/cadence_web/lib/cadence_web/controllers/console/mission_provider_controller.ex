defmodule CadenceWeb.Console.MissionProviderController do
  @moduledoc """
  L12 (owner: api-ops): mission-provider writes under
  `/api/console/v1/missions/:mission_id/providers`. The list is `CommsController.providers`.
  Contract: docs/apogee/api/setup.md §Mission providers (L12). Mission admins.

  Validate and sync answer `200` with `result.ok: false` when the provider refuses, can't be
  reached or doesn't answer within the deadline (25 s); the row's health says why.
  """

  use CadenceWeb, :controller

  require Logger

  alias Cadence.Control.Providers.MissionProviderWrites
  alias Cadence.Reads.Comms.ProviderHealth
  alias Cadence.Reads.CommsDirectory
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def options(conn, _params) do
    case MissionProviderWrites.options(scope(conn), mission_id(conn)) do
      {:ok, options} -> json(conn, %{data: ConfigJSON.encode(options)})
      error -> error(conn, error)
    end
  end

  def create(conn, params) do
    case MissionProviderWrites.create(scope(conn), mission_id(conn), params) do
      {:ok, provider} -> conn |> put_status(:created) |> reply(provider, nil)
      error -> error(conn, error)
    end
  end

  def validate(conn, %{"provider_id" => id}) do
    case MissionProviderWrites.validate(scope(conn), mission_id(conn), id, opts()) do
      {:ok, provider, outcome} -> reply(conn, provider, result(provider, outcome, :validate))
      error -> error(conn, error)
    end
  end

  def sync(conn, %{"provider_id" => id}) do
    case MissionProviderWrites.sync(scope(conn), mission_id(conn), id, opts()) do
      {:ok, provider, outcome} ->
        stations =
          if outcome == :ok,
            do: get_in(provider.inventory_sync_document, ["ground_stations", "total_count"])

        reply(conn, provider, Map.put(result(provider, outcome, :sync), :stations, stations))

      error ->
        error(conn, error)
    end
  end

  def archive(conn, %{"provider_id" => id} = params) do
    case MissionProviderWrites.archive(scope(conn), mission_id(conn), id, params) do
      {:ok, provider} -> reply(conn, provider, nil)
      error -> error(conn, error)
    end
  end

  defp reply(conn, provider, nil),
    do:
      json(conn, %{
        data: ConfigJSON.encode(%{provider: CommsDirectory.provider(scope(conn), provider)})
      })

  defp reply(conn, provider, result),
    do:
      json(conn, %{
        data:
          ConfigJSON.encode(%{
            provider: CommsDirectory.provider(scope(conn), provider),
            result: result
          })
      })

  defp result(_provider, :ok, _which), do: %{ok: true, message: nil}

  defp result(provider, :failed, which),
    do: %{ok: false, message: Map.fetch!(ProviderHealth.of(provider), which).error}

  defp error(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:error, {:grant_changed, %{version: version}}}),
    do: Problem.respond(conn, :grant_changed, %{version: version})

  defp error(conn, {:error, :grant_revoked}), do: Problem.respond(conn, :grant_revoked)

  defp error(conn, {:error, reason})
       when reason in [:forbidden, :scope_mismatch, :authenticated_user_required],
       do: Problem.respond(conn, :forbidden)

  defp error(conn, {:error, :mission_provider_not_found}),
    do: Problem.respond(conn, :provider_not_found)

  defp error(conn, error) do
    Logger.warning("mission provider write failed: #{inspect(error, limit: 20)}")
    Problem.respond(conn, :invalid_params)
  end

  # Tests shorten the deadline; production uses the default.
  defp opts, do: Application.get_env(:cadence_web, :mission_provider_call_opts, [])

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
