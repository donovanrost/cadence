defmodule Cadence.Dashboards.DataLinks do
  @moduledoc """
  Builders for dashboard data links and evidence references.

  Source adapters attach these typed references to frames, fields, and warnings.
  The web layer can render or route them without needing source-specific map
  conventions.
  """

  alias Cadence.Dashboards.{DataContext, DataLink, EvidenceRef, PlannedSourceRequest}
  alias Cadence.Dashboards.DataLinks.EvidenceRefs

  @spec request_context(PlannedSourceRequest.t(), binary() | nil, keyword()) :: map()
  def request_context(%PlannedSourceRequest{} = request, observable_id \\ nil, opts \\ []) do
    %{
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      observable_id: observable_id,
      scope: context_map(request.scope_context),
      time: context_map(request.time_context),
      data: request_data_context(request, opts),
      limit: context_map(request.limit_context),
      sampling: context_map(request.sampling)
    }
    |> drop_empty_values()
  end

  defp request_data_context(%PlannedSourceRequest{} = request, opts) do
    data_context = context_map(request.data_context)
    source_binding = Keyword.get(opts, :source_binding)

    data_context
    |> maybe_put(:realm, inferred_replay_realm(request))
    |> maybe_put(
      :view,
      DataContext.source_value(request.data_context, request.logical_source, :view)
    )
    |> maybe_put(
      :validity_state,
      DataContext.source_value(request.data_context, request.logical_source, :validity_state)
    )
    |> maybe_put(
      :replay_run_id,
      DataContext.source_value(request.data_context, request.logical_source, :replay_run_id)
    )
    |> maybe_put(
      :data_source_id,
      source_binding_data_source_id(source_binding) ||
        DataContext.source_value(request.data_context, request.logical_source, :data_source_id)
    )
    |> maybe_put(
      :source_binding_id,
      source_binding_id(source_binding) ||
        DataContext.source_value(request.data_context, request.logical_source, :source_binding_id)
    )
    |> maybe_put(
      :dataset,
      source_binding_dataset(source_binding) ||
        DataContext.source_value(request.data_context, request.logical_source, :dataset)
    )
  end

  @spec telemetry_point_link(PlannedSourceRequest.t(), binary() | nil, keyword()) ::
          DataLink.t() | nil
  def telemetry_point_link(%PlannedSourceRequest{} = request, observable_id, opts \\ []) do
    case string_id(observable_id) do
      nil ->
        nil

      point_id ->
        data_link(
          :telemetry_point,
          Keyword.get(opts, :label, "Telemetry point"),
          point_id,
          request_context(request, point_id, opts),
          opts
        )
    end
  end

  @spec telemetry_sample_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) ::
          [DataLink.t()]
  def telemetry_sample_links(%PlannedSourceRequest{} = request, samples, opts \\ []) do
    samples
    |> List.wrap()
    |> Enum.map(fn sample ->
      sample
      |> attr(:sample_id)
      |> string_id()
      |> case do
        nil ->
          nil

        sample_id ->
          observable_id = attr(sample, :point_id)

          data_link(
            :telemetry_sample,
            Keyword.get(opts, :label, "Telemetry sample"),
            sample_id,
            request_context(request, observable_id, opts),
            opts
          )
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec telemetry_sample_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  defdelegate telemetry_sample_evidence_refs(samples), to: EvidenceRefs

  @spec telemetry_links(PlannedSourceRequest.t(), binary() | nil, [map() | struct()], keyword()) ::
          [DataLink.t()]
  def telemetry_links(%PlannedSourceRequest{} = request, observable_id, samples, opts \\ []) do
    [
      telemetry_point_link(request, observable_id, opts)
      | telemetry_sample_links(request, samples, opts)
    ]
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec limit_links(PlannedSourceRequest.t(), binary() | nil, [map() | struct()], keyword()) ::
          [DataLink.t()]
  def limit_links(%PlannedSourceRequest{} = request, observable_id, events, opts \\ []) do
    events = List.wrap(events)

    [
      telemetry_point_link(request, observable_id, opts)
      | limit_event_links(request, events, opts) ++
          limit_definition_links(request, events, opts) ++
          telemetry_sample_links(request, events, opts)
    ]
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec limit_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  defdelegate limit_event_evidence_refs(events), to: EvidenceRefs
  @spec limit_definition_interval_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  defdelegate limit_definition_interval_evidence_refs(intervals), to: EvidenceRefs
  @spec operational_interval_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def operational_interval_evidence_refs(intervals, opts \\ []),
    do: EvidenceRefs.operational_interval_evidence_refs(intervals, opts)

  @spec mission_event_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) ::
          [DataLink.t()]
  def mission_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.map(fn event ->
      event
      |> attr(:mission_event_id)
      |> string_id()
      |> case do
        nil ->
          nil

        event_id ->
          data_link(
            :mission_event,
            Keyword.get(opts, :label, "Mission event"),
            event_id,
            request_context(request, attr(event, :subject_id), opts),
            opts
          )
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec operational_event_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) :: [
          DataLink.t()
        ]
  def operational_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.map(fn event ->
      event
      |> attr(:source_event_id)
      |> string_id()
      |> event_link(
        :operational_event,
        Keyword.get(opts, :label, "Operational event"),
        request_context(request, operational_event_subject_id(event), opts),
        opts
      )
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec operational_event_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def operational_event_evidence_refs(events, opts \\ []),
    do: EvidenceRefs.operational_event_evidence_refs(events, opts)

  @spec command_queue_entry_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def command_queue_entry_evidence_refs(entries, opts \\ []),
    do: EvidenceRefs.command_queue_entry_evidence_refs(entries, opts)

  @spec command_release_attempt_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def command_release_attempt_evidence_refs(attempts, opts \\ []),
    do: EvidenceRefs.command_release_attempt_evidence_refs(attempts, opts)

  @spec command_verifier_instance_evidence_refs([map() | struct()], keyword()) :: [
          EvidenceRef.t()
        ]
  def command_verifier_instance_evidence_refs(verifier_instances, opts \\ []),
    do: EvidenceRefs.command_verifier_instance_evidence_refs(verifier_instances, opts)

  @spec command_verifier_matched_record_evidence_refs([map() | struct()], keyword()) :: [
          EvidenceRef.t()
        ]
  def command_verifier_matched_record_evidence_refs(verifier_instances, opts \\ []),
    do: EvidenceRefs.command_verifier_matched_record_evidence_refs(verifier_instances, opts)

  @spec mission_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  defdelegate mission_event_evidence_refs(events), to: EvidenceRefs

  @spec source_health_event_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) ::
          [DataLink.t()]
  def source_health_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.flat_map(fn event ->
      context = request_context(request, attr(event, :source_health_key), opts)

      [
        event
        |> attr(:source_health_event_id)
        |> string_id()
        |> event_link(:source_health_event, "Source health event", context, opts),
        operational_event_link(
          request,
          :source_health_event,
          attr(event, :source_health_event_id),
          attr(event, :source_health_key),
          opts,
          attr(event, :replay_run_id)
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec source_health_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  defdelegate source_health_event_evidence_refs(events), to: EvidenceRefs

  @spec source_watermark_event_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) ::
          [DataLink.t()]
  def source_watermark_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.flat_map(fn event ->
      context = request_context(request, attr(event, :source_watermark_key), opts)

      [
        event
        |> attr(:source_watermark_event_id)
        |> string_id()
        |> event_link(:source_watermark_event, "Source watermark event", context, opts),
        operational_event_link(
          request,
          :source_watermark_event,
          attr(event, :source_watermark_event_id),
          attr(event, :source_watermark_key),
          opts,
          attr(event, :replay_run_id)
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec source_watermark_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  defdelegate source_watermark_event_evidence_refs(events), to: EvidenceRefs

  @spec source_capability_posture_event_links(
          PlannedSourceRequest.t(),
          [map() | struct()],
          keyword()
        ) ::
          [DataLink.t()]
  def source_capability_posture_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.map(fn event ->
      operational_event_link(
        request,
        :source_capability_posture,
        source_capability_posture_operational_event_id(event),
        source_capability_posture_subject_id(event),
        opts
      )
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec source_capability_posture_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  defdelegate source_capability_posture_event_evidence_refs(events), to: EvidenceRefs
  @spec source_binding_interval_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def source_binding_interval_evidence_refs(intervals, opts \\ []),
    do: EvidenceRefs.source_binding_interval_evidence_refs(intervals, opts)

  @spec telemetry_revision_decision_event_links(
          PlannedSourceRequest.t(),
          [map() | struct()],
          keyword()
        ) :: [DataLink.t()]
  def telemetry_revision_decision_event_links(
        %PlannedSourceRequest{} = request,
        events,
        opts \\ []
      ) do
    events
    |> List.wrap()
    |> Enum.flat_map(fn event ->
      subject_id = attr(event, :observable_id) || attr(event, :point_id)
      context = request_context(request, subject_id, opts)

      [
        event
        |> attr(:decision_event_id)
        |> string_id()
        |> event_link(
          :telemetry_revision_decision_event,
          "Telemetry revision decision event",
          context,
          opts
        ),
        operational_event_link(
          request,
          :telemetry_observation_identity_decision_event,
          attr(event, :decision_event_id),
          subject_id,
          opts
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec telemetry_revision_decision_event_evidence_refs([map() | struct()]) :: [
          EvidenceRef.t()
        ]
  defdelegate telemetry_revision_decision_event_evidence_refs(events), to: EvidenceRefs

  @spec telemetry_backfill_lifecycle_event_links(
          PlannedSourceRequest.t(),
          [map() | struct()],
          keyword()
        ) :: [DataLink.t()]
  def telemetry_backfill_lifecycle_event_links(
        %PlannedSourceRequest{} = request,
        events,
        opts \\ []
      ) do
    events
    |> List.wrap()
    |> Enum.flat_map(fn event ->
      subject_id = attr(event, :observable_id) || attr(event, :point_id)
      context = request_context(request, subject_id, opts)

      [
        event
        |> attr(:backfill_lifecycle_event_id)
        |> string_id()
        |> event_link(
          :telemetry_backfill_lifecycle_event,
          "Telemetry backfill lifecycle event",
          context,
          opts
        ),
        operational_event_link(
          request,
          :telemetry_backfill_lifecycle_event,
          attr(event, :backfill_lifecycle_event_id),
          subject_id,
          opts
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec telemetry_backfill_lifecycle_event_evidence_refs([map() | struct()]) :: [
          EvidenceRef.t()
        ]
  defdelegate telemetry_backfill_lifecycle_event_evidence_refs(events), to: EvidenceRefs
  @spec contact_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) :: [DataLink.t()]
  def contact_links(%PlannedSourceRequest{} = request, contacts, opts \\ []) do
    contacts
    |> List.wrap()
    |> Enum.map(fn contact ->
      contact
      |> contact_id()
      |> string_id()
      |> case do
        nil ->
          nil

        contact_id ->
          data_link(
            :contact,
            Keyword.get(opts, :label, "Contact"),
            contact_id,
            request_context(request, contact_id, opts),
            opts
          )
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec operational_resource_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) :: [
          DataLink.t()
        ]
  def operational_resource_links(%PlannedSourceRequest{} = request, rows, opts \\ []) do
    rows
    |> List.wrap()
    |> Enum.flat_map(&operational_resource_row_links(request, &1, opts))
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec contact_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  defdelegate contact_evidence_refs(contacts), to: EvidenceRefs
  @spec request_observable_links(PlannedSourceRequest.t(), keyword()) :: [DataLink.t()]
  def request_observable_links(%PlannedSourceRequest{} = request, opts \\ []) do
    request.observables
    |> List.wrap()
    |> Enum.take(1)
    |> Enum.map(&telemetry_point_link(request, &1, opts))
    |> Enum.reject(&is_nil/1)
  end

  defp limit_event_links(%PlannedSourceRequest{} = request, events, opts) do
    Enum.map(events, fn event ->
      event
      |> attr(:limit_event_id)
      |> string_id()
      |> case do
        nil ->
          nil

        event_id ->
          data_link(
            :limit_event,
            Keyword.get(opts, :label, "Limit event"),
            event_id,
            request_context(request, attr(event, :point_id), opts),
            opts
          )
      end
    end)
  end

  defp limit_definition_links(%PlannedSourceRequest{} = request, events, opts) do
    Enum.map(events, fn event ->
      event
      |> attr(:limit_definition_id)
      |> string_id()
      |> case do
        nil ->
          nil

        definition_id ->
          data_link(
            :limit_definition,
            Keyword.get(opts, :definition_label, "Limit definition"),
            definition_id,
            request_context(request, attr(event, :point_id), opts),
            opts
          )
      end
    end)
  end

  defp operational_resource_row_links(%PlannedSourceRequest{} = request, row, opts) do
    [
      operational_resource_link(
        request,
        :transport,
        attr(row, :transport_id),
        Keyword.get(opts, :transport_label, "Transport"),
        row,
        opts
      ),
      operational_resource_link(
        request,
        :source_endpoint,
        attr(row, :source_endpoint_id),
        Keyword.get(opts, :source_endpoint_label, "Source endpoint"),
        row,
        opts
      ),
      operational_resource_link(
        request,
        :ground_station,
        attr(row, :ground_station_id),
        Keyword.get(opts, :ground_station_label, "Ground station"),
        row,
        opts
      ),
      operational_resource_link(
        request,
        :link,
        attr(row, :link_id),
        Keyword.get(opts, :link_label, "Link"),
        row,
        opts
      ),
      operational_resource_link(
        request,
        :contact,
        attr(row, :contact_id),
        Keyword.get(opts, :contact_label, "Contact"),
        row,
        opts
      )
    ]
  end

  defp operational_resource_link(%PlannedSourceRequest{} = request, target, id, label, row, opts) do
    case string_id(id) do
      nil ->
        nil

      target_id ->
        context =
          request
          |> request_context(attr(row, :observable_id), opts)
          |> maybe_put(:operational_resource, operational_resource_context(row))

        data_link(target, label, target_id, context, opts)
    end
  end

  defp operational_resource_context(row) do
    %{
      resource_id: attr(row, :resource_id),
      scope_kind: attr(row, :scope_kind),
      transport_id: attr(row, :transport_id),
      source_endpoint_id: attr(row, :source_endpoint_id),
      ground_station_id: attr(row, :ground_station_id),
      link_id: attr(row, :link_id),
      contact_id: attr(row, :contact_id),
      adapter_key: attr(row, :adapter_key)
    }
    |> drop_empty_values()
  end

  defp contact_id(contact) do
    attr(contact, :realized_contact_id) || attr(contact, :scheduled_contact_id)
  end

  defp operational_event_subject_id(event) do
    [
      :subject_id,
      :contact_id,
      :scheduled_contact_id,
      :realized_contact_id,
      :transport_id,
      :source_endpoint_id,
      :ground_station_id,
      :link_id,
      :resource_id,
      :source_record_id
    ]
    |> Enum.find_value(&attr(event, &1))
  end

  defp event_link(nil, _target, _label, _context, _opts), do: nil

  defp event_link(event_id, target, default_label, context, opts) do
    data_link(
      target,
      Keyword.get(opts, :label, default_label),
      event_id,
      context,
      opts
    )
  end

  defp operational_event_link(
         %PlannedSourceRequest{} = request,
         source_record_kind,
         source_record_id,
         subject_id,
         opts,
         replay_run_id \\ nil
       ) do
    source_record_kind
    |> canonical_operational_event_id(source_record_id, replay_run_id)
    |> event_link(
      :operational_event,
      "Canonical operational event",
      request_context(request, subject_id, opts),
      opts
    )
  end

  defp canonical_operational_event_id(_source_record_kind, nil), do: nil

  defp canonical_operational_event_id(source_record_kind, source_record_id) do
    canonical_operational_event_id(source_record_kind, source_record_id, nil)
  end

  defp canonical_operational_event_id(_source_record_kind, nil, _replay_run_id), do: nil

  defp canonical_operational_event_id(source_record_kind, source_record_id, replay_run_id) do
    case {source_record_kind, string_id(source_record_id)} do
      {:source_capability_posture, "operational_event:" <> _rest = event_id} ->
        event_id

      {:source_capability_posture, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_capability_posture, event_id, replay_run_id)

      {:source_health_event, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_health_event, event_id, replay_run_id)

      {:source_watermark_event, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_watermark_event, event_id, replay_run_id)

      {:telemetry_backfill_lifecycle_event, event_id} when is_binary(event_id) ->
        "operational_event:telemetry_backfill_lifecycle_event:#{event_id}"

      {:telemetry_observation_identity_decision_event, event_id} when is_binary(event_id) ->
        "operational_event:telemetry_observation_identity_decision_event:#{event_id}"

      _other ->
        nil
    end
  end

  defp scoped_operational_event_id(source_record_kind, source_record_id, replay_run_id)
       when is_binary(replay_run_id) and replay_run_id != "" do
    "operational_event:#{source_record_kind}:#{replay_run_id}:#{source_record_id}"
  end

  defp scoped_operational_event_id(source_record_kind, source_record_id, _replay_run_id) do
    "operational_event:#{source_record_kind}:#{source_record_id}"
  end

  defp data_link(target, label, target_id, context, opts) do
    %DataLink{
      link_id: Keyword.get(opts, :link_id, link_id(target, target_id, context)),
      label: label,
      target: target,
      target_id: target_id,
      route: Keyword.get(opts, :route),
      context: context,
      presentation: Keyword.get(opts, :presentation, :side_panel),
      source: Keyword.get(opts, :source, :field)
    }
  end

  defp link_id(target, target_id, context) do
    [target, target_id, Map.get(context, :source_request_id)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(":", &to_string/1)
  end

  defp dedupe_links(links) do
    Enum.uniq_by(links, &{&1.target, &1.target_id, &1.source})
  end

  defp context_map(nil), do: %{}

  defp context_map(%_struct{} = context) do
    context
    |> Map.from_struct()
    |> drop_empty_values()
  end

  defp context_map(context) when is_map(context), do: drop_empty_values(context)
  defp context_map(context), do: context

  defp inferred_replay_realm(%PlannedSourceRequest{
         data_context: data_context,
         time_context: time_context
       }) do
    cond do
      explicit_realm?(data_context) ->
        nil

      normalized_time_mode(attr(time_context, :mode)) == :replay_run ->
        :replay

      true ->
        nil
    end
  end

  defp explicit_realm?(data_context) when is_map(data_context) do
    Map.has_key?(data_context, :realm) or Map.has_key?(data_context, "realm")
  end

  defp explicit_realm?(_data_context), do: false

  defp normalized_time_mode(value) when is_atom(value), do: value

  defp normalized_time_mode(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> case do
      "replay_run" -> :replay_run
      other -> other
    end
  end

  defp normalized_time_mode(value), do: value

  defp drop_empty_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> empty_value?(value) end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp source_binding_id(%{binding: binding}), do: attr(binding, :binding_id)
  defp source_binding_id(source_binding), do: attr(source_binding, :binding_id)

  defp source_binding_data_source_id(%{data_source: data_source}),
    do: attr(data_source, :data_source_id)

  defp source_binding_data_source_id(source_binding), do: attr(source_binding, :data_source_id)

  defp source_binding_dataset(%{binding: binding}), do: attr(binding, :dataset)
  defp source_binding_dataset(source_binding), do: attr(source_binding, :dataset)

  defp empty_value?(nil), do: true
  defp empty_value?(%{} = map), do: map_size(map) == 0
  defp empty_value?([]), do: true
  defp empty_value?(_value), do: false

  defp source_capability_posture_operational_event_id(event) do
    attr(event, :event_id) ||
      canonical_operational_event_id(
        :source_capability_posture,
        event |> attr(:causality) |> attr(:source_record_id)
      )
  end

  defp source_capability_posture_subject_id(event) do
    event
    |> attr(:subject)
    |> attr(:id)
  end

  defp attr(item, key) when is_map(item) and is_atom(key) do
    Map.get(item, key, Map.get(item, Atom.to_string(key)))
  end

  defp attr(_item, _key), do: nil

  defp string_id(value) when is_binary(value) and value != "", do: value
  defp string_id(_value), do: nil
end
