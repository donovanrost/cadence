defmodule Cadence.Contacts.Scheduler do
  @moduledoc """
  Signal-driven scheduler and safety reconciler for contact lifecycle state.
  """

  use GenServer

  alias Cadence.Contacts
  alias Cadence.Contacts.{RealizedContact, ScheduledContact}
  alias Cadence.Runtime
  alias Cadence.Runtime.MissionRuntime

  @default_safety_poll_interval_ms 60_000
  @max_timer_ms 2_147_483_647
  @event_prefix [:cadence, :contacts, :scheduler]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @type projection :: %{
          scheduled_contacts: %{optional(binary()) => ScheduledContact.t()}
        }

  @spec notify_contact_changed(binary() | ScheduledContact.t() | RealizedContact.t(), keyword()) ::
          :ok
  def notify_contact_changed(contact_or_mission_id, opts \\ [])

  def notify_contact_changed(mission_id, opts) when is_binary(mission_id) and is_list(opts) do
    notify_contact_change(mission_id, {:contact_changed, mission_id}, opts)
  end

  def notify_contact_changed(%ScheduledContact{} = scheduled_contact, opts) when is_list(opts) do
    notify_contact_change(
      scheduled_contact.mission_id,
      {:scheduled_contact_changed, scheduled_contact},
      opts
    )
  end

  def notify_contact_changed(%RealizedContact{} = realized_contact, opts) when is_list(opts) do
    notify_contact_change(
      realized_contact.mission_id,
      {:realized_contact_changed, realized_contact},
      opts
    )
  end

  @spec notify_contact_changed(GenServer.server(), binary()) :: :ok
  def notify_contact_changed(server, mission_id) when is_binary(mission_id) do
    notify_server(server, {:contact_changed, mission_id})
  end

  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  end

  defp notify_contact_change(mission_id, message, opts) do
    case Keyword.fetch(opts, :server) do
      {:ok, server} -> notify_server(server, message)
      :error -> notify_mission_scheduler(mission_id, message)
    end
  end

  defp notify_server(server, message) do
    case server_pid(server) do
      nil -> :ok
      pid when is_pid(pid) -> GenServer.cast(pid, message)
    end
  end

  @spec reconcile_now(GenServer.server(), DateTime.t()) :: {:ok, map()}
  def reconcile_now(server \\ __MODULE__, %DateTime{} = reference_time) do
    GenServer.call(server, {:reconcile_now, reference_time}, :infinity)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.get(opts, :mission_id)

    state = %{
      mission_id: mission_id,
      safety_poll_interval_ms:
        Keyword.get(
          opts,
          :safety_poll_interval_ms,
          Keyword.get(opts, :poll_interval_ms, @default_safety_poll_interval_ms)
        ),
      auto_schedule?: Keyword.get(opts, :auto_schedule?, true),
      run_on_boot?: Keyword.get(opts, :run_on_boot?, true),
      reference_time_fun: Keyword.get(opts, :reference_time_fun, &DateTime.utc_now/0),
      projection: empty_projection(),
      mission_timers: %{},
      safety_timer: nil
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    state =
      state
      |> maybe_reconcile_on_boot()
      |> rebuild_projection()
      |> schedule_known_mission_wakeups()
      |> schedule_safety_reconcile()

    {:noreply, state}
  end

  @impl true
  def handle_call({:reconcile_now, %DateTime{} = reference_time}, _from, state) do
    {reply, measurements} = timed(fn -> reconcile_scope(state, reference_time) end)
    emit(:reconcile, state, measurements_for_reconcile(reply, measurements), %{reason: :manual})

    state =
      state
      |> rebuild_projection()
      |> schedule_known_mission_wakeups()

    {:reply, reply, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_from_state(state), state}
  end

  @impl true
  def handle_cast({:contact_changed, mission_id}, state) do
    if owns_mission?(state, mission_id) do
      emit(:notification, state, %{count: 1}, %{mission_id: mission_id, contact_kind: :unknown})
      {:noreply, schedule_changed_mission(state, mission_id)}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:scheduled_contact_changed, %ScheduledContact{} = scheduled_contact}, state) do
    if owns_mission?(state, scheduled_contact.mission_id) do
      emit(:notification, state, %{count: 1}, %{
        mission_id: scheduled_contact.mission_id,
        contact_kind: :scheduled,
        scheduled_contact_id: scheduled_contact.scheduled_contact_id,
        lifecycle_state: scheduled_contact.lifecycle_state
      })

      state =
        state
        |> project_scheduled_contact(scheduled_contact)
        |> schedule_changed_mission(scheduled_contact.mission_id)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:realized_contact_changed, %RealizedContact{} = realized_contact}, state) do
    if owns_mission?(state, realized_contact.mission_id) do
      emit(:notification, state, %{count: 1}, %{
        mission_id: realized_contact.mission_id,
        contact_kind: :realized,
        realized_contact_id: realized_contact.realized_contact_id,
        lifecycle_state: realized_contact.lifecycle_state
      })

      {:noreply, schedule_changed_mission(state, realized_contact.mission_id)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:mission_wakeup, mission_id, token}, state) do
    case Map.get(state.mission_timers, mission_id) do
      %{token: ^token} ->
        emit(:timer_fired, state, %{count: 1}, %{mission_id: mission_id})

        state =
          state
          |> clear_mission_timer(mission_id)
          |> reconcile_mission(mission_id)
          |> schedule_mission_wakeup(mission_id)

        {:noreply, state}

      _stale_or_canceled_timer ->
        emit(:stale_timer, state, %{count: 1}, %{mission_id: mission_id})
        {:noreply, state}
    end
  end

  def handle_info(:safety_reconcile, state) do
    {reply, measurements} = timed(fn -> reconcile_scope(state, resolve_reference_time(state)) end)

    emit(:safety_reconcile, state, measurements_for_reconcile(reply, measurements), %{
      reason: :safety
    })

    state =
      state
      |> rebuild_projection()
      |> schedule_known_mission_wakeups()
      |> schedule_safety_reconcile()

    {:noreply, state}
  end

  defp maybe_reconcile_on_boot(%{run_on_boot?: true} = state) do
    {reply, measurements} = timed(fn -> reconcile_scope(state, resolve_reference_time(state)) end)

    emit(:reconcile, state, measurements_for_reconcile(reply, measurements), %{reason: :boot})
    state
  end

  defp maybe_reconcile_on_boot(state), do: state

  defp reconcile_scope(%{mission_id: nil}, reference_time) do
    Contacts.reconcile(reference_time)
  end

  defp reconcile_scope(%{mission_id: mission_id}, reference_time) when is_binary(mission_id) do
    Contacts.reconcile(mission_id, reference_time)
  end

  defp reconcile_mission(state, mission_id) do
    reference_time = resolve_reference_time(state)

    {{:ok, summary}, measurements} =
      timed(fn -> Contacts.reconcile(mission_id, reference_time) end)

    emit(:reconcile, state, measurements_for_reconcile({:ok, summary}, measurements), %{
      mission_id: mission_id,
      reason: :timer
    })

    apply_reconcile_summary(state, summary)
  end

  defp schedule_changed_mission(%{auto_schedule?: false} = state, _mission_id), do: state

  defp schedule_changed_mission(state, mission_id) do
    reference_time = resolve_reference_time(state)

    case next_wakeup(state, mission_id, reference_time) do
      nil ->
        cancel_mission_timer(state, mission_id)

      %DateTime{} = wake_at ->
        if DateTime.compare(wake_at, reference_time) == :gt do
          schedule_mission_wakeup_at(state, mission_id, wake_at)
        else
          state
          |> reconcile_mission(mission_id)
          |> schedule_mission_wakeup(mission_id)
        end
    end
  end

  defp schedule_known_mission_wakeups(%{auto_schedule?: false} = state), do: state

  defp schedule_known_mission_wakeups(%{mission_id: mission_id} = state)
       when is_binary(mission_id) do
    case next_projected_wakeup(state, mission_id, resolve_reference_time(state)) do
      nil -> cancel_mission_timer(state, mission_id)
      %DateTime{} = wake_at -> schedule_mission_wakeup_at(state, mission_id, wake_at)
    end
  end

  defp schedule_known_mission_wakeups(state) do
    state = cancel_mission_timers(state)

    state
    |> resolve_reference_time()
    |> Contacts.list_contact_scheduler_wakeups(state.mission_id)
    |> Enum.reduce(state, fn %{mission_id: mission_id, wake_at: wake_at}, acc ->
      schedule_mission_wakeup_at(acc, mission_id, wake_at)
    end)
  end

  defp schedule_mission_wakeup(%{auto_schedule?: false} = state, _mission_id), do: state

  defp schedule_mission_wakeup(state, mission_id) do
    case next_wakeup(state, mission_id, resolve_reference_time(state)) do
      nil -> cancel_mission_timer(state, mission_id)
      %DateTime{} = wake_at -> schedule_mission_wakeup_at(state, mission_id, wake_at)
    end
  end

  defp schedule_mission_wakeup_at(state, mission_id, %DateTime{} = wake_at) do
    state = cancel_mission_timer(state, mission_id)
    token = make_ref()
    delay_ms = delay_ms(wake_at, resolve_reference_time(state))
    ref = Process.send_after(self(), {:mission_wakeup, mission_id, token}, delay_ms)

    emit(:timer_scheduled, state, %{count: 1, delay_ms: delay_ms}, %{
      mission_id: mission_id,
      wake_at: wake_at
    })

    put_in(state.mission_timers[mission_id], %{ref: ref, token: token, wake_at: wake_at})
  end

  defp schedule_safety_reconcile(%{auto_schedule?: false} = state), do: state

  defp schedule_safety_reconcile(state) do
    state = cancel_safety_timer(state)
    ref = Process.send_after(self(), :safety_reconcile, state.safety_poll_interval_ms)
    %{state | safety_timer: ref}
  end

  defp cancel_mission_timers(state) do
    Enum.reduce(Map.keys(state.mission_timers), state, &cancel_mission_timer(&2, &1))
  end

  defp cancel_mission_timer(state, mission_id) do
    case Map.pop(state.mission_timers, mission_id) do
      {nil, _mission_timers} ->
        state

      {%{ref: ref}, mission_timers} ->
        _ = Process.cancel_timer(ref)
        %{state | mission_timers: mission_timers}
    end
  end

  defp clear_mission_timer(state, mission_id) do
    %{state | mission_timers: Map.delete(state.mission_timers, mission_id)}
  end

  defp cancel_safety_timer(%{safety_timer: nil} = state), do: state

  defp cancel_safety_timer(%{safety_timer: ref} = state) do
    _ = Process.cancel_timer(ref)
    %{state | safety_timer: nil}
  end

  defp delay_ms(wake_at, reference_time) do
    wake_at
    |> DateTime.diff(reference_time, :millisecond)
    |> max(0)
    |> min(@max_timer_ms)
  end

  defp server_pid(server) when is_pid(server), do: server
  defp server_pid(server), do: GenServer.whereis(server)

  defp notify_mission_scheduler(mission_id, message) do
    if scheduler_enabled?() do
      case Runtime.ensure_mission_started(mission_id) do
        {:ok, _mission_runtime} ->
          mission_id
          |> MissionRuntime.contact_scheduler_name()
          |> notify_server(message)

        {:error, _reason} ->
          :ok
      end
    else
      :ok
    end
  end

  defp scheduler_enabled? do
    :cadence
    |> Application.get_env(:contact_scheduler, [])
    |> Keyword.get(:enabled, true)
  end

  defp owns_mission?(%{mission_id: nil}, _mission_id), do: true
  defp owns_mission?(%{mission_id: mission_id}, mission_id), do: true
  defp owns_mission?(_state, _mission_id), do: false

  defp resolve_reference_time(state), do: state.reference_time_fun.()

  defp rebuild_projection(%{mission_id: nil} = state), do: state

  defp rebuild_projection(%{mission_id: mission_id} = state) do
    {projection, measurements} =
      timed(fn -> Contacts.contact_scheduler_projection(mission_id) end)

    emit(
      :projection_rebuild,
      state,
      Map.put(measurements, :projected_contact_count, projected_contact_count(projection)),
      %{
        mission_id: mission_id
      }
    )

    %{state | projection: projection}
  end

  defp empty_projection, do: %{scheduled_contacts: %{}}

  defp project_scheduled_contact(state, %ScheduledContact{} = scheduled_contact) do
    if scheduled_contact.lifecycle_state in [:scheduled, :realized] do
      put_in(
        state.projection.scheduled_contacts[scheduled_contact.scheduled_contact_id],
        scheduled_contact
      )
    else
      update_in(
        state.projection.scheduled_contacts,
        &Map.delete(&1, scheduled_contact.scheduled_contact_id)
      )
    end
  end

  defp next_wakeup(%{mission_id: mission_id} = state, mission_id, reference_time)
       when is_binary(mission_id) do
    next_projected_wakeup(state, mission_id, reference_time)
  end

  defp next_wakeup(_state, mission_id, reference_time) do
    Contacts.next_contact_scheduler_wakeup(mission_id, reference_time)
  end

  defp next_projected_wakeup(state, mission_id, reference_time) do
    state.projection.scheduled_contacts
    |> Map.values()
    |> Enum.filter(&(&1.mission_id == mission_id))
    |> Enum.flat_map(&scheduled_contact_wakeups(&1, reference_time))
    |> case do
      [] -> nil
      wakeups -> Enum.min_by(wakeups, &datetime_sort_key/1)
    end
  end

  defp scheduled_contact_wakeups(
         %ScheduledContact{lifecycle_state: :scheduled} = contact,
         reference_time
       ) do
    cond do
      match?(%DateTime{}, contact.ends_at) and
          DateTime.compare(contact.ends_at, reference_time) != :gt ->
        [reference_time]

      DateTime.compare(contact.starts_at, reference_time) != :gt ->
        [reference_time]

      true ->
        [contact.starts_at]
    end
  end

  defp scheduled_contact_wakeups(
         %ScheduledContact{lifecycle_state: :realized, ends_at: nil},
         _reference_time
       ),
       do: []

  defp scheduled_contact_wakeups(
         %ScheduledContact{lifecycle_state: :realized, ends_at: %DateTime{} = ends_at},
         reference_time
       ) do
    [max_datetime(ends_at, reference_time)]
  end

  defp scheduled_contact_wakeups(_contact, _reference_time), do: []

  defp apply_reconcile_summary(state, %{reference_time: %DateTime{} = reference_time} = summary) do
    state
    |> remove_projected_scheduled_contacts(Map.get(summary, :expired_scheduled_contact_ids, []))
    |> remove_projected_scheduled_contacts(Map.get(summary, :completed_scheduled_contact_ids, []))
    |> mark_due_projected_contacts_realized(reference_time)
  end

  defp remove_projected_scheduled_contacts(state, scheduled_contact_ids) do
    update_in(state.projection.scheduled_contacts, fn scheduled_contacts ->
      Enum.reduce(scheduled_contact_ids, scheduled_contacts, &Map.delete(&2, &1))
    end)
  end

  defp mark_due_projected_contacts_realized(state, reference_time) do
    update_in(state.projection.scheduled_contacts, fn scheduled_contacts ->
      Map.new(scheduled_contacts, fn
        {scheduled_contact_id, %ScheduledContact{lifecycle_state: :scheduled} = contact} ->
          {scheduled_contact_id, maybe_mark_contact_realized(contact, reference_time)}

        entry ->
          entry
      end)
    end)
  end

  defp maybe_mark_contact_realized(%ScheduledContact{} = contact, reference_time) do
    cond do
      match?(%DateTime{}, contact.ends_at) and
          DateTime.compare(contact.ends_at, reference_time) != :gt ->
        contact

      DateTime.compare(contact.starts_at, reference_time) != :gt ->
        %ScheduledContact{contact | lifecycle_state: :realized}

      true ->
        contact
    end
  end

  defp snapshot_from_state(state) do
    %{
      mission_id: state.mission_id,
      scheduled_contact_ids:
        state.projection.scheduled_contacts
        |> Map.keys()
        |> Enum.sort(),
      mission_timer_count: map_size(state.mission_timers)
    }
  end

  defp max_datetime(%DateTime{} = datetime, %DateTime{} = minimum) do
    if DateTime.compare(datetime, minimum) == :lt, do: minimum, else: datetime
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)

  defp timed(fun) when is_function(fun, 0) do
    started_at = System.monotonic_time()
    result = fun.()

    elapsed_us =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)

    {result, %{duration_us: elapsed_us}}
  end

  defp measurements_for_reconcile({:ok, summary}, measurements) do
    measurements
    |> Map.put(:completed_realized_contact_count, length(summary.completed_realized_contact_ids))
    |> Map.put(
      :completed_scheduled_contact_count,
      length(summary.completed_scheduled_contact_ids)
    )
    |> Map.put(:error_count, length(summary.errors))
    |> Map.put(:expired_scheduled_contact_count, length(summary.expired_scheduled_contact_ids))
    |> Map.put(:realized_scheduled_contact_count, length(summary.realized_scheduled_contact_ids))
    |> Map.put(:restarted_realized_contact_count, length(summary.restarted_realized_contact_ids))
  end

  defp projected_contact_count(%{scheduled_contacts: scheduled_contacts})
       when is_map(scheduled_contacts) do
    map_size(scheduled_contacts)
  end

  defp emit(event, state, measurements, metadata) when is_atom(event) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      state
      |> scheduler_metadata()
      |> Map.merge(metadata)
    )
  end

  defp scheduler_metadata(state) do
    %{
      mission_id: state.mission_id,
      mode: scheduler_mode(state),
      projected_contact_count: projected_contact_count(state.projection),
      timer_count: map_size(state.mission_timers)
    }
  end

  defp scheduler_mode(%{mission_id: nil}), do: :global_safety
  defp scheduler_mode(%{mission_id: mission_id}) when is_binary(mission_id), do: :mission
end
