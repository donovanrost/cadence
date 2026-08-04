defmodule Cadence.Dashboards.Sources.OperationalObservables.CommandQueueDepth do
  @moduledoc """
  Materializes command queue depth rows, frames, and revision fingerprints.

  The source adapter supplies queue entries and source identity. This module
  owns queue scoping, pending-entry aggregation, frame presentation, and the
  durable revision projection for the command queue depth observable.
  """

  alias Cadence.Dashboards.Sources.OperationalObservables.LatestFreshness

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    RuntimeCacheKey,
    ScopeContext
  }

  alias Cadence.Reads.OperationalState

  @observable_id "commanding.queue_depth"

  @spec resolve(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    entries_fun =
      Keyword.get(opts, :command_queue_entries_fun, &default_entries/3)

    request
    |> then(
      &rows(
        entries_fun.(organization_id, mission_id, adapter_opts),
        &1,
        mission_id,
        Keyword.get(opts, :read_time, DateTime.utc_now())
      )
    )
    |> LatestFreshness.annotate(request, opts)
    |> then(&frame(request, &1, source_context))
  end

  @spec rows([term()], PlannedSourceRequest.t(), term(), DateTime.t()) :: [map()]
  def rows(entries, %PlannedSourceRequest{} = request, mission_id, observed_at) do
    entries =
      Enum.filter(
        entries,
        &(pending?(&1) and matches_scope?(&1, request))
      )

    {scope_kind, resource_id, scope_ids} = depth_scope(request, mission_id)

    [
      %{
        observable_id: @observable_id,
        resource_id: resource_id,
        label: depth_label(scope_kind, resource_id),
        scope_kind: scope_kind,
        source_endpoint_id: depth_source_endpoint_id(scope_kind, scope_ids),
        value: length(entries),
        unit: "commands",
        observed_at: observed_at,
        source: %{entries: entries}
      }
    ]
  end

  @spec frame(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def frame(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:command_queue_depth",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        field("observable_id", :string, rows, :observable_id),
        field("resource_id", :string, rows, :resource_id),
        field("label", :string, rows, :label),
        field("scope_kind", :enum, rows, :scope_kind),
        field("source_endpoint_id", :string, rows, :source_endpoint_id),
        field("value", :number, rows, :value),
        field("unit", :string, rows, :unit),
        field("observed_at", :time, rows, :observed_at),
        field("freshness_state", :enum, rows, :freshness_state),
        field("age_ms", :number, rows, :age_ms)
      ],
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :latest,
          supported_capability: :command_queue_depth,
          product_family: :commanding,
          observable_ids: observable_ids(rows),
          observable_id: @observable_id,
          unit: "commands",
          command_queue_entry_ids: entry_ids(rows),
          returned_points: length(rows),
          freshness_policy: latest_freshness_policy(rows),
          freshness_checked_at: latest_freshness_checked_at(rows),
          warning_codes: latest_freshness_warning_codes(rows),
          links: DataLinks.operational_resource_links(request, rows, source: :frame),
          evidence_refs: entry_evidence_refs(rows)
        })
    }
  end

  @spec revision([term()]) :: binary()
  def revision(entries) do
    "command_queue_depth:" <>
      RuntimeCacheKey.fingerprint(%{
        entries:
          entries
          |> Enum.filter(&pending?/1)
          |> Enum.map(&revision_entry/1)
          |> Enum.sort_by(&(&1.command_queue_entry_id || ""))
      })
  end

  @spec default_revision(binary(), binary(), keyword()) :: binary()
  def default_revision(organization_id, mission_id, opts) do
    organization_id
    |> default_entries(mission_id, opts)
    |> revision()
  end

  defp default_entries(organization_id, mission_id, _opts) do
    OperationalState.list_pending_command_queue_entries(organization_id, mission_id)
  end

  defp depth_scope(request, mission_id) do
    [
      scoped_depth_scope(request, :source_endpoint),
      scoped_depth_scope(request, :spacecraft),
      scoped_depth_scope(request, :contact)
    ]
    |> Enum.find_value(fn
      nil -> nil
      scope -> scope
    end)
    |> case do
      nil -> {:mission, mission_id, [mission_id]}
      scoped -> scoped
    end
  end

  defp scoped_depth_scope(request, kind) do
    case scope_ids(request, kind) do
      [] -> nil
      [scope_id] -> {kind, scope_id, [scope_id]}
      scope_ids -> {kind, Enum.join(scope_ids, ","), scope_ids}
    end
  end

  defp depth_label(:mission, _resource_id), do: "Pending commands"

  defp depth_label(scope_kind, resource_id) do
    "#{humanize_atom(scope_kind)} / #{resource_id}"
  end

  defp depth_source_endpoint_id(:source_endpoint, [resource_id]), do: resource_id
  defp depth_source_endpoint_id(_scope_kind, _scope_ids), do: nil

  defp matches_scope?(entry, request) do
    matches_scope_id?(source_endpoint_id(entry), scope_ids(request, :source_endpoint)) and
      matches_scope_id?(metadata_attr(entry, :spacecraft_id), scope_ids(request, :spacecraft)) and
      matches_scope_id?(contact_id(entry), scope_ids(request, :contact))
  end

  defp source_endpoint_id(entry) do
    attr(entry, :source_endpoint_ref) || attr(entry, :queue_lane_key)
  end

  defp contact_id(entry) do
    metadata_attr(entry, :contact_id) ||
      metadata_attr(entry, :scheduled_contact_id) ||
      metadata_attr(entry, :realized_contact_id)
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

  defp entry_evidence_refs(rows) do
    rows
    |> entries_from_rows()
    |> DataLinks.command_queue_entry_evidence_refs(source: :operational_observables)
  end

  defp entry_ids(rows) do
    rows
    |> entries_from_rows()
    |> Enum.map(&attr(&1, :command_queue_entry_id))
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp entries_from_rows(rows) do
    rows
    |> List.wrap()
    |> Enum.flat_map(fn row ->
      row
      |> attr(:source)
      |> case do
        %{entries: entries} when is_list(entries) -> entries
        %{"entries" => entries} when is_list(entries) -> entries
        _other -> []
      end
    end)
  end

  defp revision_entry(entry) do
    %{
      command_queue_entry_id: attr(entry, :command_queue_entry_id),
      source_endpoint_ref: attr(entry, :source_endpoint_ref),
      queue_lane_key: attr(entry, :queue_lane_key),
      queue_sequence: attr(entry, :queue_sequence),
      priority: attr(entry, :priority),
      lifecycle_state: attr(entry, :lifecycle_state),
      enqueued_at: attr(entry, :enqueued_at),
      not_before: attr(entry, :not_before),
      expires_at: attr(entry, :expires_at),
      metadata: attr(entry, :metadata)
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

  defp latest_freshness_warning_codes(rows) do
    rows
    |> values(:freshness_state)
    |> Enum.uniq()
    |> Enum.flat_map(fn
      :stale -> [:stale_data]
      :missing -> [:missing_snapshot]
      :unknown -> [:watermark_unknown]
      _state -> []
    end)
    |> Enum.uniq()
  end

  defp latest_freshness_policy([%{freshness_policy: policy} | _rows]), do: policy
  defp latest_freshness_policy(_rows), do: %{}

  defp latest_freshness_checked_at([row | _rows]) do
    case attr(row, :freshness_checked_at) do
      %DateTime{} = checked_at -> checked_at
      _value -> nil
    end
  end

  defp latest_freshness_checked_at(_rows), do: nil

  defp pending?(entry), do: attr(entry, :lifecycle_state) in [:pending, "pending"]

  defp humanize_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp metadata_attr(value, key), do: value |> attr(:metadata) |> attr(key)

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil
end
