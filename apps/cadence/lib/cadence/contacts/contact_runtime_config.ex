defmodule Cadence.Contacts.ContactRuntimeConfig do
  @moduledoc """
  Prepares and resolves pinned runtime configuration for scheduled contacts.
  """

  alias Cadence.Contacts.LinkAssignment
  alias Cadence.Contacts.LinkAssignmentStore
  alias Cadence.Contacts.Path
  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.PathTemplateStore
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Contacts.Validation

  @spec prepare(ScheduledContact.t()) :: {:ok, ScheduledContact.t()} | {:error, term()}
  def prepare(%ScheduledContact{} = scheduled_contact) do
    with :ok <- validate_ref_list(scheduled_contact.link_assignment_refs, "link_assignment_id"),
         {:ok, link_assignments} <-
           resolve_link_assignment_refs(
             scheduled_contact.organization_id,
             scheduled_contact.mission_id,
             scheduled_contact.link_assignment_refs
           ),
         :ok <-
           Validation.reusable_path_refs(
             ids_from_refs(scheduled_contact.link_assignment_refs, "link_assignment_id")
           ),
         {:ok, path_template_refs} <-
           normalize_versioned_refs(
             scheduled_contact.path_template_ids,
             scheduled_contact.path_template_refs,
             "path_template_id",
             fn ref ->
               PathTemplateStore.fetch_ref(
                 scheduled_contact.organization_id,
                 scheduled_contact.mission_id,
                 ref
               )
             end
           ),
         :ok <-
           Validation.reusable_path_refs(ids_from_refs(path_template_refs, "path_template_id")) do
      source_endpoint_refs =
        scheduled_contact.source_endpoint_refs
        |> Kernel.++(Enum.map(link_assignments, & &1.source_endpoint_ref))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      {:ok,
       %ScheduledContact{
         scheduled_contact
         | source_endpoint_refs: source_endpoint_refs,
           link_assignment_refs: Enum.map(link_assignments, &link_assignment_ref/1),
           path_template_ids: ids_from_refs(path_template_refs, "path_template_id"),
           path_template_refs: path_template_refs
       }}
    end
  end

  @spec validate(ScheduledContact.t()) :: :ok | {:error, term()}
  def validate(%ScheduledContact{} = scheduled_contact) do
    with {:ok, resolved_paths} <- resolve_paths(scheduled_contact) do
      Validation.scheduled_contact(scheduled_contact, resolved_paths)
    end
  end

  @spec resolve_paths(ScheduledContact.t()) :: {:ok, [Path.t()]} | {:error, term()}
  def resolve_paths(%ScheduledContact{} = scheduled_contact) do
    with {:ok, assignment_paths} <-
           resolve_link_assignment_paths(
             scheduled_contact.organization_id,
             scheduled_contact.mission_id,
             scheduled_contact.link_assignment_refs
           ),
         {:ok, template_paths} <-
           resolve_path_templates(
             scheduled_contact.organization_id,
             scheduled_contact.mission_id,
             scheduled_contact.path_template_ids,
             scheduled_contact.path_template_refs
           ) do
      {:ok, assignment_paths ++ template_paths ++ scheduled_contact.paths}
    end
  end

  defp resolve_link_assignment_paths(_organization_id, _mission_id, []), do: {:ok, []}

  defp resolve_link_assignment_paths(organization_id, mission_id, link_assignment_refs)
       when is_binary(mission_id) and is_list(link_assignment_refs) do
    Enum.reduce_while(link_assignment_refs, {:ok, []}, fn ref, {:ok, acc} ->
      with {:ok, %LinkAssignment{} = assignment} <-
             fetch_link_assignment_ref(organization_id, mission_id, ref),
           {:ok, %PathTemplate{} = path_template} <-
             PathTemplateStore.fetch_ref(organization_id, mission_id, %{
               "path_template_id" => assignment.path_template_id,
               "version" => assignment.path_template_version
             }),
           {:ok, %Path{} = resolved_path} <-
             assignment_path_template(assignment, path_template)
             |> PathTemplateStore.resolve() do
        {:cont, {:ok, acc ++ [resolved_path]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp assignment_path_template(%LinkAssignment{} = assignment, %PathTemplate{} = path_template) do
    provider_profile_refs =
      if assignment.provider_profile_refs == [] do
        path_template.provider_profile_refs
      else
        assignment.provider_profile_refs
      end

    transport_profile_refs =
      if assignment.transport_profile_refs == [] do
        path_template.transport_profile_refs
      else
        assignment.transport_profile_refs
      end

    metadata =
      path_template.metadata
      |> Map.merge(assignment.metadata)
      |> Map.put("link_assignment_id", assignment.link_assignment_id)
      |> Map.put("spacecraft_id", assignment.spacecraft_id)

    %PathTemplate{
      path_template
      | path_id: assignment.link_assignment_id,
        direction: assignment.direction,
        selection_role: assignment.selection_role,
        source_endpoint_ref: assignment.source_endpoint_ref,
        provider_path_ref: assignment.provider_path_ref || path_template.provider_path_ref,
        provider_profile_ids: ids_from_refs(provider_profile_refs, "provider_profile_id"),
        provider_profile_refs: provider_profile_refs,
        transport_profile_ids: ids_from_refs(transport_profile_refs, "transport_profile_id"),
        transport_profile_refs: transport_profile_refs,
        metadata: metadata
    }
  end

  defp resolve_path_templates(_organization_id, _mission_id, [], []), do: {:ok, []}

  defp resolve_path_templates(organization_id, mission_id, path_template_ids, path_template_refs)
       when is_binary(mission_id) and is_list(path_template_ids) and is_list(path_template_refs) do
    refs =
      if path_template_refs == [],
        do: refs_from_ids(path_template_ids, "path_template_id"),
        else: path_template_refs

    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      with {:ok, %PathTemplate{} = path_template} <-
             PathTemplateStore.fetch_ref(organization_id, mission_id, ref),
           {:ok, %Path{} = resolved_path} <- PathTemplateStore.resolve(path_template) do
        {:cont, {:ok, acc ++ [resolved_path]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_link_assignment_refs(organization_id, mission_id, link_assignment_refs)
       when is_list(link_assignment_refs) do
    Enum.reduce_while(link_assignment_refs, {:ok, []}, fn ref, {:ok, acc} ->
      case fetch_link_assignment_ref(organization_id, mission_id, ref) do
        {:ok, %LinkAssignment{} = assignment} -> {:cont, {:ok, acc ++ [assignment]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_link_assignment_ref(organization_id, mission_id, ref) do
    case Map.get(ref, "link_assignment_id") do
      link_assignment_id when is_binary(link_assignment_id) and link_assignment_id != "" ->
        fetch_link_assignment(organization_id, mission_id, link_assignment_id)

      _other ->
        {:error, :invalid_contact_runtime_config_reference}
    end
  end

  defp fetch_link_assignment(organization_id, mission_id, link_assignment_id)
       when is_binary(organization_id) and organization_id != "" do
    LinkAssignmentStore.fetch(organization_id, mission_id, link_assignment_id)
  end

  defp fetch_link_assignment(_organization_id, mission_id, link_assignment_id) do
    LinkAssignmentStore.fetch(mission_id, link_assignment_id)
  end

  defp link_assignment_ref(%LinkAssignment{} = assignment) do
    %{"link_assignment_id" => assignment.link_assignment_id}
  end

  defp normalize_versioned_refs([], [], _id_key, _fetch_ref), do: {:ok, []}

  defp normalize_versioned_refs(ids, refs, id_key, fetch_ref)
       when is_list(ids) and is_list(refs) and is_binary(id_key) and is_function(fetch_ref, 1) do
    requested_refs =
      cond do
        refs != [] -> refs
        ids != [] -> refs_from_ids(ids, id_key)
        true -> []
      end

    with :ok <- validate_ref_list(requested_refs, id_key),
         :ok <- validate_ref_id_alignment(ids, requested_refs, id_key) do
      resolve_versioned_refs(requested_refs, id_key, fetch_ref)
    end
  end

  defp validate_ref_list(refs, id_key) when is_list(refs) and is_binary(id_key) do
    if Enum.all?(refs, fn ref ->
         is_binary(Map.get(ref, id_key)) and Map.get(ref, id_key) != "" and
           (is_nil(Map.get(ref, "version")) or
              (is_integer(Map.get(ref, "version")) and Map.get(ref, "version") > 0))
       end) do
      :ok
    else
      {:error, :invalid_contact_runtime_config_reference}
    end
  end

  defp validate_ref_id_alignment([], _refs, _id_key), do: :ok

  defp validate_ref_id_alignment(ids, refs, id_key) do
    if ids == ids_from_refs(refs, id_key) do
      :ok
    else
      {:error, :contact_runtime_config_reference_mismatch}
    end
  end

  defp resolve_versioned_refs(refs, id_key, fetch_ref) do
    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      case fetch_ref.(ref) do
        {:ok, resource} ->
          versioned_ref = %{
            id_key => Map.fetch!(resource, :path_template_id),
            "version" => resource.version
          }

          {:cont, {:ok, acc ++ [versioned_ref]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp ids_from_refs(refs, id_key), do: Enum.map(refs, &Map.get(&1, id_key))
  defp refs_from_ids(ids, id_key), do: Enum.map(ids, &%{id_key => &1})
end
