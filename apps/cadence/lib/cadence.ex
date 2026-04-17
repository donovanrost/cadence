defmodule Cadence do
  @moduledoc """
  Core entry points for the redesigned Cadence system.

  The first implemented vertical slice is:

  1. raw ingress evidence
  2. canonical packet record decode
  3. governed application dispatch
  4. definition-bound telemetry handling
  5. canonical telemetry samples
  """

  alias Cadence.Accounts
  alias Cadence.Accounts.User
  alias Cadence.Activations
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.ApplicationDispatch.DispatchDecision
  alias Cadence.ApplicationDispatch.Dispatcher
  alias Cadence.Auth
  alias Cadence.Auth.Scope, as: CurrentScope
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, ImporterDescriptor, ImportRun}
  alias Cadence.Catalog.Command.Compiler, as: CommandCatalogCompiler
  alias Cadence.Catalog.Command.Compiler.Result, as: CommandCompilerResult
  alias Cadence.Catalog.Command.Snapshot, as: CommandCatalogSnapshot
  alias Cadence.Catalog.Telemetry.Compiler, as: TelemetryCatalogCompiler
  alias Cadence.Catalog.Telemetry.Compiler.Result, as: TelemetryCompilerResult
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot
  alias Cadence.Commanding

  alias Cadence.Commanding.{
    CommandApproval,
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandStage,
    CommandVerifierInstance,
    StagedCommandItem
  }

  alias Cadence.Contacts, as: ContactsService

  alias Cadence.Contacts.{
    ContactAction,
    PathTemplate,
    ProviderProfile,
    RealizedContact,
    ScheduledContact,
    TransportProfile
  }

  alias Cadence.DerivedTelemetry, as: DerivedTelemetryService
  alias Cadence.DerivedTelemetry.Definition, as: DerivedTelemetryDefinition
  alias Cadence.Governance
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Jobs
  alias Cadence.Limits, as: LimitsService
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Missions
  alias Cadence.Missions.Mission
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization
  alias Cadence.Persistence
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  alias Cadence.Projections.DerivedTelemetryLatestValues,
    as: DerivedTelemetryLatestValueProjection

  alias Cadence.Projections.TelemetryLatestLimitStates, as: TelemetryLatestLimitStateProjection
  alias Cadence.Projections.TelemetryLatestValues, as: TelemetryLatestValueProjection
  alias Cadence.Protocol.{PacketRecord, ProtocolAnomaly, TMFrameIngress, TransferFrameRecord}
  alias Cadence.Protocol.SpacePacketDecoder
  alias Cadence.Reads.DerivedTelemetry, as: DerivedTelemetryReads
  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.Reads.MissionEvents, as: MissionEventReads
  alias Cadence.Reads.MissionHealth, as: MissionHealthReads
  alias Cadence.Reads.Replay, as: ReplayReads
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Replay
  alias Cadence.Replay.Diff, as: ReplayDiff
  alias Cadence.Replay.Scope
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  @type processing_result :: %{
          raw_evidence: RawEvidence.t(),
          packet_records: [PacketRecord.t()],
          transfer_frame_records: [TransferFrameRecord.t()],
          protocol_anomalies: [ProtocolAnomaly.t()],
          dispatch_decisions: [DispatchDecision.t()],
          outputs: [term()],
          runtime_records: map()
        }

  @spec bootstrap_organization(Organization.t(), ServiceIdentity.t(), Mission.t() | nil) ::
          {:ok,
           %{
             organization: Organization.t(),
             mission: Mission.t() | nil,
             service_identity: ServiceIdentity.t(),
             api_token: binary()
           }}
          | {:error, term()}
  def bootstrap_organization(
        %Organization{} = organization,
        %ServiceIdentity{} = service_identity,
        mission \\ nil
      ) do
    Auth.bootstrap(organization, service_identity, mission)
  end

  @spec authenticate_api_token(binary(), keyword()) :: {:ok, CurrentScope.t()} | {:error, term()}
  def authenticate_api_token(api_token, opts \\ []) when is_binary(api_token) and is_list(opts) do
    Auth.authenticate_api_token(api_token, opts)
  end

  @spec sign_in(binary(), binary()) ::
          {:ok, Cadence.Accounts.issued_user_session()} | {:error, term()}
  def sign_in(email, password) when is_binary(email) and is_binary(password) do
    Auth.sign_in(email, password)
  end

  @spec login_bootstrap_admin(binary(), binary()) ::
          {:ok, %{user: User.t(), session_token: binary(), expires_at: DateTime.t()}}
          | {:error, term()}
  def login_bootstrap_admin(email, password)
      when is_binary(email) and is_binary(password) do
    Auth.login_bootstrap_admin(email, password)
  end

  @spec login_user(binary(), binary()) ::
          {:ok, %{user: User.t(), session_token: binary(), expires_at: DateTime.t()}}
          | {:error, term()}
  def login_user(email, password) when is_binary(email) and is_binary(password) do
    Auth.login_user(email, password)
  end

  @spec ensure_bootstrap_admin() :: {:ok, User.t()} | {:error, term()}
  def ensure_bootstrap_admin do
    Auth.ensure_bootstrap_admin()
  end

  @spec revoke_bootstrap_admin_session(binary()) :: :ok
  def revoke_bootstrap_admin_session(session_token) when is_binary(session_token) do
    Auth.revoke_bootstrap_admin_session(session_token)
  end

  @spec revoke_user_session(binary()) :: :ok
  def revoke_user_session(session_token) when is_binary(session_token) do
    Auth.revoke_user_session(session_token)
  end

  @spec fetch_organization_invitation(binary()) ::
          {:ok, Cadence.Accounts.OrganizationInvitation.t()} | {:error, term()}
  def fetch_organization_invitation(invitation_token) when is_binary(invitation_token) do
    Auth.fetch_organization_invitation(invitation_token)
  end

  @spec accept_organization_invitation(binary(), map()) :: {:ok, map()} | {:error, term()}
  def accept_organization_invitation(invitation_token, attrs)
      when is_binary(invitation_token) and is_map(attrs) do
    Auth.accept_organization_invitation(invitation_token, attrs)
  end

  @spec bootstrap_admin_enabled?() :: boolean()
  def bootstrap_admin_enabled? do
    Auth.bootstrap_admin_enabled?()
  end

  @spec persist_organization(Organization.t()) :: {:ok, Organization.t()} | {:error, term()}
  def persist_organization(%Organization{} = organization) do
    Organizations.persist_organization(organization)
  end

  @spec fetch_organization(binary()) :: {:ok, Organization.t()} | {:error, term()}
  def fetch_organization(organization_id) when is_binary(organization_id) do
    Organizations.fetch_organization(organization_id)
  end

  @spec list_organizations() :: [Organization.t()]
  def list_organizations do
    Organizations.list_organizations()
  end

  @spec count_organizations() :: non_neg_integer()
  def count_organizations do
    Organizations.count_organizations()
  end

  @spec list_organization_members(binary()) :: [map()]
  def list_organization_members(organization_id) when is_binary(organization_id) do
    Accounts.list_organization_members(organization_id)
  end

  @spec list_pending_invitations(binary()) :: [map()]
  def list_pending_invitations(organization_id) when is_binary(organization_id) do
    Accounts.list_pending_invitations(organization_id)
  end

  @spec count_users() :: non_neg_integer()
  def count_users do
    Accounts.count_users()
  end

  @spec persist_mission(Mission.t()) :: {:ok, Mission.t()} | {:error, term()}
  def persist_mission(%Mission{} = mission) do
    Missions.persist_mission(mission)
  end

  @spec fetch_mission(binary(), binary()) :: {:ok, Mission.t()} | {:error, term()}
  def fetch_mission(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    Missions.fetch_mission(organization_id, mission_id)
  end

  @spec list_missions(binary()) :: [Mission.t()]
  def list_missions(organization_id) when is_binary(organization_id) do
    Missions.list_missions(organization_id)
  end

  @spec persist_spacecraft(binary(), Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    SpacecraftStore.persist_spacecraft(organization_id, spacecraft)
  end

  @spec persist_spacecraft(Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(%Spacecraft{} = spacecraft) do
    SpacecraftStore.persist_spacecraft(spacecraft)
  end

  @spec fetch_spacecraft(binary(), binary(), binary()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id)
  end

  @spec fetch_spacecraft(binary(), binary()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft(mission_id, spacecraft_id)
      when is_binary(mission_id) and is_binary(spacecraft_id) do
    SpacecraftStore.fetch_spacecraft(mission_id, spacecraft_id)
  end

  @spec list_spacecraft(binary(), binary()) :: [Spacecraft.t()]
  def list_spacecraft(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    SpacecraftStore.list_spacecraft(organization_id, mission_id)
  end

  @spec list_spacecraft(binary()) :: [Spacecraft.t()]
  def list_spacecraft(mission_id) when is_binary(mission_id) do
    SpacecraftStore.list_spacecraft(mission_id)
  end

  @spec issue_service_identity(ServiceIdentity.t()) ::
          {:ok, %{service_identity: ServiceIdentity.t(), api_token: binary()}} | {:error, term()}
  def issue_service_identity(%ServiceIdentity{} = service_identity) do
    Auth.issue_service_identity(service_identity)
  end

  @spec list_catalog_importers(keyword()) :: [
          %{module: module(), descriptor: ImporterDescriptor.t()}
        ]
  def list_catalog_importers(opts \\ []) when is_list(opts) do
    Catalog.list_importers(opts)
  end

  @spec persist_catalog_artifact(binary(), Artifact.t()) ::
          {:ok, Artifact.t()} | {:error, term()}
  def persist_catalog_artifact(organization_id, %Artifact{} = artifact)
      when is_binary(organization_id) do
    Catalog.persist_artifact(organization_id, artifact)
  end

  @spec fetch_catalog_artifact(binary(), binary(), binary()) ::
          {:ok, Artifact.t()} | {:error, term()}
  def fetch_catalog_artifact(organization_id, mission_id, artifact_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(artifact_id) do
    Catalog.fetch_artifact(organization_id, mission_id, artifact_id)
  end

  @spec list_catalog_artifacts(binary(), binary(), keyword()) :: [Artifact.t()]
  def list_catalog_artifacts(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Catalog.list_artifacts(organization_id, mission_id, opts)
  end

  @spec start_catalog_import_run(binary(), binary(), binary(), binary(), keyword()) ::
          {:ok, ImportRun.t()} | {:error, term()}
  def start_catalog_import_run(organization_id, mission_id, artifact_id, importer_key, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(artifact_id) and
             is_binary(importer_key) and is_list(opts) do
    Catalog.start_import_run(organization_id, mission_id, artifact_id, importer_key, opts)
  end

  @spec fetch_catalog_import_run(binary(), binary(), binary()) ::
          {:ok, ImportRun.t()} | {:error, term()}
  def fetch_catalog_import_run(organization_id, mission_id, import_run_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(import_run_id) do
    Catalog.fetch_import_run(organization_id, mission_id, import_run_id)
  end

  @spec list_catalog_import_runs(binary(), binary(), keyword()) :: [ImportRun.t()]
  def list_catalog_import_runs(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Catalog.list_import_runs(organization_id, mission_id, opts)
  end

  @spec fetch_catalog_telemetry_snapshot(binary(), binary(), binary()) ::
          {:ok, TelemetryCatalogSnapshot.t()} | {:error, term()}
  def fetch_catalog_telemetry_snapshot(organization_id, mission_id, snapshot_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) do
    Catalog.fetch_telemetry_snapshot(organization_id, mission_id, snapshot_id)
  end

  @spec list_catalog_telemetry_snapshots(binary(), binary(), keyword()) ::
          [TelemetryCatalogSnapshot.t()]
  def list_catalog_telemetry_snapshots(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Catalog.list_telemetry_snapshots(organization_id, mission_id, opts)
  end

  @spec fetch_catalog_command_snapshot(binary(), binary(), binary()) ::
          {:ok, CommandCatalogSnapshot.t()} | {:error, term()}
  def fetch_catalog_command_snapshot(organization_id, mission_id, snapshot_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) do
    Catalog.fetch_command_snapshot(organization_id, mission_id, snapshot_id)
  end

  @spec list_catalog_command_snapshots(binary(), binary(), keyword()) ::
          [CommandCatalogSnapshot.t()]
  def list_catalog_command_snapshots(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Catalog.list_command_snapshots(organization_id, mission_id, opts)
  end

  @spec persist_command_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def persist_command_stage(organization_id, %CommandStage{} = command_stage)
      when is_binary(organization_id) do
    Commanding.persist_command_stage(organization_id, command_stage)
  end

  @spec update_command_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def update_command_stage(organization_id, %CommandStage{} = command_stage)
      when is_binary(organization_id) do
    Commanding.update_command_stage(organization_id, command_stage)
  end

  @spec fetch_command_stage(binary(), binary(), binary()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def fetch_command_stage(organization_id, mission_id, command_stage_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_stage_id) do
    Commanding.fetch_command_stage(organization_id, mission_id, command_stage_id)
  end

  @spec list_command_stages(binary(), binary(), keyword()) :: [CommandStage.t()]
  def list_command_stages(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Commanding.list_command_stages(organization_id, mission_id, opts)
  end

  @spec persist_staged_command_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def persist_staged_command_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    Commanding.persist_staged_command_item(organization_id, staged_command_item)
  end

  @spec update_staged_command_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def update_staged_command_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    Commanding.update_staged_command_item(organization_id, staged_command_item)
  end

  @spec fetch_staged_command_item(binary(), binary(), binary()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def fetch_staged_command_item(organization_id, mission_id, staged_command_item_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(staged_command_item_id) do
    Commanding.fetch_staged_command_item(organization_id, mission_id, staged_command_item_id)
  end

  @spec list_staged_command_items(binary(), binary(), keyword()) :: [StagedCommandItem.t()]
  def list_staged_command_items(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Commanding.list_staged_command_items(organization_id, mission_id, opts)
  end

  @spec persist_command_request(binary(), CommandRequest.t()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def persist_command_request(organization_id, %CommandRequest{} = command_request)
      when is_binary(organization_id) do
    Commanding.persist_command_request(organization_id, command_request)
  end

  @spec fetch_command_request(binary(), binary(), binary()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def fetch_command_request(organization_id, mission_id, command_request_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_request_id) do
    Commanding.fetch_command_request(organization_id, mission_id, command_request_id)
  end

  @spec list_command_requests(binary(), binary(), keyword()) :: [CommandRequest.t()]
  def list_command_requests(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Commanding.list_command_requests(organization_id, mission_id, opts)
  end

  @spec approve_command_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{approval: CommandApproval.t(), command_request: CommandRequest.t()}}
          | {:error, term()}
  def approve_command_request(
        organization_id,
        mission_id,
        command_request_id,
        approved_by,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_request_id) and is_map(approved_by) and is_list(opts) do
    Commanding.approve_command_request(
      organization_id,
      mission_id,
      command_request_id,
      approved_by,
      opts
    )
  end

  @spec reject_command_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{approval: CommandApproval.t(), command_request: CommandRequest.t()}}
          | {:error, term()}
  def reject_command_request(
        organization_id,
        mission_id,
        command_request_id,
        rejected_by,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_request_id) and is_map(rejected_by) and is_list(opts) do
    Commanding.reject_command_request(
      organization_id,
      mission_id,
      command_request_id,
      rejected_by,
      opts
    )
  end

  @spec fetch_command_approval(binary(), binary(), binary()) ::
          {:ok, CommandApproval.t()} | {:error, term()}
  def fetch_command_approval(organization_id, mission_id, command_approval_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_approval_id) do
    Commanding.fetch_command_approval(organization_id, mission_id, command_approval_id)
  end

  @spec list_command_approvals(binary(), binary(), keyword()) :: [CommandApproval.t()]
  def list_command_approvals(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Commanding.list_command_approvals(organization_id, mission_id, opts)
  end

  @spec enqueue_command_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{command_request: CommandRequest.t(), queue_entry: CommandQueueEntry.t()}}
          | {:error, term()}
  def enqueue_command_request(
        organization_id,
        mission_id,
        command_request_id,
        enqueued_by \\ %{},
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_request_id) and is_map(enqueued_by) and is_list(opts) do
    Commanding.enqueue_command_request(
      organization_id,
      mission_id,
      command_request_id,
      enqueued_by,
      opts
    )
  end

  @spec fetch_command_queue_entry(binary(), binary(), binary()) ::
          {:ok, CommandQueueEntry.t()} | {:error, term()}
  def fetch_command_queue_entry(organization_id, mission_id, command_queue_entry_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_queue_entry_id) do
    Commanding.fetch_command_queue_entry(organization_id, mission_id, command_queue_entry_id)
  end

  @spec list_command_queue_entries(binary(), binary(), keyword()) :: [CommandQueueEntry.t()]
  def list_command_queue_entries(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Commanding.list_command_queue_entries(organization_id, mission_id, opts)
  end

  @spec fetch_command_release_attempt(binary(), binary(), binary()) ::
          {:ok, CommandReleaseAttempt.t()} | {:error, term()}
  def fetch_command_release_attempt(organization_id, mission_id, command_release_attempt_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_release_attempt_id) do
    Commanding.fetch_command_release_attempt(
      organization_id,
      mission_id,
      command_release_attempt_id
    )
  end

  @spec list_command_release_attempts(binary(), binary(), keyword()) ::
          [CommandReleaseAttempt.t()]
  def list_command_release_attempts(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Commanding.list_command_release_attempts(organization_id, mission_id, opts)
  end

  @spec fetch_command_verifier_instance(binary(), binary(), binary()) ::
          {:ok, CommandVerifierInstance.t()} | {:error, term()}
  def fetch_command_verifier_instance(organization_id, mission_id, command_verifier_instance_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_verifier_instance_id) do
    Commanding.fetch_command_verifier_instance(
      organization_id,
      mission_id,
      command_verifier_instance_id
    )
  end

  @spec list_command_verifier_instances(binary(), binary(), keyword()) ::
          [CommandVerifierInstance.t()]
  def list_command_verifier_instances(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Commanding.list_command_verifier_instances(organization_id, mission_id, opts)
  end

  @spec release_command_queue_entry(binary(), binary(), binary(), binary(), map(), keyword()) ::
          {:ok,
           %{
             release_attempt: CommandReleaseAttempt.t(),
             queue_entry: CommandQueueEntry.t(),
             command_request: CommandRequest.t()
           }}
          | {:error, term()}
  def release_command_queue_entry(
        organization_id,
        mission_id,
        command_queue_entry_id,
        realized_contact_id,
        released_by \\ %{},
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_queue_entry_id) and is_binary(realized_contact_id) and
             is_map(released_by) and is_list(opts) do
    Commanding.release_command_queue_entry(
      organization_id,
      mission_id,
      command_queue_entry_id,
      realized_contact_id,
      released_by,
      opts
    )
  end

  @spec submit_staged_command_items(binary(), binary(), binary(), [binary()], map()) ::
          {:ok, [CommandRequest.t()]} | {:error, term()}
  def submit_staged_command_items(
        organization_id,
        mission_id,
        command_stage_id,
        staged_command_item_ids,
        requested_by \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_stage_id) and
             is_list(staged_command_item_ids) and is_map(requested_by) do
    Commanding.submit_staged_command_items(
      organization_id,
      mission_id,
      command_stage_id,
      staged_command_item_ids,
      requested_by
    )
  end

  @spec recompile_catalog_telemetry_snapshot(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def recompile_catalog_telemetry_snapshot(organization_id, mission_id, snapshot_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) and
             is_list(opts) do
    Catalog.recompile_telemetry_snapshot(organization_id, mission_id, snapshot_id, opts)
  end

  @spec diff_catalog_telemetry_snapshot_runtime(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def diff_catalog_telemetry_snapshot_runtime(
        organization_id,
        mission_id,
        snapshot_id,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) and
             is_list(opts) do
    Catalog.diff_telemetry_snapshot_runtime(organization_id, mission_id, snapshot_id, opts)
  end

  @spec materialize_catalog_telemetry_snapshot_runtime(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def materialize_catalog_telemetry_snapshot_runtime(
        organization_id,
        mission_id,
        snapshot_id,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) and
             is_list(opts) do
    Catalog.materialize_telemetry_snapshot_runtime(organization_id, mission_id, snapshot_id, opts)
  end

  @spec compile_telemetry_catalog_snapshot(TelemetryCatalogSnapshot.t(), keyword()) ::
          TelemetryCompilerResult.t()
  def compile_telemetry_catalog_snapshot(
        %TelemetryCatalogSnapshot{} = telemetry_catalog_snapshot,
        opts \\ []
      )
      when is_list(opts) do
    TelemetryCatalogCompiler.compile(telemetry_catalog_snapshot, opts)
  end

  @spec compile_command_catalog_snapshot(CommandCatalogSnapshot.t(), keyword()) ::
          CommandCompilerResult.t()
  def compile_command_catalog_snapshot(
        %CommandCatalogSnapshot{} = command_catalog_snapshot,
        opts \\ []
      )
      when is_list(opts) do
    CommandCatalogCompiler.compile(command_catalog_snapshot, opts)
  end

  @spec fetch_service_identity(binary(), binary()) ::
          {:ok, ServiceIdentity.t()} | {:error, term()}
  def fetch_service_identity(organization_id, service_identity_id)
      when is_binary(organization_id) and is_binary(service_identity_id) do
    Auth.fetch_service_identity(organization_id, service_identity_id)
  end

  @spec list_service_identities(binary(), keyword()) :: [ServiceIdentity.t()]
  def list_service_identities(organization_id, opts \\ [])
      when is_binary(organization_id) and is_list(opts) do
    Auth.list_service_identities(organization_id, opts)
  end

  @spec process_telemetry_ingress(RawEvidence.t(), BindingSet.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence, %BindingSet{} = binding_set) do
    with {:ok, %RawEvidence{} = resolved_raw_evidence} <- resolve_raw_evidence(raw_evidence),
         :ok <- validate_binding_set_mission(resolved_raw_evidence, binding_set),
         {:ok, decode_result} <- decode_raw_evidence_packets(resolved_raw_evidence),
         {:ok, dispatch_result} <- execute_dispatches(decode_result, binding_set) do
      {:ok, build_processing_result(resolved_raw_evidence, dispatch_result)}
    end
  end

  @spec process_telemetry_ingress(RawEvidence.t(), binary()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence, binding_set_id)
      when is_binary(binding_set_id) do
    with {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_latest_binding_set(raw_evidence.mission_id, binding_set_id) do
      process_telemetry_ingress(raw_evidence, binding_set)
    end
  end

  @spec process_telemetry_ingress(RawEvidence.t(), binary(), pos_integer()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence, binding_set_id, version)
      when is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_binding_set(raw_evidence.mission_id, binding_set_id, version) do
      process_telemetry_ingress(raw_evidence, binding_set)
    end
  end

  @spec process_telemetry_ingress(RawEvidence.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence) do
    with {:ok, %RawEvidence{} = resolved_raw_evidence} <- resolve_raw_evidence(raw_evidence) do
      Runtime.process_telemetry_ingress(resolved_raw_evidence)
    end
  end

  @spec process_and_persist_telemetry_ingress(RawEvidence.t(), BindingSet.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist_telemetry_ingress(
        %RawEvidence{} = raw_evidence,
        %BindingSet{} = binding_set
      ) do
    with {:ok, processing_result} <- process_telemetry_ingress(raw_evidence, binding_set) do
      Persistence.persist_processing_result(processing_result)
    end
  end

  @spec process_and_persist_telemetry_ingress(RawEvidence.t(), binary()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist_telemetry_ingress(%RawEvidence{} = raw_evidence, binding_set_id)
      when is_binary(binding_set_id) do
    with {:ok, processing_result} <- process_telemetry_ingress(raw_evidence, binding_set_id) do
      Persistence.persist_processing_result(processing_result)
    end
  end

  @spec process_and_persist_telemetry_ingress(RawEvidence.t(), binary(), pos_integer()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist_telemetry_ingress(
        %RawEvidence{} = raw_evidence,
        binding_set_id,
        version
      )
      when is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with {:ok, processing_result} <-
           process_telemetry_ingress(raw_evidence, binding_set_id, version) do
      Persistence.persist_processing_result(processing_result)
    end
  end

  @spec process_and_persist_telemetry_ingress(RawEvidence.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist_telemetry_ingress(%RawEvidence{} = raw_evidence) do
    TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
      ingress_started_at = System.monotonic_time()

      resolve_result =
        TelemetryProfiler.with_stage(:resolve, fn ->
          resolve_raw_evidence(raw_evidence)
        end)

      resolve_us = elapsed_us(ingress_started_at)

      case resolve_result do
        {:ok, %RawEvidence{} = resolved_raw_evidence} ->
          handle_resolved_ingress(resolved_raw_evidence, ingress_started_at, resolve_us)

        {:error, reason} ->
          TelemetryProfiler.record_ingress_result(
            raw_evidence,
            resolve_us: resolve_us,
            end_to_end_us: elapsed_us(ingress_started_at),
            error?: true
          )

          {:error, reason}
      end
    end)
  end

  defp handle_resolved_ingress(
         %RawEvidence{} = resolved_raw_evidence,
         ingress_started_at,
         resolve_us
       ) do
    runtime_started_at = System.monotonic_time()

    runtime_result =
      TelemetryProfiler.with_stage(:runtime, fn ->
        Runtime.process_telemetry_ingress(resolved_raw_evidence)
      end)

    runtime_us = elapsed_us(runtime_started_at)

    case runtime_result do
      {:ok, processing_result} ->
        finalize_persisted_ingress(
          resolved_raw_evidence,
          processing_result,
          ingress_started_at,
          resolve_us,
          runtime_us
        )

      {:error, reason} ->
        TelemetryProfiler.record_ingress_result(
          resolved_raw_evidence,
          resolve_us: resolve_us,
          runtime_us: runtime_us,
          end_to_end_us: elapsed_us(ingress_started_at),
          error?: true
        )

        {:error, reason}
    end
  end

  defp finalize_persisted_ingress(
         %RawEvidence{} = resolved_raw_evidence,
         processing_result,
         ingress_started_at,
         resolve_us,
         runtime_us
       ) do
    persistence_started_at = System.monotonic_time()

    persistence_result =
      TelemetryProfiler.with_stage(:persistence, fn ->
        Persistence.persist_processing_result(processing_result)
      end)

    persistence_us = elapsed_us(persistence_started_at)
    end_to_end_us = elapsed_us(ingress_started_at)

    TelemetryProfiler.record_ingress_result(
      resolved_raw_evidence,
      resolve_us: resolve_us,
      runtime_us: runtime_us,
      persistence_us: persistence_us,
      end_to_end_us: end_to_end_us,
      error?: match?({:error, _reason}, persistence_result),
      processing_result: processing_result
    )

    normalize_persistence_result(persistence_result)
  end

  defp normalize_persistence_result({:ok, persisted_result}), do: {:ok, persisted_result}
  defp normalize_persistence_result({:error, reason}), do: {:error, reason}

  @spec activate_binding_set(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, Cadence.Activations.BindingSetActivation.t()} | {:error, term()}
  def activate_binding_set(organization_id, mission_id, binding_set_id, version, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 and is_list(opts) do
    Activations.activate_binding_set(organization_id, mission_id, binding_set_id, version, opts)
  end

  @spec activate_binding_set(binary(), binary(), pos_integer(), keyword()) ::
          {:ok, Cadence.Activations.BindingSetActivation.t()} | {:error, term()}
  def activate_binding_set(mission_id, binding_set_id, version, opts \\ [])
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 and is_list(opts) do
    Runtime.activate_binding_set(mission_id, binding_set_id, version, opts)
  end

  @spec fetch_active_binding_set(binary(), binary()) ::
          {:ok, Cadence.ApplicationDispatch.BindingSet.t()} | {:error, term()}
  def fetch_active_binding_set(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    Activations.fetch_active_binding_set(organization_id, mission_id)
  end

  @spec fetch_active_binding_set(binary()) ::
          {:ok, Cadence.ApplicationDispatch.BindingSet.t()} | {:error, term()}
  def fetch_active_binding_set(mission_id) when is_binary(mission_id) do
    Runtime.fetch_active_binding_set(mission_id)
  end

  @spec fetch_active_binding_set_activation(binary(), binary()) ::
          {:ok, Cadence.Activations.BindingSetActivation.t()} | {:error, term()}
  def fetch_active_binding_set_activation(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    Activations.fetch_active_activation(organization_id, mission_id)
  end

  @spec fetch_active_binding_set_activation(binary()) ::
          {:ok, Cadence.Activations.BindingSetActivation.t()} | {:error, term()}
  def fetch_active_binding_set_activation(mission_id) when is_binary(mission_id) do
    Runtime.fetch_active_activation(mission_id)
  end

  @spec persist_scheduled_contact(ScheduledContact.t()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def persist_scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    ContactsService.persist_scheduled_contact(scheduled_contact)
  end

  @spec persist_provider_profile(binary(), ProviderProfile.t()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def persist_provider_profile(organization_id, %ProviderProfile{} = provider_profile)
      when is_binary(organization_id) do
    ContactsService.persist_provider_profile(organization_id, provider_profile)
  end

  @spec persist_provider_profile(ProviderProfile.t()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def persist_provider_profile(%ProviderProfile{} = provider_profile) do
    ContactsService.persist_provider_profile(provider_profile)
  end

  @spec fetch_provider_profile(binary(), binary()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile(mission_id, provider_profile_id)
      when is_binary(mission_id) and is_binary(provider_profile_id) do
    ContactsService.fetch_provider_profile(mission_id, provider_profile_id)
  end

  @spec fetch_provider_profile(binary(), binary(), binary()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile(organization_id, mission_id, provider_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) do
    ContactsService.fetch_provider_profile(organization_id, mission_id, provider_profile_id)
  end

  @spec fetch_provider_profile_version(binary(), binary(), pos_integer()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile_version(mission_id, provider_profile_id, version)
      when is_binary(mission_id) and is_binary(provider_profile_id) and is_integer(version) and
             version > 0 do
    ContactsService.fetch_provider_profile_version(mission_id, provider_profile_id, version)
  end

  @spec fetch_provider_profile_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile_version(organization_id, mission_id, provider_profile_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_integer(version) and version > 0 do
    ContactsService.fetch_provider_profile_version(
      organization_id,
      mission_id,
      provider_profile_id,
      version
    )
  end

  @spec list_provider_profiles(binary()) :: [ProviderProfile.t()]
  def list_provider_profiles(mission_id) when is_binary(mission_id) do
    ContactsService.list_provider_profiles(mission_id)
  end

  @spec list_provider_profiles(binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactsService.list_provider_profiles(organization_id, mission_id)
  end

  @spec list_provider_profile_versions(binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profile_versions(mission_id, provider_profile_id)
      when is_binary(mission_id) and is_binary(provider_profile_id) do
    ContactsService.list_provider_profile_versions(mission_id, provider_profile_id)
  end

  @spec list_provider_profile_versions(binary(), binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profile_versions(organization_id, mission_id, provider_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) do
    ContactsService.list_provider_profile_versions(
      organization_id,
      mission_id,
      provider_profile_id
    )
  end

  @spec version_provider_profile(binary(), binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def version_provider_profile(organization_id, mission_id, provider_profile_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_map(attrs) do
    ContactsService.version_provider_profile(
      organization_id,
      mission_id,
      provider_profile_id,
      attrs
    )
  end

  @spec delete_provider_profile(binary(), binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def delete_provider_profile(
        organization_id,
        mission_id,
        provider_profile_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_map(metadata_patch) do
    ContactsService.delete_provider_profile(
      organization_id,
      mission_id,
      provider_profile_id,
      metadata_patch
    )
  end

  @spec persist_transport_profile(binary(), TransportProfile.t()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def persist_transport_profile(organization_id, %TransportProfile{} = transport_profile)
      when is_binary(organization_id) do
    ContactsService.persist_transport_profile(organization_id, transport_profile)
  end

  @spec persist_transport_profile(TransportProfile.t()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def persist_transport_profile(%TransportProfile{} = transport_profile) do
    ContactsService.persist_transport_profile(transport_profile)
  end

  @spec fetch_transport_profile(binary(), binary()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile(mission_id, transport_profile_id)
      when is_binary(mission_id) and is_binary(transport_profile_id) do
    ContactsService.fetch_transport_profile(mission_id, transport_profile_id)
  end

  @spec fetch_transport_profile(binary(), binary(), binary()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile(organization_id, mission_id, transport_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) do
    ContactsService.fetch_transport_profile(organization_id, mission_id, transport_profile_id)
  end

  @spec fetch_transport_profile_version(binary(), binary(), pos_integer()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile_version(mission_id, transport_profile_id, version)
      when is_binary(mission_id) and is_binary(transport_profile_id) and is_integer(version) and
             version > 0 do
    ContactsService.fetch_transport_profile_version(mission_id, transport_profile_id, version)
  end

  @spec fetch_transport_profile_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile_version(organization_id, mission_id, transport_profile_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_integer(version) and version > 0 do
    ContactsService.fetch_transport_profile_version(
      organization_id,
      mission_id,
      transport_profile_id,
      version
    )
  end

  @spec list_transport_profiles(binary()) :: [TransportProfile.t()]
  def list_transport_profiles(mission_id) when is_binary(mission_id) do
    ContactsService.list_transport_profiles(mission_id)
  end

  @spec list_transport_profiles(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactsService.list_transport_profiles(organization_id, mission_id)
  end

  @spec list_transport_profile_versions(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profile_versions(mission_id, transport_profile_id)
      when is_binary(mission_id) and is_binary(transport_profile_id) do
    ContactsService.list_transport_profile_versions(mission_id, transport_profile_id)
  end

  @spec list_transport_profile_versions(binary(), binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profile_versions(organization_id, mission_id, transport_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) do
    ContactsService.list_transport_profile_versions(
      organization_id,
      mission_id,
      transport_profile_id
    )
  end

  @spec version_transport_profile(binary(), binary(), binary(), map()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def version_transport_profile(organization_id, mission_id, transport_profile_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_map(attrs) do
    ContactsService.version_transport_profile(
      organization_id,
      mission_id,
      transport_profile_id,
      attrs
    )
  end

  @spec delete_transport_profile(binary(), binary(), binary(), map()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def delete_transport_profile(
        organization_id,
        mission_id,
        transport_profile_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_map(metadata_patch) do
    ContactsService.delete_transport_profile(
      organization_id,
      mission_id,
      transport_profile_id,
      metadata_patch
    )
  end

  @spec persist_path_template(binary(), PathTemplate.t()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def persist_path_template(organization_id, %PathTemplate{} = path_template)
      when is_binary(organization_id) do
    ContactsService.persist_path_template(organization_id, path_template)
  end

  @spec persist_path_template(PathTemplate.t()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def persist_path_template(%PathTemplate{} = path_template) do
    ContactsService.persist_path_template(path_template)
  end

  @spec fetch_path_template(binary(), binary()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template(mission_id, path_template_id)
      when is_binary(mission_id) and is_binary(path_template_id) do
    ContactsService.fetch_path_template(mission_id, path_template_id)
  end

  @spec fetch_path_template(binary(), binary(), binary()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template(organization_id, mission_id, path_template_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) do
    ContactsService.fetch_path_template(organization_id, mission_id, path_template_id)
  end

  @spec fetch_path_template_version(binary(), binary(), pos_integer()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template_version(mission_id, path_template_id, version)
      when is_binary(mission_id) and is_binary(path_template_id) and is_integer(version) and
             version > 0 do
    ContactsService.fetch_path_template_version(mission_id, path_template_id, version)
  end

  @spec fetch_path_template_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template_version(organization_id, mission_id, path_template_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_integer(version) and version > 0 do
    ContactsService.fetch_path_template_version(
      organization_id,
      mission_id,
      path_template_id,
      version
    )
  end

  @spec list_path_templates(binary()) :: [PathTemplate.t()]
  def list_path_templates(mission_id) when is_binary(mission_id) do
    ContactsService.list_path_templates(mission_id)
  end

  @spec list_path_templates(binary(), binary()) :: [PathTemplate.t()]
  def list_path_templates(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactsService.list_path_templates(organization_id, mission_id)
  end

  @spec list_path_template_versions(binary(), binary()) :: [PathTemplate.t()]
  def list_path_template_versions(mission_id, path_template_id)
      when is_binary(mission_id) and is_binary(path_template_id) do
    ContactsService.list_path_template_versions(mission_id, path_template_id)
  end

  @spec list_path_template_versions(binary(), binary(), binary()) :: [PathTemplate.t()]
  def list_path_template_versions(organization_id, mission_id, path_template_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(path_template_id) do
    ContactsService.list_path_template_versions(organization_id, mission_id, path_template_id)
  end

  @spec version_path_template(binary(), binary(), binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def version_path_template(organization_id, mission_id, path_template_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(path_template_id) and
             is_map(attrs) do
    ContactsService.version_path_template(organization_id, mission_id, path_template_id, attrs)
  end

  @spec delete_path_template(binary(), binary(), binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def delete_path_template(organization_id, mission_id, path_template_id, metadata_patch \\ %{})
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(path_template_id) and
             is_map(metadata_patch) do
    ContactsService.delete_path_template(
      organization_id,
      mission_id,
      path_template_id,
      metadata_patch
    )
  end

  @spec persist_scheduled_contact(binary(), ScheduledContact.t()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def persist_scheduled_contact(organization_id, %ScheduledContact{} = scheduled_contact)
      when is_binary(organization_id) do
    ContactsService.persist_scheduled_contact(organization_id, scheduled_contact)
  end

  @spec fetch_scheduled_contact(binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled_contact(mission_id, scheduled_contact_id)
      when is_binary(mission_id) and is_binary(scheduled_contact_id) do
    ContactsService.fetch_scheduled_contact(mission_id, scheduled_contact_id)
  end

  @spec fetch_scheduled_contact(binary(), binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) do
    ContactsService.fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id)
  end

  @spec list_scheduled_contacts(binary()) :: [ScheduledContact.t()]
  def list_scheduled_contacts(mission_id) when is_binary(mission_id) do
    ContactsService.list_scheduled_contacts(mission_id)
  end

  @spec list_scheduled_contacts(binary(), binary()) :: [ScheduledContact.t()]
  def list_scheduled_contacts(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactsService.list_scheduled_contacts(organization_id, mission_id)
  end

  @spec list_contact_actions(binary(), keyword()) :: [ContactAction.t()]
  def list_contact_actions(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    ContactsService.list_contact_actions(mission_id, opts)
  end

  @spec list_contact_actions(binary(), binary(), keyword()) :: [ContactAction.t()]
  def list_contact_actions(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    ContactsService.list_contact_actions(organization_id, mission_id, opts)
  end

  @spec list_mission_events(binary(), keyword()) :: [Cadence.MissionEvents.Entry.t()]
  def list_mission_events(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    MissionEventReads.list_for_mission(mission_id, opts)
  end

  @spec list_mission_events(binary(), binary(), keyword()) :: [Cadence.MissionEvents.Entry.t()]
  def list_mission_events(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    MissionEventReads.list_for_mission(organization_id, mission_id, opts)
  end

  @spec rebuild_mission_events(binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_mission_events(mission_id) when is_binary(mission_id) do
    MissionEventProjection.rebuild(mission_id)
  end

  @spec rebuild_mission_events(binary(), binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_mission_events(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      MissionEventProjection.rebuild(mission_id)
    end
  end

  @spec start_rebuild_mission_events(binary()) ::
          {:ok, Cadence.Projections.MissionEvents.Run.t()} | {:error, term()}
  def start_rebuild_mission_events(mission_id) when is_binary(mission_id) do
    MissionEventProjection.start_rebuild(mission_id)
  end

  @spec start_rebuild_mission_events(binary(), binary()) ::
          {:ok, Cadence.Projections.MissionEvents.Run.t()} | {:error, term()}
  def start_rebuild_mission_events(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      MissionEventProjection.start_rebuild(mission_id)
    end
  end

  @spec fetch_mission_event_rebuild_run(binary()) ::
          {:ok, Cadence.Projections.MissionEvents.Run.t()} | {:error, term()}
  def fetch_mission_event_rebuild_run(rebuild_run_id) when is_binary(rebuild_run_id) do
    MissionEventProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_mission_event_rebuild_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_mission_event_rebuild_job(rebuild_run_id) when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:mission_event_rebuild, rebuild_run_id)
  end

  @spec realize_scheduled_contact(binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def realize_scheduled_contact(mission_id, scheduled_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(scheduled_contact_id) and is_list(opts) do
    ContactsService.realize_scheduled_contact(mission_id, scheduled_contact_id, opts)
  end

  @spec realize_scheduled_contact(binary(), binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def realize_scheduled_contact(organization_id, mission_id, scheduled_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) and is_list(opts) do
    ContactsService.realize_scheduled_contact(
      organization_id,
      mission_id,
      scheduled_contact_id,
      opts
    )
  end

  @spec cancel_scheduled_contact(binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel_scheduled_contact(mission_id, scheduled_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(scheduled_contact_id) and is_list(opts) do
    ContactsService.cancel_scheduled_contact(mission_id, scheduled_contact_id, opts)
  end

  @spec cancel_scheduled_contact(binary(), binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel_scheduled_contact(organization_id, mission_id, scheduled_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) and is_list(opts) do
    ContactsService.cancel_scheduled_contact(
      organization_id,
      mission_id,
      scheduled_contact_id,
      opts
    )
  end

  @spec reconcile_contact_lifecycle(DateTime.t()) :: {:ok, map()}
  def reconcile_contact_lifecycle(%DateTime{} = reference_time) do
    ContactsService.reconcile(reference_time)
  end

  @spec persist_realized_contact(RealizedContact.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def persist_realized_contact(%RealizedContact{} = realized_contact) do
    ContactsService.persist_realized_contact(realized_contact)
  end

  @spec persist_realized_contact(binary(), RealizedContact.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def persist_realized_contact(organization_id, %RealizedContact{} = realized_contact)
      when is_binary(organization_id) do
    ContactsService.persist_realized_contact(organization_id, realized_contact)
  end

  @spec fetch_realized_contact(binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    ContactsService.fetch_realized_contact(mission_id, realized_contact_id)
  end

  @spec fetch_realized_contact(binary(), binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    ContactsService.fetch_realized_contact(organization_id, mission_id, realized_contact_id)
  end

  @spec list_realized_contacts(binary()) :: [RealizedContact.t()]
  def list_realized_contacts(mission_id) when is_binary(mission_id) do
    ContactsService.list_realized_contacts(mission_id)
  end

  @spec list_realized_contacts(binary(), binary()) :: [RealizedContact.t()]
  def list_realized_contacts(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactsService.list_realized_contacts(organization_id, mission_id)
  end

  @spec start_realized_contact(RealizedContact.t()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(%RealizedContact{} = realized_contact) do
    ContactsService.start_realized_contact(realized_contact)
  end

  @spec start_realized_contact(binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    ContactsService.start_realized_contact(mission_id, realized_contact_id)
  end

  @spec start_realized_contact(binary(), binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    ContactsService.start_realized_contact(organization_id, mission_id, realized_contact_id)
  end

  @spec end_realized_contact_early(binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def end_realized_contact_early(mission_id, realized_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_list(opts) do
    ContactsService.end_realized_contact_early(mission_id, realized_contact_id, opts)
  end

  @spec end_realized_contact_early(binary(), binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def end_realized_contact_early(organization_id, mission_id, realized_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_list(opts) do
    ContactsService.end_realized_contact_early(
      organization_id,
      mission_id,
      realized_contact_id,
      opts
    )
  end

  @spec stop_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    ContactsService.stop_realized_contact(mission_id, realized_contact_id)
  end

  @spec stop_realized_contact(binary(), binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    ContactsService.stop_realized_contact(organization_id, mission_id, realized_contact_id)
  end

  @spec realized_contact_snapshot(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    Runtime.realized_contact_snapshot(mission_id, realized_contact_id)
  end

  @spec realized_contact_snapshot(binary(), binary(), binary()) ::
          {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.realized_contact_snapshot(mission_id, realized_contact_id)
    end
  end

  @spec path_runtime_snapshot(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def path_runtime_snapshot(mission_id, realized_contact_id, path_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) do
    Runtime.path_runtime_snapshot(mission_id, realized_contact_id, path_id)
  end

  @spec path_runtime_snapshot(binary(), binary(), binary(), binary()) ::
          {:ok, map()} | {:error, term()}
  def path_runtime_snapshot(organization_id, mission_id, realized_contact_id, path_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_binary(path_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.path_runtime_snapshot(mission_id, realized_contact_id, path_id)
    end
  end

  @spec handle_path_transport_event(binary(), binary(), binary(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_path_transport_event(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    Runtime.handle_path_transport_event(
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id,
      event,
      opts
    )
  end

  @spec handle_path_transport_event(
          binary(),
          binary(),
          binary(),
          binary(),
          binary(),
          term(),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def handle_path_transport_event(
        organization_id,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.handle_path_transport_event(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts
      )
    end
  end

  @spec handle_path_control_input(binary(), binary(), binary(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_path_control_input(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    Runtime.handle_path_control_input(
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id,
      control_input,
      opts
    )
  end

  @spec handle_path_control_input(
          binary(),
          binary(),
          binary(),
          binary(),
          binary(),
          term(),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def handle_path_control_input(
        organization_id,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.handle_path_control_input(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts
      )
    end
  end

  @spec advance_realized_contact_time(binary(), binary(), DateTime.t()) :: :ok | {:error, term()}
  def advance_realized_contact_time(mission_id, realized_contact_id, %DateTime{} = target_time)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    Runtime.advance_realized_contact_time(mission_id, realized_contact_id, target_time)
  end

  @spec advance_realized_contact_time(binary(), binary(), binary(), DateTime.t()) ::
          :ok | {:error, term()}
  def advance_realized_contact_time(
        organization_id,
        mission_id,
        realized_contact_id,
        %DateTime{} = target_time
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.advance_realized_contact_time(mission_id, realized_contact_id, target_time)
    end
  end

  @spec persist_source_endpoint(binary(), SourceEndpoint.t()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def persist_source_endpoint(organization_id, %SourceEndpoint{} = source_endpoint)
      when is_binary(organization_id) do
    SourceEndpoints.persist_source_endpoint(organization_id, source_endpoint)
  end

  @spec persist_source_endpoint(SourceEndpoint.t()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def persist_source_endpoint(%SourceEndpoint{} = source_endpoint) do
    SourceEndpoints.persist_source_endpoint(source_endpoint)
  end

  @spec fetch_source_endpoint(binary(), binary(), binary()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def fetch_source_endpoint(organization_id, mission_id, source_endpoint_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(source_endpoint_id) do
    SourceEndpoints.fetch_source_endpoint(organization_id, mission_id, source_endpoint_id)
  end

  @spec fetch_source_endpoint(binary(), binary()) :: {:ok, SourceEndpoint.t()} | {:error, term()}
  def fetch_source_endpoint(mission_id, source_endpoint_id)
      when is_binary(mission_id) and is_binary(source_endpoint_id) do
    SourceEndpoints.fetch_source_endpoint(mission_id, source_endpoint_id)
  end

  @spec list_source_endpoints(binary(), binary()) :: [SourceEndpoint.t()]
  def list_source_endpoints(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    SourceEndpoints.list_source_endpoints(organization_id, mission_id)
  end

  @spec list_source_endpoints(binary(), keyword()) :: [SourceEndpoint.t()]
  def list_source_endpoints(mission_id, opts) when is_binary(mission_id) and is_list(opts) do
    SourceEndpoints.list_source_endpoints(mission_id, opts)
  end

  @spec list_source_endpoints(binary(), binary(), keyword()) :: [SourceEndpoint.t()]
  def list_source_endpoints(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    SourceEndpoints.list_source_endpoints(organization_id, mission_id, opts)
  end

  @spec list_source_endpoints(binary()) :: [SourceEndpoint.t()]
  def list_source_endpoints(mission_id) when is_binary(mission_id) do
    SourceEndpoints.list_source_endpoints(mission_id)
  end

  @spec persist_packet_definition(binary(), PacketDefinition.t()) ::
          {:ok, PacketDefinition.t()} | {:error, term()}
  def persist_packet_definition(organization_id, %PacketDefinition{} = packet_definition)
      when is_binary(organization_id) do
    Governance.persist_packet_definition(organization_id, packet_definition)
  end

  @spec persist_packet_definition(PacketDefinition.t()) ::
          {:ok, PacketDefinition.t()} | {:error, term()}
  def persist_packet_definition(%PacketDefinition{} = packet_definition) do
    Governance.persist_packet_definition(packet_definition)
  end

  @spec list_packet_definitions(binary(), binary()) :: [PacketDefinition.t()]
  def list_packet_definitions(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    Governance.list_packet_definitions(organization_id, mission_id)
  end

  @spec list_packet_definitions(binary()) :: [PacketDefinition.t()]
  def list_packet_definitions(mission_id) when is_binary(mission_id) do
    Governance.list_packet_definitions(mission_id)
  end

  @spec persist_binding_set(binary(), BindingSet.t()) :: {:ok, BindingSet.t()} | {:error, term()}
  def persist_binding_set(organization_id, %BindingSet{} = binding_set)
      when is_binary(organization_id),
      do: Governance.persist_binding_set(organization_id, binding_set)

  @spec persist_binding_set(BindingSet.t()) :: {:ok, BindingSet.t()} | {:error, term()}
  def persist_binding_set(%BindingSet{} = binding_set),
    do: Governance.persist_binding_set(binding_set)

  @spec fetch_binding_set(binary(), binary(), binary(), pos_integer()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def fetch_binding_set(organization_id, mission_id, binding_set_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 do
    Governance.fetch_binding_set(organization_id, mission_id, binding_set_id, version)
  end

  @spec fetch_binding_set(binary(), binary(), pos_integer()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def fetch_binding_set(mission_id, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Governance.fetch_binding_set(mission_id, binding_set_id, version)
  end

  defp resolve_raw_evidence(%RawEvidence{} = raw_evidence) do
    SourceEndpoints.resolve_raw_evidence(raw_evidence)
  end

  defp elapsed_us(started_at) when is_integer(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :microsecond)
  end

  @spec fetch_latest_binding_set(binary(), binary(), binary()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def fetch_latest_binding_set(organization_id, mission_id, binding_set_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) do
    Governance.fetch_latest_binding_set(organization_id, mission_id, binding_set_id)
  end

  @spec fetch_latest_binding_set(binary(), binary()) :: {:ok, BindingSet.t()} | {:error, term()}
  def fetch_latest_binding_set(mission_id, binding_set_id)
      when is_binary(mission_id) and is_binary(binding_set_id) do
    Governance.fetch_latest_binding_set(mission_id, binding_set_id)
  end

  @spec persist_derived_definition(DerivedTelemetryDefinition.t()) ::
          {:ok, DerivedTelemetryDefinition.t()} | {:error, term()}
  def persist_derived_definition(%DerivedTelemetryDefinition{} = definition) do
    Governance.persist_derived_definition(definition)
  end

  @spec list_derived_definitions(binary()) :: [DerivedTelemetryDefinition.t()]
  def list_derived_definitions(mission_id) when is_binary(mission_id) do
    Governance.list_derived_definitions(mission_id)
  end

  @spec persist_limit_definition(LimitDefinition.t()) ::
          {:ok, LimitDefinition.t()} | {:error, term()}
  def persist_limit_definition(%LimitDefinition{} = definition) do
    Governance.persist_limit_definition(definition)
  end

  @spec list_limit_definitions(binary()) :: [LimitDefinition.t()]
  def list_limit_definitions(mission_id) when is_binary(mission_id) do
    Governance.list_limit_definitions(mission_id)
  end

  @spec telemetry_history(binary(), binary(), keyword()) :: [Cadence.Telemetry.Sample.t()]
  def telemetry_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    TelemetryReads.sample_history(mission_id, point_id, opts)
  end

  @spec telemetry_history(binary(), binary(), binary(), keyword()) ::
          [Cadence.Telemetry.Sample.t()]
  def telemetry_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    TelemetryReads.sample_history(organization_id, mission_id, point_id, opts)
  end

  @spec derived_telemetry_history(binary(), binary(), keyword()) ::
          [Cadence.DerivedTelemetry.Sample.t()]
  def derived_telemetry_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    DerivedTelemetryReads.sample_history(mission_id, point_id, opts)
  end

  @spec derived_telemetry_history(binary(), binary(), binary(), keyword()) ::
          [Cadence.DerivedTelemetry.Sample.t()]
  def derived_telemetry_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    DerivedTelemetryReads.sample_history(organization_id, mission_id, point_id, opts)
  end

  @spec latest_telemetry_value(binary(), binary(), keyword()) ::
          Cadence.Telemetry.Sample.t() | nil
  def latest_telemetry_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    TelemetryReads.latest_value(mission_id, point_id, opts)
  end

  @spec latest_telemetry_value(binary(), binary(), binary(), keyword()) ::
          Cadence.Telemetry.Sample.t() | nil
  def latest_telemetry_value(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    TelemetryReads.latest_value(organization_id, mission_id, point_id, opts)
  end

  @spec latest_telemetry_values(binary(), keyword()) :: [Cadence.Telemetry.Sample.t()]
  def latest_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryReads.latest_values_for_mission(mission_id, opts)
  end

  @spec latest_telemetry_values(binary(), binary(), keyword()) ::
          [Cadence.Telemetry.Sample.t()]
  def latest_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    TelemetryReads.latest_values_for_mission(organization_id, mission_id, opts)
  end

  @spec latest_derived_telemetry_value(binary(), binary(), keyword()) ::
          Cadence.DerivedTelemetry.Sample.t() | nil
  def latest_derived_telemetry_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    DerivedTelemetryReads.latest_value(mission_id, point_id, opts)
  end

  @spec latest_derived_telemetry_value(binary(), binary(), binary(), keyword()) ::
          Cadence.DerivedTelemetry.Sample.t() | nil
  def latest_derived_telemetry_value(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    DerivedTelemetryReads.latest_value(organization_id, mission_id, point_id, opts)
  end

  @spec latest_derived_telemetry_values(binary(), keyword()) ::
          [Cadence.DerivedTelemetry.Sample.t()]
  def latest_derived_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryReads.latest_values_for_mission(mission_id, opts)
  end

  @spec latest_derived_telemetry_values(binary(), binary(), keyword()) ::
          [Cadence.DerivedTelemetry.Sample.t()]
  def latest_derived_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryReads.latest_values_for_mission(organization_id, mission_id, opts)
  end

  @spec latest_telemetry_limit_state(binary(), binary(), keyword()) ::
          Cadence.Limits.Event.t() | nil
  def latest_telemetry_limit_state(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    LimitReads.latest_state(mission_id, point_id, opts)
  end

  @spec latest_telemetry_limit_state(binary(), binary(), binary(), keyword()) ::
          Cadence.Limits.Event.t() | nil
  def latest_telemetry_limit_state(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    LimitReads.latest_state(organization_id, mission_id, point_id, opts)
  end

  @spec latest_telemetry_limit_states(binary(), keyword()) :: [Cadence.Limits.Event.t()]
  def latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    LimitReads.latest_states_for_mission(mission_id, opts)
  end

  @spec latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          [Cadence.Limits.Event.t()]
  def latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    LimitReads.latest_states_for_mission(organization_id, mission_id, opts)
  end

  @spec mission_health_summary(binary(), keyword()) :: Cadence.Reads.MissionHealth.t()
  def mission_health_summary(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    MissionHealthReads.summary(mission_id, opts)
  end

  @spec mission_health_summary(binary(), binary(), keyword()) :: Cadence.Reads.MissionHealth.t()
  def mission_health_summary(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    MissionHealthReads.summary(organization_id, mission_id, opts)
  end

  @spec telemetry_limit_event_history(binary(), binary(), keyword()) ::
          [Cadence.Limits.Event.t()]
  def telemetry_limit_event_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    LimitReads.event_history(mission_id, point_id, opts)
  end

  @spec telemetry_limit_event_history(binary(), binary(), binary(), keyword()) ::
          [Cadence.Limits.Event.t()]
  def telemetry_limit_event_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    LimitReads.event_history(organization_id, mission_id, point_id, opts)
  end

  @spec replay_telemetry_evidence(binary(), binary() | [binary()], binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Replay.replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
  end

  @spec replay_telemetry_evidence(
          binary(),
          binary(),
          binary() | [binary()],
          binary(),
          pos_integer()
        ) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def replay_telemetry_evidence(
        organization_id,
        mission_id,
        evidence_ids,
        binding_set_id,
        version
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with_mission_scope(organization_id, mission_id, fn ->
      Replay.replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
    end)
  end

  @spec replay_telemetry_scope(binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def replay_telemetry_scope(mission_id, %Scope{} = scope, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Replay.replay_telemetry_scope(mission_id, scope, binding_set_id, version)
  end

  @spec replay_telemetry_scope(binary(), binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def replay_telemetry_scope(
        organization_id,
        mission_id,
        %Scope{} = scope,
        binding_set_id,
        version
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with_mission_scope(organization_id, mission_id, fn ->
      Replay.replay_telemetry_scope(mission_id, scope, binding_set_id, version)
    end)
  end

  @spec start_replay_telemetry_evidence(binary(), binary() | [binary()], binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def start_replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Replay.start_replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
  end

  @spec start_replay_telemetry_evidence(
          binary(),
          binary(),
          binary() | [binary()],
          binary(),
          pos_integer()
        ) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def start_replay_telemetry_evidence(
        organization_id,
        mission_id,
        evidence_ids,
        binding_set_id,
        version
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with_mission_scope(organization_id, mission_id, fn ->
      Replay.start_replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
    end)
  end

  @spec start_replay_telemetry_scope(binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def start_replay_telemetry_scope(mission_id, %Scope{} = scope, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Replay.start_replay_telemetry_scope(mission_id, scope, binding_set_id, version)
  end

  @spec start_replay_telemetry_scope(binary(), binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def start_replay_telemetry_scope(
        organization_id,
        mission_id,
        %Scope{} = scope,
        binding_set_id,
        version
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with_mission_scope(organization_id, mission_id, fn ->
      Replay.start_replay_telemetry_scope(mission_id, scope, binding_set_id, version)
    end)
  end

  @spec fetch_replay_run(binary()) :: {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def fetch_replay_run(replay_run_id) when is_binary(replay_run_id) do
    ReplayReads.fetch_run(replay_run_id)
  end

  @spec replay_telemetry_samples(binary(), keyword()) :: [Cadence.Telemetry.Sample.t()]
  def replay_telemetry_samples(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    ReplayReads.telemetry_samples(replay_run_id, opts)
  end

  @spec replay_managed_capability_records(binary(), keyword()) ::
          [Cadence.Runtime.ManagedCapabilityRecord.t()]
  def replay_managed_capability_records(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    ReplayReads.managed_capability_records(replay_run_id, opts)
  end

  @spec replay_managed_action_requests(binary(), keyword()) ::
          [Cadence.Runtime.ManagedActionRequest.t()]
  def replay_managed_action_requests(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    ReplayReads.managed_action_requests(replay_run_id, opts)
  end

  @spec replay_managed_timer_events(binary(), keyword()) ::
          [Cadence.Runtime.ManagedTimerEvent.t()]
  def replay_managed_timer_events(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    ReplayReads.managed_timer_events(replay_run_id, opts)
  end

  @spec fetch_background_job(binary()) :: {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_background_job(job_id) when is_binary(job_id) do
    Jobs.fetch_job(job_id)
  end

  @spec fetch_replay_job(binary()) :: {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_replay_job(replay_run_id) when is_binary(replay_run_id) do
    Jobs.fetch_job_for_run(:replay_telemetry_scope, replay_run_id)
  end

  @spec evaluate_derived_telemetry(binary(), keyword()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def evaluate_derived_telemetry(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryService.evaluate(mission_id, opts)
  end

  @spec evaluate_derived_telemetry(binary(), binary(), keyword()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def evaluate_derived_telemetry(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      DerivedTelemetryService.evaluate(mission_id, opts)
    end)
  end

  @spec start_evaluate_derived_telemetry(binary(), keyword()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def start_evaluate_derived_telemetry(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryService.start_evaluate(mission_id, opts)
  end

  @spec start_evaluate_derived_telemetry(binary(), binary(), keyword()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def start_evaluate_derived_telemetry(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      DerivedTelemetryService.start_evaluate(mission_id, opts)
    end)
  end

  @spec fetch_derived_telemetry_run(binary()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def fetch_derived_telemetry_run(derived_run_id) when is_binary(derived_run_id) do
    DerivedTelemetryService.fetch_run(derived_run_id)
  end

  @spec fetch_derived_telemetry_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_derived_telemetry_job(derived_run_id) when is_binary(derived_run_id) do
    Jobs.fetch_job_for_run(:derived_telemetry_evaluation, derived_run_id)
  end

  @spec rebuild_latest_derived_telemetry_values(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_derived_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryLatestValueProjection.rebuild(mission_id, opts)
  end

  @spec rebuild_latest_derived_telemetry_values(binary(), binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_derived_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      DerivedTelemetryLatestValueProjection.rebuild(mission_id, opts)
    end)
  end

  @spec start_rebuild_latest_derived_telemetry_values(binary(), keyword()) ::
          {:ok, Cadence.Projections.DerivedTelemetryLatestValues.Run.t()} | {:error, term()}
  def start_rebuild_latest_derived_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryLatestValueProjection.start_rebuild(mission_id, opts)
  end

  @spec start_rebuild_latest_derived_telemetry_values(binary(), binary(), keyword()) ::
          {:ok, Cadence.Projections.DerivedTelemetryLatestValues.Run.t()} | {:error, term()}
  def start_rebuild_latest_derived_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      DerivedTelemetryLatestValueProjection.start_rebuild(mission_id, opts)
    end)
  end

  @spec fetch_latest_derived_telemetry_value_rebuild_run(binary()) ::
          {:ok, Cadence.Projections.DerivedTelemetryLatestValues.Run.t()} | {:error, term()}
  def fetch_latest_derived_telemetry_value_rebuild_run(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    DerivedTelemetryLatestValueProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_latest_derived_telemetry_value_rebuild_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_latest_derived_telemetry_value_rebuild_job(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:derived_telemetry_latest_value_rebuild, rebuild_run_id)
  end

  @spec diff_replay_run(binary()) :: Cadence.Replay.Diff.report()
  def diff_replay_run(replay_run_id) when is_binary(replay_run_id) do
    ReplayDiff.diff_run(replay_run_id)
  end

  @spec evaluate_telemetry_limits(binary(), keyword()) ::
          {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def evaluate_telemetry_limits(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    LimitsService.evaluate(mission_id, opts)
  end

  @spec evaluate_telemetry_limits(binary(), binary(), keyword()) ::
          {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def evaluate_telemetry_limits(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      LimitsService.evaluate(mission_id, opts)
    end)
  end

  @spec start_evaluate_telemetry_limits(binary(), keyword()) ::
          {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def start_evaluate_telemetry_limits(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    LimitsService.start_evaluate(mission_id, opts)
  end

  @spec start_evaluate_telemetry_limits(binary(), binary(), keyword()) ::
          {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def start_evaluate_telemetry_limits(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      LimitsService.start_evaluate(mission_id, opts)
    end)
  end

  @spec fetch_telemetry_limit_run(binary()) :: {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def fetch_telemetry_limit_run(limit_run_id) when is_binary(limit_run_id) do
    LimitsService.fetch_run(limit_run_id)
  end

  @spec fetch_telemetry_limit_job(binary()) :: {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_telemetry_limit_job(limit_run_id) when is_binary(limit_run_id) do
    Jobs.fetch_job_for_run(:telemetry_limit_evaluation, limit_run_id)
  end

  @spec rebuild_latest_telemetry_values(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestValueProjection.rebuild(mission_id, opts)
  end

  @spec rebuild_latest_telemetry_values(binary(), binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestValueProjection.rebuild(mission_id, opts)
    end)
  end

  @spec start_rebuild_latest_telemetry_values(binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestValues.Run.t()} | {:error, term()}
  def start_rebuild_latest_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestValueProjection.start_rebuild(mission_id, opts)
  end

  @spec start_rebuild_latest_telemetry_values(binary(), binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestValues.Run.t()} | {:error, term()}
  def start_rebuild_latest_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestValueProjection.start_rebuild(mission_id, opts)
    end)
  end

  @spec fetch_latest_telemetry_value_rebuild_run(binary()) ::
          {:ok, Cadence.Projections.TelemetryLatestValues.Run.t()} | {:error, term()}
  def fetch_latest_telemetry_value_rebuild_run(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    TelemetryLatestValueProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_latest_telemetry_value_rebuild_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_latest_telemetry_value_rebuild_job(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:telemetry_latest_value_rebuild, rebuild_run_id)
  end

  @spec rebuild_latest_telemetry_limit_states(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestLimitStateProjection.rebuild(mission_id, opts)
  end

  @spec rebuild_latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestLimitStateProjection.rebuild(mission_id, opts)
    end)
  end

  @spec refresh_latest_telemetry_limit_states(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def refresh_latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestLimitStateProjection.refresh_from_latest_values(mission_id, opts)
  end

  @spec refresh_latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def refresh_latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestLimitStateProjection.refresh_from_latest_values(mission_id, opts)
    end)
  end

  @spec start_rebuild_latest_telemetry_limit_states(binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def start_rebuild_latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestLimitStateProjection.start_rebuild(mission_id, opts)
  end

  @spec start_rebuild_latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def start_rebuild_latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestLimitStateProjection.start_rebuild(mission_id, opts)
    end)
  end

  @spec start_refresh_latest_telemetry_limit_states(binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def start_refresh_latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestLimitStateProjection.start_refresh_from_latest_values(mission_id, opts)
  end

  @spec start_refresh_latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def start_refresh_latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestLimitStateProjection.start_refresh_from_latest_values(mission_id, opts)
    end)
  end

  @spec fetch_latest_telemetry_limit_state_rebuild_run(binary()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def fetch_latest_telemetry_limit_state_rebuild_run(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    TelemetryLatestLimitStateProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_latest_telemetry_limit_state_refresh_run(binary()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def fetch_latest_telemetry_limit_state_refresh_run(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    TelemetryLatestLimitStateProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_latest_telemetry_limit_state_rebuild_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_latest_telemetry_limit_state_rebuild_job(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:telemetry_latest_limit_state_rebuild, rebuild_run_id)
  end

  @spec fetch_latest_telemetry_limit_state_refresh_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_latest_telemetry_limit_state_refresh_job(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:telemetry_latest_limit_state_refresh, rebuild_run_id)
  end

  defp with_mission_scope(organization_id, mission_id, fun)
       when is_binary(organization_id) and is_binary(mission_id) and is_function(fun, 0) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      fun.()
    end
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family} = raw_evidence)
       when protocol_family in [:space_packet, :packet, :space_packet_stream] do
    with {:ok, %PacketRecord{} = packet_record} <- SpacePacketDecoder.decode(raw_evidence) do
      {:ok,
       %{
         packet_records: [packet_record],
         transfer_frame_records: [],
         protocol_anomalies: []
       }}
    end
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family} = raw_evidence)
       when protocol_family in [:tm, :tm_transfer_frame] do
    with {:ok, pipeline_state} <- TMFrameIngress.init(),
         {:ok, tm_result, <<>>, _pipeline_state, _continuity_state} <-
           TMFrameIngress.process(raw_evidence, pipeline_state, %{}, <<>>) do
      {:ok, tm_result}
    else
      {:ok, _tm_result, rest, _pipeline_state, _continuity_state} ->
        {:error, {:incomplete_tm_frame_bytes, byte_size(rest)}}
    end
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family}) do
    {:error, {:unsupported_ingress_protocol_family, protocol_family}}
  end

  defp execute_dispatches(
         %{
           packet_records: packet_records,
           transfer_frame_records: transfer_frame_records,
           protocol_anomalies: protocol_anomalies
         },
         %BindingSet{} = binding_set
       ) do
    with {:ok, dispatch_results} <- execute_dispatches(packet_records, binding_set) do
      {:ok,
       %{
         packet_records: packet_records,
         transfer_frame_records: transfer_frame_records,
         protocol_anomalies: protocol_anomalies,
         dispatch_results: dispatch_results
       }}
    end
  end

  defp execute_dispatches(packet_records, %BindingSet{} = binding_set)
       when is_list(packet_records) do
    Enum.reduce_while(packet_records, {:ok, []}, fn %PacketRecord{} = packet_record, {:ok, acc} ->
      with {:ok, %DispatchDecision{} = dispatch_decision} <-
             Dispatcher.dispatch(packet_record, binding_set),
           {:ok, outputs} <- Dispatcher.execute(packet_record, dispatch_decision) do
        {:cont,
         {:ok,
          acc ++
            [
              %{
                packet_record: packet_record,
                dispatch_decision: dispatch_decision,
                outputs: outputs
              }
            ]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_processing_result(%RawEvidence{} = raw_evidence, %{
         packet_records: packet_records,
         transfer_frame_records: transfer_frame_records,
         protocol_anomalies: protocol_anomalies,
         dispatch_results: dispatch_results
       }) do
    dispatch_decisions = Enum.map(dispatch_results, & &1.dispatch_decision)
    outputs = Enum.flat_map(dispatch_results, & &1.outputs)

    %{
      raw_evidence: raw_evidence,
      packet_records: packet_records,
      transfer_frame_records: transfer_frame_records,
      protocol_anomalies: protocol_anomalies,
      dispatch_decisions: dispatch_decisions,
      outputs: outputs,
      runtime_records: %{capability_records: [], action_requests: [], timer_events: []}
    }
  end

  defp validate_binding_set_mission(
         %RawEvidence{mission_id: mission_id},
         %BindingSet{mission_id: mission_id}
       ),
       do: :ok

  defp validate_binding_set_mission(
         %RawEvidence{mission_id: evidence_mission_id},
         %BindingSet{mission_id: binding_set_mission_id}
       ) do
    {:error, {:binding_set_mission_mismatch, evidence_mission_id, binding_set_mission_id}}
  end
end
