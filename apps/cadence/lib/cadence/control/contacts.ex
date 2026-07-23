defmodule Cadence.Control.Contacts do
  @moduledoc "Control-plane executor for exact realized Contact runtime handoffs."

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlanExecutionItem, ContactPlanExecutions}

  alias Cadence.Contacts.{
    ContactStore,
    ProviderReservation,
    ProviderReservations,
    RealizedContact,
    ScheduledContact
  }

  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Management.Contacts.ApprovedContactPlan
  alias Cadence.Runtime.Contacts, as: RuntimeContacts
  alias Cadence.Runtime.RealizedContactRuntimeSpec

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
         :ok <- accept_approved_plan(approved_plan) do
      ContactPlanExecutions.execute(current_scope, mission_id, plan_id, opts)
    end
  end

  @spec list_plan_execution(binary(), binary(), binary(), pos_integer()) ::
          [ContactPlanExecutionItem.t()]
  def list_plan_execution(organization_id, mission_id, plan_id, version),
    do: ContactPlanExecutions.list(organization_id, mission_id, plan_id, version)

  @spec fetch_provider_reservation(binary(), binary(), binary()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def fetch_provider_reservation(organization_id, mission_id, reservation_id),
    do: ProviderReservations.fetch(organization_id, mission_id, reservation_id)

  @spec fetch_scheduled_contact(binary(), binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id),
    do: ContactStore.fetch_scheduled(organization_id, mission_id, scheduled_contact_id)

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
      paths: realized_contact.paths,
      clock_mode: realized_contact.clock_mode,
      initial_time: realized_contact.initial_time,
      metadata: realized_contact.metadata
    })
  end
end
