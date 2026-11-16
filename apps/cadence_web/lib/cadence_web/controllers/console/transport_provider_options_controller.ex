defmodule CadenceWeb.Console.TransportProviderOptionsController do
  @moduledoc """
  `GET /api/console/v1/missions/:mission_id/config/kinds/transport/provider-options` (comms
  parity 2): the provider-managed transport form's dependent choices and derived preview
  (`Cadence.Reads.TransportProviderOptions`). Query: `provider_id`, `service_profile_id`,
  `delivery_profile_id`, each optional. Read-only; it serves staging, so it needs `config.stage`.
  Contract: docs/apogee/api/changes.md §Transport provider options.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.Configuration
  alias Cadence.Management.Transports
  alias Cadence.Reads.TransportProviderOptions
  alias CadenceWeb.Console.Problem

  @params [
    {"provider_id", :provider_id},
    {"service_profile_id", :service_profile_id},
    {"delivery_profile_id", :delivery_profile_id}
  ]

  def show(conn, params) do
    scope = conn.assigns.current_scope
    mission_id = conn.assigns.current_mission.mission_id

    with {:ok, permissions} <- Configuration.permissions(scope, mission_id),
         true <- "config.stage" in permissions,
         {:ok, selection} <- selection(params) do
      json(conn, %{
        data:
          TransportProviderOptions.load(
            scope.organization_id,
            mission_id,
            selection,
            &Transports.derive/3
          )
      })
    else
      false -> Problem.respond(conn, :forbidden)
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
      {:error, _reason} -> Problem.respond(conn, :forbidden)
    end
  end

  defp selection(params) do
    bad =
      for {key, _field} <- @params,
          value = params[key],
          not is_nil(value) and not is_binary(value),
          into: %{},
          do: {key, "must be text"}

    if bad == %{},
      do: {:ok, Map.new(@params, fn {key, field} -> {field, blank_to_nil(params[key])} end)},
      else: {:error, {:invalid_params, bad}}
  end

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
