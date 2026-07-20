defmodule Cadence.Contacts.LinkAssignmentStore do
  @moduledoc """
  Persists link assignments and enforces their scoped runtime references.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Contacts.LinkAssignment
  alias Cadence.Contacts.LinkAssignmentStore.LinkAssignmentRow
  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.PathTemplateStore
  alias Cadence.Contacts.ProfileStore
  alias Cadence.Contacts.Validation
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @spec persist(binary(), LinkAssignment.t()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def persist(organization_id, %LinkAssignment{} = assignment)
      when is_binary(organization_id) do
    with {:ok, scoped_assignment} <- put_organization_scope(assignment, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_assignment.organization_id, scoped_assignment.mission_id),
         :ok <- validate(scoped_assignment),
         {:ok, _row} <-
           Repo.insert(LinkAssignmentRow.changeset(scoped_assignment),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :link_assignment_id]
           ) do
      fetch(
        scoped_assignment.organization_id,
        scoped_assignment.mission_id,
        scoped_assignment.link_assignment_id
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def fetch(organization_id, mission_id, link_assignment_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(link_assignment_id) do
    case Repo.get_by(LinkAssignmentRow,
           organization_id: organization_id,
           mission_id: mission_id,
           link_assignment_id: link_assignment_id
         ) do
      nil ->
        {:error, :contact_link_assignment_not_found}

      %LinkAssignmentRow{lifecycle_state: "deleted"} ->
        {:error, :contact_link_assignment_not_found}

      %LinkAssignmentRow{} = row ->
        {:ok, LinkAssignmentRow.to_domain(row)}
    end
  end

  @spec fetch(binary(), binary()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def fetch(mission_id, link_assignment_id)
      when is_binary(mission_id) and is_binary(link_assignment_id) do
    case Repo.get_by(LinkAssignmentRow,
           mission_id: mission_id,
           link_assignment_id: link_assignment_id
         ) do
      nil ->
        {:error, :contact_link_assignment_not_found}

      %LinkAssignmentRow{lifecycle_state: "deleted"} ->
        {:error, :contact_link_assignment_not_found}

      %LinkAssignmentRow{} = row ->
        {:ok, LinkAssignmentRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary()) :: [LinkAssignment.t()]
  def list(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    LinkAssignmentRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.lifecycle_state == "active"
    )
    |> order_by([row], asc: row.link_assignment_id)
    |> Repo.all()
    |> Enum.map(&LinkAssignmentRow.to_domain/1)
  end

  @spec delete(binary(), binary(), binary(), map()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def delete(organization_id, mission_id, link_assignment_id, metadata_patch)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(link_assignment_id) and is_map(metadata_patch) do
    with {:ok, %LinkAssignment{} = assignment} <-
           fetch(organization_id, mission_id, link_assignment_id) do
      metadata =
        assignment.metadata
        |> Map.merge(metadata_patch)
        |> Map.put("deleted_at", DateTime.utc_now() |> DateTime.to_iso8601())

      {1, _rows} =
        LinkAssignmentRow
        |> where(
          [row],
          row.organization_id == ^organization_id and row.mission_id == ^mission_id and
            row.link_assignment_id == ^link_assignment_id
        )
        |> Repo.update_all(set: [lifecycle_state: "deleted", metadata: %{"value" => metadata}])

      {:ok, %LinkAssignment{assignment | lifecycle_state: :deleted, metadata: metadata}}
    end
  end

  defp validate(%LinkAssignment{} = assignment) do
    with :ok <- Validation.mission_id(assignment.mission_id),
         :ok <- Validation.required_binary(assignment.spacecraft_id, :missing_spacecraft_id),
         :ok <-
           Validation.required_binary(
             assignment.source_endpoint_ref,
             :missing_source_endpoint_ref
           ),
         :ok <- Validation.required_binary(assignment.path_template_id, :missing_path_template_id),
         {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(
             assignment.organization_id,
             assignment.mission_id,
             assignment.spacecraft_id
           ),
         {:ok, source_endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             assignment.organization_id,
             assignment.mission_id,
             assignment.source_endpoint_ref
           ),
         :ok <- validate_source_endpoint(spacecraft, source_endpoint),
         {:ok, path_template} <-
           PathTemplateStore.fetch_version(
             assignment.organization_id,
             assignment.mission_id,
             assignment.path_template_id,
             assignment.path_template_version
           ),
         :ok <- validate_template_match(assignment, path_template),
         :ok <- validate_profile_refs(assignment) do
      validate_ref_ids(assignment)
    end
  end

  defp validate_source_endpoint(spacecraft, source_endpoint) do
    if source_endpoint.spacecraft_id == spacecraft.spacecraft_id do
      :ok
    else
      {:error, :link_assignment_source_endpoint_mismatch}
    end
  end

  defp validate_template_match(
         %LinkAssignment{} = assignment,
         %PathTemplate{} = path_template
       ) do
    if assignment.direction == path_template.direction and
         assignment.selection_role == path_template.selection_role do
      :ok
    else
      {:error, :link_assignment_path_template_mismatch}
    end
  end

  defp validate_profile_refs(%LinkAssignment{} = assignment) do
    with :ok <-
           validate_refs(
             assignment.organization_id,
             assignment.mission_id,
             assignment.provider_profile_refs,
             "provider_profile_id",
             :contact_provider_profile_not_found,
             &ProfileStore.fetch_provider_profile/3,
             &ProfileStore.fetch_provider_profile_version/4
           ) do
      validate_refs(
        assignment.organization_id,
        assignment.mission_id,
        assignment.transport_profile_refs,
        "transport_profile_id",
        :contact_transport_profile_not_found,
        &ProfileStore.fetch_transport_profile/3,
        &ProfileStore.fetch_transport_profile_version/4
      )
    end
  end

  defp validate_refs(
         organization_id,
         mission_id,
         refs,
         id_key,
         not_found_reason,
         fetch_current,
         fetch_version
       ) do
    Enum.reduce_while(refs, :ok, fn ref, :ok ->
      case fetch_ref(
             organization_id,
             mission_id,
             ref,
             id_key,
             not_found_reason,
             fetch_current,
             fetch_version
           ) do
        {:ok, _profile} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_ref(
         organization_id,
         mission_id,
         ref,
         id_key,
         not_found_reason,
         fetch_current,
         fetch_version
       ) do
    resource_id = Map.get(ref, id_key)
    version = Map.get(ref, "version")

    cond do
      not (is_binary(resource_id) and resource_id != "") ->
        {:error, :invalid_contact_runtime_config_reference}

      not is_nil(version) and not (is_integer(version) and version > 0) ->
        {:error, :invalid_contact_runtime_config_reference}

      is_integer(version) ->
        fetch_version.(organization_id, mission_id, resource_id, version)
        |> normalize_ref_result(not_found_reason)

      true ->
        fetch_current.(organization_id, mission_id, resource_id)
        |> normalize_ref_result(not_found_reason)
    end
  end

  defp normalize_ref_result({:ok, %{lifecycle_state: :deleted}}, not_found_reason) do
    {:error, not_found_reason}
  end

  defp normalize_ref_result({:ok, profile}, _not_found_reason), do: {:ok, profile}
  defp normalize_ref_result({:error, reason}, _not_found_reason), do: {:error, reason}

  defp validate_ref_ids(%LinkAssignment{} = assignment) do
    case Validation.reusable_path_refs(
           ids_from_refs(assignment.provider_profile_refs, "provider_profile_id")
         ) do
      :ok ->
        Validation.reusable_path_refs(
          ids_from_refs(assignment.transport_profile_refs, "transport_profile_id")
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ids_from_refs(refs, id_key) do
    Enum.map(refs, &Map.get(&1, id_key))
  end

  defp put_organization_scope(%LinkAssignment{} = assignment, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case assignment.organization_id do
      nil ->
        {:ok, %LinkAssignment{assignment | organization_id: organization_id}}

      ^organization_id ->
        {:ok, assignment}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          assignment.mission_id}}
    end
  end
end
