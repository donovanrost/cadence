defmodule Cadence.Commanding.ReleaseTargetSelection do
  @moduledoc """
  Selects eligible realized contacts, uplink paths, and transport bindings.
  """

  alias Cadence.Commanding.CommandRequest
  alias Cadence.Contacts
  alias Cadence.Contacts.{Path, RealizedContact, TransportBinding}

  @spec fetch_realized_contact(binary(), binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized_contact(organization_id, mission_id, realized_contact_id) do
    with {:ok, %RealizedContact{} = realized_contact} <-
           Contacts.fetch_realized_contact(organization_id, mission_id, realized_contact_id),
         :ok <- ensure_realized_contact_releasable(realized_contact) do
      {:ok, realized_contact}
    end
  end

  @spec resolve_dispatch(binary(), binary(), CommandRequest.t()) ::
          {:ok,
           %{
             realized_contact: RealizedContact.t(),
             path: Path.t(),
             transport_binding: TransportBinding.t()
           }}
          | {:error, term()}
  def resolve_dispatch(organization_id, mission_id, %CommandRequest{} = command_request) do
    organization_id
    |> Contacts.list_realized_contacts(mission_id)
    |> Enum.filter(fn %RealizedContact{} = realized_contact ->
      ensure_realized_contact_releasable(realized_contact) == :ok
    end)
    |> Enum.sort_by(&dispatch_contact_sort_key/1)
    |> Enum.reduce_while(
      {:error,
       {:command_queue_lane_no_release_target, command_request.source_endpoint_ref, mission_id}},
      fn %RealizedContact{} = realized_contact, _acc ->
        case resolve(realized_contact, command_request, []) do
          {:ok,
           %{path: %Path{} = path, transport_binding: %TransportBinding{} = transport_binding}} ->
            {:halt,
             {:ok,
              %{
                realized_contact: realized_contact,
                path: path,
                transport_binding: transport_binding
              }}}

          {:error, _reason} ->
            {:cont,
             {:error,
              {:command_queue_lane_no_release_target, command_request.source_endpoint_ref,
               mission_id}}}
        end
      end
    )
  end

  @spec resolve(RealizedContact.t(), CommandRequest.t(), keyword()) ::
          {:ok, %{path: Path.t(), transport_binding: TransportBinding.t()}} | {:error, term()}
  def resolve(
        %RealizedContact{} = realized_contact,
        %CommandRequest{} = command_request,
        opts
      )
      when is_list(opts) do
    with {:ok, %Path{} = path} <- resolve_release_path(realized_contact, command_request, opts),
         {:ok, %TransportBinding{} = transport_binding} <-
           resolve_release_transport_binding(path, command_request, opts) do
      {:ok, %{path: path, transport_binding: transport_binding}}
    end
  end

  defp ensure_realized_contact_releasable(%RealizedContact{lifecycle_state: lifecycle_state})
       when lifecycle_state in [:defined, :active],
       do: :ok

  defp ensure_realized_contact_releasable(%RealizedContact{} = realized_contact) do
    {:error,
     {:realized_contact_not_releasable, realized_contact.realized_contact_id,
      realized_contact.lifecycle_state}}
  end

  defp dispatch_contact_sort_key(%RealizedContact{} = realized_contact) do
    lifecycle_rank =
      case realized_contact.lifecycle_state do
        :active -> 0
        :defined -> 1
        _other -> 2
      end

    {lifecycle_rank, realized_contact.realized_at || realized_contact.initial_time,
     realized_contact.realized_contact_id}
  end

  defp resolve_release_path(
         %RealizedContact{} = realized_contact,
         %CommandRequest{} = command_request,
         opts
       ) do
    case Keyword.get(opts, :path_id) do
      path_id when is_binary(path_id) ->
        with {:ok, %Path{} = path} <- fetch_contact_path(realized_contact, path_id),
             :ok <- ensure_uplink_path(path),
             :ok <- ensure_selected_uplink_path(path),
             :ok <-
               ensure_path_matches_source_endpoint(path, command_request.source_endpoint_ref) do
          {:ok, path}
        end

      _other ->
        select_release_path(realized_contact, command_request.source_endpoint_ref)
    end
  end

  defp fetch_contact_path(%RealizedContact{} = realized_contact, path_id) do
    case Enum.find(realized_contact.paths, &(&1.path_id == path_id)) do
      nil ->
        {:error,
         {:realized_contact_path_not_found, realized_contact.realized_contact_id, path_id}}

      %Path{} = path ->
        {:ok, path}
    end
  end

  defp ensure_uplink_path(%Path{direction: :uplink}), do: :ok

  defp ensure_uplink_path(%Path{} = path),
    do: {:error, {:realized_contact_path_not_uplink, path.path_id}}

  defp ensure_selected_uplink_path(%Path{selection_role: :selected}), do: :ok

  defp ensure_selected_uplink_path(%Path{} = path) do
    {:error, {:realized_contact_path_not_selected_for_uplink, path.path_id}}
  end

  defp ensure_path_matches_source_endpoint(%Path{source_endpoint_ref: nil}, _source_endpoint_ref),
    do: :ok

  defp ensure_path_matches_source_endpoint(
         %Path{source_endpoint_ref: source_endpoint_ref},
         source_endpoint_ref
       ),
       do: :ok

  defp ensure_path_matches_source_endpoint(%Path{} = path, source_endpoint_ref) do
    {:error, {:realized_contact_path_source_endpoint_mismatch, path.path_id, source_endpoint_ref}}
  end

  defp select_release_path(%RealizedContact{} = realized_contact, source_endpoint_ref) do
    matching_paths =
      Enum.filter(realized_contact.paths, fn %Path{} = path ->
        path.direction == :uplink and path.selection_role == :selected and
          (is_nil(path.source_endpoint_ref) or path.source_endpoint_ref == source_endpoint_ref)
      end)

    case matching_paths do
      [%Path{} = path] ->
        {:ok, path}

      [] ->
        {:error,
         {:selected_uplink_path_not_found, realized_contact.realized_contact_id,
          source_endpoint_ref}}

      _multiple ->
        {:error,
         {:realized_contact_has_multiple_matching_selected_uplink_paths,
          realized_contact.realized_contact_id, source_endpoint_ref}}
    end
  end

  defp resolve_release_transport_binding(
         %Path{} = path,
         %CommandRequest{} = command_request,
         opts
       ) do
    case Keyword.get(opts, :transport_binding_id) do
      transport_binding_id when is_binary(transport_binding_id) ->
        with {:ok, %TransportBinding{} = transport_binding} <-
               fetch_transport_binding(path, transport_binding_id),
             :ok <-
               ensure_transport_binding_matches_preferred_service(
                 transport_binding,
                 command_request
               ) do
          {:ok, transport_binding}
        end

      _other ->
        select_transport_binding(path, command_request)
    end
  end

  defp fetch_transport_binding(%Path{} = path, transport_binding_id) do
    case Enum.find(path.transport_bindings, &(&1.transport_binding_id == transport_binding_id)) do
      nil -> {:error, {:uplink_transport_binding_not_found, path.path_id, transport_binding_id}}
      %TransportBinding{} = transport_binding -> {:ok, transport_binding}
    end
  end

  defp select_transport_binding(%Path{transport_bindings: []} = path, %CommandRequest{}) do
    {:error, {:uplink_transport_binding_not_configured, path.path_id}}
  end

  defp select_transport_binding(
         %Path{transport_bindings: [transport_binding]},
         %CommandRequest{} = command_request
       ) do
    with :ok <-
           ensure_transport_binding_matches_preferred_service(
             transport_binding,
             command_request
           ) do
      {:ok, transport_binding}
    end
  end

  defp select_transport_binding(%Path{} = path, %CommandRequest{} = command_request) do
    preferred_uplink_service = command_request.preferred_uplink_service

    matching_transport_bindings =
      Enum.filter(path.transport_bindings, fn %TransportBinding{} = transport_binding ->
        transport_binding_matches_preferred_service?(transport_binding, preferred_uplink_service)
      end)

    case {preferred_uplink_service, matching_transport_bindings} do
      {preferred_uplink_service, [%TransportBinding{} = transport_binding]}
      when is_binary(preferred_uplink_service) and preferred_uplink_service != "" ->
        {:ok, transport_binding}

      {preferred_uplink_service, []}
      when is_binary(preferred_uplink_service) and preferred_uplink_service != "" ->
        {:error,
         {:preferred_uplink_transport_binding_not_found, path.path_id, preferred_uplink_service}}

      {nil, _matching_transport_bindings} ->
        {:error, {:multiple_uplink_transport_bindings_require_explicit_selection, path.path_id}}

      {_preferred_uplink_service, _matching_transport_bindings} ->
        {:error, {:multiple_uplink_transport_bindings_match_preferred_service, path.path_id}}
    end
  end

  defp ensure_transport_binding_matches_preferred_service(
         %TransportBinding{} = transport_binding,
         %CommandRequest{} = command_request
       ) do
    if transport_binding_matches_preferred_service?(
         transport_binding,
         command_request.preferred_uplink_service
       ) do
      :ok
    else
      {:error,
       {:preferred_uplink_transport_binding_not_found, transport_binding.transport_binding_id,
        command_request.preferred_uplink_service}}
    end
  end

  defp transport_binding_matches_preferred_service?(
         %TransportBinding{},
         preferred_uplink_service
       )
       when not is_binary(preferred_uplink_service) or preferred_uplink_service == "",
       do: true

  defp transport_binding_matches_preferred_service?(
         %TransportBinding{} = transport_binding,
         preferred_uplink_service
       ) do
    preferred_uplink_service in transport_binding_service_names(transport_binding)
  end

  defp transport_binding_service_names(%TransportBinding{} = transport_binding) do
    configuration_service_name =
      case transport_binding.configuration do
        configuration when is_map(configuration) ->
          Map.get(configuration, :service_name) || Map.get(configuration, "service_name")

        _other ->
          nil
      end

    metadata_service_name =
      Map.get(transport_binding.metadata, :service_name) ||
        Map.get(transport_binding.metadata, "service_name")

    [
      configuration_service_name,
      metadata_service_name,
      Atom.to_string(transport_binding.family_key)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end
end
