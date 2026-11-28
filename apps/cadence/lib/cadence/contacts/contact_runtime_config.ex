defmodule Cadence.Contacts.ContactRuntimeConfig do
  @moduledoc """
  Prepares and resolves pinned runtime configuration for scheduled contacts.
  """

  alias Cadence.Contacts.LinkAssignment
  alias Cadence.Contacts.LinkAssignmentStore
  alias Cadence.Contacts.Path
  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.PathTemplateStore
  alias Cadence.Contacts.PathTemplateStore.VersionedReferences
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
    [scheduled_contact]
    |> resolve_paths_many()
    |> Map.fetch!(scheduled_contact)
  end

  @doc "Resolve each scheduled contact with one batch of runtime references per mission scope."
  @spec resolve_paths_many([ScheduledContact.t()]) :: %{
          ScheduledContact.t() => {:ok, [Path.t()]} | {:error, term()}
        }
  def resolve_paths_many(contacts) do
    contacts
    |> Enum.group_by(&{&1.organization_id, &1.mission_id})
    |> Enum.flat_map(fn {{org, mission}, contacts} ->
      resolve_mission_paths(org, mission, contacts)
    end)
    |> Map.new()
  end

  defp resolve_mission_paths(org, mission, contacts) do
    assignment_ids =
      for contact <- contacts,
          ref <- contact.link_assignment_refs,
          id = Map.get(ref, "link_assignment_id"),
          is_binary(id) and id != "",
          uniq: true,
          do: id

    assignments =
      if is_binary(org) and org != "",
        do: LinkAssignmentStore.fetch_many(org, mission, assignment_ids),
        else: LinkAssignmentStore.fetch_many(mission, assignment_ids)

    template_refs =
      Enum.flat_map(contacts, &template_refs/1) ++
        Enum.map(Map.values(assignments), &assignment_template_ref/1)

    templates = PathTemplateStore.load_refs(org, mission, template_refs)

    by_contact =
      Enum.map(contacts, fn contact ->
        assigned =
          Enum.map(contact.link_assignment_refs, &assignment_template(&1, assignments, templates))

        direct =
          Enum.map(template_refs(contact), &PathTemplateStore.fetch_loaded_ref(templates, &1))

        {contact, assigned, direct}
      end)

    # Keep each missing reference in its original position so the first failing path still
    # determines the contact's error, including failures while resolving a template's bindings.
    resolvable =
      for {_contact, assigned, direct} <- by_contact,
          {:ok, template} <- assigned ++ direct,
          do: template

    resolved = PathTemplateStore.resolve_many(resolvable)

    Enum.map(by_contact, fn {contact, assigned, direct} ->
      {contact, assemble_paths(contact, assigned, direct, resolved)}
    end)
  end

  defp template_refs(contact) do
    VersionedReferences.refs(
      contact.path_template_ids,
      contact.path_template_refs,
      "path_template_id"
    )
  end

  defp assignment_template_ref(assignment) do
    %{
      "path_template_id" => assignment.path_template_id,
      "version" => assignment.path_template_version
    }
  end

  defp assignment_template(ref, assignments, templates) do
    with {:ok, assignment} <- fetch_link_assignment_ref(ref, &Map.fetch(assignments, &1)),
         {:ok, template} <-
           PathTemplateStore.fetch_loaded_ref(templates, assignment_template_ref(assignment)) do
      {:ok, assignment_path_template(assignment, template)}
    else
      :error -> {:error, :contact_link_assignment_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp assemble_paths(contact, assigned, direct, resolved) do
    with {:ok, assignment_paths} <- resolved_templates(assigned, resolved),
         {:ok, template_paths} <- resolved_templates(direct, resolved) do
      {:ok, assignment_paths ++ booked(contact, template_paths) ++ contact.paths}
    end
  end

  defp resolved_templates(templates, resolved) do
    Enum.reduce_while(templates, {:ok, []}, fn ref, {:ok, acc} ->
      with {:ok, template} <- ref,
           {:ok, path} <- Map.fetch!(resolved, template) do
        {:cont, {:ok, acc ++ [path]}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # A provider booking names the paths of the route it was booked on. On that contact those
  # paths are the selected ones, even when the route is a candidate (a fallback station chosen
  # because the primary was unavailable); otherwise the contact could never be scheduled.
  defp booked(%ScheduledContact{metadata: %{"provider_reservation_id" => id}} = contact, paths)
       when is_binary(id),
       do: Enum.map(paths, &scope_uplink_resource(%{&1 | selection_role: :selected}, contact, id))

  defp booked(_scheduled_contact, paths), do: paths

  # DECISIONS #59: a provider-managed pass is its own external uplink session, so its uplink
  # resource is the booking's, not the route listener's. Protocol state then doesn't carry
  # from one pass into the next (each pass's FOP initializes from the FARM's first report),
  # while a restart within a pass still finds that pass's sends and fails closed. Two sessions
  # can't share one listener: it binds its port exclusively.
  defp scope_uplink_resource(path, contact, reservation_id) do
    booking = contact.provider_contact_ref || reservation_id

    bindings =
      Enum.map(path.provider_bindings, fn binding ->
        case binding.configuration do
          %{"uplink_resource_id" => resource} = config when is_binary(resource) ->
            %{
              binding
              | configuration:
                  Map.put(config, "uplink_resource_id", resource <> ":pass:" <> booking)
            }

          _no_uplink ->
            binding
        end
      end)

    %{path | provider_bindings: bindings}
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

  defp resolve_link_assignment_refs(organization_id, mission_id, link_assignment_refs)
       when is_list(link_assignment_refs) do
    Enum.reduce_while(link_assignment_refs, {:ok, []}, fn ref, {:ok, acc} ->
      case fetch_link_assignment_ref(ref, &fetch_link_assignment(organization_id, mission_id, &1)) do
        {:ok, %LinkAssignment{} = assignment} -> {:cont, {:ok, acc ++ [assignment]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_link_assignment_ref(ref, fetch) do
    case Map.get(ref, "link_assignment_id") do
      link_assignment_id when is_binary(link_assignment_id) and link_assignment_id != "" ->
        fetch.(link_assignment_id)

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
