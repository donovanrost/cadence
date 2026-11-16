defmodule Cadence.Control.Contacts do
  @moduledoc "Control-plane executor for exact realized Contact runtime handoffs."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.ListenClaims

  alias Cadence.ContactPlanning.{
    ConfirmationWindow,
    ContactPlanExecutionItem,
    ContactPlanExecutions,
    FleetRunLock
  }

  alias Cadence.Contacts.{
    ContactStore,
    ListenerRefusalAttention,
    ProviderReservation,
    ProviderReservations,
    RealizedContact,
    ScheduledContact,
    Scheduler
  }

  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Management.Contacts.ApprovedContactPlan
  alias Cadence.Platform.ResolutionEvidence
  alias Cadence.Runtime.Contacts, as: RuntimeContacts
  alias Cadence.Runtime.RealizedContactRuntimeSpec
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @doc "Reviews a scoped provider reservation before resolving its uncertain outcome."
  def review_provider_reservation_resolution(%Scope{} = scope, mission, id) do
    with :ok <-
           Policy.authorize(scope, :resolve_provider_reservation, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }) do
      ProviderReservations.review_resolution(scope.organization_id, mission, id)
    end
  end

  @doc "Records evidence on the original reservation without resubmitting to the provider."
  def resolve_provider_reservation(%Scope{} = scope, mission, id, attrs) do
    with :ok <-
           Policy.authorize(scope, :resolve_provider_reservation, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, evidence} <- ResolutionEvidence.new(Scope.audit_actor(scope), attrs) do
      ProviderReservations.resolve_attempt(scope.organization_id, mission, id, evidence)
    end
  end

  @doc "Waits for in-flight contact scheduling before mission shutdown or reconfiguration."
  @spec await_scheduler_settled(GenServer.server()) :: {:ok, term()} | {:error, :noproc}
  def await_scheduler_settled(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> Scheduler.await_settled(server)
      nil -> {:ok, :disabled}
    end
  end

  @spec accept_approved_plan(ApprovedContactPlan.t()) :: :ok | {:error, term()}
  def accept_approved_plan(%ApprovedContactPlan{} = approved_plan),
    do: ContactPlanExecutions.accept(approved_plan)

  @spec approve_and_accept_plan(
          Scope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, ApprovedContactPlan.t()} | {:error, term()}
  def approve_and_accept_plan(
        %Scope{} = current_scope,
        mission_id,
        plan_id,
        expected_version,
        expected_hash,
        reason,
        opts \\ []
      ) do
    with {:ok, approved_plan} <-
           ManagementContacts.approve_plan(
             current_scope,
             mission_id,
             plan_id,
             expected_version,
             expected_hash,
             reason,
             opts
           ),
         :ok <- accept_approved_plan(approved_plan) do
      {:ok, approved_plan}
    end
  end

  @spec execute_approved_plan(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, %{plan: struct(), items: [ContactPlanExecutionItem.t()]}} | {:error, term()}
  def execute_approved_plan(%Scope{} = current_scope, mission_id, plan_id, opts \\ []) do
    with {:ok, approved_plan} <-
           ManagementContacts.fetch_approved_plan(
             current_scope.organization_id,
             mission_id,
             plan_id
           ),
         :ok <- expected_approved_plan(approved_plan, opts),
         :ok <- accept_approved_plan(approved_plan) do
      ContactPlanExecutions.execute(current_scope, mission_id, plan_id, opts)
    end
  end

  defp expected_approved_plan(approved_plan, opts) do
    case {Keyword.fetch(opts, :expected_plan_version), Keyword.fetch(opts, :expected_plan_hash)} do
      {:error, :error} ->
        :ok

      {{:ok, version}, {:ok, hash}}
      when is_integer(version) and is_binary(hash) and
             version == approved_plan.contact_plan_version and
             hash == approved_plan.content_sha256 ->
        :ok

      _ ->
        {:error, :stale_contact_plan_evidence}
    end
  end

  @spec list_plan_execution(binary(), binary(), binary(), pos_integer()) ::
          [ContactPlanExecutionItem.t()]
  def list_plan_execution(organization_id, mission_id, plan_id, version),
    do: ContactPlanExecutions.list(organization_id, mission_id, plan_id, version)

  @doc """
  A plan's lifecycle as operators see it (DECISIONS #52). An `executing` plan that no session
  is executing reads by its unfinished items:

  - `:interrupted` when any were never placed (`pending`/`requesting`). Execute resumes those
    and only re-reads `uncertain` ones; it never re-sends them.
  - `:unconfirmed` when an `uncertain` item (placed, provider hasn't answered) has waited past
    the provider confirmation window, counted from placement (`started_at`, set when the item is
    claimed just before the provider call), so later provider errors don't restart it. It needs
    operator resolution, not Execute.
  - `:executing` when every unfinished item is `uncertain` within the window. Nothing to
    resume; the plan settles when the provider confirms.

  A `partially_reserved` plan reads the same way when no session is executing it (U61, 11-16):
  the execution projection writes `partially_reserved` as soon as one item is reserved, while the
  rest may still be pending. A run that stopped after booking some passes then reads
  `:interrupted`, not booked. With nothing unfinished it stays `:partially_reserved` (the
  failed items have their own resolution).

  Options: `:now`, `:confirmation_window_ms` (default from `:provider_confirmation_window_ms`).
  """
  @spec plan_state(binary(), binary(), binary(), atom(), keyword()) :: atom()
  def plan_state(organization_id, mission_id, plan_id, lifecycle_state, opts \\ [])

  def plan_state(organization_id, mission_id, plan_id, state, opts)
      when state in [:executing, :partially_reserved] do
    if FleetRunLock.key_held?(
         ContactPlanExecutions.execution_key(organization_id, mission_id, plan_id)
       ),
       do: state,
       else: unattended_state(organization_id, mission_id, plan_id, state, opts)
  end

  def plan_state(_organization_id, _mission_id, _plan_id, lifecycle_state, _opts),
    do: lifecycle_state

  defp unattended_state(organization_id, mission_id, plan_id, state, opts) do
    unfinished =
      organization_id
      |> plan_items(mission_id, plan_id)
      |> Enum.filter(&(&1.lifecycle_state in [:pending, :requesting, :uncertain]))

    cond do
      unfinished == [] and state == :partially_reserved -> :partially_reserved
      unfinished == [] -> :interrupted
      Enum.any?(unfinished, &(&1.lifecycle_state != :uncertain)) -> :interrupted
      Enum.any?(unfinished, &ConfirmationWindow.overdue?(&1, opts)) -> :unconfirmed
      true -> state
    end
  end

  defp plan_items(organization_id, mission_id, plan_id) do
    case ManagementContacts.fetch_approved_plan(organization_id, mission_id, plan_id) do
      {:ok, approved} ->
        list_plan_execution(organization_id, mission_id, plan_id, approved.contact_plan_version)

      {:error, _reason} ->
        []
    end
  end

  defdelegate list_plan_execution_page(organization_id, mission_id, plan_id, version, page),
    to: ContactPlanExecutions,
    as: :list_page

  defdelegate list_contact_records_page(org, mission, kind, page),
    to: ContactStore,
    as: :list_record_page

  defdelegate list_provider_reservations_page(org, mission, page),
    to: ProviderReservations,
    as: :list_mission_page

  @doc "Per-spacecraft in-contact / next AOS / last LOS from booked reservations."
  defdelegate contact_summary(org, mission, now),
    to: ProviderReservations,
    as: :contact_summary

  @doc "Reservations overlapping a time window (console passes read)."
  defdelegate list_provider_reservations_in_window(org, mission, from, to, opts \\ []),
    to: ProviderReservations,
    as: :list_in_window

  @doc "Whether the booking's uplink leg was dropped by an accepted change (no command window)."
  defdelegate uplink_leg_dropped?(reservation), to: Cadence.Contacts.UplinkLegs, as: :dropped?

  @doc "Dropped uplink legs among the reservations, with when and why (api U46 reads)."
  defdelegate uplink_drops(org, mission, reservation_ids),
    to: Cadence.Contacts.UplinkLegs,
    as: :drops

  @spec fetch_provider_reservation(binary(), binary(), binary()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def fetch_provider_reservation(organization_id, mission_id, reservation_id),
    do: ProviderReservations.fetch(organization_id, mission_id, reservation_id)

  defdelegate fetch_provider_change(organization_id, change_id),
    to: Cadence.Contacts.ProviderReservationChanges,
    as: :fetch

  defdelegate list_provider_changes_page(org, mission, reservation, before_revision),
    to: Cadence.Contacts.ProviderReservationChanges,
    as: :list_page

  defdelegate approve_provider_change(scope, change_id, hash, reason),
    to: Cadence.Contacts.ProviderChangeApprovals,
    as: :approve

  defdelegate reject_provider_change(scope, change_id, hash, reason),
    to: Cadence.Contacts.ProviderChangeApprovals,
    as: :reject

  defdelegate acknowledge_provider_change(scope, change_id, hash, reason),
    to: Cadence.Contacts.ProviderChangeApprovals,
    as: :acknowledge

  @spec fetch_scheduled_contact(binary(), binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id),
    do: ContactStore.fetch_scheduled(organization_id, mission_id, scheduled_contact_id)

  defdelegate fetch_realized_contact(org, mission, contact), to: ContactStore, as: :fetch_realized

  defdelegate fetch_scheduled_contact_revision(org, mission, contact, revision),
    to: Cadence.Contacts.ScheduledContactRevisions,
    as: :fetch_scoped

  defdelegate list_scheduled_contact_revisions_page(
                org,
                mission,
                contact,
                revision,
                before_revision
              ), to: Cadence.Contacts.ScheduledContactRevisions, as: :list_page

  @spec start_realized_contact(RealizedContact.t()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(%RealizedContact{} = realized_contact) do
    # SAFETY: a listen host:port is one mission's (ListenClaims). A pass whose pinned listener
    # another mission also claims doesn't start, so neither mission's listener can take the
    # other's peer (fail closed).
    with :ok <- ListenClaims.check_paths(realized_contact.mission_id, realized_contact.paths),
         {:ok, %RealizedContactRuntimeSpec{} = spec} <- runtime_spec(realized_contact) do
      RuntimeContacts.start(spec)
    end
  end

  @doc """
  Starts an ended contact's runtime without intake, to store what its ingress journal kept
  (DECISIONS #71 replay): journals, executor and projector only; no provider adapter or transport.
  """
  @spec start_replay(RealizedContact.t()) :: {:ok, pid()} | {:error, term()}
  def start_replay(%RealizedContact{} = realized_contact) do
    with {:ok, %RealizedContactRuntimeSpec{} = spec} <-
           runtime_spec(realized_contact, intake?: false) do
      RuntimeContacts.start(spec)
    end
  end

  @spec stop_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(mission_id, realized_contact_id),
    do: RuntimeContacts.stop(mission_id, realized_contact_id)

  @spec stop_realized_contact_sync(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact_sync(mission_id, realized_contact_id),
    do: RuntimeContacts.stop_sync(mission_id, realized_contact_id)

  @spec quiesce_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def quiesce_realized_contact(mission_id, realized_contact_id),
    do: RuntimeContacts.quiesce(mission_id, realized_contact_id)

  @spec terminate_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def terminate_realized_contact(mission_id, realized_contact_id),
    do: RuntimeContacts.terminate(mission_id, realized_contact_id)

  @spec realized_contact_journal_backlog(binary(), binary()) :: map()
  def realized_contact_journal_backlog(mission_id, realized_contact_id),
    do: RuntimeContacts.backlog(mission_id, realized_contact_id)

  @spec realized_contact_incomplete_at_end(binary(), binary()) :: [map()]
  def realized_contact_incomplete_at_end(mission_id, realized_contact_id),
    do: RuntimeContacts.incomplete_at_end(mission_id, realized_contact_id)

  @spec ingress_journal_enabled?() :: boolean()
  def ingress_journal_enabled?, do: RuntimeContacts.journal_enabled?()

  @spec journaled_realized_contact_ids(binary()) :: MapSet.t(binary())
  def journaled_realized_contact_ids(mission_id), do: RuntimeContacts.journaled_ids(mission_id)

  @spec stored_ingress_journals(binary()) :: [map()]
  def stored_ingress_journals(mission_id), do: RuntimeContacts.stored_journals(mission_id)

  @doc "The ingress journal's disk (Runtime.Contacts.journal_volume/1, ux U66)."
  @spec ingress_journal_volume(keyword()) :: {:ok, map()} | :unknown
  def ingress_journal_volume(opts \\ []), do: RuntimeContacts.journal_volume(opts)

  @doc "The mission's shared-listener adapters and their refusals (Runtime.Contacts, ux U50)."
  @spec listener_refusals(binary()) :: [map()]
  def listener_refusals(mission_id), do: RuntimeContacts.listener_refusals(mission_id)

  @spec listener_refusals(binary(), binary()) :: [map()]
  def listener_refusals(mission_id, realized_contact_id),
    do: RuntimeContacts.listener_refusals(mission_id, realized_contact_id)

  @doc """
  Second connections refused for a contact (ux U50 Technical details): live while it runs, else
  what its settler recorded at LOS, else nil.
  """
  @spec second_connections_refused(binary(), binary(), binary()) :: non_neg_integer() | nil
  def second_connections_refused(organization_id, mission_id, realized_contact_id),
    do:
      ListenerRefusalAttention.second_connections_refused(
        organization_id,
        mission_id,
        realized_contact_id
      )

  @spec ingress_journal_open?(binary(), binary()) :: boolean()
  def ingress_journal_open?(mission_id, realized_contact_id),
    do: RuntimeContacts.journal_open?(mission_id, realized_contact_id)

  @spec stored_ingress_journal_drain(map()) ::
          {:drained, non_neg_integer()} | {:not_drained, term(), non_neg_integer()}
  def stored_ingress_journal_drain(stream), do: RuntimeContacts.stored_journal_drain(stream)

  @spec reclaim_stored_ingress_journal(map()) :: :ok | {:error, term()}
  def reclaim_stored_ingress_journal(stream), do: RuntimeContacts.reclaim_stored_journal(stream)

  @spec running_realized_contact_ids(binary()) :: [binary()]
  def running_realized_contact_ids(mission_id), do: RuntimeContacts.running_ids(mission_id)

  @spec realized_contact_running?(binary(), binary()) :: boolean()
  def realized_contact_running?(mission_id, realized_contact_id),
    do: RuntimeContacts.running?(mission_id, realized_contact_id)

  @spec realized_contact_snapshot(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(mission_id, realized_contact_id),
    do: RuntimeContacts.snapshot(mission_id, realized_contact_id)

  defp runtime_spec(realized_contact, opts \\ []) do
    RealizedContactRuntimeSpec.new(%{
      intake?: Keyword.get(opts, :intake?, true),
      runtime_spec_id: "realized_contact_runtime:#{realized_contact.realized_contact_id}",
      generation: 1,
      realized_contact_id: realized_contact.realized_contact_id,
      organization_id: realized_contact.organization_id,
      mission_id: realized_contact.mission_id,
      scheduled_contact_id: realized_contact.scheduled_contact_id,
      source_endpoint_refs: realized_contact.source_endpoint_refs,
      contact_intents: realized_contact.contact_intents,
      paths: Enum.map(realized_contact.paths, &runtime_path(realized_contact, &1)),
      clock_mode: realized_contact.clock_mode,
      initial_time: realized_contact.initial_time,
      metadata: realized_contact.metadata
    })
  end

  defp runtime_path(realized_contact, path) do
    source_endpoint_ref =
      effective_source_endpoint_ref(
        path.source_endpoint_ref,
        realized_contact.source_endpoint_refs
      )

    path
    |> Map.from_struct()
    |> Map.put(:source_endpoint_ref, source_endpoint_ref)
    |> put_spacecraft(
      realized_contact,
      source_endpoint_spacecraft_id(realized_contact, source_endpoint_ref)
    )
  end

  # The path's spacecraft and its SCID (a profile acceptor routes a downlink peer by it, #87).
  defp put_spacecraft(path, _realized_contact, nil),
    do:
      Map.merge(path, %{source_endpoint_spacecraft_id: nil, source_endpoint_spacecraft_scid: nil})

  defp put_spacecraft(path, realized_contact, spacecraft_id) do
    fetched =
      case realized_contact.organization_id do
        org when is_binary(org) and org != "" ->
          SpacecraftStore.fetch_spacecraft(org, realized_contact.mission_id, spacecraft_id)

        _none ->
          SpacecraftStore.fetch_spacecraft(realized_contact.mission_id, spacecraft_id)
      end

    scid =
      case fetched do
        {:ok, %{scid: scid}} when is_integer(scid) -> scid
        _unknown -> nil
      end

    Map.merge(path, %{
      source_endpoint_spacecraft_id: spacecraft_id,
      source_endpoint_spacecraft_scid: scid
    })
  end

  defp effective_source_endpoint_ref(source_endpoint_ref, _contact_source_endpoint_refs)
       when is_binary(source_endpoint_ref) and source_endpoint_ref != "",
       do: source_endpoint_ref

  defp effective_source_endpoint_ref(_source_endpoint_ref, [source_endpoint_ref]),
    do: source_endpoint_ref

  defp effective_source_endpoint_ref(_source_endpoint_ref, _contact_source_endpoint_refs), do: nil

  defp source_endpoint_spacecraft_id(_realized_contact, source_endpoint_ref)
       when source_endpoint_ref in [nil, ""],
       do: nil

  defp source_endpoint_spacecraft_id(realized_contact, source_endpoint_ref) do
    fetch_result =
      case realized_contact.organization_id do
        organization_id when is_binary(organization_id) and organization_id != "" ->
          SourceEndpoints.fetch_source_endpoint(
            organization_id,
            realized_contact.mission_id,
            source_endpoint_ref
          )

        _other ->
          SourceEndpoints.fetch_source_endpoint(realized_contact.mission_id, source_endpoint_ref)
      end

    case fetch_result do
      {:ok, source_endpoint} -> source_endpoint.spacecraft_id
      {:error, _reason} -> nil
    end
  end
end
