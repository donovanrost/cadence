defmodule Cadence.OperationalEvents.Event do
  @moduledoc """
  Canonical operational event envelope.

  This is the domain boundary for facts that should project into mission
  timelines, dashboard overlays, audit views, and future effective-interval
  projections. It is intentionally store-agnostic for the first slice: existing
  subsystem records can be converted into this envelope before projection.
  """

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.OperationalEvents.Event.{Normalization, RuntimeEvents, SourceEvents}

  import Normalization

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
        activation_id: activation.activation_id,
        generation: activation.generation,
        binding_set_content_sha256: activation.binding_set_content_sha256
      },
      current: %{
        binding_set_id: activation.binding_set_id,
        binding_set_version: activation.binding_set_version,
        activation_id: activation.activation_id,
        generation: activation.generation,
        binding_set_content_sha256: activation.binding_set_content_sha256
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
    RuntimeEvents.from_operational_observable_state_snapshot(attrs, &new/1)
  end

  @spec from_operational_observable_metric_sample(map()) :: t()
  def from_operational_observable_metric_sample(attrs) when is_map(attrs) do
    RuntimeEvents.from_operational_observable_metric_sample(attrs, &new/1)
  end

  @spec from_transport_capability_record(TransportCapabilityRecord.t(), binary() | nil) :: t()
  def from_transport_capability_record(
        %TransportCapabilityRecord{} = capability_record,
        replay_run_id \\ nil
      ) do
    RuntimeEvents.from_transport_capability_record(capability_record, replay_run_id, &new/1)
  end

  @spec from_transport_action_request(TransportActionRequest.t(), binary() | nil) :: t()
  def from_transport_action_request(
        %TransportActionRequest{} = action_request,
        replay_run_id \\ nil
      ) do
    RuntimeEvents.from_transport_action_request(action_request, replay_run_id, &new/1)
  end

  @spec from_transport_timer_event(TransportTimerEvent.t(), binary() | nil) :: t()
  def from_transport_timer_event(%TransportTimerEvent{} = timer_event, replay_run_id \\ nil) do
    RuntimeEvents.from_transport_timer_event(timer_event, replay_run_id, &new/1)
  end

  @spec from_managed_capability_record(ManagedCapabilityRecord.t(), binary() | nil) :: t()
  def from_managed_capability_record(
        %ManagedCapabilityRecord{} = capability_record,
        replay_run_id \\ nil
      ) do
    RuntimeEvents.from_managed_capability_record(capability_record, replay_run_id, &new/1)
  end

  @spec from_managed_action_request(ManagedActionRequest.t(), binary() | nil) :: t()
  def from_managed_action_request(%ManagedActionRequest{} = action_request, replay_run_id \\ nil) do
    RuntimeEvents.from_managed_action_request(action_request, replay_run_id, &new/1)
  end

  @spec from_managed_timer_event(ManagedTimerEvent.t(), binary() | nil) :: t()
  def from_managed_timer_event(%ManagedTimerEvent{} = timer_event, replay_run_id \\ nil) do
    RuntimeEvents.from_managed_timer_event(timer_event, replay_run_id, &new/1)
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
    SourceEvents.from_dashboard_lifecycle_event(lifecycle_event, &new/1)
  end

  @spec from_data_binding_event(DataBindingEvent.t()) :: t()
  def from_data_binding_event(%DataBindingEvent{} = binding_event) do
    SourceEvents.from_data_binding_event(binding_event, &new/1)
  end

  @spec from_source_capability_posture(map()) :: t()
  def from_source_capability_posture(attrs) when is_map(attrs) do
    SourceEvents.from_source_capability_posture(attrs, &new/1)
  end

  @spec from_source_health_event(SourceHealthEvent.t()) :: t()
  def from_source_health_event(%SourceHealthEvent{} = source_event) do
    SourceEvents.from_source_health_event(source_event, &new/1)
  end

  @spec from_source_watermark_event(SourceWatermarkEvent.t()) :: t()
  def from_source_watermark_event(%SourceWatermarkEvent{} = source_event) do
    SourceEvents.from_source_watermark_event(source_event, &new/1)
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
end
