defmodule Cadence.Contacts.ContactSettler do
  @moduledoc """
  Settles one ended realized contact (DECISIONS #71): ending a contact never waits on the TSDB.

  `ContactLifecycle` records the end (`completed` or `stopped`, with `settlement.state`
  `"settling"`) and hands the contact here, then returns: neither the contact scheduler nor an
  operator's stop waits on a runtime. The settler quiesces the contact's runtime (intake stops
  first: transports and providers; then the ingress journal drains into the TSDB), then stops it:

  - drained: `settled`;
  - the deadline passes first, or the quiesce fails: `unsettled`, with `unpersisted_journal`
    naming what is still on disk. The deadline is long (hours) and bounds resources; nothing
    waits on it. Nothing is dropped: the journal keeps every entry its processing cursor hasn't
    passed, and the replay follow-up stores it.

  A contact whose runtime isn't running when its settler starts reads `settled` with
  `runtime: "absent"`: its on-disk journal wasn't inspected (the replay follow-up does that).

  One settler per contact (registered); temporary. A node restart leaves the contact
  `settling` with no settler, which reconcile's sweep finds.

  **Replay** (`replay/2`, the #71 follow-up): the same settler, on an ended contact whose journal
  still holds telemetry. It starts the contact's runtime without intake (journals and their
  drain only), then quiesces it with a shorter deadline. One replay per mission at a time: a
  replaying settler is registered by mission.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Cadence.Contacts.ContactSettlement
  alias Cadence.Contacts.ListenerRefusalAttention
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Contacts.Scheduler
  alias Cadence.Control.Contacts, as: Runtime
  alias Cadence.Control.ProcessNamespace
  alias Cadence.Projections.DataSources.Watermarks.Coalescer

  @doc "The settlers' supervisor, a child of the control root supervisor."
  @spec supervisor_name(ProcessNamespace.t()) :: GenServer.name()
  def supervisor_name(%ProcessNamespace{} = namespace \\ ProcessNamespace.default()),
    do: ProcessNamespace.via(namespace, :contact_settler_supervisor)

  @doc """
  Hands `contact` to its settler and returns without waiting. Idempotent: `:ok` when one is
  already settling it. Options: `:deadline_ms`, `:process_namespace`.
  """
  @spec settle(RealizedContact.t(), keyword()) :: :ok | {:error, term()}
  def settle(contact, opts \\ [])

  def settle(%RealizedContact{} = contact, opts) do
    if ContactSettlement.state(contact) in [nil, "settling"] do
      case start_settler(contact, opts) do
        {:error, {:already_started, _pid}} -> :ok
        other -> other
      end
    else
      :ok
    end
  end

  @doc """
  Replays an ended contact's journal (#71 follow-up) and returns without waiting. `:ok` when
  started, `{:error, :replay_running}` when the mission already has one.
  """
  @spec replay(RealizedContact.t(), keyword()) :: :ok | {:error, term()}
  def replay(%RealizedContact{} = contact, opts \\ []) do
    case start_settler(contact, Keyword.put(opts, :mode, :replay)) do
      {:error, {:already_started, _pid}} -> {:error, :replay_running}
      other -> other
    end
  end

  @doc "Whether the mission has a replay running."
  @spec replaying?(binary(), ProcessNamespace.t()) :: boolean()
  def replaying?(mission_id, namespace \\ ProcessNamespace.default()),
    do: GenServer.whereis(replay_name(namespace, mission_id)) != nil

  defp start_settler(contact, opts) do
    namespace = Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
    spec = {__MODULE__, Keyword.merge(opts, contact: contact, process_namespace: namespace)}

    case GenServer.whereis(supervisor_name(namespace)) do
      nil -> start_unsupervised(spec)
      supervisor -> started(DynamicSupervisor.start_child(supervisor, spec))
    end
  end

  # A node whose control tree predates the settlers' supervisor (a code reload, not a restart)
  # still settles: the settler runs unlinked, which a node restart's sweep backs up anyway.
  defp start_unsupervised({__MODULE__, opts}) do
    %RealizedContact{} = contact = Keyword.fetch!(opts, :contact)
    namespace = Keyword.fetch!(opts, :process_namespace)

    started(GenServer.start(__MODULE__, opts, name: process_name(namespace, contact, opts)))
  end

  defp started({:ok, _pid}), do: :ok
  defp started({:error, {:already_started, _pid}} = error), do: error
  defp started({:error, reason}), do: {:error, reason}

  @doc "Whether a settler is settling the contact now."
  @spec settling?(binary(), binary(), ProcessNamespace.t()) :: boolean()
  def settling?(mission_id, realized_contact_id, namespace \\ ProcessNamespace.default()) do
    GenServer.whereis(name(namespace, mission_id, realized_contact_id)) != nil
  end

  def start_link(opts) do
    %RealizedContact{} = contact = Keyword.fetch!(opts, :contact)
    namespace = Keyword.fetch!(opts, :process_namespace)

    GenServer.start_link(__MODULE__, opts, name: process_name(namespace, contact, opts))
  end

  @impl true
  def init(opts) do
    contact = Keyword.fetch!(opts, :contact)
    mode = Keyword.get(opts, :mode, :settle)

    default_deadline =
      if mode == :replay,
        do: &ContactSettlement.replay_deadline_ms/0,
        else: &ContactSettlement.deadline_ms/0

    deadline_ms = Keyword.get_lazy(opts, :deadline_ms, default_deadline)

    {:ok, %{contact: contact, mode: mode, deadline_ms: deadline_ms, worker: nil, deadline: nil},
     {:continue, :quiesce}}
  end

  @impl true
  def handle_continue(:quiesce, %{mode: :replay, contact: contact} = state) do
    {:ok, contact} = ContactSettlement.replay_started(contact)

    case Runtime.start_replay(contact) do
      {:ok, _pid} ->
        start_quiesce(%{state | contact: contact})

      {:error, reason} ->
        finish(%{state | contact: contact}, {:unsettled, "settle_failed", reason})
    end
  end

  def handle_continue(:quiesce, %{contact: contact} = state) do
    %{mission_id: mission_id, realized_contact_id: id} = contact

    if Runtime.realized_contact_running?(mission_id, id),
      do: start_quiesce(state),
      else: finish(state, :absent)
  end

  defp start_quiesce(%{contact: %{mission_id: mission_id, realized_contact_id: id}} = state) do
    worker =
      spawn_monitor(fn -> exit({:quiesced, Runtime.quiesce_realized_contact(mission_id, id)}) end)

    deadline = Process.send_after(self(), :deadline, state.deadline_ms)
    {:noreply, %{state | worker: worker, deadline: deadline}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{worker: {_pid2, ref}} = state) do
    Process.cancel_timer(state.deadline)

    case reason do
      {:quiesced, :ok} -> finish(state, :settled)
      {:quiesced, {:error, error}} -> finish(state, {:unsettled, "settle_failed", error})
      other -> finish(state, {:unsettled, "settle_failed", other})
    end
  end

  def handle_info(:deadline, %{worker: {pid, ref}} = state) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
    finish(state, {:unsettled, "settle_deadline", nil})
  end

  def handle_info(_message, state), do: {:noreply, state}

  # The backlog is read while the journals still run, then the runtime stops (no quiesce: the
  # journal is durable on disk and keeps what its processing cursor hasn't passed).
  defp finish(%{contact: contact} = state, outcome) do
    %{mission_id: mission_id, realized_contact_id: id} = contact

    backlog =
      case outcome do
        {:unsettled, _reason, _error} -> Runtime.realized_contact_journal_backlog(mission_id, id)
        _settled_or_absent -> %{}
      end

    # Its listener refusals (ux U50) live in its adapters: read them before they stop.
    refusals =
      ListenerRefusalAttention.settlement_document(
        Runtime.listener_refusals(mission_id, id),
        DateTime.utc_now()
      )

    # What a stream gave up at its end (a frame or packet that never completed): read before stop.
    incomplete = Runtime.realized_contact_incomplete_at_end(mission_id, id)
    # And what its frame-SCID cross-check refused (DECISIONS #102), likewise before stop.
    scid_checks = Runtime.realized_contact_scid_checks(mission_id, id)

    stop = Runtime.terminate_realized_contact(mission_id, id)
    # End of pass: write the mission's pending watermark window (#690) so the pass reads settled.
    log_unwritten_watermark(Coalescer.flush_mission(mission_id), mission_id)

    _ =
      if state.mode == :replay,
        do: ContactSettlement.record_replay(contact, outcome, backlog, stop),
        else:
          ContactSettlement.record(
            contact,
            outcome,
            backlog,
            stop,
            refusals,
            incomplete,
            scid_checks
          )

    # Its runtime is gone, listener included: a pass that couldn't start (ux U45) starts now.
    :ok = Scheduler.retry_starts(mission_id)
    {:stop, :normal, state}
  end

  defp log_unwritten_watermark(:ok, _mission_id), do: :ok

  defp log_unwritten_watermark({:error, reason}, mission_id) do
    Logger.error(
      "contact settled with an unwritten watermark window for mission #{mission_id}: #{inspect(reason)}"
    )
  end

  defp process_name(namespace, contact, opts) do
    if Keyword.get(opts, :mode) == :replay,
      do: replay_name(namespace, contact.mission_id),
      else: name(namespace, contact.mission_id, contact.realized_contact_id)
  end

  defp name(namespace, mission_id, realized_contact_id),
    do: ProcessNamespace.via(namespace, {:contact_settler, mission_id, realized_contact_id})

  defp replay_name(namespace, mission_id),
    do: ProcessNamespace.via(namespace, {:contact_replay, mission_id})
end
