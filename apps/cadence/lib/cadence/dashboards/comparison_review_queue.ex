defmodule Cadence.Dashboards.ComparisonReviewQueue do
  @moduledoc """
  Read model for dashboard comparison review lifecycle events.
  """

  @request_event :comparison_review_requested
  @request_event_string "comparison_review_requested"
  @resolution_event :comparison_review_resolved
  @resolution_event_string "comparison_review_resolved"

  @type open_summary :: %{
          count: non_neg_integer(),
          count_text: binary(),
          requests: [map()],
          request_ids: [binary()],
          request_ids_attr: binary(),
          placement_ids: [binary()],
          placements_attr: binary(),
          scope_kind: binary() | nil,
          scope_kinds: [binary()],
          scope_kinds_attr: binary(),
          scope_ids: [binary()],
          scope_ids_attr: binary(),
          contact_ids: [binary()],
          contact_ids_attr: binary(),
          resource_ids: [binary()],
          resource_ids_attr: binary(),
          transport_ids: [binary()],
          transport_ids_attr: binary(),
          source_endpoint_ids: [binary()],
          source_endpoint_ids_attr: binary(),
          ground_station_ids: [binary()],
          ground_station_ids_attr: binary(),
          scope_link_ids: [binary()],
          scope_link_ids_attr: binary()
        }

  @type request_summary :: %{
          event_id: binary() | nil,
          schema: binary(),
          kind: binary(),
          status: binary(),
          resolved?: boolean(),
          resolution_event_id: binary() | nil,
          open_count: non_neg_integer(),
          open_count_text: binary(),
          placement_ids: [binary()],
          placements_attr: binary(),
          operational_context: map(),
          findings: [map()]
        }

  @type finding_summary :: %{
          placement_id: binary(),
          title: binary(),
          state: binary(),
          decision_status: binary()
        }

  @type resolution_summary :: %{
          source_request_event_id: binary(),
          disposition: binary(),
          resolution_reason: binary(),
          selected_placement_id: binary(),
          affected_placement_ids: [binary()],
          affected_placements_attr: binary(),
          affected_placements_text: binary(),
          workflow_intent_kind: binary(),
          workflow_intent_action: binary(),
          workflow_selection_count_text: binary(),
          source_open_count_text: binary(),
          source_open_placement_ids: [binary()],
          source_open_placements_attr: binary(),
          source_scope_kind: binary(),
          source_scope_ids: [binary()],
          source_scope_ids_attr: binary(),
          source_contact_ids: [binary()],
          source_contact_ids_attr: binary(),
          source_resource_ids: [binary()],
          source_resource_ids_attr: binary(),
          source_transport_ids: [binary()],
          source_transport_ids_attr: binary(),
          source_endpoint_ids: [binary()],
          source_endpoint_ids_attr: binary(),
          source_ground_station_ids: [binary()],
          source_ground_station_ids_attr: binary(),
          source_scope_link_ids: [binary()],
          source_scope_link_ids_attr: binary(),
          source_bulk_decision_actionable_count_text: binary(),
          source_bulk_decision_actionable_placement_ids: [binary()],
          source_bulk_decision_actionable_placements_attr: binary(),
          source_bulk_decision_skipped_count_text: binary(),
          source_bulk_decision_skipped_placement_ids: [binary()],
          source_bulk_decision_skipped_placements_attr: binary(),
          source_bulk_decision_skipped_reasons: [binary()],
          source_bulk_decision_skipped_reasons_attr: binary()
        }

  @spec open_summary([map()]) :: open_summary()
  def open_summary(events) when is_list(events) do
    requests = open_requests(events)

    request_ids =
      Enum.map(requests, &event_value(&1, :dashboard_lifecycle_event_id)) |> present_values()

    placement_ids = Enum.flat_map(requests, &request_placements/1) |> Enum.uniq()

    operational_context =
      requests
      |> Enum.flat_map(&request_findings/1)
      |> operational_context()

    count = length(requests)

    %{
      count: count,
      count_text: Integer.to_string(count),
      requests: requests,
      request_ids: request_ids,
      request_ids_attr: Enum.join(request_ids, ","),
      placement_ids: placement_ids,
      placements_attr: Enum.join(placement_ids, ",")
    }
    |> Map.merge(operational_context)
  end

  @spec open_request_count_text([map()]) :: binary()
  def open_request_count_text(events) when is_list(events) do
    events
    |> open_summary()
    |> Map.fetch!(:count_text)
  end

  @spec open_request_ids_attr([map()]) :: binary()
  def open_request_ids_attr(events) when is_list(events) do
    events
    |> open_summary()
    |> Map.fetch!(:request_ids_attr)
  end

  @spec open_request_ids([map()]) :: [binary()]
  def open_request_ids(events) when is_list(events) do
    events
    |> open_summary()
    |> Map.fetch!(:request_ids)
  end

  @spec open_placements_attr([map()]) :: binary()
  def open_placements_attr(events) when is_list(events) do
    events
    |> open_summary()
    |> Map.fetch!(:placements_attr)
  end

  @spec open_placement_ids([map()]) :: [binary()]
  def open_placement_ids(events) when is_list(events) do
    events
    |> open_summary()
    |> Map.fetch!(:placement_ids)
  end

  @spec open_requests([map()]) :: [map()]
  def open_requests(events) when is_list(events) do
    Enum.filter(events, fn event ->
      request_event?(event) and not request_resolved?(event, events)
    end)
  end

  @spec request_resolved?(map(), [map()]) :: boolean()
  def request_resolved?(event, events) when is_list(events) do
    not is_nil(request_resolution(event, events))
  end

  @spec request_resolution_event_id(map(), [map()]) :: binary() | nil
  def request_resolution_event_id(event, events) when is_list(events) do
    case request_resolution(event, events) do
      nil -> nil
      resolution -> event_value(resolution, :dashboard_lifecycle_event_id)
    end
  end

  @spec request_summary(map(), [map()]) :: request_summary()
  def request_summary(event, events \\ []) do
    placement_ids = request_placements(event)
    findings = request_findings(event)
    operational_context = operational_context(findings)
    resolved? = request_resolved?(event, events)

    %{
      event_id: event_value(event, :dashboard_lifecycle_event_id),
      schema: request_value(event, "schema"),
      kind: request_value(event, "request_kind"),
      status: if(resolved?, do: "resolved", else: "open"),
      resolved?: resolved?,
      resolution_event_id: request_resolution_event_id(event, events),
      open_count: request_open_count(event, findings),
      open_count_text: request_open_count(event, findings) |> Integer.to_string(),
      placement_ids: placement_ids,
      placements_attr: Enum.join(placement_ids, ","),
      operational_context: operational_context,
      findings: findings
    }
    |> Map.merge(operational_context)
  end

  @spec request_placements(map()) :: [binary()]
  def request_placements(event) do
    payload = event_value(event, :payload)

    placement_ids =
      payload
      |> payload_value("open_placement_ids")
      |> List.wrap()
      |> Enum.filter(&is_binary/1)

    if placement_ids == [] do
      payload
      |> payload_value("open_findings")
      |> payload_value("findings")
      |> case do
        findings when is_list(findings) ->
          findings
          |> Enum.map(&payload_value(&1, "placement_id"))
          |> Enum.filter(&is_binary/1)

        _value ->
          []
      end
    else
      placement_ids
    end
  end

  @spec request_findings(map()) :: [map()]
  def request_findings(event) do
    event
    |> event_value(:payload)
    |> payload_value("open_findings")
    |> payload_value("findings")
    |> case do
      findings when is_list(findings) -> Enum.filter(findings, &is_map/1)
      _value -> []
    end
  end

  @spec request_operational_context(map()) :: map()
  def request_operational_context(event) do
    event
    |> request_findings()
    |> operational_context()
  end

  @spec request_value(map(), binary()) :: binary()
  def request_value(event, key) when is_binary(key) do
    event
    |> event_value(:payload)
    |> payload_value(key)
    |> display_value()
  end

  @spec finding_summary(map()) :: finding_summary()
  def finding_summary(finding) when is_map(finding) do
    placement_id = finding_value(finding, "placement_id")

    %{
      placement_id: placement_id,
      title: finding_title(finding),
      state: finding_value(finding, "state"),
      decision_status: finding_value(finding, "decision_status")
    }
  end

  @spec finding_value(map(), binary()) :: binary()
  def finding_value(finding, key) when is_map(finding) and is_binary(key) do
    payload_value(finding, key) || ""
  end

  @spec resolution_summary(map()) :: resolution_summary()
  def resolution_summary(event) do
    payload = event_value(event, :payload)
    workflow_intent = payload_value(payload, "workflow_intent")

    affected_placement_ids =
      payload
      |> payload_value("affected_placement_ids")
      |> List.wrap()
      |> present_values()

    source_open_placement_ids =
      payload
      |> payload_value("source_open_placement_ids")
      |> List.wrap()
      |> present_values()

    source_bulk_decision_actionable_placement_ids =
      payload
      |> payload_value("source_bulk_decision_actionable_placement_ids")
      |> List.wrap()
      |> present_values()

    source_bulk_decision_skipped_placement_ids =
      payload
      |> payload_value("source_bulk_decision_skipped_placement_ids")
      |> List.wrap()
      |> present_values()

    source_bulk_decision_skipped_reasons =
      payload
      |> payload_value("source_bulk_decision_skipped_reasons")
      |> List.wrap()
      |> present_values()

    source_scope_ids = payload |> payload_value("source_scope_ids") |> list_values()
    source_contact_ids = payload |> payload_value("source_contact_ids") |> list_values()
    source_resource_ids = payload |> payload_value("source_resource_ids") |> list_values()
    source_transport_ids = payload |> payload_value("source_transport_ids") |> list_values()
    source_endpoint_ids = payload |> payload_value("source_endpoint_ids") |> list_values()

    source_ground_station_ids =
      payload |> payload_value("source_ground_station_ids") |> list_values()

    source_scope_link_ids = payload |> payload_value("source_scope_link_ids") |> list_values()

    %{
      source_request_event_id: resolution_value(event, "source_request_event_id"),
      disposition: resolution_value(event, "disposition"),
      resolution_reason: resolution_value(event, "resolution_reason"),
      selected_placement_id: resolution_value(event, "selected_placement_id"),
      affected_placement_ids: affected_placement_ids,
      affected_placements_attr: Enum.join(affected_placement_ids, ","),
      affected_placements_text: affected_placements_text(affected_placement_ids),
      workflow_intent_kind: workflow_intent |> payload_value("kind") |> display_value(),
      workflow_intent_action: workflow_intent |> payload_value("action") |> display_value(),
      workflow_selection_count_text:
        workflow_intent |> payload_value("selection_count") |> count_text(),
      source_open_count_text: payload |> payload_value("source_open_count") |> count_text(),
      source_open_placement_ids: source_open_placement_ids,
      source_open_placements_attr: Enum.join(source_open_placement_ids, ","),
      source_scope_kind: resolution_value(event, "source_scope_kind"),
      source_scope_ids: source_scope_ids,
      source_scope_ids_attr: Enum.join(source_scope_ids, ","),
      source_contact_ids: source_contact_ids,
      source_contact_ids_attr: Enum.join(source_contact_ids, ","),
      source_resource_ids: source_resource_ids,
      source_resource_ids_attr: Enum.join(source_resource_ids, ","),
      source_transport_ids: source_transport_ids,
      source_transport_ids_attr: Enum.join(source_transport_ids, ","),
      source_endpoint_ids: source_endpoint_ids,
      source_endpoint_ids_attr: Enum.join(source_endpoint_ids, ","),
      source_ground_station_ids: source_ground_station_ids,
      source_ground_station_ids_attr: Enum.join(source_ground_station_ids, ","),
      source_scope_link_ids: source_scope_link_ids,
      source_scope_link_ids_attr: Enum.join(source_scope_link_ids, ","),
      source_bulk_decision_actionable_count_text:
        payload |> payload_value("source_bulk_decision_actionable_count") |> count_text(),
      source_bulk_decision_actionable_placement_ids:
        source_bulk_decision_actionable_placement_ids,
      source_bulk_decision_actionable_placements_attr:
        Enum.join(source_bulk_decision_actionable_placement_ids, ","),
      source_bulk_decision_skipped_count_text:
        payload |> payload_value("source_bulk_decision_skipped_count") |> count_text(),
      source_bulk_decision_skipped_placement_ids: source_bulk_decision_skipped_placement_ids,
      source_bulk_decision_skipped_placements_attr:
        Enum.join(source_bulk_decision_skipped_placement_ids, ","),
      source_bulk_decision_skipped_reasons: source_bulk_decision_skipped_reasons,
      source_bulk_decision_skipped_reasons_attr:
        Enum.join(source_bulk_decision_skipped_reasons, ",")
    }
  end

  @spec resolution_value(map(), binary()) :: binary()
  def resolution_value(event, key) when is_binary(key) do
    event
    |> event_value(:payload)
    |> payload_value(key)
    |> display_value()
  end

  @spec event_value(map(), atom()) :: term()
  def event_value(event, key) when is_map(event) and is_atom(key) do
    Map.get(event, key) || Map.get(event, Atom.to_string(key))
  end

  def event_value(_event, _key), do: nil

  @spec payload_value(map() | nil, binary()) :: term()
  def payload_value(payload, key) when is_map(payload) and is_binary(key) do
    Map.get(payload, key) || Map.get(payload, known_atom_key(key))
  end

  def payload_value(_payload, _key), do: nil

  defp request_resolution(event, events) when is_list(events) do
    request_event_id = event_value(event, :dashboard_lifecycle_event_id)

    Enum.find(events, fn candidate ->
      resolution_event?(candidate) and
        payload_value(event_value(candidate, :payload), "source_request_event_id") ==
          request_event_id
    end)
  end

  defp request_event?(event) do
    event_value(event, :event_type) in [@request_event, @request_event_string]
  end

  defp resolution_event?(event) do
    event_value(event, :event_type) in [@resolution_event, @resolution_event_string]
  end

  defp request_open_count(event, findings) when is_list(findings) do
    case event_value(event, :payload) |> payload_value("open_count") do
      count when is_integer(count) and count >= 0 -> count
      count when is_binary(count) -> parsed_nonnegative_integer(count, length(findings))
      _value -> length(findings)
    end
  end

  defp parsed_nonnegative_integer(value, fallback) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _value -> fallback
    end
  end

  defp finding_title(finding) when is_map(finding) do
    title = finding_value(finding, "title")
    placement_id = finding_value(finding, "placement_id")

    cond do
      title != "" -> title
      placement_id != "" -> placement_id
      true -> "Untitled finding"
    end
  end

  defp affected_placements_text([]), do: "-"
  defp affected_placements_text(placement_ids), do: Enum.join(placement_ids, ", ")

  defp operational_context(findings) when is_list(findings) do
    scope_kinds = finding_values(findings, "scope_kind")
    scope_ids = finding_values(findings, ["scope_ids", "scope_id"])
    contact_ids = finding_values(findings, ["contact_ids", "contact_id"])
    resource_ids = finding_values(findings, "resource_id")
    transport_ids = finding_values(findings, "transport_id")
    source_endpoint_ids = finding_values(findings, "source_endpoint_id")
    ground_station_ids = finding_values(findings, "ground_station_id")
    scope_link_ids = finding_values(findings, "scope_link_id")

    %{
      scope_kind: single_value(scope_kinds),
      scope_kinds: scope_kinds,
      scope_kinds_attr: Enum.join(scope_kinds, ","),
      scope_ids: scope_ids,
      scope_ids_attr: Enum.join(scope_ids, ","),
      contact_ids: contact_ids,
      contact_ids_attr: Enum.join(contact_ids, ","),
      resource_ids: resource_ids,
      resource_ids_attr: Enum.join(resource_ids, ","),
      transport_ids: transport_ids,
      transport_ids_attr: Enum.join(transport_ids, ","),
      source_endpoint_ids: source_endpoint_ids,
      source_endpoint_ids_attr: Enum.join(source_endpoint_ids, ","),
      ground_station_ids: ground_station_ids,
      ground_station_ids_attr: Enum.join(ground_station_ids, ","),
      scope_link_ids: scope_link_ids,
      scope_link_ids_attr: Enum.join(scope_link_ids, ",")
    }
  end

  defp finding_values(findings, keys) when is_list(keys) do
    findings
    |> Enum.flat_map(fn finding ->
      Enum.flat_map(keys, &finding_values(finding, &1))
    end)
    |> Enum.uniq()
  end

  defp finding_values(findings, key) when is_list(findings) and is_binary(key) do
    findings
    |> Enum.flat_map(&finding_values(&1, key))
    |> Enum.uniq()
  end

  defp finding_values(finding, key) when is_map(finding) and is_binary(key) do
    finding
    |> payload_value(key)
    |> list_values()
  end

  defp finding_values(_finding, _key), do: []

  defp list_values(values) when is_list(values) do
    values
    |> Enum.flat_map(&list_values/1)
    |> Enum.uniq()
  end

  defp list_values(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp list_values(nil), do: []
  defp list_values(value) when is_atom(value), do: [Atom.to_string(value)]
  defp list_values(value) when is_integer(value), do: [Integer.to_string(value)]
  defp list_values(_value), do: []

  defp single_value([]), do: nil
  defp single_value(values), do: Enum.join(values, ",")

  defp count_text(value) when is_integer(value) and value >= 0, do: Integer.to_string(value)
  defp count_text(value) when is_binary(value) and value != "", do: value
  defp count_text(_value), do: "-"

  defp display_value(value) when is_binary(value) and value != "", do: value
  defp display_value(value) when is_integer(value), do: Integer.to_string(value)
  defp display_value(_value), do: "-"

  defp present_values(values) when is_list(values) do
    Enum.filter(values, &present?/1)
  end

  defp known_atom_key("source_request_event_id"), do: :source_request_event_id
  defp known_atom_key("open_placement_ids"), do: :open_placement_ids
  defp known_atom_key("open_findings"), do: :open_findings
  defp known_atom_key("findings"), do: :findings
  defp known_atom_key("placement_id"), do: :placement_id
  defp known_atom_key("schema"), do: :schema
  defp known_atom_key("request_kind"), do: :request_kind
  defp known_atom_key("open_count"), do: :open_count
  defp known_atom_key("title"), do: :title
  defp known_atom_key("state"), do: :state
  defp known_atom_key("decision_status"), do: :decision_status
  defp known_atom_key("scope_kind"), do: :scope_kind
  defp known_atom_key("scope_id"), do: :scope_id
  defp known_atom_key("scope_ids"), do: :scope_ids
  defp known_atom_key("resource_id"), do: :resource_id
  defp known_atom_key("contact_id"), do: :contact_id
  defp known_atom_key("contact_ids"), do: :contact_ids
  defp known_atom_key("transport_id"), do: :transport_id
  defp known_atom_key("source_endpoint_id"), do: :source_endpoint_id
  defp known_atom_key("ground_station_id"), do: :ground_station_id
  defp known_atom_key("scope_link_id"), do: :scope_link_id
  defp known_atom_key("disposition"), do: :disposition
  defp known_atom_key("resolution_reason"), do: :resolution_reason
  defp known_atom_key("selected_placement_id"), do: :selected_placement_id
  defp known_atom_key("affected_placement_ids"), do: :affected_placement_ids
  defp known_atom_key("workflow_intent"), do: :workflow_intent
  defp known_atom_key("kind"), do: :kind
  defp known_atom_key("action"), do: :action
  defp known_atom_key("selection_count"), do: :selection_count
  defp known_atom_key("source_open_count"), do: :source_open_count
  defp known_atom_key("source_open_placement_ids"), do: :source_open_placement_ids
  defp known_atom_key("source_scope_kind"), do: :source_scope_kind
  defp known_atom_key("source_scope_ids"), do: :source_scope_ids
  defp known_atom_key("source_contact_ids"), do: :source_contact_ids
  defp known_atom_key("source_resource_ids"), do: :source_resource_ids
  defp known_atom_key("source_transport_ids"), do: :source_transport_ids
  defp known_atom_key("source_endpoint_ids"), do: :source_endpoint_ids
  defp known_atom_key("source_ground_station_ids"), do: :source_ground_station_ids
  defp known_atom_key("source_scope_link_ids"), do: :source_scope_link_ids
  defp known_atom_key(_key), do: nil

  defp present?(value), do: is_binary(value) and value != ""
end
