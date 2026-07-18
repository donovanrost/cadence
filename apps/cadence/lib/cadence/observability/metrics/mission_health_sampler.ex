defmodule Cadence.Observability.Metrics.MissionHealthSampler do
  @moduledoc """
  Produces contact-aware telemetry and commanding health metrics.

  Silence is only classified as unavailable when a live realized contact
  explicitly expects downlink telemetry.
  """

  use GenServer

  alias Cadence.Commanding
  alias Cadence.Contacts
  alias Cadence.Contacts.{RealizedContact, ScheduledContact}
  alias Cadence.Observability.Metrics.Reporter
  alias Cadence.Runtime
  alias Cadence.Telemetry.CurrentValueStore

  @default_freshness_grace_seconds 30
  @default_interval_ms 15_000
  @seen_retention_seconds 86_400

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{
      command_entries_fun: Keyword.get(opts, :command_entries_fun, &command_entries/2),
      contacts_fun: Keyword.get(opts, :contacts_fun, &contacts/1),
      freshness_grace_seconds:
        Keyword.get(opts, :freshness_grace_seconds, @default_freshness_grace_seconds),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      latest_values_fun: Keyword.get(opts, :latest_values_fun, &latest_values/1),
      mission_ids_fun: Keyword.get(opts, :mission_ids_fun, &active_mission_ids/0),
      now_fun: Keyword.get(opts, :now_fun, &DateTime.utc_now/0),
      reporter: Keyword.get(opts, :reporter, Reporter),
      seen_command_deadlines: %{},
      seen_realized_contacts: %{}
    }

    send(self(), :sample)
    {:ok, state}
  end

  @impl true
  def handle_info(:sample, state) do
    schedule_sample(state.interval_ms)
    now = state.now_fun.()

    state =
      state
      |> prune_seen(now)
      |> sample_missions(now)

    {:noreply, state}
  end

  defp sample_missions(state, now) do
    Enum.reduce(state.mission_ids_fun.(), state, fn mission_id, acc ->
      sample_mission(acc, mission_id, now)
    end)
  rescue
    _exception -> state
  end

  defp sample_mission(state, mission_id, now) do
    %{realized: realized_contacts, scheduled: scheduled_contacts} =
      state.contacts_fun.(mission_id)

    expected_contacts = Enum.filter(realized_contacts, &expects_live_downlink?/1)
    expected? = expected_contacts != []
    mission_attributes = %{"cadence.mission.id" => mission_id}

    record(state, "cadence.telemetry.expected", boolean_number(expected?), mission_attributes)

    record(
      state,
      "cadence.contact.expected",
      length(expected_contacts),
      mission_attributes
    )

    freshness_seconds =
      state.latest_values_fun.(mission_id)
      |> newest_receipt_time()
      |> age_seconds(now)

    if is_number(freshness_seconds) do
      record(state, "cadence.telemetry.freshness", freshness_seconds, mission_attributes)
    end

    if expected? do
      outcome =
        if is_number(freshness_seconds) and
             freshness_seconds <= state.freshness_grace_seconds,
           do: "met",
           else: "missed"

      record(
        state,
        "cadence.telemetry.availability.interval",
        1,
        Map.put(mission_attributes, "outcome", outcome)
      )
    end

    organization_id = organization_id(realized_contacts, scheduled_contacts)
    state = sample_commands(state, organization_id, mission_id, now)
    sample_contact_realizations(state, scheduled_contacts, realized_contacts, now)
  rescue
    _exception -> state
  end

  defp sample_commands(state, nil, _mission_id, _now), do: state

  defp sample_commands(state, organization_id, mission_id, now) do
    entries = state.command_entries_fun.(organization_id, mission_id)
    pending = Enum.filter(entries, &(&1.lifecycle_state == :pending))
    attributes = %{"cadence.mission.id" => mission_id}

    record(state, "cadence.commanding.queue.pending", length(pending), attributes)

    pending
    |> Enum.filter(&eligible?(&1, now))
    |> oldest_enqueued_at()
    |> age_seconds(now)
    |> case do
      age when is_number(age) ->
        record(state, "cadence.commanding.queue.oldest_eligible.age", age, attributes)

      nil ->
        :ok
    end

    Enum.reduce(entries, state, fn entry, acc ->
      record_command_deadline(acc, entry, mission_id, now)
    end)
  end

  defp record_command_deadline(state, entry, mission_id, now) do
    command_id = entry.command_queue_entry_id

    if Map.has_key?(state.seen_command_deadlines, command_id) do
      state
    else
      case command_deadline_outcome(entry, now) do
        nil ->
          state

        outcome ->
          record(
            state,
            "cadence.commanding.deadline.result",
            1,
            %{"cadence.mission.id" => mission_id, "outcome" => outcome}
          )

          put_in(state.seen_command_deadlines[command_id], now)
      end
    end
  end

  defp sample_contact_realizations(state, scheduled_contacts, realized_contacts, now) do
    scheduled_by_id =
      Map.new(scheduled_contacts, &{&1.scheduled_contact_id, &1})

    Enum.reduce(realized_contacts, state, fn realized_contact, acc ->
      realized_contact_id = realized_contact.realized_contact_id

      with false <- Map.has_key?(acc.seen_realized_contacts, realized_contact_id),
           scheduled_contact_id when is_binary(scheduled_contact_id) <-
             realized_contact.scheduled_contact_id,
           %ScheduledContact{} = scheduled_contact <-
             Map.get(scheduled_by_id, scheduled_contact_id),
           %DateTime{} = realized_at <- realized_contact.realized_at do
        delay_seconds =
          max(DateTime.diff(realized_at, scheduled_contact.starts_at, :millisecond), 0) / 1_000

        record(
          acc,
          "cadence.contact.realization.delay",
          delay_seconds,
          %{"cadence.mission.id" => realized_contact.mission_id}
        )

        put_in(acc.seen_realized_contacts[realized_contact_id], now)
      else
        _not_new_or_unlinked -> acc
      end
    end)
  end

  defp expects_live_downlink?(%RealizedContact{
         lifecycle_state: :active,
         clock_mode: :live,
         contact_intents: intents
       }) do
    :telemetry_downlink in intents
  end

  defp expects_live_downlink?(%RealizedContact{}), do: false

  defp newest_receipt_time(samples) do
    samples
    |> Enum.map(& &1.receipt_time)
    |> Enum.filter(&match?(%DateTime{}, &1))
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp oldest_enqueued_at(entries) do
    entries
    |> Enum.map(& &1.enqueued_at)
    |> Enum.filter(&match?(%DateTime{}, &1))
    |> Enum.min(DateTime, fn -> nil end)
  end

  defp age_seconds(nil, _now), do: nil

  defp age_seconds(%DateTime{} = timestamp, %DateTime{} = now) do
    max(DateTime.diff(now, timestamp, :millisecond), 0) / 1_000
  end

  defp eligible?(entry, now) do
    is_nil(entry.not_before) or DateTime.compare(entry.not_before, now) in [:lt, :eq]
  end

  defp command_deadline_outcome(%{expires_at: nil}, _now), do: nil

  defp command_deadline_outcome(%{lifecycle_state: :released}, _now), do: "met"

  defp command_deadline_outcome(%{lifecycle_state: :pending, expires_at: expires_at}, now) do
    if DateTime.compare(expires_at, now) in [:lt, :eq], do: "missed"
  end

  defp command_deadline_outcome(_entry, _now), do: nil

  defp organization_id(realized_contacts, scheduled_contacts) do
    (realized_contacts ++ scheduled_contacts)
    |> Enum.find_value(& &1.organization_id)
  end

  defp boolean_number(true), do: 1
  defp boolean_number(false), do: 0

  defp record(state, name, value, attributes) do
    Reporter.record(state.reporter, name, value, attributes)
  end

  defp prune_seen(state, now) do
    cutoff = DateTime.add(now, -@seen_retention_seconds, :second)

    %{
      state
      | seen_command_deadlines: prune_map(state.seen_command_deadlines, cutoff),
        seen_realized_contacts: prune_map(state.seen_realized_contacts, cutoff)
    }
  end

  defp prune_map(map, cutoff) do
    Map.filter(map, fn {_id, observed_at} ->
      DateTime.compare(observed_at, cutoff) in [:gt, :eq]
    end)
  end

  defp schedule_sample(interval_ms), do: Process.send_after(self(), :sample, interval_ms)

  defp active_mission_ids, do: Runtime.running_mission_ids()

  defp contacts(mission_id) do
    %{
      scheduled: Contacts.list_scheduled_contacts(mission_id),
      realized: Contacts.list_realized_contacts(mission_id)
    }
  end

  defp latest_values(mission_id) do
    CurrentValueStore.latest_values_for_mission(mission_id)
  end

  defp command_entries(organization_id, mission_id) do
    Commanding.list_command_queue_entries(organization_id, mission_id)
  end
end
