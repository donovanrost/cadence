defmodule CadenceWeb.OpsContactScheduleLive.LiveDeps do
  @moduledoc false

  alias Cadence.Contacts.ProviderScheduling

  def list_spacecraft(organization_id, mission_id) do
    call(:list_spacecraft, [organization_id, mission_id], fn ->
      Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id)
    end)
  end

  def list_ready_routes(organization_id, mission_id, spacecraft_id) do
    call(:list_ready_routes, [organization_id, mission_id, spacecraft_id], fn ->
      Cadence.list_ready_downlink_routes(organization_id, mission_id, spacecraft_id)
    end)
  end

  def resolve_ready_route(organization_id, mission_id, spacecraft_id, route_key) do
    call(
      :resolve_ready_route,
      [organization_id, mission_id, spacecraft_id, route_key],
      fn ->
        ProviderScheduling.resolve_ready_downlink_route(
          organization_id,
          mission_id,
          spacecraft_id,
          route_key
        )
      end
    )
  end

  def search_opportunities(organization_id, mission_id, route_key, window) do
    call(:search_opportunities, [organization_id, mission_id, route_key, window], fn ->
      Cadence.search_contact_opportunities(organization_id, mission_id, route_key, window)
    end)
  end

  def reserve(organization_id, mission_id, provider_id, attrs) do
    call(:reserve, [organization_id, mission_id, provider_id, attrs], fn ->
      Cadence.reserve_provider_contact(organization_id, mission_id, provider_id, attrs)
    end)
  end

  def cancel(organization_id, mission_id, provider_reservation_id) do
    call(:cancel, [organization_id, mission_id, provider_reservation_id], fn ->
      Cadence.cancel_provider_reservation(organization_id, mission_id, provider_reservation_id)
    end)
  end

  def list_reservation_rows(organization_id, mission_id) do
    call(:list_reservation_rows, [organization_id, mission_id], fn ->
      Cadence.list_provider_reservations(organization_id, mission_id)
      |> Enum.map(&reservation_row(organization_id, mission_id, &1))
    end)
  end

  def refresh_interval_ms do
    config() |> Keyword.get(:refresh_interval_ms, 2_000)
  end

  defp call(key, args, default) do
    case Keyword.get(config(), key) do
      fun when is_function(fun) -> apply(fun, args)
      _other -> default.()
    end
  end

  defp reservation_row(organization_id, mission_id, reservation) do
    scheduled_contact =
      case Cadence.fetch_scheduled_contact(
             organization_id,
             mission_id,
             reservation.scheduled_contact_id
           ) do
        {:ok, contact} -> contact
        {:error, :scheduled_contact_not_found} -> nil
      end

    %{reservation: reservation, scheduled_contact: scheduled_contact}
  end

  defp config, do: Application.get_env(:cadence_web, :ops_contact_schedule_live, [])
end
