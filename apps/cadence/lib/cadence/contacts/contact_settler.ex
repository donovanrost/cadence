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
  """

  use GenServer, restart: :temporary

  alias Cadence.Contacts.ContactSettlement
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.Contacts, as: Runtime
  alias Cadence.Control.ProcessNamespace

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
    if ContactSettlement.state(contact) in [nil, "settling"],
      do: start_settler(contact, opts),
      else: :ok
  end

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

    started(
      GenServer.start(__MODULE__, opts,
        name: name(namespace, contact.mission_id, contact.realized_contact_id)
      )
    )
  end

  defp started({:ok, _pid}), do: :ok
  defp started({:error, {:already_started, _pid}}), do: :ok
  defp started({:error, reason}), do: {:error, reason}

  @doc "Whether a settler is settling the contact now."
  @spec settling?(binary(), binary(), ProcessNamespace.t()) :: boolean()
  def settling?(mission_id, realized_contact_id, namespace \\ ProcessNamespace.default()) do
    GenServer.whereis(name(namespace, mission_id, realized_contact_id)) != nil
  end

  def start_link(opts) do
    %RealizedContact{} = contact = Keyword.fetch!(opts, :contact)
    namespace = Keyword.fetch!(opts, :process_namespace)

    GenServer.start_link(__MODULE__, opts,
      name: name(namespace, contact.mission_id, contact.realized_contact_id)
    )
  end

  @impl true
  def init(opts) do
    contact = Keyword.fetch!(opts, :contact)
    deadline_ms = Keyword.get_lazy(opts, :deadline_ms, &ContactSettlement.deadline_ms/0)

    {:ok, %{contact: contact, deadline_ms: deadline_ms, worker: nil, deadline: nil},
     {:continue, :quiesce}}
  end

  @impl true
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

    stop = Runtime.terminate_realized_contact(mission_id, id)
    _ = ContactSettlement.record(contact, outcome, backlog, stop)
    {:stop, :normal, state}
  end

  defp name(namespace, mission_id, realized_contact_id),
    do: ProcessNamespace.via(namespace, {:contact_settler, mission_id, realized_contact_id})
end
