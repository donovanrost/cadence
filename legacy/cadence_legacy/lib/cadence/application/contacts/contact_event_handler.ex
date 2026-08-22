defmodule Cadence.Application.Contacts.ContactEventHandler do
  @moduledoc """
  Control-plane handler that records contact lifecycle events from PubSub.
  """

  use GenServer

  require Logger

  alias Cadence.Application.Organizations.OrganizationQueries
  alias Cadence.Buckets
  alias Cadence.Ports.Recordings.EventRecorder
  alias Cadence.Runtime.Missions.MissionTracker
  alias Cadence.Time.Timer, as: TimeTimer

  @existing_mission_sync_retry_ms 250

  @payload_keys [
    :organization_id,
    :mission_id,
    :contact_id,
    :contact_action_id,
    :spacecraft_target_id,
    :ground_station_target_id,
    :antenna_id,
    :direction,
    :resolved_transport_ids,
    :blocked_by_contact_id,
    :gate,
    :command_ref,
    :result,
    :policy,
    :message,
    :reason,
    :error_code,
    :error_message,
    :details
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    subscribe? = Keyword.get(opts, :subscribe?, true)

    state = %{
      subscribed_missions: MapSet.new(),
      org_ids: MapSet.new(),
      pending_existing_mission_sync?: false
    }

    if subscribe? do
      org_ids = list_org_ids()
      Enum.each(org_ids, &subscribe_org/1)

      send(self(), :sync_existing_missions)

      {:ok,
       %{
         state
         | org_ids: MapSet.new(org_ids),
           pending_existing_mission_sync?: true
       }}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:sync_existing_missions, state) do
    if mission_tracker_ready?() do
      state =
        Enum.reduce(state.org_ids, %{state | pending_existing_mission_sync?: false}, fn org_id,
                                                                                        acc ->
          subscribe_existing_missions(acc, org_id)
        end)

      {:noreply, state}
    else
      TimeTimer.send_after(self(), :sync_existing_missions, @existing_mission_sync_retry_ms)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tracker_diff, _topic, joins, leaves}, state) do
    state =
      Enum.reduce(joins, state, fn {mission_id, _meta}, acc ->
        subscribe_mission(acc, mission_id)
      end)

    state =
      Enum.reduce(leaves, state, fn {mission_id, _meta}, acc ->
        unsubscribe_mission(acc, mission_id)
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:contact_lifecycle, event_type, payload}, state) do
    record_contact_event(event_type, payload)
    {:noreply, state}
  end

  @impl true
  def handle_info({:contact_readiness, event_type, payload}, state) do
    record_contact_event(event_type, payload)
    {:noreply, state}
  end

  @impl true
  def handle_info({:contact_action, event_type, payload}, state) do
    record_contact_action_event(event_type, payload)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp record_contact_event(event_type, payload) do
    attrs = normalize_payload(payload)

    mission_id = Map.get(attrs, :mission_id)
    organization_id = Map.get(attrs, :organization_id)
    contact_id = Map.get(attrs, :contact_id)

    if is_binary(mission_id) and is_binary(organization_id) and is_binary(contact_id) do
      aggregate = %{id: contact_id, mission_id: mission_id, organization_id: organization_id}
      context = build_context(organization_id, mission_id)

      case recorder().record_with_context(event_type, aggregate, nil, attrs, context) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to record contact event: #{inspect(reason)}")
      end
    else
      Logger.error("Contact event missing required identifiers: #{inspect(payload)}")
    end
  end

  defp record_contact_action_event(event_type, payload) do
    attrs = normalize_payload(payload)

    mission_id = Map.get(attrs, :mission_id)
    organization_id = Map.get(attrs, :organization_id)
    contact_action_id = Map.get(attrs, :contact_action_id)

    if is_binary(mission_id) and is_binary(organization_id) and is_binary(contact_action_id) do
      aggregate = %{
        id: contact_action_id,
        mission_id: mission_id,
        organization_id: organization_id
      }

      context = build_context(organization_id, mission_id)

      case recorder().record_with_context(event_type, aggregate, nil, attrs, context) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to record contact action event: #{inspect(reason)}")
      end
    else
      Logger.error("Contact action event missing required identifiers: #{inspect(payload)}")
    end
  end

  defp normalize_payload(payload) do
    Enum.reduce(@payload_keys, %{}, fn key, acc ->
      case fetch_payload_value(payload, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp fetch_payload_value(payload, key) do
    case Map.fetch(payload, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Map.fetch(payload, Atom.to_string(key))
    end
  end

  defp list_org_ids do
    OrganizationQueries.list()
    |> Enum.map(& &1.id)
  end

  defp subscribe_org(org_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission_tracker:org:#{org_id}")
  end

  defp subscribe_existing_missions(state, org_id) do
    org_id
    |> MissionTracker.list_missions_for_org()
    |> Enum.reduce(state, fn {mission_id, _meta}, acc ->
      subscribe_mission(acc, mission_id)
    end)
  end

  defp subscribe_mission(state, mission_id) do
    if MapSet.member?(state.subscribed_missions, mission_id) do
      state
    else
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")
      %{state | subscribed_missions: MapSet.put(state.subscribed_missions, mission_id)}
    end
  end

  defp unsubscribe_mission(state, mission_id) do
    if MapSet.member?(state.subscribed_missions, mission_id) do
      Phoenix.PubSub.unsubscribe(Cadence.PubSub, "mission:#{mission_id}:events")
      %{state | subscribed_missions: MapSet.delete(state.subscribed_missions, mission_id)}
    else
      state
    end
  end

  defp recorder, do: EventRecorder.impl()

  defp mission_tracker_ready? do
    :ets.whereis(MissionTracker) != :undefined
  end

  defp build_context(organization_id, mission_id) do
    bucket_id = Buckets.get_or_create_mission_bucket!(organization_id, mission_id).id
    %{organization_id: organization_id, mission_id: mission_id, bucket_id: bucket_id}
  end
end
