defmodule Cadence.Runtime.Contacts.ContactScheduler do
  @moduledoc """
  Mission-scoped contact scheduler that activates/deactivates transports.

  Contacts are loaded from the runtime ConfigBundle and scheduled using
  Cadence.Time.Timer for deterministic tests.
  """

  use GenServer

  alias Cadence.Runtime.Contacts.SignalRouter
  alias Cadence.Runtime.Contacts.Supervisor, as: ContactSupervisor
  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Runtime.Transport.InterfaceSupervisor
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  require Logger

  @blocked_retry_interval_ms 2_000
  @blocked_event_rate_limit_seconds 30

  @type state :: %{
          mission_id: String.t(),
          organization_id: String.t(),
          contacts_by_id: map(),
          profiles_by_ground_station_target_id: map(),
          transport_interfaces_by_id: map(),
          transport_refcounts: map(),
          active_contacts: map(),
          contact_actions_by_contact_id: map(),
          resource_holders: map(),
          blocked_contacts: map(),
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
       active_contacts: %{},
       contact_actions_by_contact_id: %{},
       resource_holders: %{},
       blocked_contacts: %{},
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
    now = state.time_module.now()
    state = clear_timer_ref(state, contact_id, :start_ref)

    case Map.get(state.contacts_by_id, contact_id) do
      nil ->
        {:noreply, state}

      contact ->
        resource_keys = resource_keys_for_contact(contact)
        {:noreply, attempt_start_contacts(now, state, resource_keys: resource_keys)}
    end
  end

  @impl true
  def handle_info({:contact_end, contact_id}, state) do
    now = state.time_module.now()
    state = clear_timer_ref(state, contact_id, :end_ref)

    case Map.get(state.active_contacts, contact_id) do
      nil ->
        {:noreply, maybe_skip_blocked_contact(contact_id, now, state)}

      _active ->
        {:noreply, deactivate_contact(contact_id, "completed", now, state)}
    end
  end

  @impl true
  def handle_info({:contact_retry, contact_id}, state) do
    now = state.time_module.now()
    state = clear_timer_ref(state, contact_id, :retry_ref)

    case Map.get(state.contacts_by_id, contact_id) do
      nil ->
        {:noreply, clear_blocked_contact(state, contact_id)}

      contact ->
        resource_keys = resource_keys_for_contact(contact)
        {:noreply, attempt_start_contacts(now, state, resource_keys: resource_keys)}
    end
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

    contacts = planned_contacts(bundle.contacts, now)
    contacts_by_id = Map.new(contacts, fn contact -> {Map.get(contact, :id), contact} end)

    profiles_by_ground_station_target_id =
      build_profiles_by_ground_station_target_id(bundle.ground_station_profiles)

    transport_interfaces_by_id =
      bundle.transport_interfaces
      |> List.wrap()
      |> Map.new(fn transport -> {transport.id, transport} end)

    contact_actions_by_contact_id =
      build_contact_actions_by_contact_id(bundle.contact_command_actions)

    removed_contact_ids =
      state.contacts_by_id
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(contacts_by_id, &1))

    state
    |> cancel_all_timers()
    |> deactivate_removed_contacts(removed_contact_ids, now)
    |> Map.put(:contacts_by_id, contacts_by_id)
    |> Map.put(:profiles_by_ground_station_target_id, profiles_by_ground_station_target_id)
    |> Map.put(:transport_interfaces_by_id, transport_interfaces_by_id)
    |> Map.put(:contact_actions_by_contact_id, contact_actions_by_contact_id)
    |> schedule_contacts(now)
  end

  defp planned_contacts(contacts, now) do
    contacts
    |> List.wrap()
    |> Enum.filter(fn contact ->
      Map.get(contact, :state, :planned) == :planned and
        DateTime.compare(Map.get(contact, :end_time), now) == :gt
    end)
  end

  defp build_profiles_by_ground_station_target_id(profiles) do
    profiles
    |> List.wrap()
    |> Enum.group_by(&Map.get(&1, :ground_station_target_id))
    |> Map.new(fn {ground_station_id, grouped} ->
      sorted = sort_profiles(grouped)

      if length(sorted) > 1 do
        Logger.warning(
          "Multiple enabled ground station profiles found for target #{ground_station_id}; using most recent"
        )
      end

      {ground_station_id, sorted}
    end)
  end

  defp sort_profiles(profiles) do
    Enum.sort_by(
      profiles,
      fn profile ->
        {
          Map.get(profile, :inserted_at) || ~U[0001-01-01 00:00:00Z],
          Map.get(profile, :name) || ""
        }
      end,
      fn {left_dt, left_name}, {right_dt, right_name} ->
        case DateTime.compare(left_dt, right_dt) do
          :gt -> true
          :lt -> false
          :eq -> left_name <= right_name
        end
      end
    )
  end

  defp build_contact_actions_by_contact_id(actions) do
    actions
    |> List.wrap()
    |> Enum.group_by(&Map.get(&1, :contact_id))
    |> Map.new(fn {contact_id, grouped} ->
      sorted =
        Enum.sort_by(grouped, fn action ->
          {Map.get(action, :order, 0), Map.get(action, :inserted_at), Map.get(action, :id)}
        end)

      {contact_id, sorted}
    end)
  end

  defp cancel_all_timers(state) do
    Enum.each(state.timers, fn {_contact_id, timer_refs} ->
      maybe_cancel(state.timer_module, timer_refs[:start_ref])
      maybe_cancel(state.timer_module, timer_refs[:end_ref])
      maybe_cancel(state.timer_module, timer_refs[:retry_ref])
    end)

    %{state | timers: %{}}
  end

  defp maybe_cancel(_timer_module, nil), do: :ok
  defp maybe_cancel(timer_module, ref), do: timer_module.cancel(ref)

  defp deactivate_removed_contacts(state, contact_ids, now) do
    Enum.reduce(contact_ids, state, fn contact_id, acc ->
      acc
      |> clear_blocked_contact(contact_id)
      |> deactivate_contact(contact_id, "cancelled", now)
    end)
  end

  defp schedule_contacts(state, now) do
    state =
      Enum.reduce(state.contacts_by_id, state, fn {contact_id, contact}, acc ->
        acc
        |> maybe_schedule_start(contact_id, contact, now)
        |> maybe_schedule_end(contact_id, contact, now)
      end)

    attempt_start_contacts(now, state, all: true)
  end

  defp maybe_schedule_start(state, contact_id, contact, now) do
    start_time = Map.get(contact, :start_time)
    end_time = Map.get(contact, :end_time)

    cond do
      is_nil(start_time) or is_nil(end_time) ->
        state

      Map.has_key?(state.active_contacts, contact_id) ->
        state

      DateTime.compare(now, start_time) == :lt ->
        start_ref =
          state.timer_module.send_after(
            self(),
            {:contact_start, contact_id},
            ms_until(now, start_time)
          )

        put_timer_ref(state, contact_id, :start_ref, start_ref)

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

  defp attempt_start_contacts(now, state, opts) do
    contacts =
      state.contacts_by_id
      |> Map.values()
      |> Enum.filter(&eligible_for_start?(&1, now, state))
      |> filter_by_opts(opts)

    if contacts == [] do
      state
    else
      start_candidates(now, contacts, state)
    end
  end

  defp filter_by_opts(contacts, opts) do
    cond do
      Keyword.get(opts, :all, false) ->
        contacts

      contact_ids = Keyword.get(opts, :contact_ids) ->
        Enum.filter(contacts, fn contact ->
          Map.get(contact, :id) in contact_ids
        end)

      resource_keys = Keyword.get(opts, :resource_keys) ->
        Enum.filter(contacts, fn contact ->
          keys = resource_keys_for_contact(contact)
          Enum.any?(keys, &(&1 in resource_keys))
        end)

      true ->
        contacts
    end
  end

  defp eligible_for_start?(contact, now, state) do
    start_time = Map.get(contact, :start_time)
    end_time = Map.get(contact, :end_time)
    contact_id = Map.get(contact, :id)

    Map.get(contact, :state, :planned) == :planned and
      not Map.has_key?(state.active_contacts, contact_id) and
      not is_nil(start_time) and not is_nil(end_time) and
      DateTime.compare(now, start_time) != :lt and
      DateTime.compare(now, end_time) == :lt
  end

  defp start_candidates(now, contacts, state) do
    contacts
    |> Enum.sort_by(&contact_sort_key/1)
    |> Enum.reduce({state, %{}}, fn contact, {acc, reserved} ->
      handle_candidate(contact, now, acc, reserved)
    end)
    |> elem(0)
  end

  defp handle_candidate(contact, now, state, reserved) do
    contact_id = Map.get(contact, :id)
    resources = resource_keys_for_contact(contact)

    case blocked_by_contact(resources, state.resource_holders, reserved) do
      nil ->
        start_or_record_activation(contact, resources, state, reserved, contact_id)

      blocked_by ->
        {mark_blocked(contact, blocked_by, now, state), reserved}
    end
  end

  defp start_or_record_activation(contact, resources, state, reserved, contact_id) do
    case activate_contact(contact, resources, state) do
      {:ok, next_state} ->
        reserved =
          Enum.reduce(resources, reserved, fn resource_key, res ->
            Map.put(res, resource_key, contact_id)
          end)

        {next_state, reserved}

      {:error, error, next_state} ->
        publish_activation_failed(contact, error, next_state)
        {next_state, reserved}
    end
  end

  defp contact_sort_key(contact) do
    priority = Map.get(contact, :priority, 0)
    start_time = Map.get(contact, :start_time)
    start_key = if start_time, do: DateTime.to_unix(start_time, :microsecond), else: 0
    id = Map.get(contact, :id) || ""

    {-priority, start_key, id}
  end

  defp blocked_by_contact(resources, holders, reserved) do
    Enum.find_value(resources, fn resource_key ->
      Map.get(holders, resource_key) || Map.get(reserved, resource_key)
    end)
  end

  defp resource_keys_for_contact(contact) do
    antenna_key =
      {:antenna, Map.get(contact, :ground_station_target_id), Map.get(contact, :antenna_id)}

    spacecraft_key =
      case Map.get(contact, :spacecraft_target_id) do
        nil -> nil
        spacecraft_id -> {:spacecraft, spacecraft_id}
      end

    [antenna_key, spacecraft_key]
    |> Enum.reject(&is_nil/1)
  end

  defp activate_contact(contact, resources, state) do
    with {:ok, %{transport_ids: transport_ids, uplink_transport_id: uplink_transport_id}} <-
           resolve_transport_ids(contact, state),
         {:ok, next_state} <- start_transports(transport_ids, state) do
      {runtime_pid, next_state} =
        start_contact_runtime(contact, transport_ids, uplink_transport_id, next_state)

      next_state =
        next_state
        |> clear_blocked_contact(Map.get(contact, :id))
        |> add_active_contact(contact, resources, transport_ids, uplink_transport_id, runtime_pid)

      publish_contact_started(contact, transport_ids, next_state)
      {:ok, next_state}
    end
  end

  defp start_transports(transport_ids, state) do
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

      {:ok, Map.put(state, :transport_refcounts, new_refcounts)}
    end
  end

  defp start_transport_interfaces(transport_ids, state) do
    Enum.reduce(transport_ids, {[], []}, fn transport_id, {started, errors} ->
      maybe_start_transport(transport_id, state, {started, errors})
    end)
  end

  defp maybe_start_transport(transport_id, state, {started, errors}) do
    if Map.get(state.transport_refcounts, transport_id, 0) == 0 do
      start_transport_interface(transport_id, state, {started, errors})
    else
      {started, errors}
    end
  end

  defp start_transport_interface(transport_id, state, {started, errors}) do
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
  end

  defp stop_started_transports([], _state), do: :ok

  defp stop_started_transports(transport_ids, state) do
    Enum.each(transport_ids, fn transport_id ->
      _ = state.interface_supervisor.ensure_stopped(state.mission_id, transport_id)
    end)
  end

  defp start_contact_runtime(contact, transport_ids, uplink_transport_id, state) do
    contact_id = Map.get(contact, :id)
    actions = Map.get(state.contact_actions_by_contact_id, contact_id, [])

    opts = [
      mission_id: state.mission_id,
      organization_id: state.organization_id,
      contact: contact,
      transport_ids: transport_ids,
      uplink_transport_id: uplink_transport_id,
      actions: actions
    ]

    case ContactSupervisor.start_contact(state.mission_id, opts) do
      {:ok, pid} ->
        _ = SignalRouter.register(state.mission_id, contact_id, pid, transport_ids)
        {pid, state}

      {:ok, pid, _info} ->
        _ = SignalRouter.register(state.mission_id, contact_id, pid, transport_ids)
        {pid, state}

      {:error, reason} ->
        Logger.error(
          "Failed to start ContactRuntime for contact #{contact_id}: #{inspect(reason)}"
        )

        {nil, state}
    end
  end

  defp stop_contact_runtime(contact_id, runtime_pid, state) do
    _ = SignalRouter.unregister(state.mission_id, contact_id)

    if is_pid(runtime_pid) do
      send(runtime_pid, :contact_end)
    else
      :ok
    end
  end

  defp deactivate_contact(contact_id, reason, now, state) do
    case Map.get(state.active_contacts, contact_id) do
      nil ->
        state

      %{resources: resources, transport_ids: transport_ids, runtime_pid: runtime_pid} ->
        next_state =
          Enum.reduce(transport_ids, state, fn transport_id, acc ->
            decrement_transport_refcount(acc, transport_id)
          end)

        next_state =
          Enum.reduce(resources, next_state, fn resource_key, acc ->
            release_resource(acc, resource_key, contact_id)
          end)

        contact = Map.get(state.contacts_by_id, contact_id)
        publish_contact_ended(contact, reason, next_state)

        _ = stop_contact_runtime(contact_id, runtime_pid, next_state)

        next_state = %{
          next_state
          | active_contacts: Map.delete(next_state.active_contacts, contact_id)
        }

        attempt_start_contacts(now, next_state, resource_keys: resources)
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

  defp add_active_contact(
         state,
         contact,
         resources,
         transport_ids,
         uplink_transport_id,
         runtime_pid
       ) do
    contact_id = Map.get(contact, :id)
    started_at = state.time_module.now()

    state =
      Enum.reduce(resources, state, fn resource_key, acc ->
        Map.update(acc, :resource_holders, %{resource_key => contact_id}, fn holders ->
          Map.put(holders, resource_key, contact_id)
        end)
      end)

    active_entry = %{
      resources: resources,
      transport_ids: transport_ids,
      uplink_transport_id: uplink_transport_id,
      runtime_pid: runtime_pid,
      started_at: started_at
    }

    %{state | active_contacts: Map.put(state.active_contacts, contact_id, active_entry)}
  end

  defp release_resource(state, resource_key, contact_id) do
    case Map.get(state.resource_holders, resource_key) do
      ^contact_id ->
        %{state | resource_holders: Map.delete(state.resource_holders, resource_key)}

      _ ->
        state
    end
  end

  defp mark_blocked(contact, blocked_by_contact_id, now, state) do
    contact_id = Map.get(contact, :id)
    existing = Map.get(state.blocked_contacts, contact_id)

    {emit?, blocked_since} =
      case existing do
        nil ->
          {true, now}

        %{last_emitted_at: nil, blocked_since: blocked_since} ->
          {true, blocked_since}

        %{last_emitted_at: last_emitted_at, blocked_since: blocked_since} ->
          emit? =
            DateTime.diff(now, last_emitted_at, :second) >= @blocked_event_rate_limit_seconds

          {emit?, blocked_since}
      end

    if emit? do
      publish_contact_blocked(contact, blocked_by_contact_id, now, state)
    end

    blocked_entry = %{
      blocked_since: blocked_since,
      last_emitted_at: if(emit?, do: now, else: Map.get(existing || %{}, :last_emitted_at)),
      blocked_by: blocked_by_contact_id
    }

    state =
      Map.update(state, :blocked_contacts, %{contact_id => blocked_entry}, fn map ->
        Map.put(map, contact_id, blocked_entry)
      end)

    ensure_retry_timer(contact_id, state)
  end

  defp ensure_retry_timer(contact_id, state) do
    case get_timer_ref(state, contact_id, :retry_ref) do
      nil ->
        retry_ref =
          state.timer_module.send_after(
            self(),
            {:contact_retry, contact_id},
            @blocked_retry_interval_ms
          )

        put_timer_ref(state, contact_id, :retry_ref, retry_ref)

      _ref ->
        state
    end
  end

  defp clear_blocked_contact(state, contact_id) do
    state = cancel_timer_ref(state, contact_id, :retry_ref)
    %{state | blocked_contacts: Map.delete(state.blocked_contacts, contact_id)}
  end

  defp maybe_skip_blocked_contact(contact_id, now, state) do
    case Map.get(state.blocked_contacts, contact_id) do
      nil ->
        state

      _blocked ->
        maybe_skip_blocked_with_contact(
          Map.get(state.contacts_by_id, contact_id),
          contact_id,
          now,
          state
        )
    end
  end

  defp maybe_skip_blocked_with_contact(nil, contact_id, _now, state) do
    clear_blocked_contact(state, contact_id)
  end

  defp maybe_skip_blocked_with_contact(contact, contact_id, now, state) do
    end_time = Map.get(contact, :end_time)

    if end_time && DateTime.compare(now, end_time) != :lt do
      publish_contact_skipped(contact, "resource_unavailable", state)
      clear_blocked_contact(state, contact_id)
    else
      state
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

    {required_ids, missing_key, uplink_transport_id} =
      case direction do
        :uplink ->
          {[
             get_key(activation, "uplink_transport_id")
           ], "uplink_transport_id", get_key(activation, "uplink_transport_id")}

        :downlink ->
          {[
             get_key(activation, "downlink_transport_id")
           ], "downlink_transport_id", nil}

        :bidirectional ->
          {[
             get_key(activation, "uplink_transport_id"),
             get_key(activation, "downlink_transport_id")
           ], "uplink_transport_id/downlink_transport_id",
           get_key(activation, "uplink_transport_id")}
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
      case validate_transport_ids(transport_ids, state) do
        {:ok, ids} ->
          {:ok, %{transport_ids: ids, uplink_transport_id: uplink_transport_id}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp validate_transport_ids(transport_ids, state) do
    transport_ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn transport_id, {:ok, acc} ->
      validate_transport_id(transport_id, state, acc)
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_transport_id(transport_id, state, acc) do
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

  defp publish_contact_blocked(contact, blocked_by_contact_id, now, state) do
    payload =
      contact_payload(contact)
      |> Map.put(:blocked_by_contact_id, blocked_by_contact_id)
      |> Map.put(:policy, "no_preemption_priority")
      |> Map.put(:message, "Resource held by another contact")
      |> Map.put(:details, %{blocked_at: DateTime.to_iso8601(now)})

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      events_topic(state.mission_id),
      {:contact_lifecycle, :contact_blocked, payload}
    )
  end

  defp publish_contact_skipped(contact, reason, state) do
    payload =
      contact_payload(contact)
      |> Map.put(:reason, reason)

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      events_topic(state.mission_id),
      {:contact_lifecycle, :contact_skipped, payload}
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

  defp get_timer_ref(state, contact_id, key) do
    state.timers
    |> Map.get(contact_id, %{})
    |> Map.get(key)
  end

  defp clear_timer_ref(state, contact_id, key) do
    timers =
      Map.update(state.timers, contact_id, %{}, fn existing ->
        Map.delete(existing || %{}, key)
      end)

    %{state | timers: timers}
  end

  defp cancel_timer_ref(state, contact_id, key) do
    case get_timer_ref(state, contact_id, key) do
      nil ->
        state

      ref ->
        _ = state.timer_module.cancel(ref)
        clear_timer_ref(state, contact_id, key)
    end
  end
end
