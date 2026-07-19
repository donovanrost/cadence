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
  alias Cadence.Catalog.{Artifact, Database, ImporterDescriptor, ImportRun, Revision}
  alias Cadence.Catalog.Command.Compiler, as: CommandCatalogCompiler
  alias Cadence.Catalog.Command.Compiler.Result, as: CommandCompilerResult
  alias Cadence.Catalog.Command.Snapshot, as: CommandCatalogSnapshot
  alias Cadence.Catalog.Telemetry.Compiler, as: TelemetryCatalogCompiler
  alias Cadence.Catalog.Telemetry.Compiler.Result, as: TelemetryCompilerResult
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot

  alias Cadence.ContactPlanning.AutomationGrants
  alias Cadence.ContactPlanning.ContactPlanApprovals
  alias Cadence.ContactPlanning.ContactPlanExecutions
  alias Cadence.ContactPlanning.ContactPlans
  alias Cadence.ContactPlanning.ContactRequirements
  alias Cadence.ContactPlanning.ContactRequirementTemplates
  alias Cadence.ContactPlanning.FleetAutomation
  alias Cadence.ContactPlanning.FleetAutomationActions
  alias Cadence.ContactPlanning.FleetPlanner
  alias Cadence.ContactPlanning.FleetPlanningPolicies
  alias Cadence.ContactPlanning.FleetPlanningRuns
  alias Cadence.ContactPlanning.FleetRepairs
  alias Cadence.ContactPlanning.Planner, as: ContactPlanner
  alias Cadence.Dashboards
  alias Cadence.Dashboards.DataSources, as: DashboardDataSources

  alias Cadence.Comms.{GroundStation, RoutingRule, RoutingRuleEvent, Transport}
  alias Cadence.Comms.GroundStationStore
  alias Cadence.Comms.RoutingRuleStore
  alias Cadence.Comms.TransportStore
  alias Cadence.Contacts, as: ContactsService

  alias Cadence.Contacts.{
    ContactAction,
    LinkAssignment,
    PathTemplate,
    ProviderBooking,
    ProviderProfile,
    ProviderReservation,
    ProviderReservations,
    ProviderScheduling,
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
  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Ops.PointCatalog, as: OpsPointCatalog
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization
  alias Cadence.Persistence
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftTypeStore

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
  alias Cadence.Telemetry.DataManagement, as: TelemetryDataManagement
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler
  alias Cadence.Telemetry.RuntimeHealth
  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  @type ingress_latency_metric :: %{
          value_ms: number(),
          end_to_end_us: non_neg_integer(),
          observed_at: DateTime.t(),
          error?: boolean()
        }

  @type processing_result :: %{
          raw_evidence: RawEvidence.t(),
          packet_records: [PacketRecord.t()],
          transfer_frame_records: [TransferFrameRecord.t()],
          protocol_anomalies: [ProtocolAnomaly.t()],
          dispatch_decisions: [DispatchDecision.t()],
          outputs: [term()],
          runtime_records: map(),
          ingress_latency_metric: ingress_latency_metric() | nil
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

  @spec accept_invitation_as_user(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def accept_invitation_as_user(user_id, invitation_id)
      when is_binary(user_id) and is_binary(invitation_id),
      do: Accounts.accept_invitation_as_user(user_id, invitation_id)

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

  @spec list_user_memberships(binary()) :: [
          %{
            membership: Cadence.Accounts.OrganizationMembership.t(),
            organization: Cadence.Organizations.Organization.t()
          }
        ]
  def list_user_memberships(user_id) when is_binary(user_id) do
    Accounts.list_user_memberships(user_id)
  end

  @spec fetch_user_membership(binary(), binary()) ::
          {:ok, Cadence.Accounts.OrganizationMembership.t()} | {:error, :not_found}
  def fetch_user_membership(user_id, organization_id)
      when is_binary(user_id) and is_binary(organization_id) do
    Accounts.fetch_user_membership(user_id, organization_id)
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

  @spec persist_notification(Notification.t()) :: {:ok, Notification.t()} | {:error, term()}
  def persist_notification(%Notification{} = n), do: Notifications.persist_notification(n)

  @spec fetch_notification(binary()) :: {:ok, Notification.t()} | {:error, :not_found}
  def fetch_notification(notification_id) when is_binary(notification_id),
    do: Notifications.fetch_notification(notification_id)

  @spec list_notifications(binary(), keyword()) :: [Notification.t()]
  def list_notifications(user_id, opts \\ []) when is_binary(user_id),
    do: Notifications.list_notifications(user_id, opts)

  @spec count_unread_notifications(binary()) :: non_neg_integer()
  def count_unread_notifications(user_id) when is_binary(user_id),
    do: Notifications.count_unread_notifications(user_id)

  @spec mark_notification_read(binary(), binary()) ::
          {:ok, Notification.t()} | {:error, term()}
  def mark_notification_read(notification_id, user_id)
      when is_binary(notification_id) and is_binary(user_id),
      do: Notifications.mark_notification_read(notification_id, user_id)

  @spec persist_spacecraft(binary(), Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    SpacecraftStore.persist_spacecraft(organization_id, spacecraft)
  end

  @spec persist_spacecraft(Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(%Spacecraft{} = spacecraft) do
    SpacecraftStore.persist_spacecraft(spacecraft)
  end

  @spec update_spacecraft(binary(), Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def update_spacecraft(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    SpacecraftStore.update_spacecraft(organization_id, spacecraft)
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

  @spec list_spacecraft_page(binary(), binary(), [SpacecraftStore.list_opt()]) ::
          Cadence.Listing.Page.t()
  def list_spacecraft_page(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) do
    SpacecraftStore.list_spacecraft_page(organization_id, mission_id, opts)
  end

  @spec spacecraft_fleet_summary(binary(), binary()) :: map()
  def spacecraft_fleet_summary(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    SpacecraftStore.fleet_summary(organization_id, mission_id)
  end

  @spec ensure_managed_spacecraft_source_endpoint(binary(), Spacecraft.t()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def ensure_managed_spacecraft_source_endpoint(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    SpacecraftStore.ensure_managed_source_endpoint(organization_id, spacecraft)
  end

  @spec persist_spacecraft_type(binary(), SpacecraftType.t()) ::
          {:ok, SpacecraftType.t()} | {:error, term()}
  def persist_spacecraft_type(organization_id, %SpacecraftType{} = type)
      when is_binary(organization_id) do
    SpacecraftTypeStore.persist_spacecraft_type(organization_id, type)
  end

  @spec fetch_spacecraft_type(binary(), binary(), binary()) ::
          {:ok, SpacecraftType.t()} | {:error, term()}
  def fetch_spacecraft_type(organization_id, mission_id, spacecraft_type_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_type_id) do
    SpacecraftTypeStore.fetch_spacecraft_type(organization_id, mission_id, spacecraft_type_id)
  end

  @spec fetch_spacecraft_type_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, SpacecraftType.t()} | {:error, term()}
  def fetch_spacecraft_type_version(organization_id, mission_id, spacecraft_type_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_type_id) and is_integer(version) and version > 0 do
    SpacecraftTypeStore.fetch_spacecraft_type_version(
      organization_id,
      mission_id,
      spacecraft_type_id,
      version
    )
  end

  @spec list_spacecraft_types(binary(), binary()) :: [SpacecraftType.t()]
  def list_spacecraft_types(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id)
  end

  @spec list_spacecraft_type_versions(binary(), binary(), binary()) :: [SpacecraftType.t()]
  def list_spacecraft_type_versions(organization_id, mission_id, spacecraft_type_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_type_id) do
    SpacecraftTypeStore.list_spacecraft_type_versions(
      organization_id,
      mission_id,
      spacecraft_type_id
    )
  end

  @spec persist_transport(binary(), Transport.t()) :: {:ok, Transport.t()} | {:error, term()}
  def persist_transport(organization_id, %Transport{} = transport)
      when is_binary(organization_id) do
    TransportStore.persist_transport(organization_id, transport)
  end

  @spec fetch_transport(binary(), binary(), binary()) :: {:ok, Transport.t()} | {:error, term()}
  def fetch_transport(organization_id, mission_id, transport_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) do
    TransportStore.fetch_transport(organization_id, mission_id, transport_id)
  end

  @spec fetch_transport_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, Transport.t()} | {:error, term()}
  def fetch_transport_version(organization_id, mission_id, transport_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_integer(version) and version > 0 do
    TransportStore.fetch_transport_version(organization_id, mission_id, transport_id, version)
  end

  @spec list_transports(binary(), binary()) :: [Transport.t()]
  def list_transports(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    TransportStore.list_transports(organization_id, mission_id)
  end

  @spec list_transport_versions(binary(), binary(), binary()) :: [Transport.t()]
  def list_transport_versions(organization_id, mission_id, transport_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) do
    TransportStore.list_transport_versions(organization_id, mission_id, transport_id)
  end

  @spec version_transport(binary(), binary(), binary(), map()) ::
          {:ok, Transport.t()} | {:error, term()}
  def version_transport(organization_id, mission_id, transport_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_map(attrs) do
    TransportStore.version_transport(organization_id, mission_id, transport_id, attrs)
  end

  @spec archive_transport(binary(), binary(), binary(), map()) ::
          {:ok, Transport.t()} | {:error, term()}
  def archive_transport(organization_id, mission_id, transport_id, metadata_patch \\ %{})
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_map(metadata_patch) do
    TransportStore.archive_transport(organization_id, mission_id, transport_id, metadata_patch)
  end

  @spec persist_ground_station(binary(), GroundStation.t()) ::
          {:ok, GroundStation.t()} | {:error, term()}
  def persist_ground_station(organization_id, %GroundStation{} = ground_station)
      when is_binary(organization_id) do
    GroundStationStore.persist_ground_station(organization_id, ground_station)
  end

  @spec fetch_ground_station(binary(), binary(), binary()) ::
          {:ok, GroundStation.t()} | {:error, term()}
  def fetch_ground_station(organization_id, mission_id, ground_station_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(ground_station_id) do
    GroundStationStore.fetch_ground_station(organization_id, mission_id, ground_station_id)
  end

  @spec list_ground_stations(binary(), binary()) :: [GroundStation.t()]
  def list_ground_stations(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    GroundStationStore.list_ground_stations(organization_id, mission_id)
  end

  @spec update_ground_station(binary(), binary(), binary(), map()) ::
          {:ok, GroundStation.t()} | {:error, term()}
  def update_ground_station(organization_id, mission_id, ground_station_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(ground_station_id) and is_map(attrs) do
    GroundStationStore.update_ground_station(
      organization_id,
      mission_id,
      ground_station_id,
      attrs
    )
  end

  @spec archive_ground_station(binary(), binary(), binary(), map()) ::
          {:ok, GroundStation.t()} | {:error, term()}
  def archive_ground_station(
        organization_id,
        mission_id,
        ground_station_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(ground_station_id) and is_map(metadata_patch) do
    GroundStationStore.archive_ground_station(
      organization_id,
      mission_id,
      ground_station_id,
      metadata_patch
    )
  end

  @spec list_ops_telemetry_points(binary(), binary()) :: [OpsPointCatalog.point_info()]
  def list_ops_telemetry_points(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    OpsPointCatalog.list_points(organization_id, mission_id)
  end

  @spec list_dashboard_data_realms(binary(), binary()) :: [binary()]
  def list_dashboard_data_realms(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    DashboardDataSources.list_data_realms(organization_id, mission_id)
  end

  @spec create_routing_rule(binary(), RoutingRule.t(), keyword()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def create_routing_rule(organization_id, %RoutingRule{} = routing_rule, opts \\ [])
      when is_binary(organization_id) and is_list(opts) do
    RoutingRuleStore.create_routing_rule(organization_id, routing_rule, opts)
  end

  @spec update_routing_rule(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def update_routing_rule(organization_id, mission_id, routing_rule_id, attrs, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(routing_rule_id) and is_map(attrs) and is_list(opts) do
    RoutingRuleStore.update_routing_rule(
      organization_id,
      mission_id,
      routing_rule_id,
      attrs,
      opts
    )
  end

  @spec set_routing_rule_enabled(binary(), binary(), binary(), boolean(), keyword()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def set_routing_rule_enabled(organization_id, mission_id, routing_rule_id, enabled?, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(routing_rule_id) and is_boolean(enabled?) and is_list(opts) do
    RoutingRuleStore.set_routing_rule_enabled(
      organization_id,
      mission_id,
      routing_rule_id,
      enabled?,
      opts
    )
  end

  @spec archive_routing_rule(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def archive_routing_rule(
        organization_id,
        mission_id,
        routing_rule_id,
        metadata_patch \\ %{},
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(routing_rule_id) and is_map(metadata_patch) and is_list(opts) do
    RoutingRuleStore.archive_routing_rule(
      organization_id,
      mission_id,
      routing_rule_id,
      metadata_patch,
      opts
    )
  end

  @spec fetch_routing_rule(binary(), binary(), binary()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def fetch_routing_rule(organization_id, mission_id, routing_rule_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(routing_rule_id) do
    RoutingRuleStore.fetch_routing_rule(organization_id, mission_id, routing_rule_id)
  end

  @spec fetch_routing_rule_state(binary(), binary(), binary()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def fetch_routing_rule_state(organization_id, mission_id, routing_rule_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(routing_rule_id) do
    RoutingRuleStore.fetch_routing_rule_state(organization_id, mission_id, routing_rule_id)
  end

  @spec list_routing_rules(binary(), binary()) :: [RoutingRule.t()]
  def list_routing_rules(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    RoutingRuleStore.list_routing_rules(organization_id, mission_id)
  end

  @spec list_routing_rules_for_spacecraft(binary(), binary(), binary()) :: [RoutingRule.t()]
  def list_routing_rules_for_spacecraft(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    RoutingRuleStore.list_routing_rules_for_spacecraft(organization_id, mission_id, spacecraft_id)
  end

  @spec list_routing_rule_events(binary(), binary(), binary()) :: [RoutingRuleEvent.t()]
  def list_routing_rule_events(organization_id, mission_id, routing_rule_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(routing_rule_id) do
    RoutingRuleStore.list_routing_rule_events(organization_id, mission_id, routing_rule_id)
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

  @spec create_catalog_database(binary(), binary(), map()) ::
          {:ok, Database.t()} | {:error, term()}
  def create_catalog_database(organization_id, mission_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(attrs) do
    Catalog.create_database(organization_id, mission_id, attrs)
  end

  @spec fetch_catalog_database(binary(), binary(), binary()) ::
          {:ok, Database.t()} | {:error, term()}
  def fetch_catalog_database(organization_id, mission_id, catalog_database_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_database_id) do
    Catalog.fetch_database(organization_id, mission_id, catalog_database_id)
  end

  @spec list_catalog_databases(binary(), binary(), keyword()) :: [Database.t()]
  def list_catalog_databases(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Catalog.list_databases(organization_id, mission_id, opts)
  end

  @spec list_catalog_revisions(binary(), binary(), binary() | nil, keyword()) :: [Revision.t()]
  def list_catalog_revisions(organization_id, mission_id, catalog_database_id \\ nil, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Catalog.list_revisions(organization_id, mission_id, catalog_database_id, opts)
  end

  @spec fetch_catalog_revision(binary(), binary(), binary()) ::
          {:ok, Revision.t()} | {:error, term()}
  def fetch_catalog_revision(organization_id, mission_id, catalog_revision_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_revision_id) do
    Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id)
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
        processing_result =
          put_ingress_latency_metric(
            processing_result,
            elapsed_us(ingress_started_at),
            false
          )

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

  defp put_ingress_latency_metric(processing_result, end_to_end_us, error?)
       when is_map(processing_result) and is_integer(end_to_end_us) and end_to_end_us >= 0 do
    raw_evidence = Map.get(processing_result, :raw_evidence)

    Map.put(processing_result, :ingress_latency_metric, %{
      value_ms: end_to_end_us / 1000.0,
      end_to_end_us: end_to_end_us,
      observed_at: ingress_latency_observed_at(raw_evidence),
      error?: error?
    })
  end

  defp ingress_latency_observed_at(%RawEvidence{receipt_time: %DateTime{} = receipt_time}),
    do: receipt_time

  defp ingress_latency_observed_at(_raw_evidence), do: DateTime.utc_now()

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

  @spec create_shared_link(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def create_shared_link(organization_id, mission_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(attrs) do
    ContactsService.create_shared_link(organization_id, mission_id, attrs)
  end

  @spec apply_link_template(binary(), binary(), PathTemplate.t(), [Spacecraft.t()], map()) ::
          {:ok, map()}
  def apply_link_template(
        organization_id,
        mission_id,
        %PathTemplate{} = source_template,
        spacecraft,
        attrs
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_list(spacecraft) and
             is_map(attrs) do
    ContactsService.apply_link_template(
      organization_id,
      mission_id,
      source_template,
      spacecraft,
      attrs
    )
  end

  @spec persist_link_assignment(binary(), LinkAssignment.t()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def persist_link_assignment(organization_id, %LinkAssignment{} = assignment)
      when is_binary(organization_id) do
    ContactsService.persist_link_assignment(organization_id, assignment)
  end

  @spec fetch_link_assignment(binary(), binary(), binary()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def fetch_link_assignment(organization_id, mission_id, link_assignment_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(link_assignment_id) do
    ContactsService.fetch_link_assignment(organization_id, mission_id, link_assignment_id)
  end

  @spec list_link_assignments(binary(), binary()) :: [LinkAssignment.t()]
  def list_link_assignments(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactsService.list_link_assignments(organization_id, mission_id)
  end

  @spec delete_link_assignment(binary(), binary(), binary(), map()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def delete_link_assignment(
        organization_id,
        mission_id,
        link_assignment_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(link_assignment_id) and is_map(metadata_patch) do
    ContactsService.delete_link_assignment(
      organization_id,
      mission_id,
      link_assignment_id,
      metadata_patch
    )
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

  @spec fetch_provider_reservation(binary(), binary(), binary()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def fetch_provider_reservation(organization_id, mission_id, provider_reservation_id) do
    ProviderReservations.fetch(organization_id, mission_id, provider_reservation_id)
  end

  @spec list_provider_reservations(binary(), binary()) :: [ProviderReservation.t()]
  def list_provider_reservations(organization_id, mission_id) do
    ProviderReservations.list_for_mission(organization_id, mission_id)
  end

  @spec reserve_provider_contact(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, ProviderBooking.booking_result()} | {:error, term()}
  def reserve_provider_contact(
        organization_id,
        mission_id,
        provider_id,
        attrs,
        opts \\ []
      ) do
    ProviderBooking.reserve(organization_id, mission_id, provider_id, attrs, opts)
  end

  @spec cancel_provider_reservation(binary(), binary(), binary(), keyword()) ::
          {:ok, ProviderBooking.booking_result()} | {:error, term()}
  def cancel_provider_reservation(
        organization_id,
        mission_id,
        provider_reservation_id,
        opts \\ []
      ) do
    ProviderBooking.cancel(organization_id, mission_id, provider_reservation_id, opts)
  end

  @spec list_ready_downlink_routes(binary(), binary(), binary()) ::
          {:ok, %{routes: [map()], findings: [map()]}} | {:error, term()}
  def list_ready_downlink_routes(organization_id, mission_id, spacecraft_id) do
    ProviderScheduling.list_ready_downlink_routes(organization_id, mission_id, spacecraft_id)
  end

  @spec search_contact_opportunities(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def search_contact_opportunities(organization_id, mission_id, route_key, window, opts \\ []) do
    ProviderScheduling.search_opportunities(organization_id, mission_id, route_key, window, opts)
  end

  @spec create_contact_requirement(CurrentScope.t(), binary(), map(), keyword()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def create_contact_requirement(current_scope, mission_id, attrs, opts \\ []) do
    ContactRequirements.create(current_scope, mission_id, attrs, opts)
  end

  @spec version_contact_requirement(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, struct(), struct()} | {:error, term()}
  def version_contact_requirement(
        current_scope,
        mission_id,
        requirement_id,
        expected_version,
        attrs,
        opts \\ []
      ) do
    ContactRequirements.version(
      current_scope,
      mission_id,
      requirement_id,
      expected_version,
      attrs,
      opts
    )
  end

  @spec fetch_contact_requirement(binary(), binary(), binary()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def fetch_contact_requirement(organization_id, mission_id, requirement_id) do
    ContactRequirements.fetch(organization_id, mission_id, requirement_id)
  end

  @spec list_contact_requirements(binary(), binary(), keyword()) :: [{struct(), struct()}]
  def list_contact_requirements(organization_id, mission_id, opts \\ []) do
    ContactRequirements.list(organization_id, mission_id, opts)
  end

  @spec create_contact_requirement_template(CurrentScope.t(), binary(), map(), keyword()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def create_contact_requirement_template(current_scope, mission_id, attrs, opts \\ []) do
    ContactRequirementTemplates.create(current_scope, mission_id, attrs, opts)
  end

  @spec version_contact_requirement_template(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, struct(), struct()} | {:error, term()}
  def version_contact_requirement_template(
        current_scope,
        mission_id,
        template_id,
        expected_version,
        attrs,
        opts \\ []
      ) do
    ContactRequirementTemplates.version(
      current_scope,
      mission_id,
      template_id,
      expected_version,
      attrs,
      opts
    )
  end

  @spec fetch_contact_requirement_template(binary(), binary(), binary()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def fetch_contact_requirement_template(organization_id, mission_id, template_id) do
    ContactRequirementTemplates.fetch(organization_id, mission_id, template_id)
  end

  @spec list_contact_requirement_templates(binary(), binary(), keyword()) ::
          [{struct(), struct()}]
  def list_contact_requirement_templates(organization_id, mission_id, opts \\ []) do
    ContactRequirementTemplates.list(organization_id, mission_id, opts)
  end

  @spec activate_contact_requirement_template(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def activate_contact_requirement_template(
        current_scope,
        mission_id,
        template_id,
        expected_version,
        reason,
        opts \\ []
      ) do
    ContactRequirementTemplates.activate(
      current_scope,
      mission_id,
      template_id,
      expected_version,
      reason,
      opts
    )
  end

  @spec pause_contact_requirement_template(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def pause_contact_requirement_template(
        current_scope,
        mission_id,
        template_id,
        expected_version,
        reason,
        opts \\ []
      ) do
    ContactRequirementTemplates.pause(
      current_scope,
      mission_id,
      template_id,
      expected_version,
      reason,
      opts
    )
  end

  @spec close_contact_requirement_template(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def close_contact_requirement_template(
        current_scope,
        mission_id,
        template_id,
        expected_version,
        reason,
        opts \\ []
      ) do
    ContactRequirementTemplates.close(
      current_scope,
      mission_id,
      template_id,
      expected_version,
      reason,
      opts
    )
  end

  @spec materialize_contact_requirement_template(
          CurrentScope.t(),
          binary(),
          binary(),
          DateTime.t(),
          DateTime.t(),
          keyword()
        ) :: {:ok, [map()]} | {:error, term()}
  def materialize_contact_requirement_template(
        current_scope,
        mission_id,
        template_id,
        from,
        until,
        opts \\ []
      ) do
    ContactRequirementTemplates.materialize(
      current_scope,
      mission_id,
      template_id,
      from,
      until,
      opts
    )
  end

  @spec materialize_active_contact_requirement_templates(
          CurrentScope.t(),
          binary(),
          DateTime.t(),
          DateTime.t(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def materialize_active_contact_requirement_templates(
        current_scope,
        mission_id,
        from,
        until,
        opts \\ []
      ) do
    ContactRequirementTemplates.materialize_active(
      current_scope,
      mission_id,
      from,
      until,
      opts
    )
  end

  @spec create_fleet_planning_policy(CurrentScope.t(), binary(), map(), keyword()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def create_fleet_planning_policy(current_scope, mission_id, attrs, opts \\ []) do
    FleetPlanningPolicies.create(current_scope, mission_id, attrs, opts)
  end

  @spec version_fleet_planning_policy(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, struct(), struct()} | {:error, term()}
  def version_fleet_planning_policy(
        current_scope,
        mission_id,
        policy_id,
        expected_version,
        attrs,
        opts \\ []
      ) do
    FleetPlanningPolicies.version(
      current_scope,
      mission_id,
      policy_id,
      expected_version,
      attrs,
      opts
    )
  end

  @spec fetch_fleet_planning_policy(binary(), binary()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def fetch_fleet_planning_policy(organization_id, mission_id) do
    FleetPlanningPolicies.fetch(organization_id, mission_id)
  end

  @spec fetch_active_fleet_planning_policy(binary(), binary()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def fetch_active_fleet_planning_policy(organization_id, mission_id) do
    FleetPlanningPolicies.fetch_active(organization_id, mission_id)
  end

  @spec fetch_fleet_planning_policy_version(
          binary(),
          binary(),
          binary(),
          pos_integer()
        ) :: {:ok, struct()} | {:error, term()}
  def fetch_fleet_planning_policy_version(
        organization_id,
        mission_id,
        policy_id,
        version
      ) do
    FleetPlanningPolicies.fetch_version(
      organization_id,
      mission_id,
      policy_id,
      version
    )
  end

  @spec approve_fleet_planning_policy(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, struct(), struct(), struct()} | {:error, term()}
  def approve_fleet_planning_policy(
        current_scope,
        mission_id,
        policy_id,
        expected_version,
        expected_hash,
        reason,
        opts \\ []
      ) do
    FleetPlanningPolicies.approve(
      current_scope,
      mission_id,
      policy_id,
      expected_version,
      expected_hash,
      reason,
      opts
    )
  end

  @spec reject_fleet_planning_policy(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, struct(), struct(), struct()} | {:error, term()}
  def reject_fleet_planning_policy(
        current_scope,
        mission_id,
        policy_id,
        expected_version,
        expected_hash,
        reason,
        opts \\ []
      ) do
    FleetPlanningPolicies.reject(
      current_scope,
      mission_id,
      policy_id,
      expected_version,
      expected_hash,
      reason,
      opts
    )
  end

  @spec retire_fleet_planning_policy(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def retire_fleet_planning_policy(
        current_scope,
        mission_id,
        policy_id,
        expected_version,
        reason,
        opts \\ []
      ) do
    FleetPlanningPolicies.retire(
      current_scope,
      mission_id,
      policy_id,
      expected_version,
      reason,
      opts
    )
  end

  @spec create_fleet_planning_run(CurrentScope.t(), binary(), map(), keyword()) ::
          {:ok, struct(), [struct()]} | {:error, term()}
  def create_fleet_planning_run(current_scope, mission_id, attrs, opts \\ []) do
    FleetPlanningRuns.create(current_scope, mission_id, attrs, opts)
  end

  @spec fetch_fleet_planning_run(binary(), binary(), binary()) ::
          {:ok, struct()} | {:error, term()}
  def fetch_fleet_planning_run(organization_id, mission_id, run_id) do
    FleetPlanningRuns.fetch(organization_id, mission_id, run_id)
  end

  @spec list_fleet_planning_runs(binary(), binary(), keyword()) :: [struct()]
  def list_fleet_planning_runs(organization_id, mission_id, opts \\ []) do
    FleetPlanningRuns.list(organization_id, mission_id, opts)
  end

  @spec list_fleet_planning_run_requirement_refs(binary(), binary(), binary()) :: [struct()]
  def list_fleet_planning_run_requirement_refs(organization_id, mission_id, run_id) do
    FleetPlanningRuns.list_requirement_refs(organization_id, mission_id, run_id)
  end

  @spec list_fleet_planning_decisions(binary(), binary(), binary()) :: [struct()]
  def list_fleet_planning_decisions(organization_id, mission_id, run_id) do
    FleetPlanningRuns.list_decisions(organization_id, mission_id, run_id)
  end

  @spec start_fleet_planning_run(CurrentScope.t(), binary(), map(), keyword()) ::
          {:ok, struct(), [struct()]} | {:error, term()}
  def start_fleet_planning_run(current_scope, mission_id, attrs, opts \\ []) do
    FleetPlanner.start(current_scope, mission_id, attrs, opts)
  end

  @spec run_fleet_planning(CurrentScope.t(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run_fleet_planning(current_scope, mission_id, run_id, opts \\ []) do
    FleetPlanner.run(current_scope, mission_id, run_id, opts)
  end

  @spec plan_fleet_contacts(CurrentScope.t(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def plan_fleet_contacts(current_scope, mission_id, attrs, opts \\ []) do
    FleetPlanner.plan(current_scope, mission_id, attrs, opts)
  end

  @spec repair_fleet_contacts(
          CurrentScope.t(),
          binary(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def repair_fleet_contacts(
        current_scope,
        mission_id,
        source_run_id,
        source_plan_id,
        source_plan_version,
        attrs,
        opts \\ []
      ) do
    FleetRepairs.repair(
      current_scope,
      mission_id,
      source_run_id,
      source_plan_id,
      source_plan_version,
      attrs,
      opts
    )
  end

  @spec issue_automation_grant(CurrentScope.t(), binary(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def issue_automation_grant(current_scope, mission_id, attrs, opts \\ []) do
    AutomationGrants.issue(current_scope, mission_id, attrs, opts)
  end

  @spec revoke_automation_grant(
          CurrentScope.t(),
          binary(),
          binary(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def revoke_automation_grant(
        current_scope,
        mission_id,
        grant_id,
        expected_hash,
        reason,
        opts \\ []
      ) do
    AutomationGrants.revoke(
      current_scope,
      mission_id,
      grant_id,
      expected_hash,
      reason,
      opts
    )
  end

  @spec list_automation_grants(binary(), binary(), keyword()) :: [struct()]
  def list_automation_grants(organization_id, mission_id, opts \\ []) do
    AutomationGrants.list(organization_id, mission_id, opts)
  end

  @spec automate_fleet_plan(CurrentScope.t(), binary(), map(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def automate_fleet_plan(current_scope, mission_id, attrs, grant_id, opts \\ []) do
    FleetAutomation.plan(current_scope, mission_id, attrs, grant_id, opts)
  end

  @spec automate_fleet_repair(
          CurrentScope.t(),
          binary(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          binary(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def automate_fleet_repair(
        current_scope,
        mission_id,
        source_run_id,
        source_plan_id,
        source_plan_version,
        attrs,
        grant_id,
        opts \\ []
      ) do
    FleetAutomation.repair(
      current_scope,
      mission_id,
      source_run_id,
      source_plan_id,
      source_plan_version,
      attrs,
      grant_id,
      opts
    )
  end

  @spec resume_fleet_automation(
          CurrentScope.t(),
          binary(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def resume_fleet_automation(current_scope, mission_id, run_id, grant_id, opts \\ []) do
    FleetAutomation.run(current_scope, mission_id, run_id, grant_id, opts)
  end

  @spec list_fleet_automation_actions(binary(), binary(), binary()) :: [struct()]
  def list_fleet_automation_actions(organization_id, mission_id, run_id) do
    FleetAutomationActions.list(organization_id, mission_id, run_id)
  end

  @spec plan_contact_requirement(CurrentScope.t(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def plan_contact_requirement(
        current_scope,
        mission_id,
        requirement_id,
        requirement_version,
        opts \\ []
      ) do
    ContactPlanner.run(
      current_scope,
      mission_id,
      requirement_id,
      requirement_version,
      opts
    )
  end

  @spec create_contact_plan(CurrentScope.t(), binary(), map(), keyword()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def create_contact_plan(current_scope, mission_id, attrs, opts \\ []) do
    ContactPlans.create(current_scope, mission_id, attrs, opts)
  end

  @spec version_contact_plan(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, struct(), struct()} | {:error, term()}
  def version_contact_plan(
        current_scope,
        mission_id,
        contact_plan_id,
        expected_version,
        attrs,
        opts \\ []
      ) do
    ContactPlans.version(
      current_scope,
      mission_id,
      contact_plan_id,
      expected_version,
      attrs,
      opts
    )
  end

  @spec submit_contact_plan(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def submit_contact_plan(
        current_scope,
        mission_id,
        contact_plan_id,
        expected_version,
        reason,
        opts \\ []
      ) do
    ContactPlans.submit(
      current_scope,
      mission_id,
      contact_plan_id,
      expected_version,
      reason,
      opts
    )
  end

  @spec fetch_contact_plan(binary(), binary(), binary()) ::
          {:ok, struct(), struct()} | {:error, term()}
  def fetch_contact_plan(organization_id, mission_id, contact_plan_id) do
    ContactPlans.fetch(organization_id, mission_id, contact_plan_id)
  end

  @spec list_contact_plans(binary(), binary(), keyword()) :: [{struct(), struct()}]
  def list_contact_plans(organization_id, mission_id, opts \\ []) do
    ContactPlans.list(organization_id, mission_id, opts)
  end

  @spec list_contact_plan_approvals(binary(), binary(), binary()) :: [struct()]
  def list_contact_plan_approvals(organization_id, mission_id, contact_plan_id) do
    ContactPlanApprovals.list(organization_id, mission_id, contact_plan_id)
  end

  @spec approve_contact_plan(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, struct(), struct(), struct()} | {:error, term()}
  def approve_contact_plan(
        current_scope,
        mission_id,
        contact_plan_id,
        expected_version,
        expected_hash,
        reason,
        opts \\ []
      ) do
    ContactPlanApprovals.approve(
      current_scope,
      mission_id,
      contact_plan_id,
      expected_version,
      expected_hash,
      reason,
      opts
    )
  end

  @spec reject_contact_plan(
          CurrentScope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, struct(), struct(), struct()} | {:error, term()}
  def reject_contact_plan(
        current_scope,
        mission_id,
        contact_plan_id,
        expected_version,
        expected_hash,
        reason,
        opts \\ []
      ) do
    ContactPlanApprovals.reject(
      current_scope,
      mission_id,
      contact_plan_id,
      expected_version,
      expected_hash,
      reason,
      opts
    )
  end

  @spec execute_contact_plan(CurrentScope.t(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute_contact_plan(current_scope, mission_id, contact_plan_id, opts \\ []) do
    ContactPlanExecutions.execute(current_scope, mission_id, contact_plan_id, opts)
  end

  @spec list_contact_plan_execution_items(binary(), binary(), binary(), pos_integer()) :: [
          struct()
        ]
  def list_contact_plan_execution_items(
        organization_id,
        mission_id,
        contact_plan_id,
        contact_plan_version
      ) do
    ContactPlanExecutions.list(
      organization_id,
      mission_id,
      contact_plan_id,
      contact_plan_version
    )
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

  @spec fetch_operational_event(binary()) :: {:ok, OperationalEvent.t()} | {:error, :not_found}
  def fetch_operational_event(event_id) when is_binary(event_id) do
    OperationalEvents.fetch_event(event_id)
  end

  @spec list_operational_events(binary(), keyword()) :: [OperationalEvent.t()]
  def list_operational_events(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.list_events(mission_id, opts)
  end

  @spec list_operational_events(binary(), binary(), keyword()) :: [OperationalEvent.t()]
  def list_operational_events(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.list_events(organization_id, mission_id, opts)
  end

  @spec operational_binding_set_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_binding_set_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.binding_set_intervals(mission_id, opts)
  end

  @spec operational_binding_set_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_binding_set_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.binding_set_intervals(organization_id, mission_id, opts)
  end

  @spec operational_application_binding_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_application_binding_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.application_binding_intervals(mission_id, opts)
  end

  @spec operational_application_binding_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_application_binding_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.application_binding_intervals(organization_id, mission_id, opts)
  end

  @spec operational_catalog_revision_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_catalog_revision_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.catalog_revision_intervals(mission_id, opts)
  end

  @spec operational_catalog_revision_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_catalog_revision_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.catalog_revision_intervals(organization_id, mission_id, opts)
  end

  @spec operational_source_binding_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_source_binding_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.source_binding_intervals(mission_id, opts)
  end

  @spec operational_source_binding_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_source_binding_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.source_binding_intervals(organization_id, mission_id, opts)
  end

  @spec operational_source_health_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_source_health_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.source_health_intervals(mission_id, opts)
  end

  @spec operational_source_health_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_source_health_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.source_health_intervals(organization_id, mission_id, opts)
  end

  @spec operational_transport_execution_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_transport_execution_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.transport_execution_intervals(mission_id, opts)
  end

  @spec operational_transport_execution_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_transport_execution_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.transport_execution_intervals(organization_id, mission_id, opts)
  end

  @spec operational_observable_state_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_observable_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.operational_observable_state_intervals(mission_id, opts)
  end

  @spec operational_observable_state_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_observable_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.operational_observable_state_intervals(organization_id, mission_id, opts)
  end

  @spec operational_connection_state_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_connection_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.connection_state_intervals(mission_id, opts)
  end

  @spec operational_connection_state_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_connection_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.connection_state_intervals(organization_id, mission_id, opts)
  end

  @spec operational_link_rf_state_intervals(binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_link_rf_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.link_rf_state_intervals(mission_id, opts)
  end

  @spec operational_link_rf_state_intervals(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.EffectiveInterval.t()
        ]
  def operational_link_rf_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.link_rf_state_intervals(organization_id, mission_id, opts)
  end

  @spec operational_observable_metric_samples(binary(), keyword()) :: [map()]
  def operational_observable_metric_samples(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    OperationalEvents.operational_observable_metric_samples(mission_id, opts)
  end

  @spec operational_observable_metric_samples(binary(), binary(), keyword()) :: [map()]
  def operational_observable_metric_samples(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    OperationalEvents.operational_observable_metric_samples(organization_id, mission_id, opts)
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
    LimitsService.persist_limit_definition(definition)
  end

  @spec list_limit_definitions(binary()) :: [LimitDefinition.t()]
  def list_limit_definitions(mission_id) when is_binary(mission_id) do
    LimitsService.list_limit_definitions(mission_id)
  end

  @spec backfill_telemetry_samples([Cadence.Telemetry.Sample.t()], map(), keyword()) ::
          :ok | {:error, term()}
  def backfill_telemetry_samples(samples, attrs, opts \\ [])
      when is_list(samples) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.backfill_samples(samples, attrs, opts)
  end

  @spec import_telemetry_samples([Cadence.Telemetry.Sample.t()], map(), keyword()) ::
          :ok | {:error, term()}
  def import_telemetry_samples(samples, attrs, opts \\ [])
      when is_list(samples) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.import_samples(samples, attrs, opts)
  end

  @spec list_telemetry_backfill_lifecycle_events(binary(), keyword()) :: [
          Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()
        ]
  def list_telemetry_backfill_lifecycle_events(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryStorage.list_backfill_lifecycle_events(mission_id, opts)
  end

  @spec fetch_telemetry_backfill_lifecycle_event(binary(), keyword()) ::
          Cadence.Telemetry.Storage.BackfillLifecycleEvent.t() | nil
  def fetch_telemetry_backfill_lifecycle_event(backfill_lifecycle_event_id, opts \\ [])
      when is_binary(backfill_lifecycle_event_id) and is_list(opts) do
    TelemetryStorage.fetch_backfill_lifecycle_event(backfill_lifecycle_event_id, opts)
  end

  @spec record_telemetry_historical_data_workflow_event(
          atom() | binary(),
          atom() | binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_event(workflow, stage, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_event(workflow, stage, attrs, opts)
  end

  @spec record_telemetry_historical_data_workflow_request(
          atom() | binary(),
          map(),
          [binary() | nil],
          keyword()
        ) ::
          {:ok, [Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()]} | {:error, term()}
  def record_telemetry_historical_data_workflow_request(workflow, attrs, point_ids, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_list(point_ids) and
             is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_request(
      workflow,
      attrs,
      point_ids,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_correction_request(
          atom() | binary(),
          map(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_correction_request(
        workflow,
        attrs,
        correction,
        opts \\ []
      )
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_map(correction) and
             is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_correction_request(
      workflow,
      attrs,
      correction,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_correction_transition(
          atom() | binary(),
          atom() | binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_correction_transition(
        workflow,
        stage,
        correction_event_id,
        attrs,
        opts \\ []
      )
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_binary(correction_event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_correction_transition(
      workflow,
      stage,
      correction_event_id,
      attrs,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_stage_transition(
          atom() | binary(),
          atom() | binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_stage_transition(
        workflow,
        stage,
        source_event_id,
        attrs,
        opts \\ []
      )
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_binary(source_event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_stage_transition(
      workflow,
      stage,
      source_event_id,
      attrs,
      opts
    )
  end

  @spec telemetry_historical_data_workflow_action_policy(map()) :: %{
          retry_job: TelemetryDataManagement.historical_data_workflow_action_decision(),
          retry_group_failed_jobs:
            TelemetryDataManagement.historical_data_workflow_action_decision(),
          correction_request: TelemetryDataManagement.historical_data_workflow_action_decision()
        }
  def telemetry_historical_data_workflow_action_policy(context) when is_map(context) do
    TelemetryDataManagement.historical_data_workflow_action_policy(context)
  end

  @spec telemetry_historical_data_workflow_stage_action_policy(map(), atom() | binary()) ::
          TelemetryDataManagement.historical_data_workflow_action_decision()
  def telemetry_historical_data_workflow_stage_action_policy(context, stage)
      when is_map(context) and (is_atom(stage) or is_binary(stage)) do
    TelemetryDataManagement.historical_data_workflow_stage_action_policy(context, stage)
  end

  @spec telemetry_historical_data_workflow_group_stage_action_policy(map(), atom() | binary()) ::
          TelemetryDataManagement.historical_data_workflow_action_decision()
  def telemetry_historical_data_workflow_group_stage_action_policy(context, stage)
      when is_map(context) and (is_atom(stage) or is_binary(stage)) do
    TelemetryDataManagement.historical_data_workflow_group_stage_action_policy(context, stage)
  end

  @spec telemetry_historical_data_workflow_explanation_summary(map()) ::
          TelemetryDataManagement.historical_data_workflow_explanation_summary()
  def telemetry_historical_data_workflow_explanation_summary(context) when is_map(context) do
    TelemetryDataManagement.historical_data_workflow_explanation_summary(context)
  end

  @spec record_telemetry_historical_data_workflow_group_transition(
          atom() | binary(),
          atom() | binary(),
          binary() | [Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()],
          map(),
          keyword()
        ) ::
          {:ok, [Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()], [term()]}
          | {:error, term()}
  def record_telemetry_historical_data_workflow_group_transition(
        workflow,
        stage,
        group_events,
        attrs,
        opts \\ []
      )
      when is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_group_transition(
      workflow,
      stage,
      group_events,
      attrs,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_stale_replacement_inspection(
          binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_stale_replacement_inspection(
        job_id,
        event_id,
        attrs,
        opts \\ []
      )
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_stale_replacement_inspection(
      job_id,
      event_id,
      attrs,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_missing_replacement_inspection(
          binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_missing_replacement_inspection(
        request_group_id,
        replacement_run_id,
        attrs,
        opts \\ []
      )
      when is_binary(request_group_id) and is_binary(replacement_run_id) and is_map(attrs) and
             is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_missing_replacement_inspection(
      request_group_id,
      replacement_run_id,
      attrs,
      opts
    )
  end

  @spec requeue_telemetry_historical_data_workflow_stale_replacement_job(
          binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Jobs.Job.t(), Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()}
          | {:error, term()}
  def requeue_telemetry_historical_data_workflow_stale_replacement_job(
        job_id,
        event_id,
        attrs,
        opts \\ []
      )
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.requeue_historical_data_workflow_stale_replacement_job(
      job_id,
      event_id,
      attrs,
      opts
    )
  end

  @spec start_telemetry_historical_data_workflow_job(atom() | binary(), map(), keyword()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def start_telemetry_historical_data_workflow_job(workflow, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.start_historical_data_workflow_job(workflow, attrs, opts)
  end

  @spec apply_telemetry_observation_identity_decision(
          binary(),
          atom() | binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.ObservationIdentityState.t()} | {:error, term()}
  def apply_telemetry_observation_identity_decision(
        observation_identity_id,
        decision,
        attrs,
        opts \\ []
      )
      when is_binary(observation_identity_id) and (is_atom(decision) or is_binary(decision)) and
             is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.apply_observation_identity_decision(
      observation_identity_id,
      decision,
      attrs,
      opts
    )
  end

  @spec apply_telemetry_observation_identity_decisions(
          [map()],
          atom() | binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.DataManagement.observation_identity_decision_batch_summary()}
          | {:error, term()}
  def apply_telemetry_observation_identity_decisions(items, decision, attrs, opts \\ [])
      when is_list(items) and (is_atom(decision) or is_binary(decision)) and is_map(attrs) and
             is_list(opts) do
    TelemetryDataManagement.apply_observation_identity_decisions(items, decision, attrs, opts)
  end

  @spec list_telemetry_observation_identity_decision_events(binary(), keyword()) :: [
          Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent.t()
        ]
  def list_telemetry_observation_identity_decision_events(observation_identity_id, opts \\ [])
      when is_binary(observation_identity_id) and is_list(opts) do
    TelemetryStorage.list_observation_identity_decision_events(observation_identity_id, opts)
  end

  @spec record_telemetry_late_data_policy_decision(atom() | binary(), map(), keyword()) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_late_data_policy_decision(decision, attrs, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_late_data_policy_decision(decision, attrs, opts)
  end

  @spec execute_telemetry_late_data_policy(atom() | binary(), map(), keyword()) ::
          {:ok, TelemetryDataManagement.late_data_policy_execution_result()} | {:error, term()}
  def execute_telemetry_late_data_policy(decision, attrs, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.execute_late_data_policy(decision, attrs, opts)
  end

  @spec telemetry_late_data_policy_execution_mode(map()) ::
          TelemetryDataManagement.late_data_policy_execution_mode()
  def telemetry_late_data_policy_execution_mode(attrs) when is_map(attrs) do
    TelemetryDataManagement.late_data_policy_execution_mode(attrs)
  end

  @spec telemetry_late_data_policy_write_opts(atom() | binary(), keyword()) ::
          {:ok, keyword()} | {:error, term()}
  def telemetry_late_data_policy_write_opts(decision, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_list(opts) do
    TelemetryDataManagement.late_data_policy_write_opts(decision, opts)
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

  @spec telemetry_history_result(binary(), binary(), keyword()) ::
          {:ok, %{samples: [Cadence.Telemetry.Sample.t()], diagnostics: map()}} | {:error, term()}
  def telemetry_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    TelemetryReads.sample_history_result(mission_id, point_id, opts)
  end

  @spec telemetry_history_result(binary(), binary(), binary(), keyword()) ::
          {:ok, %{samples: [Cadence.Telemetry.Sample.t()], diagnostics: map()}} | {:error, term()}
  def telemetry_history_result(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    TelemetryReads.sample_history_result(organization_id, mission_id, point_id, opts)
  end

  @spec decimated_telemetry_history(binary(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def decimated_telemetry_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    TelemetryReads.decimated_sample_history(mission_id, point_id, opts)
  end

  @spec decimated_telemetry_history(binary(), binary(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def decimated_telemetry_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    TelemetryReads.decimated_sample_history(organization_id, mission_id, point_id, opts)
  end

  @spec decimated_telemetry_history_result(binary(), binary(), keyword()) ::
          {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  def decimated_telemetry_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    TelemetryReads.decimated_sample_history_result(mission_id, point_id, opts)
  end

  @spec decimated_telemetry_history_result(binary(), binary(), binary(), keyword()) ::
          {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  def decimated_telemetry_history_result(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    TelemetryReads.decimated_sample_history_result(organization_id, mission_id, point_id, opts)
  end

  @spec telemetry_watermark(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def telemetry_watermark(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    TelemetryReads.sample_watermark(mission_id, point_id, opts)
  end

  @spec telemetry_watermark(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def telemetry_watermark(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    TelemetryReads.sample_watermark(organization_id, mission_id, point_id, opts)
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

  @spec runtime_health_snapshot() :: RuntimeHealth.snapshot()
  def runtime_health_snapshot do
    RuntimeHealth.snapshot()
  end

  @spec dashboard_runtime_invalidation_decisions(keyword()) :: [
          Cadence.Dashboards.RuntimeInvalidation.DecisionProjection.decision_row()
        ]
  def dashboard_runtime_invalidation_decisions(opts \\ []) when is_list(opts) do
    case durable_dashboard_runtime_invalidation_decisions(opts) do
      [] ->
        RuntimeHealth.snapshot()
        |> Dashboards.dashboard_runtime_invalidation_decisions(opts)

      decisions ->
        decisions
    end
  end

  @spec durable_dashboard_runtime_invalidation_decisions(keyword()) :: [
          Cadence.Dashboards.RuntimeInvalidation.DecisionProjection.decision_row()
        ]
  def durable_dashboard_runtime_invalidation_decisions(opts \\ []) when is_list(opts) do
    Dashboards.durable_dashboard_runtime_invalidation_decisions(opts)
  rescue
    _error -> []
  catch
    :exit, _reason -> []
  end

  @spec record_dashboard_runtime_invalidation_decision(
          Cadence.Dashboards.RuntimeInvalidation.Event.t(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Dashboards.RuntimeInvalidation.DecisionEvent.t()} | {:error, term()}
  def record_dashboard_runtime_invalidation_decision(event, decision, opts \\ [])
      when is_map(decision) and is_list(opts) do
    Dashboards.record_dashboard_runtime_invalidation_decision(event, decision, opts)
  end

  @spec dashboard_source_capability_posture_events(
          Cadence.Dashboards.DashboardResolveResult.t(),
          keyword() | map()
        ) :: [Cadence.OperationalEvents.Event.t()]
  def dashboard_source_capability_posture_events(result, opts \\ []) do
    Dashboards.dashboard_source_capability_posture_events(result, opts)
  end

  @spec record_dashboard_source_capability_postures(
          Cadence.Dashboards.DashboardResolveResult.t(),
          keyword() | map()
        ) :: {:ok, [Cadence.OperationalEvents.Event.t()]} | {:error, term()}
  def record_dashboard_source_capability_postures(result, opts \\ []) do
    Dashboards.record_dashboard_source_capability_postures(result, opts)
  end

  @spec list_dashboard_source_capability_posture_events(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.Event.t()
        ]
  def list_dashboard_source_capability_posture_events(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Dashboards.list_dashboard_source_capability_posture_events(organization_id, mission_id, opts)
  end

  @spec reset_runtime_health() :: :ok
  def reset_runtime_health do
    RuntimeHealth.reset()
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

  @spec telemetry_limit_definition_intervals(binary(), binary(), keyword()) ::
          [Cadence.Limits.DefinitionInterval.t()]
  def telemetry_limit_definition_intervals(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    LimitReads.definition_intervals(mission_id, point_id, opts)
  end

  @spec telemetry_limit_definition_intervals(binary(), binary(), binary(), keyword()) ::
          [Cadence.Limits.DefinitionInterval.t()]
  def telemetry_limit_definition_intervals(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    LimitReads.definition_intervals(organization_id, mission_id, point_id, opts)
  end

  @spec telemetry_limit_watermark(binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def telemetry_limit_watermark(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    LimitReads.watermark_result(mission_id, point_id, opts)
  end

  @spec telemetry_limit_watermark(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def telemetry_limit_watermark(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    LimitReads.watermark_result(organization_id, mission_id, point_id, opts)
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

  @spec list_replay_runs(binary(), binary(), keyword()) :: [Cadence.Replay.Run.t()]
  def list_replay_runs(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    ReplayReads.list_runs(organization_id, mission_id, opts)
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

  @spec fetch_telemetry_historical_data_workflow_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_telemetry_historical_data_workflow_job(workflow_run_id)
      when is_binary(workflow_run_id) do
    Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, workflow_run_id)
  end

  @spec retry_telemetry_historical_data_workflow_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def retry_telemetry_historical_data_workflow_job(job_id) when is_binary(job_id) do
    with {:ok, %{job_type: :telemetry_historical_data_workflow}} <- Jobs.fetch_job(job_id),
         {:ok, retried_job} <- Jobs.retry_failed_job(job_id) do
      {:ok, retried_job}
    else
      {:ok, %{job_type: job_type}} ->
        {:error, {:unexpected_job_type, job_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec retry_telemetry_historical_data_workflow_job(binary(), binary(), map(), keyword()) ::
          {:ok, Cadence.Jobs.Job.t(), Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()}
          | {:error, term()}
  def retry_telemetry_historical_data_workflow_job(job_id, event_id, attrs, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.retry_historical_data_workflow_job(job_id, event_id, attrs, opts)
  end

  @spec retry_telemetry_historical_data_workflow_group_failed_jobs(binary(), map(), keyword()) ::
          {:ok, Cadence.Telemetry.DataManagement.historical_data_workflow_group_retry_summary()}
          | {:error, term()}
  def retry_telemetry_historical_data_workflow_group_failed_jobs(
        request_group_id,
        attrs,
        opts \\ []
      )
      when is_binary(request_group_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.retry_historical_data_workflow_group_failed_jobs(
      request_group_id,
      attrs,
      opts
    )
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
