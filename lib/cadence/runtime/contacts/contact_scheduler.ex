defmodule Cadence.Runtime.Contacts.ContactScheduler do
  @moduledoc """
  Mission-scoped contact scheduler that activates/deactivates transports.

  Contacts are loaded from the runtime ConfigBundle and scheduled using
  Cadence.Time.Timer for deterministic tests.
  """

  use GenServer

  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Runtime.Transport.InterfaceSupervisor
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  @type state :: %{
          mission_id: String.t(),
          organization_id: String.t(),
          contacts_by_id: map(),
          profiles_by_ground_station_target_id: map(),
          transport_interfaces_by_id: map(),
          transport_refcounts: map(),
          contact_started_transports: map(),
          timers: map(),
          interface_supervisor: module(),
          time_module: module(),
          timer_module: module()
        }

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    organization_id = Keyword.fetch!(opts, :organization_id)
    name = Keyword.get(opts, :name, via_tuple(mission_id))

    GenServer.start_link(
      __MODULE__,
      %{
        mission_id: mission_id,
        organization_id: organization_id,
        interface_supervisor: Keyword.get(opts, :interface_supervisor, InterfaceSupervisor),
        time_module: Keyword.get(opts, :time_module, CadenceTime),
        timer_module: Keyword.get(opts, :timer_module, TimeTimer)
      },
      name: name
    )
  end

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, config_topic(state.mission_id))

    send(self(), :load_config)

    {:ok,
     Map.merge(state, %{
       contacts_by_id: %{},
       profiles_by_ground_station_target_id: %{},
       transport_interfaces_by_id: %{},
       transport_refcounts: %{},
       contact_started_transports: %{},
       timers: %{}
     })}
  end

  @impl true
  def handle_info(:load_config, state) do
    {:noreply, refresh_from_bundle(state)}
  end

  @impl true
  def handle_info({:config_updated, _version}, state) do
    {:noreply, refresh_from_bundle(state)}
  end

  @impl true
  def handle_info({:contact_start, contact_id}, state) do
    {:noreply, maybe_start_contact(contact_id, state)}
  end

  @impl true
  def handle_info({:contact_end, contact_id}, state) do
    {:noreply, deactivate_contact(contact_id, "completed", state)}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  defp refresh_from_bundle(state) do
    case ConfigBundle.fetch(state.mission_id) do
      {:ok, bundle} -> apply_bundle(bundle, state)
      {:error, :not_found} -> state
    end
  end

  defp apply_bundle(%ConfigBundle{} = bundle, state) do
    now = state.time_module.now()

    contacts =
      bundle.contacts
      |> List.wrap()
      |> Enum.filter(fn contact ->
        Map.get(contact, :state, :planned) == :planned and
          DateTime.compare(Map.get(contact, :end_time), now) == :gt
      end)

    contacts_by_id = Map.new(contacts, fn contact -> {Map.get(contact, :id), contact} end)

    profiles_by_ground_station_target_id =
      bundle.ground_station_profiles
      |> List.wrap()
      |> Enum.group_by(&Map.get(&1, :ground_station_target_id))

    transport_interfaces_by_id =
      bundle.transport_interfaces
      |> List.wrap()
      |> Map.new(fn transport -> {transport.id, transport} end)

    removed_contact_ids =
      state.contacts_by_id
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(contacts_by_id, &1))

    state
    |> cancel_all_timers()
    |> deactivate_removed_contacts(removed_contact_ids)
    |> Map.put(:contacts_by_id, contacts_by_id)
    |> Map.put(:profiles_by_ground_station_target_id, profiles_by_ground_station_target_id)
    |> Map.put(:transport_interfaces_by_id, transport_interfaces_by_id)
    |> schedule_contacts(now)
  end

  defp cancel_all_timers(state) do
    Enum.each(state.timers, fn {_contact_id, timer_refs} ->
      maybe_cancel(state.timer_module, timer_refs[:start_ref])
      maybe_cancel(state.timer_module, timer_refs[:end_ref])
    end)

    %{state | timers: %{}}
  end

  defp maybe_cancel(_timer_module, nil), do: :ok
  defp maybe_cancel(timer_module, ref), do: timer_module.cancel(ref)

  defp deactivate_removed_contacts(state, contact_ids) do
    Enum.reduce(contact_ids, state, fn contact_id, acc ->
      deactivate_contact(contact_id, "cancelled", acc)
    end)
  end

  defp schedule_contacts(state, now) do
    Enum.reduce(state.contacts_by_id, state, fn {contact_id, contact}, acc ->
      acc
      |> maybe_schedule_start(contact_id, contact, now)
      |> maybe_schedule_end(contact_id, contact, now)
    end)
  end

  defp maybe_schedule_start(state, contact_id, contact, now) do
    start_time = Map.get(contact, :start_time)
    end_time = Map.get(contact, :end_time)

    cond do
      is_nil(start_time) or is_nil(end_time) ->
        state

      Map.has_key?(state.contact_started_transports, contact_id) ->
        state

      DateTime.compare(now, start_time) == :lt ->
        start_ref =
          state.timer_module.send_after(
            self(),
            {:contact_start, contact_id},
            ms_until(now, start_time)
          )

        put_timer_ref(state, contact_id, :start_ref, start_ref)

      DateTime.compare(now, end_time) == :lt ->
        maybe_start_contact(contact_id, state)

      true ->
        state
    end
  end

  defp maybe_schedule_end(state, contact_id, contact, now) do
    end_time = Map.get(contact, :end_time)

    cond do
      is_nil(end_time) ->
        state

      DateTime.compare(now, end_time) == :lt ->
        end_ref =
          state.timer_module.send_after(
            self(),
            {:contact_end, contact_id},
            ms_until(now, end_time)
          )

        put_timer_ref(state, contact_id, :end_ref, end_ref)

      true ->
        state
    end
  end

  defp maybe_start_contact(contact_id, state) do
    if Map.has_key?(state.contact_started_transports, contact_id) do
      state
    else
      case Map.get(state.contacts_by_id, contact_id) do
        nil ->
          state

        contact ->
          case activate_contact(contact, state) do
            {:ok, next_state} ->
              next_state

            {:error, error, next_state} ->
              publish_activation_failed(contact, error, next_state)
              next_state
          end
      end
    end
  end

  defp activate_contact(contact, state) do
    with {:ok, transport_ids} <- resolve_transport_ids(contact, state),
         {:ok, next_state} <- start_transports(contact, transport_ids, state) do
      publish_contact_started(contact, transport_ids, next_state)
      {:ok, next_state}
    end
  end

  defp start_transports(contact, transport_ids, state) do
    old_refcounts = state.transport_refcounts

    {start_ids, start_errors} = start_transport_interfaces(transport_ids, state)

    if start_errors != [] do
      stop_started_transports(start_ids, state)
      {:error, %{code: "transport_start_failed", details: %{errors: start_errors}}, state}
    else
      new_refcounts =
        Enum.reduce(transport_ids, old_refcounts, fn transport_id, acc ->
          Map.update(acc, transport_id, 1, &(&1 + 1))
        end)

      next_state =
        state
        |> Map.put(:transport_refcounts, new_refcounts)
        |> Map.update(:contact_started_transports, %{}, fn map ->
          Map.put(map, Map.get(contact, :id), transport_ids)
        end)

      {:ok, next_state}
    end
  end

  defp start_transport_interfaces(transport_ids, state) do
    Enum.reduce(transport_ids, {[], []}, fn transport_id, {started, errors} ->
      if Map.get(state.transport_refcounts, transport_id, 0) == 0 do
        case Map.get(state.transport_interfaces_by_id, transport_id) do
          nil ->
            {started, [%{transport_id: transport_id, reason: :not_found} | errors]}

          transport ->
            case state.interface_supervisor.ensure_started(
                   state.mission_id,
                   transport_id,
                   transport
                 ) do
              :ok ->
                {[transport_id | started], errors}

              {:error, reason} ->
                {started, [%{transport_id: transport_id, reason: reason} | errors]}
            end
        end
      else
        {started, errors}
      end
    end)
  end

  defp stop_started_transports([], _state), do: :ok

  defp stop_started_transports(transport_ids, state) do
    Enum.each(transport_ids, fn transport_id ->
      _ = state.interface_supervisor.ensure_stopped(state.mission_id, transport_id)
    end)
  end

  defp deactivate_contact(contact_id, reason, state) do
    case Map.get(state.contact_started_transports, contact_id) do
      nil ->
        state

      transport_ids ->
        next_state =
          Enum.reduce(transport_ids, state, fn transport_id, acc ->
            decrement_transport_refcount(acc, transport_id)
          end)

        contact = Map.get(state.contacts_by_id, contact_id)
        publish_contact_ended(contact, reason, next_state)

        %{
          next_state
          | contact_started_transports:
              Map.delete(next_state.contact_started_transports, contact_id)
        }
    end
  end

  defp decrement_transport_refcount(state, transport_id) do
    case Map.get(state.transport_refcounts, transport_id, 0) do
      0 ->
        state

      1 ->
        _ = state.interface_supervisor.ensure_stopped(state.mission_id, transport_id)
        %{state | transport_refcounts: Map.delete(state.transport_refcounts, transport_id)}

      count ->
        %{
          state
          | transport_refcounts: Map.put(state.transport_refcounts, transport_id, count - 1)
        }
    end
  end

  defp resolve_transport_ids(contact, state) do
    ground_station_id = Map.get(contact, :ground_station_target_id)

    profile =
      state.profiles_by_ground_station_target_id
      |> Map.get(ground_station_id, [])
      |> List.first()

    if is_nil(profile) do
      {:error, %{code: "profile_not_found", message: "No ground station profile found"}}
    else
      antennas =
        profile
        |> Map.get(:resources, %{})
        |> get_key("antennas", [])

      antenna =
        Enum.find(antennas, fn item ->
          to_string(get_key(item, "id")) == to_string(Map.get(contact, :antenna_id))
        end)

      if is_nil(antenna) do
        {:error, %{code: "antenna_not_found", message: "No matching antenna in profile"}}
      else
        resolve_transport_ids_for_antenna(contact, antenna, state)
      end
    end
  end

  defp resolve_transport_ids_for_antenna(contact, antenna, state) do
    activation = get_key(antenna, "activation", %{})
    direction = Map.get(contact, :direction)

    {required_ids, missing_key} =
      case direction do
        :uplink ->
          {[get_key(activation, "uplink_transport_id")], "uplink_transport_id"}

        :downlink ->
          {[get_key(activation, "downlink_transport_id")], "downlink_transport_id"}

        :bidirectional ->
          {[
             get_key(activation, "uplink_transport_id"),
             get_key(activation, "downlink_transport_id")
           ], "uplink_transport_id/downlink_transport_id"}
      end

    transport_ids = Enum.reject(required_ids, &is_nil/1)

    if Enum.count(transport_ids) != Enum.count(required_ids) do
      {:error,
       %{
         code: "missing_transport_id",
         message: "Missing transport id",
         details: %{key: missing_key}
       }}
    else
      validate_transport_ids(transport_ids, state)
    end
  end

  defp validate_transport_ids(transport_ids, state) do
    transport_ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn transport_id, {:ok, acc} ->
      case Map.get(state.transport_interfaces_by_id, transport_id) do
        nil ->
          {:halt,
           {:error,
            %{
              code: "transport_not_found",
              message: "Transport not found",
              details: %{id: transport_id}
            }}}

        transport ->
          if Map.get(transport, :enabled, true) == true do
            {:cont, {:ok, [transport_id | acc]}}
          else
            {:halt,
             {:error,
              %{
                code: "transport_disabled",
                message: "Transport disabled",
                details: %{id: transport_id}
              }}}
          end
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      {:error, error} -> {:error, error}
    end
  end

  defp publish_contact_started(contact, transport_ids, state) do
    payload =
      contact_payload(contact)
      |> Map.put(:resolved_transport_ids, transport_ids)

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      events_topic(state.mission_id),
      {:contact_lifecycle, :contact_started, payload}
    )
  end

  defp publish_contact_ended(nil, _reason, _state), do: :ok

  defp publish_contact_ended(contact, reason, state) do
    payload =
      contact_payload(contact)
      |> Map.put(:reason, reason)

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      events_topic(state.mission_id),
      {:contact_lifecycle, :contact_ended, payload}
    )
  end

  defp publish_activation_failed(contact, error, state) do
    payload =
      contact_payload(contact)
      |> Map.put(:error_code, Map.get(error, :code) || Map.get(error, :error_code) || "unknown")
      |> Map.put(:error_message, Map.get(error, :message))
      |> Map.put(:details, Map.get(error, :details, %{}))

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      events_topic(state.mission_id),
      {:contact_lifecycle, :contact_activation_failed, payload}
    )
  end

  defp contact_payload(contact) do
    %{
      organization_id: Map.get(contact, :organization_id),
      mission_id: Map.get(contact, :mission_id),
      contact_id: Map.get(contact, :id),
      spacecraft_target_id: Map.get(contact, :spacecraft_target_id),
      ground_station_target_id: Map.get(contact, :ground_station_target_id),
      antenna_id: Map.get(contact, :antenna_id),
      direction: Map.get(contact, :direction)
    }
  end

  defp ms_until(now, target_time) do
    diff = DateTime.diff(target_time, now, :millisecond)
    if diff < 0, do: 0, else: diff
  end

  defp config_topic(mission_id), do: "mission:#{mission_id}:config"
  defp events_topic(mission_id), do: "mission:#{mission_id}:events"

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:contact_scheduler, mission_id}}}
  end

  defp get_key(map, key, default \\ nil) do
    cond do
      is_map(map) and Map.has_key?(map, key) ->
        Map.get(map, key)

      (is_map(map) and is_binary(key) and atom_key_for(key)) &&
          Map.has_key?(map, atom_key_for(key)) ->
        Map.get(map, atom_key_for(key))

      true ->
        default
    end
  end

  defp atom_key_for("antennas"), do: :antennas
  defp atom_key_for("activation"), do: :activation
  defp atom_key_for("id"), do: :id
  defp atom_key_for("name"), do: :name
  defp atom_key_for("uplink_transport_id"), do: :uplink_transport_id
  defp atom_key_for("downlink_transport_id"), do: :downlink_transport_id
  defp atom_key_for(_), do: nil

  defp put_timer_ref(state, contact_id, key, ref) do
    timers =
      Map.update(state.timers, contact_id, %{key => ref}, fn existing ->
        Map.put(existing || %{}, key, ref)
      end)

    %{state | timers: timers}
  end
end
