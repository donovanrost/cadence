defmodule Cadence.Contacts.ProviderContactReconciler do
  @moduledoc """
  Reconciles terminal external-provider events into canonical Cadence contact state.

  The cursor is process-local. Replaying events after restart is safe because
  scheduled-contact cancellation is idempotent.
  """

  use GenServer

  alias Cadence.Contacts
  @default_poll_interval_ms 5_000
  @terminal_failure_events [
    "reservation.rejected",
    "reservation.canceled",
    "reservation.failed",
    "reservation.terminated_early"
  ]

  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec reconcile_now(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def reconcile_now(server \\ __MODULE__) do
    GenServer.call(server, :reconcile_now, :infinity)
  end

  @spec reconcile_events([map()]) :: %{canceled: non_neg_integer(), ignored: non_neg_integer()}
  def reconcile_events(events) when is_list(events) do
    Enum.reduce(events, %{canceled: 0, ignored: 0}, fn event, summary ->
      case reconcile_event(event) do
        :canceled -> Map.update!(summary, :canceled, &(&1 + 1))
        :ignored -> Map.update!(summary, :ignored, &(&1 + 1))
      end
    end)
  end

  @impl true
  def init(opts) do
    state = %{
      cursor: Keyword.get(opts, :cursor, 0),
      safety_poll_interval_ms:
        Keyword.get(opts, :safety_poll_interval_ms, @default_poll_interval_ms),
      events_fun: Keyword.fetch!(opts, :events_fun)
    }

    schedule_poll(state.safety_poll_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:reconcile_now, _from, state) do
    {reply, state} = poll(state)
    {:reply, reply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_poll(state.safety_poll_interval_ms)
    {_reply, state} = poll(state)
    {:noreply, state}
  end

  defp poll(state) do
    case state.events_fun.(state.cursor) do
      {:ok, %{"data" => events, "next_cursor" => next_cursor}} ->
        summary = reconcile_events(events)
        {{:ok, summary}, %{state | cursor: next_cursor}}

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  defp reconcile_event(%{
         "type" => type,
         "resource_id" => provider_contact_ref,
         "data" => %{"mission_profile_ref" => mission_id} = data
       })
       when type in @terminal_failure_events and is_binary(mission_id) do
    with {:ok, scheduled_contact} <-
           Contacts.fetch_scheduled_contact_by_provider_ref(mission_id, provider_contact_ref),
         {:ok, _canceled_contact} <-
           Contacts.cancel_scheduled_contact(
             mission_id,
             scheduled_contact.scheduled_contact_id,
             actor: %{"kind" => "system", "id" => "ground_station_provider"},
             reason: data["reason"] || type
           ) do
      :canceled
    else
      _other -> :ignored
    end
  end

  defp reconcile_event(_event), do: :ignored

  defp schedule_poll(interval_ms), do: Process.send_after(self(), :poll, interval_ms)
end
