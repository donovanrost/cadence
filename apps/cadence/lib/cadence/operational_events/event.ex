defmodule Cadence.OperationalEvents.Event do
  @moduledoc """
  Canonical operational event envelope.

  This is the domain boundary for facts that should project into mission
  timelines, dashboard overlays, audit views, and future effective-interval
  projections. It is intentionally store-agnostic for the first slice: existing
  subsystem records can be converted into this envelope before projection.
  """

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Catalog.Revision
  alias Cadence.Contacts.{ContactAction, RealizedContact, ScheduledContact}

  alias Cadence.Dashboards.{
    DataBindingEvent,
    LifecycleEvent,
    SourceHealthEvent,
    SourceWatermarkEvent
  }

  alias Cadence.Limits.DefinitionLifecycleEvent

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    ManagedTimerEvent,
    TransportActionRequest,
    TransportCapabilityRecord,
    TransportTimerEvent
  }

  alias Cadence.Telemetry.Storage.{BackfillLifecycleEvent, ObservationIdentityDecisionEvent}

  @categories [
    :catalog,
    :runtime,
    :contact,
    :telemetry,
    :limits,
    :commanding,
    :comms,
    :data_source,
    :source_credential,
    :dashboard,
    :replay,
    :security
  ]

  @severities [:info, :warning, :error, :critical]
  @actor_kinds [:user, :service, :system, :replay]

  @subject_kinds [
    :spacecraft,
    :contact,
    :source_endpoint,
    :ground_station,
    :transport,
    :link,
    :catalog_revision,
    :binding_set,
    :source_binding,
    :data_source,
    :source_credential,
    :dashboard,
    :telemetry_point,
    :limit_definition,
    :command,
    :capability_instance
  ]

  @source_record_kinds [
    :binding_set_activation,
    :catalog_revision,
    :dashboard_data_binding_event,
    :dashboard_lifecycle_event,
    :source_capability_posture,
    :telemetry_backfill_lifecycle_event,
    :telemetry_observation_identity_decision_event,
    :source_health_event,
    :source_watermark_event,
    :limit_definition_lifecycle_event,
    :operational_observable_snapshot,
    :connection_state_snapshot,
    :link_rf_lock_state_snapshot,
    :link_frame_sync_state_snapshot,
    :routing_rule_event,
    :contact_action,
    :managed_action_request,
    :managed_capability_record,
    :managed_timer_event,
    :transport_capability_record,
    :transport_action_request,
    :transport_timer_event,
    :scheduled_contact,
    :realized_contact,
    :provider_audit_entry
  ]

  @type category ::
          :catalog
          | :runtime
          | :contact
          | :telemetry
          | :limits
          | :commanding
          | :comms
          | :data_source
          | :source_credential
          | :dashboard
          | :replay
          | :security

  @type severity :: :info | :warning | :error | :critical
  @type actor_kind :: :user | :service | :system | :replay

  @type subject_kind ::
          :spacecraft
          | :contact
          | :source_endpoint
          | :ground_station
          | :transport
          | :link
          | :catalog_revision
          | :binding_set
          | :source_binding
          | :data_source
          | :source_credential
          | :dashboard
          | :telemetry_point
          | :limit_definition
          | :command
          | :capability_instance

  @type source_record_kind ::
          :binding_set_activation
          | :catalog_revision
          | :dashboard_data_binding_event
          | :dashboard_lifecycle_event
          | :source_capability_posture
          | :telemetry_backfill_lifecycle_event
          | :telemetry_observation_identity_decision_event
          | :source_health_event
          | :source_watermark_event
          | :limit_definition_lifecycle_event
          | :operational_observable_snapshot
          | :connection_state_snapshot
          | :link_rf_lock_state_snapshot
          | :link_frame_sync_state_snapshot
          | :routing_rule_event
          | :contact_action
          | :managed_action_request
          | :managed_capability_record
          | :managed_timer_event
          | :transport_capability_record
          | :transport_action_request
          | :transport_timer_event
          | :scheduled_contact
          | :realized_contact
          | :provider_audit_entry

  @type actor :: %{
          optional(:kind) => actor_kind(),
          optional(:id) => binary(),
          optional(:display_name) => binary(),
          optional(:auth_context) => map()
        }

  @type subject :: %{kind: subject_kind(), id: binary()}

  @type scope :: %{
          optional(:spacecraft_id) => binary(),
          optional(:contact_id) => binary(),
          optional(:logical_source) => atom() | binary(),
          optional(:source_binding_id) => binary(),
          optional(:source_endpoint_ref) => binary(),
          optional(:data_realm) => atom() | binary(),
          optional(:data_source_id) => binary(),
          optional(:replay_run_id) => binary(),
          optional(:dataset) => binary(),
          optional(:point_id) => binary(),
          optional(:limit_set_name) => binary(),
          optional(:scope_type) => atom() | binary(),
          optional(:scope_ref) => binary()
        }

  @type causality :: %{
          optional(:correlation_id) => binary(),
          optional(:causation_event_id) => binary(),
          optional(:source_record_kind) => source_record_kind(),
          optional(:source_record_id) => binary(),
          optional(:job_id) => binary(),
          optional(:replay_run_id) => binary(),
          optional(:import_run_id) => binary()
        }

  @type t :: %__MODULE__{
          event_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          occurred_at: DateTime.t(),
          recorded_at: DateTime.t(),
          effective_at: DateTime.t() | nil,
          category: category(),
          kind: atom(),
          severity: severity() | nil,
          actor: actor(),
          subject: subject() | nil,
          scope: scope(),
          causality: causality(),
          payload: map(),
          previous: map(),
          current: map(),
          metadata: map()
        }

  defstruct [
    :event_id,
    :organization_id,
    :mission_id,
    :occurred_at,
    :recorded_at,
    :effective_at,
    :category,
    :kind,
    :severity,
    :subject,
    actor: %{kind: :system},
    scope: %{},
    causality: %{},
    payload: %{},
    previous: %{},
    current: %{},
    metadata: %{}
  ]

  @spec categories() :: [category()]
  def categories, do: @categories

  @spec subject_kinds() :: [subject_kind()]
  def subject_kinds, do: @subject_kinds

  @spec source_record_kinds() :: [source_record_kind()]
  def source_record_kinds, do: @source_record_kinds

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    occurred_at = fetch_required(attrs, :occurred_at)

    %__MODULE__{
      event_id: fetch_required(attrs, :event_id),
      organization_id:
        text_value(Map.get(attrs, :organization_id, Map.get(attrs, "organization_id"))),
      mission_id: fetch_required(attrs, :mission_id),
      occurred_at: occurred_at,
      recorded_at: Map.get(attrs, :recorded_at, Map.get(attrs, "recorded_at", occurred_at)),
      effective_at: Map.get(attrs, :effective_at, Map.get(attrs, "effective_at")),
      category: known_atom!(fetch_required(attrs, :category), @categories, :category),
      kind: normalize_kind(fetch_required(attrs, :kind)),
      severity:
        attrs
        |> Map.get(:severity, Map.get(attrs, "severity"))
        |> known_optional_atom!(@severities, :severity),
      actor: normalize_actor(Map.get(attrs, :actor, Map.get(attrs, "actor", %{kind: :system}))),
      subject: normalize_subject(Map.get(attrs, :subject, Map.get(attrs, "subject"))),
      scope: normalize_scope(Map.get(attrs, :scope, Map.get(attrs, "scope", %{}))),
      causality:
        normalize_causality(Map.get(attrs, :causality, Map.get(attrs, "causality", %{}))),
      payload: map_value(Map.get(attrs, :payload, Map.get(attrs, "payload", %{}))),
      previous: map_value(Map.get(attrs, :previous, Map.get(attrs, "previous", %{}))),
      current: map_value(Map.get(attrs, :current, Map.get(attrs, "current", %{}))),
      metadata: map_value(Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})))
    }
  end

  @spec from_binding_set_activation(BindingSetActivation.t()) :: t()
  def from_binding_set_activation(%BindingSetActivation{} = activation) do
    new(%{
      event_id: "operational_event:binding_set_activation:#{activation.activation_id}",
      organization_id: activation.organization_id,
      mission_id: activation.mission_id,
      occurred_at: activation.activated_at,
      recorded_at: activation.activated_at,
      effective_at: activation.activated_at,
      category: :runtime,
      kind: :binding_set_activated,
      severity: :info,
      actor: %{kind: :system},
      subject: %{kind: :binding_set, id: activation.binding_set_id},
      causality: %{
        correlation_id: activation.binding_set_id,
        source_record_kind: :binding_set_activation,
        source_record_id: activation.activation_id
      },
      payload: %{
        binding_set_id: activation.binding_set_id,
        binding_set_version: activation.binding_set_version,
        activation_id: activation.activation_id
      },
      current: %{
        binding_set_id: activation.binding_set_id,
        binding_set_version: activation.binding_set_version,
        activation_id: activation.activation_id
      },
      metadata: activation.metadata
    })
  end

  @spec from_scheduled_contact_interval(ScheduledContact.t(), DateTime.t() | nil) :: t()
  def from_scheduled_contact_interval(%ScheduledContact{} = contact, recorded_at \\ nil) do
    recorded_at = recorded_at || DateTime.utc_now()

    new(%{
      event_id: "operational_event:scheduled_contact_interval:#{contact.scheduled_contact_id}",
      organization_id: contact.organization_id,
      mission_id: contact.mission_id,
      occurred_at: contact.starts_at,
      recorded_at: recorded_at,
      effective_at: contact.starts_at,
      category: :contact,
      kind: :scheduled_contact_interval,
      severity: :info,
      actor: %{kind: :system},
      subject: %{kind: :contact, id: contact.scheduled_contact_id},
      scope: contact_scope(contact.scheduled_contact_id, contact.source_endpoint_refs),
      causality: %{
        correlation_id: contact.scheduled_contact_id,
        source_record_kind: :scheduled_contact,
        source_record_id: contact.scheduled_contact_id
      },
      payload: scheduled_contact_interval_payload(contact),
      current: scheduled_contact_interval_payload(contact),
      metadata: contact.metadata
    })
  end

  @spec from_realized_contact_interval(RealizedContact.t(), DateTime.t() | nil) :: t()
  def from_realized_contact_interval(%RealizedContact{} = contact, recorded_at \\ nil) do
    starts_at = contact.realized_at || contact.initial_time || recorded_at || DateTime.utc_now()
    recorded_at = recorded_at || starts_at

    new(%{
      event_id: "operational_event:realized_contact_interval:#{contact.realized_contact_id}",
      organization_id: contact.organization_id,
      mission_id: contact.mission_id,
      occurred_at: starts_at,
      recorded_at: recorded_at,
      effective_at: starts_at,
      category: :contact,
      kind: :realized_contact_interval,
      severity: :info,
      actor: %{kind: :system},
      subject: %{kind: :contact, id: contact.realized_contact_id},
      scope: contact_scope(contact.realized_contact_id, contact.source_endpoint_refs),
      causality: %{
        correlation_id: contact.realized_contact_id,
        source_record_kind: :realized_contact,
        source_record_id: contact.realized_contact_id
      },
      payload: realized_contact_interval_payload(contact, starts_at),
      current: realized_contact_interval_payload(contact, starts_at),
      metadata: contact.metadata
    })
  end

  @spec from_contact_action(ContactAction.t()) :: t()
  def from_contact_action(%ContactAction{} = contact_action) do
    new(%{
      event_id: "operational_event:contact_action:#{contact_action.contact_action_id}",
      organization_id: contact_action.organization_id,
      mission_id: contact_action.mission_id,
      occurred_at: contact_action.occurred_at,
      recorded_at: contact_action.occurred_at,
      effective_at: contact_action.occurred_at,
      category: :contact,
      kind: contact_action.action_kind,
      severity: contact_action_severity(contact_action.action_kind),
      actor: contact_action_actor(contact_action.actor),
      subject: contact_action_subject(contact_action),
      scope: contact_action_scope(contact_action),
      causality: %{
        correlation_id:
          contact_action.realized_contact_id ||
            contact_action.scheduled_contact_id ||
            contact_action.contact_action_id,
        source_record_kind: :contact_action,
        source_record_id: contact_action.contact_action_id
      },
      payload: contact_action_payload(contact_action),
      current: contact_action_payload(contact_action),
      metadata: contact_action.metadata
    })
  end

  @spec from_operational_observable_state_snapshot(map()) :: t()
  def from_operational_observable_state_snapshot(attrs) when is_map(attrs) do
    snapshot_id =
      attrs
      |> Map.get(:snapshot_id, Map.get(attrs, "snapshot_id", Map.get(attrs, :source_record_id)))
      |> text_value!()

    observed_at = operational_observable_observed_at(attrs)

    replay_run_id = text_value(Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")))
    payload = operational_observable_state_payload(attrs, observed_at)
    scope_kind = Map.fetch!(payload, :scope_kind)
    resource_id = Map.fetch!(payload, :resource_id)
    source_record_kind = operational_observable_state_source_record_kind(payload.observable_id)

    new(%{
      event_id: scoped_event_id(source_record_kind, snapshot_id, replay_run_id),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: fetch_required(attrs, :mission_id),
      occurred_at: observed_at,
      recorded_at: Map.get(attrs, :recorded_at, Map.get(attrs, "recorded_at", observed_at)),
      effective_at: observed_at,
      category: Map.get(attrs, :category, Map.get(attrs, "category", :comms)),
      kind: Map.get(attrs, :kind, Map.get(attrs, "kind", :operational_observable_state_changed)),
      severity: Map.get(attrs, :severity, Map.get(attrs, "severity", :info)),
      actor: Map.get(attrs, :actor, Map.get(attrs, "actor", %{kind: :system})),
      subject: %{kind: operational_observable_subject_kind(scope_kind), id: resource_id},
      scope: operational_observable_scope(payload, replay_run_id),
      causality:
        %{
          correlation_id: "#{payload.observable_id}:#{resource_id}",
          source_record_kind: source_record_kind,
          source_record_id: snapshot_id,
          replay_run_id: replay_run_id
        }
        |> compact(),
      payload: payload,
      current: payload,
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    })
  end

  @spec from_operational_observable_metric_sample(map()) :: t()
  def from_operational_observable_metric_sample(attrs) when is_map(attrs) do
    sample_id =
      attrs
      |> Map.get(:sample_id, Map.get(attrs, "sample_id", Map.get(attrs, :source_record_id)))
      |> text_value!()

    observed_at = operational_observable_observed_at(attrs)

    replay_run_id = text_value(Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")))
    payload = operational_observable_metric_payload(attrs, observed_at)
    scope_kind = Map.fetch!(payload, :scope_kind)
    resource_id = Map.fetch!(payload, :resource_id)

    new(%{
      event_id: scoped_event_id(:operational_observable_snapshot, sample_id, replay_run_id),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: fetch_required(attrs, :mission_id),
      occurred_at: observed_at,
      recorded_at: Map.get(attrs, :recorded_at, Map.get(attrs, "recorded_at", observed_at)),
      effective_at: observed_at,
      category: Map.get(attrs, :category, Map.get(attrs, "category", :comms)),
      kind: Map.get(attrs, :kind, Map.get(attrs, "kind", :operational_observable_metric_sampled)),
      severity: Map.get(attrs, :severity, Map.get(attrs, "severity", :info)),
      actor: Map.get(attrs, :actor, Map.get(attrs, "actor", %{kind: :system})),
      subject: %{kind: operational_observable_subject_kind(scope_kind), id: resource_id},
      scope: operational_observable_scope(payload, replay_run_id),
      causality:
        %{
          correlation_id: "#{payload.observable_id}:#{resource_id}",
          source_record_kind: :operational_observable_snapshot,
          source_record_id: sample_id,
          replay_run_id: replay_run_id
        }
        |> compact(),
      payload: payload,
      current: payload,
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    })
  end

  @spec from_transport_capability_record(TransportCapabilityRecord.t(), binary() | nil) :: t()
  def from_transport_capability_record(
        %TransportCapabilityRecord{} = capability_record,
        replay_run_id \\ nil
      ) do
    scope = maybe_put_replay_run_id(transport_capability_scope(capability_record), replay_run_id)

    payload =
      maybe_put_replay_run_id(transport_capability_payload(capability_record), replay_run_id)

    new(%{
      event_id:
        scoped_event_id(
          :transport_capability_record,
          capability_record.transport_record_id,
          replay_run_id
        ),
      mission_id: capability_record.mission_id,
      occurred_at: capability_record.recorded_at,
      recorded_at: capability_record.recorded_at,
      effective_at: capability_record.recorded_at,
      category: :comms,
      kind: transport_capability_record_kind(capability_record.event_kind),
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :transport, id: capability_record.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: capability_record.capability_instance_id,
            source_record_kind: :transport_capability_record,
            source_record_id: capability_record.transport_record_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(capability_record.metadata, replay_run_id)
    })
  end

  @spec from_transport_action_request(TransportActionRequest.t(), binary() | nil) :: t()
  def from_transport_action_request(
        %TransportActionRequest{} = action_request,
        replay_run_id \\ nil
      ) do
    scope = maybe_put_replay_run_id(transport_action_scope(action_request), replay_run_id)
    payload = maybe_put_replay_run_id(transport_action_payload(action_request), replay_run_id)

    new(%{
      event_id:
        scoped_event_id(
          :transport_action_request,
          action_request.action_request_id,
          replay_run_id
        ),
      mission_id: action_request.mission_id,
      occurred_at: action_request.requested_at,
      recorded_at: action_request.requested_at,
      effective_at: action_request.requested_at,
      category: :comms,
      kind: :transport_action_requested,
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :transport, id: action_request.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id:
              action_request.command_release_attempt_id ||
                action_request.command_request_id ||
                action_request.action_request_id,
            causation_event_id: action_request.command_release_attempt_id,
            source_record_kind: :transport_action_request,
            source_record_id: action_request.action_request_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(action_request.metadata, replay_run_id)
    })
  end

  @spec from_transport_timer_event(TransportTimerEvent.t(), binary() | nil) :: t()
  def from_transport_timer_event(%TransportTimerEvent{} = timer_event, replay_run_id \\ nil) do
    scope = maybe_put_replay_run_id(transport_timer_scope(timer_event), replay_run_id)
    payload = maybe_put_replay_run_id(transport_timer_payload(timer_event), replay_run_id)

    new(%{
      event_id:
        scoped_event_id(:transport_timer_event, timer_event.timer_event_id, replay_run_id),
      mission_id: timer_event.mission_id,
      occurred_at: timer_event.occurred_at,
      recorded_at: timer_event.occurred_at,
      effective_at: timer_event.occurred_at,
      category: :comms,
      kind: transport_timer_event_kind(timer_event.event_kind),
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :transport, id: timer_event.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: "#{timer_event.capability_instance_id}:#{timer_event.timer_key}",
            source_record_kind: :transport_timer_event,
            source_record_id: timer_event.timer_event_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(timer_event.metadata, replay_run_id)
    })
  end

  @spec from_managed_capability_record(ManagedCapabilityRecord.t(), binary() | nil) :: t()
  def from_managed_capability_record(
        %ManagedCapabilityRecord{} = capability_record,
        replay_run_id \\ nil
      ) do
    scope = maybe_put_replay_run_id(managed_capability_scope(capability_record), replay_run_id)

    payload =
      maybe_put_replay_run_id(managed_capability_payload(capability_record), replay_run_id)

    new(%{
      event_id:
        scoped_event_id(
          "managed_capability_record",
          capability_record.capability_record_id,
          replay_run_id
        ),
      mission_id: capability_record.mission_id,
      occurred_at: capability_record.recorded_at,
      recorded_at: capability_record.recorded_at,
      effective_at: capability_record.recorded_at,
      category: :runtime,
      kind: managed_capability_record_kind(capability_record.event_kind),
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :capability_instance, id: capability_record.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: capability_record.capability_instance_id,
            source_record_kind: :managed_capability_record,
            source_record_id: capability_record.capability_record_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(capability_record.metadata, replay_run_id)
    })
  end

  @spec from_managed_action_request(ManagedActionRequest.t(), binary() | nil) :: t()
  def from_managed_action_request(%ManagedActionRequest{} = action_request, replay_run_id \\ nil) do
    scope = maybe_put_replay_run_id(managed_action_scope(action_request), replay_run_id)
    payload = maybe_put_replay_run_id(managed_action_payload(action_request), replay_run_id)

    new(%{
      event_id:
        scoped_event_id("managed_action_request", action_request.action_request_id, replay_run_id),
      mission_id: action_request.mission_id,
      occurred_at: action_request.requested_at,
      recorded_at: action_request.requested_at,
      effective_at: action_request.requested_at,
      category: :runtime,
      kind: :managed_action_requested,
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :capability_instance, id: action_request.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: action_request.capability_instance_id,
            source_record_kind: :managed_action_request,
            source_record_id: action_request.action_request_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: action_request.request_document
    })
  end

  @spec from_managed_timer_event(ManagedTimerEvent.t(), binary() | nil) :: t()
  def from_managed_timer_event(%ManagedTimerEvent{} = timer_event, replay_run_id \\ nil) do
    scope = maybe_put_replay_run_id(managed_timer_scope(timer_event), replay_run_id)
    payload = maybe_put_replay_run_id(managed_timer_payload(timer_event), replay_run_id)

    new(%{
      event_id: scoped_event_id("managed_timer_event", timer_event.timer_event_id, replay_run_id),
      mission_id: timer_event.mission_id,
      occurred_at: timer_event.occurred_at,
      recorded_at: timer_event.occurred_at,
      effective_at: timer_event.occurred_at,
      category: :runtime,
      kind: managed_timer_event_kind(timer_event.event_kind),
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :capability_instance, id: timer_event.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: "#{timer_event.capability_instance_id}:#{timer_event.timer_key}",
            source_record_kind: :managed_timer_event,
            source_record_id: timer_event.timer_event_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(timer_event.metadata, replay_run_id)
    })
  end

  @spec from_catalog_revision(Revision.t(), DateTime.t()) :: t()
  def from_catalog_revision(%Revision{} = revision, %DateTime{} = occurred_at) do
    occurred_at = DateTime.truncate(occurred_at, :microsecond)

    new(%{
      event_id: "operational_event:catalog_revision:#{revision.catalog_revision_id}",
      organization_id: revision.organization_id,
      mission_id: revision.mission_id,
      occurred_at: occurred_at,
      recorded_at: occurred_at,
      effective_at: occurred_at,
      category: :catalog,
      kind: :catalog_revision_registered,
      severity: :info,
      actor: catalog_revision_actor(revision.created_by),
      subject: %{kind: :catalog_revision, id: revision.catalog_revision_id},
      scope: catalog_revision_scope(revision),
      causality: %{
        correlation_id: revision.catalog_database_id,
        source_record_kind: :catalog_revision,
        source_record_id: revision.catalog_revision_id,
        import_run_id: revision.import_run_id
      },
      payload: %{
        catalog_revision_id: revision.catalog_revision_id,
        catalog_database_id: revision.catalog_database_id,
        revision_number: revision.revision_number,
        revision_label: revision.revision_label,
        catalog_family: revision.catalog_family,
        artifact_id: revision.artifact_id,
        import_run_id: revision.import_run_id,
        telemetry_snapshot_id: revision.telemetry_snapshot_id,
        command_snapshot_id: revision.command_snapshot_id,
        content_sha256: revision.content_sha256,
        notes: revision.notes,
        revision_metadata: revision.metadata
      },
      current: %{
        catalog_revision_id: revision.catalog_revision_id,
        catalog_database_id: revision.catalog_database_id,
        revision_number: revision.revision_number,
        revision_label: revision.revision_label,
        catalog_family: revision.catalog_family,
        telemetry_snapshot_id: revision.telemetry_snapshot_id,
        command_snapshot_id: revision.command_snapshot_id
      },
      metadata: revision.metadata
    })
  end

  defp contact_scope(contact_id, source_endpoint_refs) do
    %{
      contact_id: contact_id,
      source_endpoint_refs: source_endpoint_refs
    }
    |> compact()
  end

  defp scheduled_contact_interval_payload(%ScheduledContact{} = contact) do
    Map.merge(contact_scope(contact.scheduled_contact_id, contact.source_endpoint_refs), %{
      contact_kind: :scheduled_contact,
      contact_id: contact.scheduled_contact_id,
      scheduled_contact_id: contact.scheduled_contact_id,
      realized_contact_id: contact.realized_contact_id,
      starts_at: contact.starts_at,
      ends_at: contact.ends_at,
      status: contact.lifecycle_state,
      lifecycle_state: contact.lifecycle_state,
      provider_contact_ref: contact.provider_contact_ref,
      contact_intents: contact.contact_intents,
      link_assignment_refs: contact.link_assignment_refs,
      path_template_ids: contact.path_template_ids,
      path_template_refs: contact.path_template_refs
    })
  end

  defp realized_contact_interval_payload(%RealizedContact{} = contact, starts_at) do
    Map.merge(contact_scope(contact.realized_contact_id, contact.source_endpoint_refs), %{
      contact_kind: :realized_contact,
      contact_id: contact.realized_contact_id,
      scheduled_contact_id: contact.scheduled_contact_id,
      realized_contact_id: contact.realized_contact_id,
      starts_at: starts_at,
      realized_at: contact.realized_at,
      initial_time: contact.initial_time,
      ends_at: contact_end_time(contact.metadata),
      status: contact.lifecycle_state,
      lifecycle_state: contact.lifecycle_state,
      clock_mode: contact.clock_mode,
      contact_intents: contact.contact_intents
    })
  end

  defp contact_end_time(metadata) when is_map(metadata) do
    Map.get(metadata, :completed_at) ||
      Map.get(metadata, "completed_at") ||
      Map.get(metadata, :stopped_at) ||
      Map.get(metadata, "stopped_at") ||
      Map.get(metadata, :ended_at) ||
      Map.get(metadata, "ended_at")
  end

  defp contact_end_time(_metadata), do: nil

  defp contact_action_severity(:scheduled_contact_canceled), do: :warning
  defp contact_action_severity(:realized_contact_ended_early), do: :warning
  defp contact_action_severity(_action_kind), do: :info

  defp contact_action_actor(actor) when is_map(actor) and map_size(actor) > 0, do: actor
  defp contact_action_actor(_actor), do: %{kind: :system}

  defp contact_action_subject(%ContactAction{realized_contact_id: realized_contact_id})
       when is_binary(realized_contact_id) and realized_contact_id != "" do
    %{kind: :contact, id: realized_contact_id}
  end

  defp contact_action_subject(%ContactAction{scheduled_contact_id: scheduled_contact_id})
       when is_binary(scheduled_contact_id) and scheduled_contact_id != "" do
    %{kind: :contact, id: scheduled_contact_id}
  end

  defp contact_action_subject(%ContactAction{}), do: nil

  defp contact_action_scope(%ContactAction{} = contact_action) do
    %{
      contact_id: contact_action.realized_contact_id || contact_action.scheduled_contact_id,
      scheduled_contact_id: contact_action.scheduled_contact_id,
      realized_contact_id: contact_action.realized_contact_id
    }
    |> compact()
  end

  defp contact_action_payload(%ContactAction{} = contact_action) do
    Map.merge(contact_action_scope(contact_action), %{
      contact_action_id: contact_action.contact_action_id,
      action_kind: contact_action.action_kind,
      reason: contact_action.reason,
      actor: contact_action.actor,
      occurred_at: contact_action.occurred_at,
      action_metadata: contact_action.metadata
    })
  end

  defp operational_observable_observed_at(attrs) do
    Map.get(attrs, :observed_at) ||
      Map.get(attrs, "observed_at") ||
      Map.get(attrs, :occurred_at) ||
      Map.fetch!(attrs, "occurred_at")
  end

  defp operational_observable_state_payload(attrs, observed_at) do
    observable_id =
      attrs
      |> Map.get(:observable_id, Map.get(attrs, "observable_id"))
      |> text_value!()

    resource_id =
      attrs
      |> Map.get(:resource_id, Map.get(attrs, "resource_id"))
      |> text_value!()

    scope_kind =
      attrs
      |> Map.get(:scope_kind, Map.get(attrs, "scope_kind", :transport))
      |> normalize_kind()

    %{
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: scope_kind,
      transport_id: text_value(Map.get(attrs, :transport_id, Map.get(attrs, "transport_id"))),
      spacecraft_id: text_value(Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id"))),
      contact_id:
        text_value(
          Map.get(
            attrs,
            :contact_id,
            Map.get(
              attrs,
              "contact_id",
              Map.get(attrs, :scheduled_contact_id, Map.get(attrs, :realized_contact_id))
            )
          )
        ),
      scheduled_contact_id:
        text_value(Map.get(attrs, :scheduled_contact_id, Map.get(attrs, "scheduled_contact_id"))),
      realized_contact_id:
        text_value(Map.get(attrs, :realized_contact_id, Map.get(attrs, "realized_contact_id"))),
      source_endpoint_id:
        text_value(
          Map.get(
            attrs,
            :source_endpoint_id,
            Map.get(attrs, "source_endpoint_id", Map.get(attrs, :source_endpoint_ref))
          )
        ),
      ground_station_id:
        text_value(
          Map.get(
            attrs,
            :ground_station_id,
            Map.get(attrs, "ground_station_id", Map.get(attrs, :antenna_id))
          )
        ),
      link_id:
        text_value(
          Map.get(
            attrs,
            :link_id,
            Map.get(attrs, "link_id", Map.get(attrs, :link_assignment_id))
          )
        ),
      adapter_key: Map.get(attrs, :adapter_key, Map.get(attrs, "adapter_key")),
      connection_state: Map.get(attrs, :connection_state, Map.get(attrs, "connection_state")),
      state: Map.get(attrs, :state, Map.get(attrs, "state")),
      normalized_state: Map.get(attrs, :normalized_state, Map.get(attrs, "normalized_state")),
      observed_at: observed_at,
      replay_run_id: text_value(Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")))
    }
    |> compact()
  end

  defp operational_observable_metric_payload(attrs, observed_at) do
    observable_id =
      attrs
      |> Map.get(:observable_id, Map.get(attrs, "observable_id"))
      |> text_value!()

    resource_id =
      attrs
      |> Map.get(:resource_id, Map.get(attrs, "resource_id"))
      |> text_value!()

    scope_kind =
      attrs
      |> Map.get(:scope_kind, Map.get(attrs, "scope_kind", :transport))
      |> normalize_kind()

    %{
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: scope_kind,
      transport_id: text_value(Map.get(attrs, :transport_id, Map.get(attrs, "transport_id"))),
      spacecraft_id: text_value(Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id"))),
      contact_id:
        text_value(
          Map.get(
            attrs,
            :contact_id,
            Map.get(
              attrs,
              "contact_id",
              Map.get(attrs, :scheduled_contact_id, Map.get(attrs, :realized_contact_id))
            )
          )
        ),
      scheduled_contact_id:
        text_value(Map.get(attrs, :scheduled_contact_id, Map.get(attrs, "scheduled_contact_id"))),
      realized_contact_id:
        text_value(Map.get(attrs, :realized_contact_id, Map.get(attrs, "realized_contact_id"))),
      source_endpoint_id:
        text_value(
          Map.get(
            attrs,
            :source_endpoint_id,
            Map.get(attrs, "source_endpoint_id", Map.get(attrs, :source_endpoint_ref))
          )
        ),
      ground_station_id:
        text_value(
          Map.get(
            attrs,
            :ground_station_id,
            Map.get(attrs, "ground_station_id", Map.get(attrs, :antenna_id))
          )
        ),
      link_id:
        text_value(
          Map.get(
            attrs,
            :link_id,
            Map.get(attrs, "link_id", Map.get(attrs, :link_assignment_id))
          )
        ),
      adapter_key: Map.get(attrs, :adapter_key, Map.get(attrs, "adapter_key")),
      value: Map.get(attrs, :value, Map.get(attrs, "value")),
      unit: Map.get(attrs, :unit, Map.get(attrs, "unit", Map.get(attrs, :value_unit))),
      downlink_bitrate: Map.get(attrs, :downlink_bitrate, Map.get(attrs, "downlink_bitrate")),
      downlink_bitrate_bps:
        Map.get(attrs, :downlink_bitrate_bps, Map.get(attrs, "downlink_bitrate_bps")),
      uplink_bitrate: Map.get(attrs, :uplink_bitrate, Map.get(attrs, "uplink_bitrate")),
      uplink_bitrate_bps:
        Map.get(attrs, :uplink_bitrate_bps, Map.get(attrs, "uplink_bitrate_bps")),
      bitrate: Map.get(attrs, :bitrate, Map.get(attrs, "bitrate")),
      snr_db: Map.get(attrs, :snr_db, Map.get(attrs, "snr_db")),
      snr: Map.get(attrs, :snr, Map.get(attrs, "snr")),
      signal_to_noise_ratio_db:
        Map.get(attrs, :signal_to_noise_ratio_db, Map.get(attrs, "signal_to_noise_ratio_db")),
      eb_n0_db: Map.get(attrs, :eb_n0_db, Map.get(attrs, "eb_n0_db")),
      ebn0_db: Map.get(attrs, :ebn0_db, Map.get(attrs, "ebn0_db")),
      energy_per_bit_to_noise_density_db:
        Map.get(
          attrs,
          :energy_per_bit_to_noise_density_db,
          Map.get(attrs, "energy_per_bit_to_noise_density_db")
        ),
      symbol_rate_sps: Map.get(attrs, :symbol_rate_sps, Map.get(attrs, "symbol_rate_sps")),
      symbol_rate: Map.get(attrs, :symbol_rate, Map.get(attrs, "symbol_rate")),
      symbols_per_second:
        Map.get(attrs, :symbols_per_second, Map.get(attrs, "symbols_per_second")),
      doppler_hz: Map.get(attrs, :doppler_hz, Map.get(attrs, "doppler_hz")),
      doppler: Map.get(attrs, :doppler, Map.get(attrs, "doppler")),
      frequency_offset_hz:
        Map.get(attrs, :frequency_offset_hz, Map.get(attrs, "frequency_offset_hz")),
      carrier_frequency_offset_hz:
        Map.get(
          attrs,
          :carrier_frequency_offset_hz,
          Map.get(attrs, "carrier_frequency_offset_hz")
        ),
      observed_at: observed_at,
      replay_run_id: text_value(Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")))
    }
    |> compact()
  end

  defp operational_observable_state_source_record_kind("comms.transport.connection_state"),
    do: :connection_state_snapshot

  defp operational_observable_state_source_record_kind("ground.station.connection_state"),
    do: :connection_state_snapshot

  defp operational_observable_state_source_record_kind("link.rf_lock_state"),
    do: :link_rf_lock_state_snapshot

  defp operational_observable_state_source_record_kind("link.frame_sync_state"),
    do: :link_frame_sync_state_snapshot

  defp operational_observable_state_source_record_kind(_observable_id),
    do: :operational_observable_snapshot

  defp operational_observable_scope(payload, replay_run_id) do
    %{
      logical_source: :operational_observables,
      scope_type: payload.scope_kind,
      scope_ref: payload.resource_id,
      transport_id: Map.get(payload, :transport_id),
      spacecraft_id: Map.get(payload, :spacecraft_id),
      contact_id: Map.get(payload, :contact_id),
      scheduled_contact_id: Map.get(payload, :scheduled_contact_id),
      realized_contact_id: Map.get(payload, :realized_contact_id),
      source_endpoint_id: Map.get(payload, :source_endpoint_id),
      ground_station_id: Map.get(payload, :ground_station_id),
      link_id: Map.get(payload, :link_id),
      replay_run_id: replay_run_id
    }
    |> compact()
  end

  defp operational_observable_subject_kind(kind)
       when kind in [:ground_station, :transport, :link, :spacecraft, :contact, :source_endpoint],
       do: kind

  defp operational_observable_subject_kind(_kind), do: :capability_instance

  defp transport_capability_record_kind(:initialized), do: :transport_initialized

  defp transport_capability_record_kind(:transport_event_handled),
    do: :transport_event_handled

  defp transport_capability_record_kind(:control_input_handled),
    do: :transport_control_input_handled

  defp transport_capability_record_kind(:timer_handled), do: :transport_timer_handled

  defp transport_capability_scope(%TransportCapabilityRecord{} = capability_record) do
    %{
      contact_id: capability_record.realized_contact_id,
      realized_contact_id: capability_record.realized_contact_id,
      path_id: capability_record.path_id,
      capability_instance_id: capability_record.capability_instance_id,
      binding_set_id: capability_record.binding_set_id,
      activation_id: capability_record.activation_id,
      timer_key: capability_record.timer_key
    }
    |> compact()
  end

  defp transport_capability_payload(%TransportCapabilityRecord{} = capability_record) do
    Map.merge(transport_capability_scope(capability_record), %{
      transport_record_id: capability_record.transport_record_id,
      family_key: capability_record.family_key,
      binding_set_version: capability_record.binding_set_version,
      partition_affinity: capability_record.partition_affinity,
      partition_value: capability_record.partition_value,
      event_kind: capability_record.event_kind,
      emitted_record_kinds: capability_record.emitted_record_kinds,
      emitted_record_count: capability_record.emitted_record_count,
      action_request_count: capability_record.action_request_count,
      state_snapshot: capability_record.state_snapshot,
      recorded_at: capability_record.recorded_at,
      record_metadata: capability_record.metadata
    })
  end

  defp transport_action_scope(%TransportActionRequest{} = action_request) do
    %{
      contact_id: action_request.realized_contact_id,
      realized_contact_id: action_request.realized_contact_id,
      path_id: action_request.path_id,
      capability_instance_id: action_request.capability_instance_id,
      source_endpoint_ref: action_request.source_endpoint_ref,
      binding_set_id: action_request.binding_set_id,
      activation_id: action_request.activation_id
    }
    |> compact()
  end

  defp transport_action_payload(%TransportActionRequest{} = action_request) do
    Map.merge(transport_action_scope(action_request), %{
      action_request_id: action_request.action_request_id,
      family_key: action_request.family_key,
      binding_set_version: action_request.binding_set_version,
      partition_affinity: action_request.partition_affinity,
      partition_value: action_request.partition_value,
      command_release_attempt_id: action_request.command_release_attempt_id,
      command_request_id: action_request.command_request_id,
      command_name: action_request.command_name,
      signal_phase: action_request.signal_phase,
      action_kind: action_request.action_kind,
      request_document: action_request.request_document,
      requested_at: action_request.requested_at,
      action_metadata: action_request.metadata
    })
  end

  defp transport_timer_event_kind(:scheduled), do: :transport_timer_scheduled
  defp transport_timer_event_kind(:fired), do: :transport_timer_fired
  defp transport_timer_event_kind(:canceled), do: :transport_timer_canceled

  defp transport_timer_scope(%TransportTimerEvent{} = timer_event) do
    %{
      contact_id: timer_event.realized_contact_id,
      realized_contact_id: timer_event.realized_contact_id,
      path_id: timer_event.path_id,
      capability_instance_id: timer_event.capability_instance_id,
      binding_set_id: timer_event.binding_set_id,
      activation_id: timer_event.activation_id,
      timer_key: timer_event.timer_key
    }
    |> compact()
  end

  defp transport_timer_payload(%TransportTimerEvent{} = timer_event) do
    Map.merge(transport_timer_scope(timer_event), %{
      timer_event_id: timer_event.timer_event_id,
      family_key: timer_event.family_key,
      binding_set_version: timer_event.binding_set_version,
      partition_affinity: timer_event.partition_affinity,
      partition_value: timer_event.partition_value,
      event_kind: timer_event.event_kind,
      due_at: timer_event.due_at,
      occurred_at: timer_event.occurred_at,
      timer_metadata: timer_event.metadata
    })
  end

  defp managed_capability_record_kind(:initialized), do: :managed_capability_initialized
  defp managed_capability_record_kind(:record_handled), do: :managed_capability_record_handled
  defp managed_capability_record_kind(:timer_handled), do: :managed_capability_timer_handled

  defp managed_capability_scope(%ManagedCapabilityRecord{} = capability_record) do
    %{
      capability_instance_id: capability_record.capability_instance_id,
      binding_set_id: capability_record.binding_set_id,
      activation_id: capability_record.activation_id,
      partition_affinity: capability_record.partition_affinity,
      partition_value: capability_record.partition_value,
      packet_id: capability_record.packet_id,
      evidence_id: capability_record.evidence_id,
      timer_key: capability_record.timer_key
    }
    |> compact()
  end

  defp managed_capability_payload(%ManagedCapabilityRecord{} = capability_record) do
    Map.merge(managed_capability_scope(capability_record), %{
      capability_record_id: capability_record.capability_record_id,
      family_key: capability_record.family_key,
      binding_set_version: capability_record.binding_set_version,
      event_kind: capability_record.event_kind,
      emitted_record_kinds: capability_record.emitted_record_kinds,
      emitted_record_count: capability_record.emitted_record_count,
      action_request_count: capability_record.action_request_count,
      state_snapshot: capability_record.state_snapshot,
      recorded_at: capability_record.recorded_at,
      record_metadata: capability_record.metadata
    })
  end

  defp managed_action_scope(%ManagedActionRequest{} = action_request) do
    %{
      capability_instance_id: action_request.capability_instance_id,
      binding_set_id: action_request.binding_set_id,
      activation_id: action_request.activation_id,
      partition_affinity: action_request.partition_affinity,
      partition_value: action_request.partition_value,
      packet_id: action_request.packet_id,
      evidence_id: action_request.evidence_id
    }
    |> compact()
  end

  defp managed_action_payload(%ManagedActionRequest{} = action_request) do
    Map.merge(managed_action_scope(action_request), %{
      action_request_id: action_request.action_request_id,
      family_key: action_request.family_key,
      binding_set_version: action_request.binding_set_version,
      action_kind: action_request.action_kind,
      request_document: action_request.request_document,
      requested_at: action_request.requested_at
    })
  end

  defp managed_timer_event_kind(:scheduled), do: :managed_timer_scheduled
  defp managed_timer_event_kind(:fired), do: :managed_timer_fired
  defp managed_timer_event_kind(:canceled), do: :managed_timer_canceled

  defp managed_timer_scope(%ManagedTimerEvent{} = timer_event) do
    %{
      capability_instance_id: timer_event.capability_instance_id,
      binding_set_id: timer_event.binding_set_id,
      activation_id: timer_event.activation_id,
      partition_affinity: timer_event.partition_affinity,
      partition_value: timer_event.partition_value,
      packet_id: timer_event.packet_id,
      evidence_id: timer_event.evidence_id,
      timer_key: timer_event.timer_key
    }
    |> compact()
  end

  defp managed_timer_payload(%ManagedTimerEvent{} = timer_event) do
    Map.merge(managed_timer_scope(timer_event), %{
      timer_event_id: timer_event.timer_event_id,
      family_key: timer_event.family_key,
      binding_set_version: timer_event.binding_set_version,
      event_kind: timer_event.event_kind,
      due_at: timer_event.due_at,
      occurred_at: timer_event.occurred_at,
      timer_metadata: timer_event.metadata
    })
  end

  defp scoped_event_id(source_record_kind, source_record_id, replay_run_id)
       when is_binary(replay_run_id) and replay_run_id != "" do
    "operational_event:#{source_record_kind}:#{replay_run_id}:#{source_record_id}"
  end

  defp scoped_event_id(source_record_kind, source_record_id, _replay_run_id) do
    "operational_event:#{source_record_kind}:#{source_record_id}"
  end

  defp replay_actor(replay_run_id) when is_binary(replay_run_id) and replay_run_id != "" do
    %{kind: :replay, id: replay_run_id}
  end

  defp replay_actor(_replay_run_id), do: %{kind: :system}

  defp maybe_put_replay_run_id(map, replay_run_id)
       when is_map(map) and is_binary(replay_run_id) and replay_run_id != "" do
    Map.put(map, :replay_run_id, replay_run_id)
  end

  defp maybe_put_replay_run_id(map, _replay_run_id), do: map

  defp catalog_revision_actor(created_by) when is_map(created_by) do
    created_by
    |> catalog_revision_actor_id()
    |> actor_from_identity()
  end

  defp catalog_revision_actor(_created_by), do: %{kind: :system}

  defp catalog_revision_actor_id(created_by) do
    cond do
      present_text?(Map.get(created_by, "user_id")) ->
        {:user, Map.fetch!(created_by, "user_id")}

      present_text?(Map.get(created_by, :user_id)) ->
        {:user, Map.fetch!(created_by, :user_id)}

      present_text?(Map.get(created_by, "service_identity_id")) ->
        {:service, Map.fetch!(created_by, "service_identity_id")}

      present_text?(Map.get(created_by, :service_identity_id)) ->
        {:service, Map.fetch!(created_by, :service_identity_id)}

      true ->
        nil
    end
  end

  defp actor_from_identity({kind, id}), do: %{kind: kind, id: id}
  defp actor_from_identity(nil), do: %{kind: :system}

  defp present_text?(value), do: is_binary(value) and value != ""

  defp catalog_revision_scope(%Revision{} = revision) do
    %{
      catalog_database_id: revision.catalog_database_id,
      catalog_family: revision.catalog_family
    }
    |> compact()
  end

  @spec from_dashboard_lifecycle_event(LifecycleEvent.t()) :: t()
  def from_dashboard_lifecycle_event(%LifecycleEvent{} = lifecycle_event) do
    new(%{
      event_id:
        "operational_event:dashboard_lifecycle_event:#{lifecycle_event.dashboard_lifecycle_event_id}",
      organization_id: lifecycle_event.organization_id,
      mission_id: lifecycle_event.mission_id,
      occurred_at: lifecycle_event.occurred_at,
      recorded_at: lifecycle_event.occurred_at,
      effective_at: lifecycle_event.occurred_at,
      category: :dashboard,
      kind: dashboard_lifecycle_kind(lifecycle_event.event_type),
      severity: :info,
      actor: dashboard_lifecycle_actor(lifecycle_event.actor_id),
      subject: %{kind: :dashboard, id: lifecycle_event.dashboard_id},
      causality: %{
        correlation_id: lifecycle_event.dashboard_id,
        source_record_kind: :dashboard_lifecycle_event,
        source_record_id: lifecycle_event.dashboard_lifecycle_event_id
      },
      payload: %{
        dashboard_lifecycle_event_id: lifecycle_event.dashboard_lifecycle_event_id,
        dashboard_id: lifecycle_event.dashboard_id,
        event_type: lifecycle_event.event_type,
        dashboard_version: lifecycle_event.dashboard_version,
        lifecycle_payload: lifecycle_event.payload
      },
      previous: %{
        lifecycle_state: lifecycle_event.previous_lifecycle_state,
        published_version: lifecycle_event.previous_published_version
      },
      current: %{
        lifecycle_state: lifecycle_event.current_lifecycle_state,
        published_version: lifecycle_event.current_published_version,
        dashboard_version: lifecycle_event.dashboard_version
      },
      metadata: lifecycle_event.payload
    })
  end

  @spec from_data_binding_event(DataBindingEvent.t()) :: t()
  def from_data_binding_event(%DataBindingEvent{} = binding_event) do
    new(%{
      event_id:
        "operational_event:dashboard_data_binding_event:#{binding_event.data_binding_event_id}",
      organization_id: binding_event.organization_id,
      mission_id: binding_event.mission_id,
      occurred_at: binding_event.occurred_at,
      recorded_at: binding_event.occurred_at,
      effective_at: binding_event.occurred_at,
      category: :data_source,
      kind: data_binding_kind(binding_event.event_type),
      severity: data_binding_severity(binding_event.event_type),
      actor: dashboard_lifecycle_actor(binding_event.actor_id),
      subject: %{kind: :source_binding, id: binding_event.binding_id},
      scope: data_binding_scope(binding_event),
      causality: %{
        correlation_id: binding_event.binding_id,
        source_record_kind: :dashboard_data_binding_event,
        source_record_id: binding_event.data_binding_event_id
      },
      payload: %{
        data_binding_event_id: binding_event.data_binding_event_id,
        binding_id: binding_event.binding_id,
        event_type: binding_event.event_type,
        binding_version: binding_event.current_binding_version,
        logical_source: binding_event.current_logical_source,
        realm: binding_event.current_realm,
        data_source_id: binding_event.current_data_source_id,
        dataset: binding_event.current_dataset,
        priority: binding_event.current_priority,
        active_from: binding_event.current_active_from,
        active_to: binding_event.current_active_to,
        lifecycle_payload: binding_event.payload
      },
      previous: %{
        status: binding_event.previous_status,
        binding_version: binding_event.previous_binding_version,
        logical_source: binding_event.previous_logical_source,
        realm: binding_event.previous_realm,
        data_source_id: binding_event.previous_data_source_id,
        dataset: binding_event.previous_dataset,
        priority: binding_event.previous_priority,
        active_from: binding_event.previous_active_from,
        active_to: binding_event.previous_active_to
      },
      current: %{
        status: binding_event.current_status,
        binding_version: binding_event.current_binding_version,
        logical_source: binding_event.current_logical_source,
        realm: binding_event.current_realm,
        data_source_id: binding_event.current_data_source_id,
        dataset: binding_event.current_dataset,
        priority: binding_event.current_priority,
        active_from: binding_event.current_active_from,
        active_to: binding_event.current_active_to
      },
      metadata: binding_event.payload
    })
  end

  defp data_binding_kind(:registered), do: :source_binding_registered
  defp data_binding_kind(:changed), do: :source_binding_changed
  defp data_binding_kind(:enabled), do: :source_binding_enabled
  defp data_binding_kind(:disabled), do: :source_binding_disabled
  defp data_binding_kind(:superseded), do: :source_binding_superseded

  defp data_binding_severity(event_type) when event_type in [:disabled, :superseded],
    do: :warning

  defp data_binding_severity(_event_type), do: :info

  defp data_binding_scope(%DataBindingEvent{} = binding_event) do
    %{
      logical_source: binding_event.current_logical_source,
      source_binding_id: binding_event.binding_id,
      data_source_id: binding_event.current_data_source_id,
      data_realm: binding_event.current_realm,
      dataset: binding_event.current_dataset
    }
    |> compact()
  end

  defp dashboard_lifecycle_kind(:published), do: :dashboard_published
  defp dashboard_lifecycle_kind(:archived), do: :dashboard_archived
  defp dashboard_lifecycle_kind(:restored), do: :dashboard_restored
  defp dashboard_lifecycle_kind(:reverted), do: :dashboard_reverted

  defp dashboard_lifecycle_kind(:comparison_review_requested),
    do: :dashboard_comparison_review_requested

  defp dashboard_lifecycle_kind(:comparison_review_resolved),
    do: :dashboard_comparison_review_resolved

  defp dashboard_lifecycle_kind(:health_snapshot_captured),
    do: :dashboard_health_snapshot_captured

  defp dashboard_lifecycle_kind(:publish_readiness_checked),
    do: :dashboard_publish_readiness_checked

  defp dashboard_lifecycle_actor(actor_id) when is_binary(actor_id) and actor_id != "",
    do: %{kind: :user, id: actor_id}

  defp dashboard_lifecycle_actor(_actor_id), do: %{kind: :system}

  @spec from_source_capability_posture(map()) :: t()
  def from_source_capability_posture(attrs) when is_map(attrs) do
    occurred_at = source_capability_posture_occurred_at(attrs)
    posture_id = source_capability_posture_id(attrs)
    payload = source_capability_posture_payload(attrs, posture_id, occurred_at)
    scope = source_capability_posture_scope(payload)
    status = Map.fetch!(payload, :status)

    new(%{
      event_id:
        scoped_event_id(
          :source_capability_posture,
          posture_id,
          Map.get(payload, :replay_run_id)
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: fetch_required(attrs, :mission_id),
      occurred_at: occurred_at,
      recorded_at: Map.get(attrs, :recorded_at, Map.get(attrs, "recorded_at", occurred_at)),
      effective_at: occurred_at,
      category: :data_source,
      kind: source_capability_posture_kind(status),
      severity: source_capability_posture_severity(status),
      actor: Map.get(attrs, :actor, Map.get(attrs, "actor", %{kind: :system})),
      subject: source_capability_posture_subject(payload),
      scope: scope,
      causality:
        %{
          correlation_id: source_capability_posture_correlation_id(payload),
          source_record_kind: :source_capability_posture,
          source_record_id: posture_id,
          replay_run_id: Map.get(payload, :replay_run_id)
        }
        |> compact(),
      payload: payload,
      current: source_capability_posture_current(payload),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    })
  end

  @spec from_source_health_event(SourceHealthEvent.t()) :: t()
  def from_source_health_event(%SourceHealthEvent{} = source_event) do
    new(%{
      event_id:
        scoped_event_id(
          :source_health_event,
          source_event.source_health_event_id,
          source_event.replay_run_id
        ),
      organization_id: source_event.organization_id,
      mission_id: source_event.mission_id,
      occurred_at: source_event.observed_at,
      recorded_at: source_event.observed_at,
      effective_at: source_event.observed_at,
      category: :data_source,
      kind: source_health_kind(source_event.event_type),
      severity: source_health_severity(source_event.source_health),
      actor: %{kind: :system},
      subject: %{kind: :data_source, id: source_event.data_source_id},
      scope: source_event_scope(source_event),
      causality: %{
        correlation_id: source_event.source_health_key,
        source_record_kind: :source_health_event,
        source_record_id: source_event.source_health_event_id,
        replay_run_id: source_event.replay_run_id
      },
      payload:
        Map.merge(source_event_scope(source_event), %{
          source_health_event_id: source_event.source_health_event_id,
          source_health_key: source_event.source_health_key,
          event_type: source_event.event_type,
          source_health: source_event.source_health,
          previous_source_health: source_event.previous_source_health,
          reason: source_event.reason,
          source_payload: source_event.payload
        }),
      previous: %{source_health: source_event.previous_source_health},
      current: %{
        source_health: source_event.source_health,
        reason: source_event.reason
      },
      metadata: source_event.payload
    })
  end

  @spec from_source_watermark_event(SourceWatermarkEvent.t()) :: t()
  def from_source_watermark_event(%SourceWatermarkEvent{} = source_event) do
    new(%{
      event_id:
        scoped_event_id(
          :source_watermark_event,
          source_event.source_watermark_event_id,
          source_event.replay_run_id
        ),
      organization_id: source_event.organization_id,
      mission_id: source_event.mission_id,
      occurred_at: source_event.observed_at,
      recorded_at: source_event.observed_at,
      effective_at: source_event.observed_at,
      category: :data_source,
      kind: source_watermark_kind(source_event.event_type),
      severity: source_watermark_severity(source_event.event_type),
      actor: %{kind: :system},
      subject: %{kind: :data_source, id: source_event.data_source_id},
      scope: source_event_scope(source_event),
      causality: %{
        correlation_id: source_event.source_watermark_key,
        source_record_kind: :source_watermark_event,
        source_record_id: source_event.source_watermark_event_id,
        replay_run_id: source_event.replay_run_id
      },
      payload:
        Map.merge(source_event_scope(source_event), %{
          source_watermark_event_id: source_event.source_watermark_event_id,
          source_watermark_key: source_event.source_watermark_key,
          event_type: source_event.event_type,
          complete_through: source_event.complete_through,
          previous_complete_through: source_event.previous_complete_through,
          latest_receipt_time: source_event.latest_receipt_time,
          previous_latest_receipt_time: source_event.previous_latest_receipt_time,
          retention_starts_at: source_event.retention_starts_at,
          previous_retention_starts_at: source_event.previous_retention_starts_at,
          sample_count: source_event.sample_count,
          confidence: source_event.confidence,
          reason: source_event.reason,
          source_payload: source_event.payload
        }),
      previous: %{
        complete_through: source_event.previous_complete_through,
        latest_receipt_time: source_event.previous_latest_receipt_time,
        retention_starts_at: source_event.previous_retention_starts_at
      },
      current: %{
        complete_through: source_event.complete_through,
        latest_receipt_time: source_event.latest_receipt_time,
        retention_starts_at: source_event.retention_starts_at,
        sample_count: source_event.sample_count,
        confidence: source_event.confidence,
        reason: source_event.reason
      },
      metadata: source_event.payload
    })
  end

  defp source_health_kind(:degraded), do: :source_health_degraded
  defp source_health_kind(:recovered), do: :source_health_recovered
  defp source_health_kind(:unavailable), do: :source_health_unavailable
  defp source_health_kind(:unknown), do: :source_health_unknown

  defp source_health_severity(:healthy), do: :info
  defp source_health_severity(:degraded), do: :warning
  defp source_health_severity(:unavailable), do: :error
  defp source_health_severity(:unknown), do: :warning

  defp source_watermark_kind(:observed), do: :source_watermark_observed
  defp source_watermark_kind(:advanced), do: :source_watermark_advanced
  defp source_watermark_kind(:retreated), do: :source_watermark_retreated
  defp source_watermark_kind(:changed), do: :source_watermark_changed
  defp source_watermark_kind(:unknown), do: :source_watermark_unknown

  defp source_watermark_severity(:retreated), do: :warning
  defp source_watermark_severity(:unknown), do: :warning
  defp source_watermark_severity(_event_type), do: :info

  defp source_capability_posture_id(attrs) do
    Map.get(attrs, :source_capability_posture_id, Map.get(attrs, "source_capability_posture_id")) ||
      Map.get(attrs, :posture_id, Map.get(attrs, "posture_id")) ||
      [
        Map.get(attrs, :dashboard_id, Map.get(attrs, "dashboard_id")),
        Map.get(attrs, :resolve_id, Map.get(attrs, "resolve_id")),
        Map.get(attrs, :source_request_id, Map.get(attrs, "source_request_id"))
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(":")
      |> text_value!()
  end

  defp source_capability_posture_occurred_at(attrs) do
    Map.get(attrs, :observed_at) ||
      Map.get(attrs, "observed_at") ||
      Map.get(attrs, :occurred_at) ||
      Map.get(attrs, "occurred_at") ||
      raise KeyError, key: :occurred_at, term: attrs
  end

  defp source_capability_posture_payload(attrs, posture_id, occurred_at) do
    posture = Map.get(attrs, :capability_posture, Map.get(attrs, "capability_posture", %{}))
    posture_status = source_capability_posture_value(posture, :status)

    %{
      source_capability_posture_id: posture_id,
      dashboard_id: Map.get(attrs, :dashboard_id, Map.get(attrs, "dashboard_id")),
      dashboard_version: Map.get(attrs, :dashboard_version, Map.get(attrs, "dashboard_version")),
      resolve_id: Map.get(attrs, :resolve_id, Map.get(attrs, "resolve_id")),
      source_request_id: Map.get(attrs, :source_request_id, Map.get(attrs, "source_request_id")),
      logical_source: Map.get(attrs, :logical_source, Map.get(attrs, "logical_source")),
      data_source_id: Map.get(attrs, :data_source_id, Map.get(attrs, "data_source_id")),
      source_binding_id: Map.get(attrs, :source_binding_id, Map.get(attrs, "source_binding_id")),
      realm: Map.get(attrs, :realm, Map.get(attrs, "realm")),
      dataset: Map.get(attrs, :dataset, Map.get(attrs, "dataset")),
      replay_run_id: Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")),
      status: Map.get(attrs, :status, Map.get(attrs, "status", posture_status)),
      requested_sampling:
        Map.get(
          attrs,
          :requested_sampling,
          Map.get(
            attrs,
            "requested_sampling",
            source_capability_posture_value(posture, :requested_sampling)
          )
        ),
      supported_sampling:
        Map.get(
          attrs,
          :supported_sampling,
          Map.get(
            attrs,
            "supported_sampling",
            source_capability_posture_value(posture, :supported_sampling)
          )
        ),
      requested_products:
        Map.get(
          attrs,
          :requested_products,
          Map.get(
            attrs,
            "requested_products",
            source_capability_posture_value(posture, :requested_products)
          )
        ),
      supported_products:
        Map.get(
          attrs,
          :supported_products,
          Map.get(
            attrs,
            "supported_products",
            source_capability_posture_value(posture, :supported_products)
          )
        ),
      requested_time_axis:
        Map.get(
          attrs,
          :requested_time_axis,
          Map.get(
            attrs,
            "requested_time_axis",
            source_capability_posture_value(posture, :requested_time_axis)
          )
        ),
      executed_time_axis:
        Map.get(
          attrs,
          :executed_time_axis,
          Map.get(
            attrs,
            "executed_time_axis",
            source_capability_posture_value(posture, :executed_time_axis)
          )
        ),
      supported_time_axes:
        Map.get(
          attrs,
          :supported_time_axes,
          Map.get(
            attrs,
            "supported_time_axes",
            source_capability_posture_value(posture, :supported_time_axes)
          )
        ),
      fallbacks:
        Map.get(
          attrs,
          :fallbacks,
          Map.get(attrs, "fallbacks", source_capability_posture_value(posture, :fallbacks))
        ),
      unsupported:
        Map.get(
          attrs,
          :unsupported,
          Map.get(attrs, "unsupported", source_capability_posture_value(posture, :unsupported))
        ),
      source_execution_status:
        Map.get(attrs, :source_execution_status, Map.get(attrs, "source_execution_status")),
      source_execution_cache_status:
        Map.get(
          attrs,
          :source_execution_cache_status,
          Map.get(attrs, "source_execution_cache_status")
        ),
      source_execution_operator_action:
        Map.get(
          attrs,
          :source_execution_operator_action,
          Map.get(attrs, "source_execution_operator_action")
        ),
      source_execution_runtime_action:
        Map.get(
          attrs,
          :source_execution_runtime_action,
          Map.get(attrs, "source_execution_runtime_action")
        ),
      source_execution_warning_codes:
        Map.get(
          attrs,
          :source_execution_warning_codes,
          Map.get(attrs, "source_execution_warning_codes")
        ),
      observed_at: occurred_at
    }
    |> compact()
  end

  defp source_capability_posture_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp source_capability_posture_value(_map, _key), do: nil

  defp source_capability_posture_scope(payload) do
    %{
      logical_source: Map.get(payload, :logical_source),
      data_source_id: Map.get(payload, :data_source_id),
      source_binding_id: Map.get(payload, :source_binding_id),
      data_realm: Map.get(payload, :realm),
      replay_run_id: Map.get(payload, :replay_run_id),
      dataset: Map.get(payload, :dataset),
      dashboard_id: Map.get(payload, :dashboard_id),
      source_request_id: Map.get(payload, :source_request_id)
    }
    |> compact()
  end

  defp source_capability_posture_current(payload) do
    %{
      capability_status: Map.get(payload, :status),
      requested_sampling: Map.get(payload, :requested_sampling),
      supported_sampling: Map.get(payload, :supported_sampling),
      requested_products: Map.get(payload, :requested_products),
      supported_products: Map.get(payload, :supported_products),
      requested_time_axis: Map.get(payload, :requested_time_axis),
      executed_time_axis: Map.get(payload, :executed_time_axis),
      supported_time_axes: Map.get(payload, :supported_time_axes),
      fallbacks: Map.get(payload, :fallbacks),
      unsupported: Map.get(payload, :unsupported)
    }
    |> compact()
  end

  defp source_capability_posture_subject(%{data_source_id: data_source_id})
       when data_source_id not in [nil, ""],
       do: %{kind: :data_source, id: data_source_id}

  defp source_capability_posture_subject(%{source_binding_id: source_binding_id})
       when source_binding_id not in [nil, ""],
       do: %{kind: :source_binding, id: source_binding_id}

  defp source_capability_posture_subject(%{dashboard_id: dashboard_id})
       when dashboard_id not in [nil, ""],
       do: %{kind: :dashboard, id: dashboard_id}

  defp source_capability_posture_subject(_payload), do: nil

  defp source_capability_posture_correlation_id(payload) do
    Map.get(payload, :resolve_id) ||
      [
        Map.get(payload, :dashboard_id),
        Map.get(payload, :source_request_id)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(":")
      |> case do
        "" -> Map.get(payload, :source_capability_posture_id)
        correlation_id -> correlation_id
      end
  end

  defp source_capability_posture_kind(:native), do: :source_capability_native
  defp source_capability_posture_kind("native"), do: :source_capability_native
  defp source_capability_posture_kind(:fallback), do: :source_capability_fallback
  defp source_capability_posture_kind("fallback"), do: :source_capability_fallback
  defp source_capability_posture_kind(:unsupported), do: :source_capability_unsupported
  defp source_capability_posture_kind("unsupported"), do: :source_capability_unsupported
  defp source_capability_posture_kind(_status), do: :source_capability_unknown

  defp source_capability_posture_severity(:native), do: :info
  defp source_capability_posture_severity("native"), do: :info
  defp source_capability_posture_severity(:fallback), do: :warning
  defp source_capability_posture_severity("fallback"), do: :warning
  defp source_capability_posture_severity(:unsupported), do: :error
  defp source_capability_posture_severity("unsupported"), do: :error
  defp source_capability_posture_severity(_status), do: :warning

  defp source_event_scope(source_event) do
    %{
      logical_source: Map.get(source_event, :logical_source),
      data_source_id: Map.get(source_event, :data_source_id),
      source_binding_id: Map.get(source_event, :source_binding_id),
      data_realm: Map.get(source_event, :realm),
      replay_run_id: Map.get(source_event, :replay_run_id),
      dataset: Map.get(source_event, :dataset)
    }
    |> compact()
  end

  @spec from_limit_definition_lifecycle_event(DefinitionLifecycleEvent.t()) :: t()
  def from_limit_definition_lifecycle_event(%DefinitionLifecycleEvent{} = lifecycle_event) do
    new(%{
      event_id:
        "operational_event:limit_definition_lifecycle_event:#{lifecycle_event.limit_definition_lifecycle_event_id}",
      organization_id: lifecycle_event.organization_id,
      mission_id: lifecycle_event.mission_id,
      occurred_at: lifecycle_event.observed_at,
      recorded_at: lifecycle_event.observed_at,
      effective_at: lifecycle_event.active_from,
      category: :limits,
      kind: limit_definition_lifecycle_kind(lifecycle_event.event_type),
      severity: limit_definition_lifecycle_severity(lifecycle_event.event_type),
      actor: %{kind: :system},
      subject: %{kind: :limit_definition, id: lifecycle_event.limit_definition_id},
      scope: limit_definition_lifecycle_scope(lifecycle_event),
      causality: %{
        correlation_id: lifecycle_event.definition_activation_key,
        source_record_kind: :limit_definition_lifecycle_event,
        source_record_id: lifecycle_event.limit_definition_lifecycle_event_id
      },
      payload:
        Map.merge(limit_definition_lifecycle_scope(lifecycle_event), %{
          limit_definition_lifecycle_event_id:
            lifecycle_event.limit_definition_lifecycle_event_id,
          definition_activation_key: lifecycle_event.definition_activation_key,
          event_type: lifecycle_event.event_type,
          limit_definition_id: lifecycle_event.limit_definition_id,
          limit_definition_version: lifecycle_event.limit_definition_version,
          previous_limit_definition_id: lifecycle_event.previous_limit_definition_id,
          previous_limit_definition_version: lifecycle_event.previous_limit_definition_version,
          active_from: lifecycle_event.active_from,
          active_to: lifecycle_event.active_to,
          reason: lifecycle_event.reason,
          lifecycle_payload: lifecycle_event.payload
        }),
      previous: %{
        limit_definition_id: lifecycle_event.previous_limit_definition_id,
        limit_definition_version: lifecycle_event.previous_limit_definition_version
      },
      current: %{
        limit_definition_id: lifecycle_event.limit_definition_id,
        limit_definition_version: lifecycle_event.limit_definition_version,
        active_from: lifecycle_event.active_from,
        active_to: lifecycle_event.active_to,
        reason: lifecycle_event.reason
      },
      metadata: lifecycle_event.payload
    })
  end

  defp limit_definition_lifecycle_kind(:registered), do: :limit_definition_registered
  defp limit_definition_lifecycle_kind(:activated), do: :limit_definition_activated
  defp limit_definition_lifecycle_kind(:superseded), do: :limit_definition_superseded
  defp limit_definition_lifecycle_kind(:disabled), do: :limit_definition_disabled
  defp limit_definition_lifecycle_kind(:retired), do: :limit_definition_retired
  defp limit_definition_lifecycle_kind(:unknown), do: :limit_definition_lifecycle_unknown

  defp limit_definition_lifecycle_severity(:unknown), do: :warning
  defp limit_definition_lifecycle_severity(_event_type), do: :info

  defp limit_definition_lifecycle_scope(%DefinitionLifecycleEvent{} = lifecycle_event) do
    %{
      point_id: lifecycle_event.point_id,
      limit_set_name: lifecycle_event.limit_set_name,
      scope_type: lifecycle_event.scope_type,
      scope_ref: lifecycle_event.scope_ref,
      data_realm: lifecycle_event.realm
    }
    |> compact()
  end

  @spec from_backfill_lifecycle_event(BackfillLifecycleEvent.t()) :: t()
  def from_backfill_lifecycle_event(%BackfillLifecycleEvent{} = lifecycle_event) do
    new(%{
      event_id:
        "operational_event:telemetry_backfill_lifecycle_event:#{lifecycle_event.backfill_lifecycle_event_id}",
      organization_id: lifecycle_event.organization_id,
      mission_id: lifecycle_event.mission_id,
      occurred_at: lifecycle_event.occurred_at,
      recorded_at: lifecycle_event.occurred_at,
      category: :telemetry,
      kind: backfill_lifecycle_kind(lifecycle_event.event_type),
      severity: backfill_lifecycle_severity(lifecycle_event.event_type),
      actor: telemetry_actor(lifecycle_event.actor_kind, lifecycle_event.actor_id),
      subject: telemetry_subject(lifecycle_event),
      scope: telemetry_data_management_scope(lifecycle_event),
      causality: %{
        correlation_id: lifecycle_event.backfill_run_id,
        source_record_kind: :telemetry_backfill_lifecycle_event,
        source_record_id: lifecycle_event.backfill_lifecycle_event_id,
        job_id: payload_job_id(lifecycle_event.payload),
        replay_run_id: lifecycle_event.replay_run_id,
        import_run_id: import_run_id(lifecycle_event)
      },
      payload:
        Map.merge(telemetry_data_management_scope(lifecycle_event), %{
          backfill_lifecycle_event_id: lifecycle_event.backfill_lifecycle_event_id,
          backfill_run_id: lifecycle_event.backfill_run_id,
          event_type: lifecycle_event.event_type,
          source_from: lifecycle_event.source_from,
          source_to: lifecycle_event.source_to,
          receipt_from: lifecycle_event.receipt_from,
          receipt_to: lifecycle_event.receipt_to,
          sample_count: lifecycle_event.sample_count,
          authority: lifecycle_event.authority,
          reason: lifecycle_event.reason,
          lifecycle_payload: lifecycle_event.payload
        }),
      current: %{
        event_type: lifecycle_event.event_type,
        authority: lifecycle_event.authority,
        reason: lifecycle_event.reason,
        source_from: lifecycle_event.source_from,
        source_to: lifecycle_event.source_to,
        sample_count: lifecycle_event.sample_count
      },
      metadata: lifecycle_event.payload
    })
  end

  @spec from_observation_identity_decision_event(ObservationIdentityDecisionEvent.t()) :: t()
  def from_observation_identity_decision_event(
        %ObservationIdentityDecisionEvent{} = decision_event
      ) do
    new(%{
      event_id:
        "operational_event:telemetry_observation_identity_decision_event:#{decision_event.decision_event_id}",
      organization_id: decision_event.organization_id,
      mission_id: decision_event.mission_id,
      occurred_at: decision_event.occurred_at,
      recorded_at: decision_event.occurred_at,
      category: :telemetry,
      kind: observation_identity_decision_kind(decision_event.decision),
      severity: observation_identity_decision_severity(decision_event.decision),
      actor: telemetry_actor(decision_event.actor_kind, decision_event.actor_id),
      subject: %{kind: :telemetry_point, id: decision_event.point_id},
      scope: telemetry_data_management_scope(decision_event),
      causality: %{
        correlation_id: decision_event.observation_identity_id,
        source_record_kind: :telemetry_observation_identity_decision_event,
        source_record_id: decision_event.decision_event_id,
        replay_run_id: decision_event.replay_run_id
      },
      payload:
        Map.merge(telemetry_data_management_scope(decision_event), %{
          decision_event_id: decision_event.decision_event_id,
          observation_identity_id: decision_event.observation_identity_id,
          decision: decision_event.decision,
          decision_reason: decision_event.decision_reason,
          evidence_ref: decision_event.evidence_ref
        }),
      previous: decision_event.previous_state,
      current: decision_event.new_state,
      metadata: %{evidence_ref: decision_event.evidence_ref}
    })
  end

  defp backfill_lifecycle_kind(:backfill_requested), do: :telemetry_backfill_requested
  defp backfill_lifecycle_kind(:backfill_approved), do: :telemetry_backfill_approved
  defp backfill_lifecycle_kind(:backfill_rejected), do: :telemetry_backfill_rejected
  defp backfill_lifecycle_kind(:backfill_started), do: :telemetry_backfill_started
  defp backfill_lifecycle_kind(:backfill_completed), do: :telemetry_backfill_completed
  defp backfill_lifecycle_kind(:backfill_failed), do: :telemetry_backfill_failed
  defp backfill_lifecycle_kind(:backfill_retried), do: :telemetry_backfill_retried

  defp backfill_lifecycle_kind(:backfill_missing_replacement_inspected),
    do: :telemetry_backfill_missing_replacement_inspected

  defp backfill_lifecycle_kind(:backfill_stale_replacement_inspected),
    do: :telemetry_backfill_stale_replacement_inspected

  defp backfill_lifecycle_kind(:backfill_stale_replacement_requeued),
    do: :telemetry_backfill_stale_replacement_requeued

  defp backfill_lifecycle_kind(:import_requested), do: :telemetry_import_requested
  defp backfill_lifecycle_kind(:import_approved), do: :telemetry_import_approved
  defp backfill_lifecycle_kind(:import_rejected), do: :telemetry_import_rejected
  defp backfill_lifecycle_kind(:import_started), do: :telemetry_import_started
  defp backfill_lifecycle_kind(:import_completed), do: :telemetry_import_completed
  defp backfill_lifecycle_kind(:import_failed), do: :telemetry_import_failed
  defp backfill_lifecycle_kind(:import_retried), do: :telemetry_import_retried

  defp backfill_lifecycle_kind(:import_missing_replacement_inspected),
    do: :telemetry_import_missing_replacement_inspected

  defp backfill_lifecycle_kind(:import_stale_replacement_inspected),
    do: :telemetry_import_stale_replacement_inspected

  defp backfill_lifecycle_kind(:import_stale_replacement_requeued),
    do: :telemetry_import_stale_replacement_requeued

  defp backfill_lifecycle_kind(:late_data_accepted), do: :telemetry_late_data_accepted
  defp backfill_lifecycle_kind(:late_data_rejected), do: :telemetry_late_data_rejected
  defp backfill_lifecycle_kind(:unknown), do: :telemetry_backfill_lifecycle_unknown

  defp backfill_lifecycle_severity(event_type)
       when event_type in [:backfill_failed, :import_failed],
       do: :error

  defp backfill_lifecycle_severity(event_type)
       when event_type in [:backfill_rejected, :import_rejected, :late_data_rejected, :unknown],
       do: :warning

  defp backfill_lifecycle_severity(_event_type), do: :info

  defp observation_identity_decision_kind(:mark_canonical),
    do: :telemetry_observation_marked_canonical

  defp observation_identity_decision_kind(:mark_conflict),
    do: :telemetry_observation_marked_conflict

  defp observation_identity_decision_kind(:mark_superseded),
    do: :telemetry_observation_marked_superseded

  defp observation_identity_decision_kind(:mark_advisory),
    do: :telemetry_observation_marked_advisory

  defp observation_identity_decision_severity(:mark_conflict), do: :warning
  defp observation_identity_decision_severity(_decision), do: :info

  defp telemetry_actor(actor_kind, actor_id) when actor_kind in [:service, "service"],
    do: typed_actor(:service, actor_id)

  defp telemetry_actor(actor_kind, actor_id) when actor_kind in [:replay, "replay"],
    do: typed_actor(:replay, actor_id)

  defp telemetry_actor(_actor_kind, actor_id), do: user_or_system_actor(actor_id)

  defp typed_actor(kind, actor_id) when is_binary(actor_id) and actor_id != "",
    do: %{kind: kind, id: actor_id}

  defp typed_actor(_kind, _actor_id), do: %{kind: :system}

  defp user_or_system_actor(actor_id) when is_binary(actor_id) and actor_id != "",
    do: %{kind: :user, id: actor_id}

  defp user_or_system_actor(_actor_id), do: %{kind: :system}

  defp telemetry_subject(%BackfillLifecycleEvent{} = event) do
    cond do
      is_binary(event.point_id) and event.point_id != "" ->
        %{kind: :telemetry_point, id: event.point_id}

      is_binary(event.observable_id) and event.observable_id != "" ->
        %{kind: :telemetry_point, id: event.observable_id}

      is_binary(event.data_source_id) and event.data_source_id != "" ->
        %{kind: :data_source, id: event.data_source_id}

      true ->
        nil
    end
  end

  defp telemetry_data_management_scope(event) do
    %{
      logical_source: :telemetry,
      data_source_id: Map.get(event, :data_source_id),
      source_binding_id: Map.get(event, :binding_id),
      data_realm: Map.get(event, :realm),
      replay_run_id: Map.get(event, :replay_run_id),
      point_id: Map.get(event, :point_id) || Map.get(event, :observable_id),
      spacecraft_id: Map.get(event, :spacecraft_id)
    }
    |> compact()
  end

  defp payload_job_id(payload) when is_map(payload) do
    Map.get(payload, :job_id) || Map.get(payload, "job_id")
  end

  defp payload_job_id(_payload), do: nil

  defp import_run_id(%BackfillLifecycleEvent{event_type: event_type, backfill_run_id: run_id})
       when event_type in [
              :import_requested,
              :import_approved,
              :import_rejected,
              :import_started,
              :import_completed,
              :import_failed,
              :import_retried
            ],
       do: run_id

  defp import_run_id(%BackfillLifecycleEvent{}), do: nil

  defp fetch_required(attrs, key) when is_map(attrs) and is_atom(key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(attrs, Atom.to_string(key))
    end
  end

  defp normalize_actor(actor) when is_map(actor) do
    actor
    |> map_value()
    |> normalize_known_optional(:kind, @actor_kinds, :actor_kind)
    |> normalize_text_optional(:id)
    |> normalize_text_optional(:display_name)
    |> compact()
  end

  defp normalize_actor(_actor), do: %{kind: :system}

  defp normalize_subject(nil), do: nil

  defp normalize_subject(subject) when is_map(subject) do
    subject
    |> map_value()
    |> normalize_known_required(:kind, @subject_kinds, :subject_kind)
    |> normalize_text_required(:id)
    |> compact()
  end

  defp normalize_scope(scope) when is_map(scope), do: map_value(scope) |> compact()
  defp normalize_scope(_scope), do: %{}

  defp normalize_causality(causality) when is_map(causality) do
    causality
    |> map_value()
    |> normalize_text_optional(:correlation_id)
    |> normalize_text_optional(:causation_event_id)
    |> normalize_known_optional(:source_record_kind, @source_record_kinds, :source_record_kind)
    |> normalize_text_optional(:source_record_id)
    |> normalize_text_optional(:job_id)
    |> normalize_text_optional(:replay_run_id)
    |> normalize_text_optional(:import_run_id)
    |> compact()
  end

  defp normalize_causality(_causality), do: %{}

  defp normalize_known_required(map, key, known, label) do
    case fetch_map_value(map, key) do
      {:ok, value} -> put_normalized_value(map, key, known_atom!(value, known, label))
      :error -> raise KeyError, key: key, term: map
    end
  end

  defp normalize_known_optional(map, key, known, label) do
    case fetch_map_value(map, key) do
      {:ok, nil} -> Map.delete(map, key)
      {:ok, value} -> put_normalized_value(map, key, known_atom!(value, known, label))
      :error -> map
    end
  end

  defp normalize_text_required(map, key) do
    case fetch_map_value(map, key) do
      {:ok, value} -> put_normalized_value(map, key, text_value!(value))
      :error -> raise KeyError, key: key, term: map
    end
  end

  defp normalize_text_optional(map, key) do
    case fetch_map_value(map, key) do
      {:ok, nil} -> Map.delete(map, key)
      {:ok, value} -> put_normalized_value(map, key, text_value(value))
      :error -> map
    end
  end

  defp known_optional_atom!(nil, _known, _label), do: nil
  defp known_optional_atom!(value, known, label), do: known_atom!(value, known, label)

  defp known_atom!(value, known, label) when is_atom(value) do
    if value in known,
      do: value,
      else: raise(ArgumentError, "unsupported #{label}: #{inspect(value)}")
  end

  defp known_atom!(value, known, label) when is_binary(value) do
    Enum.find(known, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{label}: #{inspect(value)}"
  end

  defp known_atom!(value, _known, label),
    do: raise(ArgumentError, "unsupported #{label}: #{inspect(value)}")

  defp normalize_kind(value) when is_atom(value), do: value
  defp normalize_kind(value) when is_binary(value), do: String.to_existing_atom(value)

  defp map_value(value) when is_map(value), do: value

  defp map_value(_value), do: %{}

  defp fetch_map_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, Atom.to_string(key))
    end
  end

  defp put_normalized_value(map, key, value) when is_map(map) and is_atom(key) do
    map
    |> Map.delete(Atom.to_string(key))
    |> Map.put(key, value)
  end

  defp text_value(nil), do: nil
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)

  defp text_value!(value) do
    case text_value(value) do
      nil -> raise ArgumentError, "expected text value, got nil"
      value -> value
    end
  end

  defp compact(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}, []] end)
    |> Map.new()
  end
end
