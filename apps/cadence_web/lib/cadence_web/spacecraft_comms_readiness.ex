defmodule CadenceWeb.SpacecraftCommsReadiness do
  @moduledoc false

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  def runtime_identity(organization_id, mission_id, %Spacecraft{} = spacecraft) do
    managed_id = managed_source_endpoint_id(spacecraft.spacecraft_id)

    case Cadence.fetch_source_endpoint(organization_id, mission_id, managed_id) do
      {:ok, endpoint} ->
        endpoint

      {:error, :source_endpoint_not_found} ->
        spacecraft
        |> matching_runtime_identity_candidates(organization_id, mission_id)
        |> List.first()

      {:error, _reason} ->
        nil
    end
  end

  def runtime_identity_match(%Spacecraft{} = spacecraft, source_endpoints) do
    managed_id = managed_source_endpoint_id(spacecraft.spacecraft_id)
    managed = Enum.find(source_endpoints, &(&1.source_endpoint_id == managed_id))

    spacecraft_bound =
      Enum.find(source_endpoints, &(&1.spacecraft_id == spacecraft.spacecraft_id))

    scid_matches =
      case spacecraft.scid do
        nil -> []
        scid -> Enum.filter(source_endpoints, &(&1.scid == scid))
      end

    cond do
      managed ->
        %{endpoint: managed, kind: :managed, scid_match_count: length(scid_matches)}

      spacecraft_bound ->
        %{endpoint: spacecraft_bound, kind: :spacecraft, scid_match_count: length(scid_matches)}

      length(scid_matches) == 1 ->
        %{endpoint: hd(scid_matches), kind: :scid, scid_match_count: 1}

      true ->
        %{endpoint: nil, kind: :missing, scid_match_count: length(scid_matches)}
    end
  end

  def runtime_identity_from_match(%{endpoint: endpoint}), do: endpoint

  def link_assignment(_organization_id, _mission_id, nil),
    do: empty_link_assignment()

  def link_assignment(organization_id, mission_id, %SourceEndpoint{} = runtime_identity) do
    link_assignment_from_assignments(
      Cadence.list_link_assignments(organization_id, mission_id),
      runtime_identity,
      Cadence.list_path_templates(organization_id, mission_id)
    )
  end

  def link_assignment_from_templates(_path_templates, nil), do: empty_link_assignment()

  def link_assignment_from_templates(path_templates, %SourceEndpoint{}) do
    %{
      selected_downlink: nil,
      assigned_count: 0,
      available_downlink_count: path_templates |> available_downlink_templates() |> length()
    }
  end

  def link_assignment_from_assignments(link_assignments, runtime_identity, path_templates \\ [])

  def link_assignment_from_assignments(_link_assignments, nil, _path_templates),
    do: empty_link_assignment()

  def link_assignment_from_assignments(
        link_assignments,
        %SourceEndpoint{} = runtime_identity,
        path_templates
      ) do
    assigned_link_assignments =
      Enum.filter(
        link_assignments,
        &(&1.source_endpoint_ref == runtime_identity.source_endpoint_id)
      )

    %{
      selected_downlink:
        Enum.find(assigned_link_assignments, &selected_provider_backed_downlink?/1),
      assigned_count: length(assigned_link_assignments),
      available_downlink_count: path_templates |> available_downlink_templates() |> length()
    }
  end

  def readiness_rows(spacecraft, source_endpoints, path_templates) do
    readiness_rows(spacecraft, source_endpoints, path_templates, [])
  end

  def readiness_rows(spacecraft, source_endpoints, path_templates, link_assignments) do
    available_downlink_paths = available_downlink_templates(path_templates)

    Enum.map(spacecraft, fn spacecraft ->
      endpoint_match = runtime_identity_match(spacecraft, source_endpoints)
      assignments = assignments_for_endpoint(endpoint_match.endpoint, link_assignments)
      links = assignments
      downlink_link = ready_downlink_path(links)
      status = readiness_status(spacecraft, endpoint_match, links)

      %{
        id: spacecraft.spacecraft_id,
        spacecraft: spacecraft,
        scid: spacecraft.scid,
        endpoint_ref: endpoint_ref(endpoint_match.endpoint),
        path_template_id: downlink_link && downlink_link.path_template_id,
        endpoint_label: endpoint_label(endpoint_match),
        path_label: path_label(endpoint_match, links, available_downlink_paths),
        path_detail: path_detail(endpoint_match, links, available_downlink_paths),
        status: status,
        status_label: readiness_status_label(status),
        issue: readiness_issue(spacecraft, endpoint_match, links, available_downlink_paths),
        primary_action: primary_action(spacecraft, endpoint_match, links)
      }
    end)
  end

  def missing_path?(%{scid: nil}), do: false
  def missing_path?(%{endpoint_ref: nil}), do: false
  def missing_path?(%{status: :warning}), do: true
  def missing_path?(_row), do: false

  def identity_ready?(%{scid: scid}) when is_integer(scid), do: true
  def identity_ready?(_spacecraft), do: false

  def available_downlink_templates(path_templates) do
    Enum.filter(path_templates, fn template ->
      is_nil(template.source_endpoint_ref) and provider_backed_downlink?(template)
    end)
  end

  def ready_downlink_path(paths) do
    Enum.find(paths, &provider_backed_downlink?/1)
  end

  def managed_source_endpoint_id(spacecraft_id), do: "spacecraft_runtime:" <> spacecraft_id

  defp matching_runtime_identity_candidates(%{scid: nil}, _organization_id, _mission_id), do: []

  defp matching_runtime_identity_candidates(spacecraft, organization_id, mission_id) do
    organization_id
    |> Cadence.list_source_endpoints(mission_id)
    |> Enum.filter(&(&1.scid == spacecraft.scid or &1.spacecraft_id == spacecraft.spacecraft_id))
  end

  defp empty_link_assignment,
    do: %{selected_downlink: nil, assigned_count: 0, available_downlink_count: 0}

  defp assignments_for_endpoint(nil, _link_assignments), do: []

  defp assignments_for_endpoint(endpoint, link_assignments) do
    Enum.filter(link_assignments, &(&1.source_endpoint_ref == endpoint.source_endpoint_id))
  end

  defp provider_backed_downlink?(template) do
    template.direction == :downlink and template.provider_profile_refs != []
  end

  defp selected_provider_backed_downlink?(template) do
    provider_backed_downlink?(template) and template.selection_role == :selected
  end

  defp readiness_status(%{scid: nil}, _endpoint_match, _paths), do: :missing

  defp readiness_status(_spacecraft, %{scid_match_count: count}, _paths) when count > 1,
    do: :missing

  defp readiness_status(_spacecraft, %{endpoint: nil}, _paths), do: :missing

  defp readiness_status(_spacecraft, _endpoint_match, paths) do
    if ready_downlink_path(paths), do: :ready, else: :warning
  end

  defp readiness_issue(%{scid: nil}, _endpoint_match, _paths, _available_paths),
    do: "Set SCID so Cadence can identify this spacecraft from TM transfer frames."

  defp readiness_issue(_spacecraft, %{scid_match_count: count}, _paths, _available_paths)
       when count > 1,
       do: "Multiple runtime identities match this SCID. Resolve ambiguity before ingest."

  defp readiness_issue(_spacecraft, %{endpoint: nil}, _paths, _available_paths),
    do: "Create the managed runtime identity for this spacecraft."

  defp readiness_issue(_spacecraft, _endpoint_match, paths, available_paths) do
    cond do
      ready_downlink_path(paths) ->
        "Ready for SCID-based telemetry routing."

      available_paths != [] ->
        "Assign an available downlink link template to this spacecraft."

      true ->
        "Create a provider-backed downlink link template for this spacecraft."
    end
  end

  defp primary_action(%{scid: nil}, _endpoint_match, _paths), do: "Set SCID"
  defp primary_action(_spacecraft, %{endpoint: nil}, _paths), do: "Sync identity"

  defp primary_action(_spacecraft, _endpoint_match, paths) do
    if ready_downlink_path(paths), do: "Review readiness", else: "Assign link"
  end

  defp endpoint_label(%{endpoint: nil}), do: "Missing"
  defp endpoint_label(%{kind: :managed}), do: "Managed identity"
  defp endpoint_label(%{kind: :spacecraft}), do: "Spacecraft-bound endpoint"
  defp endpoint_label(%{kind: :scid}), do: "SCID-matched endpoint"

  defp endpoint_ref(nil), do: nil
  defp endpoint_ref(endpoint), do: endpoint.source_endpoint_id

  defp path_label(%{endpoint: nil}, [], _available_paths), do: "No downlink link"

  defp path_label(_endpoint_match, [], available_paths) when available_paths != [],
    do: "Available to assign"

  defp path_label(_endpoint_match, [], _available_paths), do: "No downlink link"

  defp path_label(_endpoint_match, paths, _available_paths) do
    downlink_paths = Enum.filter(paths, &(&1.direction == :downlink))
    "#{length(downlink_paths)} downlink link#{if length(downlink_paths) == 1, do: "", else: "s"}"
  end

  defp path_detail(%{endpoint: nil}, [], _available_paths), do: "Not configured"

  defp path_detail(_endpoint_match, [], available_paths) when available_paths != [] do
    count = length(available_paths)
    "#{count} available mission template#{if count == 1, do: "", else: "s"}"
  end

  defp path_detail(_endpoint_match, [], _available_paths), do: "Not configured"

  defp path_detail(_endpoint_match, paths, _available_paths) do
    provider_backed =
      Enum.count(paths, &provider_backed_downlink?/1)

    "#{provider_backed} provider-backed"
  end

  defp readiness_status_label(:ready), do: "Ready"
  defp readiness_status_label(:warning), do: "Needs link"
  defp readiness_status_label(:missing), do: "Needs identity"
end
