defmodule Cadence.Control.Contacts do
  @moduledoc "Control-plane executor for exact realized Contact runtime handoffs."

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlanExecutionItem, ContactPlanExecutions}

  alias Cadence.Contacts.{
    ContactStore,
    ProviderReservation,
    ProviderReservations,
    RealizedContact,
    ScheduledContact,
    Scheduler
  }

  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Management.Contacts.ApprovedContactPlan
  alias Cadence.Runtime.Contacts, as: RuntimeContacts
  alias Cadence.Runtime.RealizedContactRuntimeSpec
  alias Cadence.SourceEndpoints

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

  defdelegate list_plan_execution_page(organization_id, mission_id, plan_id, version, page),
    to: ContactPlanExecutions,
    as: :list_page

  defdelegate list_contact_records_page(org, mission, kind, page),
    to: ContactStore,
    as: :list_record_page

  defdelegate list_provider_reservations_page(org, mission, page),
    to: ProviderReservations,
    as: :list_mission_page

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
    with {:ok, %RealizedContactRuntimeSpec{} = spec} <- runtime_spec(realized_contact) do
      RuntimeContacts.start(spec)
    end
  end

  @spec stop_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(mission_id, realized_contact_id),
    do: RuntimeContacts.stop(mission_id, realized_contact_id)

  @spec stop_realized_contact_sync(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact_sync(mission_id, realized_contact_id),
    do: RuntimeContacts.stop_sync(mission_id, realized_contact_id)

  @spec realized_contact_running?(binary(), binary()) :: boolean()
  def realized_contact_running?(mission_id, realized_contact_id),
    do: RuntimeContacts.running?(mission_id, realized_contact_id)

  @spec realized_contact_snapshot(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(mission_id, realized_contact_id),
    do: RuntimeContacts.snapshot(mission_id, realized_contact_id)

  defp runtime_spec(realized_contact) do
    RealizedContactRuntimeSpec.new(%{
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
    |> Map.put(
      :source_endpoint_spacecraft_id,
      source_endpoint_spacecraft_id(realized_contact, source_endpoint_ref)
    )
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
