defmodule Cadence.Dashboards.Sources.OperationalObservables.RuntimeActivity do
  @moduledoc """
  Materializes managed and transport runtime activity rows, frames, and revisions.

  The source adapter supplies runtime events, command verifier instances, and
  source identity. This module owns event normalization, request filtering,
  verifier enrichment, frame presentation, evidence, and revision projection
  for the two runtime activity products.
  """

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    RuntimeCacheKey,
    ScopeContext
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.OperationalState

  @managed_observable_id "runtime.managed_activity"
  @transport_observable_id "runtime.transport_activity"

  @managed_event_kinds [
    :managed_capability_initialized,
    :managed_capability_record_handled,
    :managed_capability_timer_handled,
    :managed_action_requested,
    :managed_timer_scheduled,
    :managed_timer_fired,
    :managed_timer_canceled
  ]

  @transport_event_kinds [
    :transport_initialized,
    :transport_event_handled,
    :transport_control_input_handled,
    :transport_timer_handled,
    :transport_action_requested,
    :transport_timer_scheduled,
    :transport_timer_fired,
    :transport_timer_canceled
  ]

  @managed_source_record_kinds [
    :managed_capability_record,
    :managed_action_request,
    :managed_timer_event
  ]

  @transport_source_record_kinds [
    :transport_capability_record,
    :transport_action_request,
    :transport_timer_event
  ]

  @spec resolve_managed(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_managed(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    events_fun =
      Keyword.get(opts, :managed_runtime_events_fun, &default_managed_events/3)

    events_fun.(organization_id, mission_id, adapter_opts)
    |> managed_rows(request)
    |> then(&managed_frame(request, &1, source_context))
  end

  @spec resolve_transport(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_transport(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    events_fun =
      Keyword.get(opts, :transport_runtime_events_fun, &default_transport_events/3)

    rows =
      events_fun.(organization_id, mission_id, adapter_opts)
      |> transport_rows(request)

    verifier_instances_fun =
      Keyword.get(
        opts,
        :command_verifier_instances_fun,
        &default_command_verifier_instances/3
      )

    verifier_instances =
      verifier_instances_fun.(
        organization_id,
        mission_id,
        Keyword.put(adapter_opts, :command_release_attempt_ids, command_release_attempt_ids(rows))
      )

    rows
    |> attach_verifier_outcomes(verifier_instances)
    |> then(&transport_frame(request, &1, source_context))
  end

  @spec managed_rows([term()], PlannedSourceRequest.t()) :: [map()]
  def managed_rows(events, %PlannedSourceRequest{} = request) do
    events
    |> Enum.filter(&matches_managed_scope?(&1, request))
    |> Enum.map(&managed_row/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&time_in_request_window?(&1.starts_at, request))
    |> Enum.sort_by(&datetime_sort_key(&1.starts_at))
    |> apply_request_limit(request)
  end

  @spec transport_rows([term()], PlannedSourceRequest.t()) :: [map()]
  def transport_rows(events, %PlannedSourceRequest{} = request) do
    events
    |> Enum.filter(&matches_transport_scope?(&1, request))
    |> Enum.map(&transport_row/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&time_in_request_window?(&1.starts_at, request))
    |> Enum.sort_by(&datetime_sort_key(&1.starts_at))
    |> apply_request_limit(request)
  end

  @spec attach_verifier_outcomes([map()], [term()]) :: [map()]
  def attach_verifier_outcomes(rows, command_verifier_instances)
      when is_list(rows) and is_list(command_verifier_instances) do
    verifier_instances_by_release_attempt_id =
      command_verifier_instances
      |> Enum.sort_by(&command_verifier_sort_key/1)
      |> Enum.group_by(&attr(&1, :command_release_attempt_id))

    Enum.map(rows, fn row ->
      verifier_instances =
        Map.get(
          verifier_instances_by_release_attempt_id,
          row.command_release_attempt_id,
          []
        )

      %{
        row
        | command_verifier_instances: verifier_instances,
          command_verifier_instance_ids:
            joined_attr_values(verifier_instances, :command_verifier_instance_id),
          command_verification_state: command_verification_state(verifier_instances),
          command_verifier_lifecycle_states:
            joined_attr_values(verifier_instances, :lifecycle_state),
          command_verifier_matched_record_ids:
            joined_attr_values(verifier_instances, :matched_record_id),
          command_verifier_failure_reasons:
            joined_attr_values(verifier_instances, :failure_reason)
      }
    end)
  end

  @spec command_release_attempt_ids([map()]) :: [binary()]
  def command_release_attempt_ids(rows) when is_list(rows) do
    rows
    |> Enum.map(& &1.command_release_attempt_id)
    |> present_text_values()
  end

  @spec command_release_attempt_ids_from_events([term()]) :: [binary()]
  def command_release_attempt_ids_from_events(events) when is_list(events) do
    events
    |> Enum.map(fn event ->
      event
      |> then(&(attr(&1, :payload) || attr(&1, :current)))
      |> attr(:command_release_attempt_id)
    end)
    |> present_text_values()
  end

  @spec managed_frame(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def managed_frame(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:managed_runtime_activity_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        time_field(rows),
        field("observable_id", :string, rows, :observable_id),
        field("resource_id", :string, rows, :resource_id),
        field("lane_id", :string, rows, :lane_id),
        field("label", :string, rows, :label),
        field("scope_kind", :enum, rows, :scope_kind),
        field("capability_instance_id", :string, rows, :capability_instance_id),
        field("family_key", :enum, rows, :family_key),
        field("activation_id", :string, rows, :activation_id),
        field("binding_set_id", :string, rows, :binding_set_id),
        field("packet_id", :string, rows, :packet_id),
        field("evidence_id", :string, rows, :evidence_id),
        field("timer_key", :string, rows, :timer_key),
        field("action_kind", :enum, rows, :action_kind),
        field("action_request_document_json", :string, rows, :action_request_document_json),
        field("record_event_kind", :enum, rows, :record_event_kind),
        field("emitted_record_kinds", :string, rows, :emitted_record_kinds),
        field("emitted_record_count", :number, rows, :emitted_record_count),
        field("action_request_count", :number, rows, :action_request_count),
        field("state_snapshot_json", :string, rows, :state_snapshot_json),
        field("record_metadata_json", :string, rows, :record_metadata_json),
        field("runtime_fact_kind", :enum, rows, :runtime_fact_kind),
        field("runtime_fact_id", :string, rows, :runtime_fact_id),
        field("source_event_id", :string, rows, :source_event_id),
        field("state", :enum, rows, :state),
        field("normalized_state", :enum, rows, :normalized_state)
      ],
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :event_history,
          supported_capability: :managed_runtime_activity_history,
          product_family: :runtime_managed,
          state_color_policy: :managed_runtime_activity,
          observable_ids: observable_ids(rows),
          observable_id: @managed_observable_id,
          runtime_fact_ids: runtime_fact_ids(rows),
          returned_points: length(rows),
          warning_codes: [],
          links: operational_links(request, rows),
          evidence_refs:
            DataLinks.operational_event_evidence_refs(rows, source: :operational_observables)
        })
    }
  end

  @spec transport_frame(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def transport_frame(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:transport_runtime_activity_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        time_field(rows),
        field("observable_id", :string, rows, :observable_id),
        field("resource_id", :string, rows, :resource_id),
        field("lane_id", :string, rows, :lane_id),
        field("label", :string, rows, :label),
        field("scope_kind", :enum, rows, :scope_kind),
        field("transport_id", :string, rows, :transport_id),
        field("contact_id", :string, rows, :contact_id),
        field("path_id", :string, rows, :path_id),
        field("source_endpoint_ref", :string, rows, :source_endpoint_ref),
        field("capability_instance_id", :string, rows, :capability_instance_id),
        field("family_key", :enum, rows, :family_key),
        field("activation_id", :string, rows, :activation_id),
        field("binding_set_id", :string, rows, :binding_set_id),
        field("timer_key", :string, rows, :timer_key),
        field("action_kind", :enum, rows, :action_kind),
        field("command_release_attempt_id", :string, rows, :command_release_attempt_id),
        field("command_request_id", :string, rows, :command_request_id),
        field("command_verifier_instance_ids", :string, rows, :command_verifier_instance_ids),
        field("command_verification_state", :enum, rows, :command_verification_state),
        field(
          "command_verifier_lifecycle_states",
          :string,
          rows,
          :command_verifier_lifecycle_states
        ),
        field(
          "command_verifier_matched_record_ids",
          :string,
          rows,
          :command_verifier_matched_record_ids
        ),
        field(
          "command_verifier_failure_reasons",
          :string,
          rows,
          :command_verifier_failure_reasons
        ),
        field("command_name", :string, rows, :command_name),
        field("signal_phase", :enum, rows, :signal_phase),
        field("action_request_document_json", :string, rows, :action_request_document_json),
        field("record_event_kind", :enum, rows, :record_event_kind),
        field("emitted_record_kinds", :string, rows, :emitted_record_kinds),
        field("emitted_record_count", :number, rows, :emitted_record_count),
        field("action_request_count", :number, rows, :action_request_count),
        field("state_snapshot_json", :string, rows, :state_snapshot_json),
        field("record_metadata_json", :string, rows, :record_metadata_json),
        field("runtime_fact_kind", :enum, rows, :runtime_fact_kind),
        field("runtime_fact_id", :string, rows, :runtime_fact_id),
        field("source_event_id", :string, rows, :source_event_id),
        field("state", :enum, rows, :state),
        field("normalized_state", :enum, rows, :normalized_state)
      ],
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :event_history,
          supported_capability: :transport_runtime_activity_history,
          product_family: :runtime_transport,
          state_color_policy: :transport_runtime_activity,
          observable_ids: observable_ids(rows),
          observable_id: @transport_observable_id,
          runtime_fact_ids: runtime_fact_ids(rows),
          returned_points: length(rows),
          warning_codes: [],
          links: operational_links(request, rows),
          evidence_refs: transport_evidence_refs(rows)
        })
    }
  end

  @spec managed_revision([term()]) :: binary()
  def managed_revision(events) do
    "managed_runtime_activity:" <>
      RuntimeCacheKey.fingerprint(%{
        events:
          events
          |> Enum.map(&event_revision_entry/1)
          |> Enum.sort_by(&{&1.source_event_id || "", &1.occurred_at || ""})
      })
  end

  @spec transport_revision([term()], [term()]) :: binary()
  def transport_revision(events, command_verifier_instances) do
    "transport_runtime_activity:" <>
      RuntimeCacheKey.fingerprint(%{
        events:
          events
          |> Enum.map(&event_revision_entry/1)
          |> Enum.sort_by(&{&1.source_event_id || "", &1.occurred_at || ""}),
        command_verifier_instances:
          command_verifier_instances
          |> Enum.map(&verifier_revision_entry/1)
          |> Enum.sort_by(&(&1.command_verifier_instance_id || ""))
      })
  end

  @spec default_managed_revision(binary(), binary(), keyword()) :: binary()
  def default_managed_revision(organization_id, mission_id, opts) do
    organization_id
    |> default_managed_events(mission_id, opts)
    |> managed_revision()
  end

  @spec default_transport_revision(binary(), binary(), keyword()) :: binary()
  def default_transport_revision(organization_id, mission_id, opts) do
    events = default_transport_events(organization_id, mission_id, opts)

    verifier_instances =
      default_command_verifier_instances(
        organization_id,
        mission_id,
        Keyword.put(
          opts,
          :command_release_attempt_ids,
          command_release_attempt_ids_from_events(events)
        )
      )

    transport_revision(events, verifier_instances)
  end

  defp default_managed_events(organization_id, mission_id, opts) do
    OperationalState.list_operational_events(
      organization_id,
      mission_id,
      managed_event_opts(opts)
    )
  end

  defp managed_event_opts(opts) do
    [
      category: :runtime,
      kind: @managed_event_kinds,
      source_record_kind: @managed_source_record_kinds,
      from_occurred_at: Keyword.get(opts, :from),
      to_occurred_at: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      order: :asc,
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp default_transport_events(organization_id, mission_id, opts) do
    OperationalState.list_operational_events(
      organization_id,
      mission_id,
      transport_event_opts(opts)
    )
  end

  defp transport_event_opts(opts) do
    [
      category: :comms,
      kind: @transport_event_kinds,
      source_record_kind: @transport_source_record_kinds,
      from_occurred_at: Keyword.get(opts, :from),
      to_occurred_at: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      order: :asc,
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp default_command_verifier_instances(organization_id, mission_id, opts) do
    case Keyword.get(opts, :command_release_attempt_ids, []) do
      [] ->
        []

      command_release_attempt_ids when is_list(command_release_attempt_ids) ->
        Enum.flat_map(command_release_attempt_ids, fn command_release_attempt_id ->
          OperationalState.list_command_verifier_instances(
            organization_id,
            mission_id,
            command_release_attempt_id
          )
        end)
    end
  end

  defp managed_row(event) do
    payload = attr(event, :payload) || attr(event, :current) || %{}
    causality = attr(event, :causality) || %{}
    source_record_kind = attr(causality, :source_record_kind)
    source_record_id = attr(causality, :source_record_id)
    event_kind = attr(event, :kind)

    capability_instance_id =
      attr(payload, :capability_instance_id) || event_subject_id(event)

    case attr(event, :occurred_at) do
      nil ->
        nil

      occurred_at ->
        %{
          observable_id: @managed_observable_id,
          resource_id: capability_instance_id,
          lane_id: capability_instance_id,
          label: managed_label(capability_instance_id),
          scope_kind: :mission,
          capability_instance_id: capability_instance_id,
          family_key: attr(payload, :family_key),
          activation_id: attr(payload, :activation_id),
          binding_set_id: attr(payload, :binding_set_id),
          packet_id: attr(payload, :packet_id),
          evidence_id: attr(payload, :evidence_id),
          timer_key: attr(payload, :timer_key),
          action_kind: attr(payload, :action_kind),
          action_request_document_json: deterministic_json(attr(payload, :request_document)),
          record_event_kind: attr(payload, :event_kind),
          emitted_record_kinds: emitted_record_kinds_text(attr(payload, :emitted_record_kinds)),
          emitted_record_count: attr(payload, :emitted_record_count),
          action_request_count: attr(payload, :action_request_count),
          state_snapshot_json: deterministic_json(attr(payload, :state_snapshot)),
          record_metadata_json: deterministic_json(attr(payload, :record_metadata)),
          runtime_fact_kind: source_record_kind,
          runtime_fact_id: source_record_id,
          source_event_id: attr(event, :event_id),
          state: event_kind,
          normalized_state: event_kind,
          starts_at: occurred_at,
          event: event
        }
    end
  end

  defp transport_row(event) do
    payload = attr(event, :payload) || attr(event, :current) || %{}
    causality = attr(event, :causality) || %{}
    source_record_kind = attr(causality, :source_record_kind)
    source_record_id = attr(causality, :source_record_id)
    event_kind = attr(event, :kind)
    transport_id = transport_id(payload, event)

    case attr(event, :occurred_at) do
      nil ->
        nil

      occurred_at ->
        %{
          observable_id: @transport_observable_id,
          resource_id: transport_id,
          lane_id: transport_id,
          label: transport_label(transport_id),
          scope_kind: :transport,
          transport_id: transport_id,
          contact_id: transport_contact_id(payload),
          path_id: attr(payload, :path_id),
          source_endpoint_ref: attr(payload, :source_endpoint_ref),
          capability_instance_id: transport_id,
          family_key: attr(payload, :family_key),
          activation_id: attr(payload, :activation_id),
          binding_set_id: attr(payload, :binding_set_id),
          timer_key: attr(payload, :timer_key),
          action_kind: attr(payload, :action_kind),
          command_release_attempt_id: attr(payload, :command_release_attempt_id),
          command_request_id: attr(payload, :command_request_id),
          command_verifier_instances: [],
          command_verifier_instance_ids: nil,
          command_verification_state: nil,
          command_verifier_lifecycle_states: nil,
          command_verifier_matched_record_ids: nil,
          command_verifier_failure_reasons: nil,
          command_name: attr(payload, :command_name),
          signal_phase: attr(payload, :signal_phase),
          action_request_document_json: deterministic_json(attr(payload, :request_document)),
          record_event_kind: attr(payload, :event_kind),
          emitted_record_kinds: emitted_record_kinds_text(attr(payload, :emitted_record_kinds)),
          emitted_record_count: attr(payload, :emitted_record_count),
          action_request_count: attr(payload, :action_request_count),
          state_snapshot_json: deterministic_json(attr(payload, :state_snapshot)),
          record_metadata_json: transport_record_metadata_json(payload),
          runtime_fact_kind: source_record_kind,
          runtime_fact_id: source_record_id,
          source_event_id: attr(event, :event_id),
          state: event_kind,
          normalized_state: event_kind,
          starts_at: occurred_at,
          event: event
        }
    end
  end

  defp matches_managed_scope?(event, request) do
    payload = attr(event, :payload) || attr(event, :current) || %{}

    attr(event, :kind) in @managed_event_kinds and
      matches_scope_id?(attr(payload, :partition_value), scope_ids(request, :spacecraft))
  end

  defp matches_transport_scope?(event, request) do
    payload = attr(event, :payload) || attr(event, :current) || %{}

    attr(event, :kind) in @transport_event_kinds and
      matches_scope_id?(attr(payload, :capability_instance_id), scope_ids(request, :transport)) and
      matches_scope_id?(
        attr(payload, :contact_id) || attr(payload, :realized_contact_id),
        scope_ids(request, :contact)
      ) and
      matches_scope_id?(
        attr(payload, :source_endpoint_ref),
        scope_ids(request, :source_endpoint)
      ) and
      matches_scope_id?(attr(payload, :path_id), scope_ids(request, :link))
  end

  defp transport_evidence_refs(rows) do
    verifier_instances = Enum.flat_map(rows, & &1.command_verifier_instances)

    rows
    |> DataLinks.operational_event_evidence_refs(source: :operational_observables)
    |> Kernel.++(
      DataLinks.command_release_attempt_evidence_refs(rows, source: :operational_observables)
    )
    |> Kernel.++(
      DataLinks.command_verifier_instance_evidence_refs(verifier_instances,
        source: :operational_observables
      )
    )
    |> Kernel.++(
      DataLinks.command_verifier_matched_record_evidence_refs(verifier_instances,
        source: :operational_observables
      )
    )
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  defp operational_links(request, rows) do
    DataLinks.operational_resource_links(request, rows, source: :frame) ++
      DataLinks.operational_event_links(request, rows, source: :frame)
  end

  defp event_revision_entry(event) do
    causality = attr(event, :causality) || %{}

    %{
      source_event_id: attr(event, :event_id),
      source_record_kind: attr(causality, :source_record_kind),
      source_record_id: attr(causality, :source_record_id),
      kind: attr(event, :kind),
      occurred_at: attr(event, :occurred_at),
      replay_run_id: attr(event, :replay_run_id)
    }
  end

  defp verifier_revision_entry(verifier_instance) do
    %{
      command_verifier_instance_id: attr(verifier_instance, :command_verifier_instance_id),
      command_release_attempt_id: attr(verifier_instance, :command_release_attempt_id),
      command_request_id: attr(verifier_instance, :command_request_id),
      phase: attr(verifier_instance, :phase),
      severity: attr(verifier_instance, :severity),
      lifecycle_state: attr(verifier_instance, :lifecycle_state),
      matched_record_kind: attr(verifier_instance, :matched_record_kind),
      matched_record_id: attr(verifier_instance, :matched_record_id),
      matched_at: attr(verifier_instance, :matched_at),
      failure_reason: attr(verifier_instance, :failure_reason)
    }
  end

  defp command_verifier_sort_key(verifier_instance) do
    {
      datetime_sort_key(attr(verifier_instance, :matched_at)),
      attr(verifier_instance, :command_verifier_instance_id) || ""
    }
  end

  defp joined_attr_values(items, key) when is_list(items) do
    items
    |> Enum.map(&attr(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> case do
      [] -> nil
      values -> Enum.join(values, ",")
    end
  end

  defp command_verification_state([]), do: nil

  defp command_verification_state(verifier_instances) when is_list(verifier_instances) do
    lifecycle_states = Enum.map(verifier_instances, &attr(&1, :lifecycle_state))

    cond do
      Enum.any?(lifecycle_states, &(&1 in [:failed, "failed"])) -> :failed
      Enum.any?(lifecycle_states, &(&1 in [:timed_out, "timed_out"])) -> :timed_out
      Enum.any?(lifecycle_states, &(&1 in [:pending, "pending"])) -> :pending
      Enum.all?(lifecycle_states, &(&1 in [:satisfied, "satisfied"])) -> :satisfied
      true -> nil
    end
  end

  defp managed_label(capability_instance_id)
       when is_binary(capability_instance_id) and capability_instance_id != "" do
    "Managed runtime / #{capability_instance_id}"
  end

  defp managed_label(_capability_instance_id), do: "Managed runtime"

  defp transport_label(transport_id) when is_binary(transport_id) and transport_id != "" do
    "Transport runtime / #{transport_id}"
  end

  defp transport_label(_transport_id), do: "Transport runtime"

  defp transport_id(payload, event) do
    attr(payload, :capability_instance_id) || event_subject_id(event)
  end

  defp transport_contact_id(payload) do
    attr(payload, :contact_id) || attr(payload, :realized_contact_id)
  end

  defp transport_record_metadata_json(payload) do
    deterministic_json(
      attr(payload, :record_metadata) ||
        attr(payload, :action_metadata) ||
        attr(payload, :timer_metadata)
    )
  end

  defp event_subject_id(event), do: event |> attr(:subject) |> attr(:id)

  defp emitted_record_kinds_text(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.sort()
    |> Enum.join(",")
  end

  defp emitted_record_kinds_text(_values), do: nil

  defp deterministic_json(value) when is_map(value) and map_size(value) > 0 do
    value
    |> JsonDocument.encode()
    |> Jason.encode!()
  end

  defp deterministic_json(_value), do: nil

  defp runtime_fact_ids(rows) do
    rows
    |> values(:runtime_fact_id)
    |> present_text_values()
  end

  defp present_text_values(values) do
    values
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp time_field(rows) do
    %Field{
      name: "time",
      kind: :time,
      values: values(rows, :starts_at),
      metadata: %{axis: :occurred_at}
    }
  end

  defp field(name, kind, rows, key) do
    %Field{name: name, kind: kind, values: values(rows, key)}
  end

  defp values(rows, key), do: Enum.map(rows, &attr(&1, key))

  defp observable_ids(rows) do
    rows
    |> values(:observable_id)
    |> Enum.uniq()
  end

  defp scope_ids(%PlannedSourceRequest{} = request, kind) do
    primary_ids =
      if ScopeContext.primary_kind(request.scope_context) in [kind, Atom.to_string(kind)] do
        ScopeContext.primary_ids(request.scope_context)
      else
        []
      end

    typed_id = ScopeContext.scope_id(request.scope_context, kind)

    [typed_id | primary_ids]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp matches_scope_id?(_value, []), do: true
  defp matches_scope_id?(value, ids), do: value in ids

  defp time_in_request_window?(%DateTime{} = time, %PlannedSourceRequest{} = request) do
    from_time = request_time_bound(request, [:from, :start, :start_time])
    to_time = request_time_bound(request, [:to, :end, :end_time])

    after_from? = is_nil(from_time) or DateTime.compare(time, from_time) != :lt
    before_to? = is_nil(to_time) or DateTime.compare(time, to_time) != :gt

    after_from? and before_to?
  end

  defp time_in_request_window?(_time, _request), do: false

  defp request_time_bound(%PlannedSourceRequest{} = request, keys) do
    request.time_context
    |> first_context_value(keys)
    |> normalize_time_bound()
  end

  defp first_context_value(context, keys), do: Enum.find_value(keys, &context_value(context, &1))

  defp normalize_time_bound(nil), do: nil
  defp normalize_time_bound(%DateTime{} = value), do: value

  defp normalize_time_bound(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp normalize_time_bound(_value), do: nil

  defp apply_request_limit(rows, %PlannedSourceRequest{} = request) do
    case context_value(request.sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> Enum.take(rows, limit)
      _other -> rows
    end
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp datetime_sort_key(_datetime), do: 0

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil
end
