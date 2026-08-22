defmodule CadenceWeb.API.ContactParams do
  @moduledoc "Contact lifecycle request parsing boundary."

  import CadenceWeb.API.ParamParser

  alias Cadence.Contacts.{
    KnownAtom,
    Path,
    ProviderBinding,
    ScheduledContact,
    TransportBinding
  }

  @contact_intent_values [
    :telemetry_downlink,
    :command_window,
    :tracking,
    :health_check,
    :maintenance
  ]

  @spec scheduled_contact(binary(), binary(), map()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def scheduled_contact(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, source_endpoint_refs} <- optional_string_list(params, "source_endpoint_refs"),
         {:ok, contact_intents} <-
           optional_allowed_atom_list(params, "contact_intents", @contact_intent_values),
         {:ok, link_assignment_refs} <-
           optional_ref_list(params, "link_assignment_refs", "link_assignment_id"),
         {:ok, path_template_ids} <- optional_string_list(params, "path_template_ids"),
         {:ok, path_template_refs} <-
           optional_versioned_ref_list(params, "path_template_refs", "path_template_id"),
         {:ok, starts_at} <- required_datetime(params, "starts_at"),
         {:ok, ends_at} <- optional_datetime(params, "ends_at"),
         {:ok, paths} <- contact_paths(params) do
      {:ok,
       ScheduledContact.new(%{
         scheduled_contact_id: string_value(params, "scheduled_contact_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         source_endpoint_refs: source_endpoint_refs,
         contact_intents: contact_intents,
         link_assignment_refs: link_assignment_refs,
         path_template_ids: path_template_ids,
         path_template_refs: path_template_refs,
         paths: paths,
         starts_at: starts_at,
         ends_at: ends_at,
         provider_contact_ref: string_value(params, "provider_contact_ref"),
         current_revision: 1,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec realization(map()) :: {:ok, keyword()} | {:error, term()}
  def realization(params) when is_map(params) do
    with {:ok, clock_mode} <- clock_mode(params),
         {:ok, initial_time} <- optional_datetime(params, "initial_time"),
         {:ok, realized_at} <- optional_datetime(params, "realized_at"),
         {:ok, transition_time} <- optional_datetime(params, "transition_time") do
      {:ok,
       []
       |> maybe_put_opt(:clock_mode, clock_mode)
       |> maybe_put_opt(:initial_time, initial_time)
       |> maybe_put_opt(:realized_at, realized_at)
       |> maybe_put_opt(:transition_time, transition_time)
       |> maybe_put_opt(:realized_contact_id, string_value(params, "realized_contact_id"))
       |> Keyword.put(:metadata, map_value(params, "metadata"))}
    end
  end

  @spec contact_action(map()) :: {:ok, keyword()} | {:error, term()}
  def contact_action(params) when is_map(params) do
    with {:ok, transition_time} <- optional_datetime(params, "transition_time"),
         {:ok, actor} <- optional_map(params, "actor", %{}) do
      {:ok,
       []
       |> maybe_put_opt(:transition_time, transition_time)
       |> maybe_put_opt(:reason, string_value(params, "reason"))
       |> Keyword.put(:actor, actor)
       |> Keyword.put(:metadata, map_value(params, "metadata"))}
    end
  end

  defp contact_paths(params) do
    params
    |> list_value("paths")
    |> Enum.reduce_while({:ok, []}, fn path_params, {:ok, acc} ->
      case contact_path(path_params) do
        {:ok, %Path{} = path} -> {:cont, {:ok, acc ++ [path]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp contact_path(params) when is_map(params) do
    with {:ok, direction} <- direction(params),
         {:ok, selection_role} <- selection_role(params),
         {:ok, provider_bindings} <- provider_bindings(params),
         {:ok, transport_bindings} <- transport_bindings(params) do
      {:ok,
       Path.new(%{
         path_id: string_value(params, "path_id"),
         direction: direction,
         selection_role: selection_role,
         source_endpoint_ref: string_value(params, "source_endpoint_ref"),
         provider_path_ref: string_value(params, "provider_path_ref"),
         provider_bindings: provider_bindings,
         transport_bindings: transport_bindings,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  defp provider_bindings(params) do
    params
    |> list_value("provider_bindings")
    |> Enum.reduce_while({:ok, []}, fn binding_params, {:ok, acc} ->
      case provider_binding(binding_params) do
        {:ok, %ProviderBinding{} = provider_binding} ->
          {:cont, {:ok, acc ++ [provider_binding]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp provider_binding(params) when is_map(params) do
    with {:ok, adapter_key} <- provider_adapter_key(params),
         {:ok, configuration} <- optional_map(params, "configuration", %{}) do
      {:ok,
       ProviderBinding.new(%{
         provider_binding_id: string_value(params, "provider_binding_id"),
         adapter_key: adapter_key,
         configuration: configuration,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  defp provider_adapter_key(params) do
    case Map.get(params, "adapter_key") do
      nil ->
        {:ok, nil}

      value ->
        try do
          {:ok, KnownAtom.provider_adapter_key!(value)}
        rescue
          ArgumentError -> {:error, {:invalid_param, "adapter_key", :unknown_atom}}
        end
    end
  end

  defp transport_bindings(params) do
    params
    |> list_value("transport_bindings")
    |> Enum.reduce_while({:ok, []}, fn binding_params, {:ok, acc} ->
      case transport_binding(binding_params) do
        {:ok, %TransportBinding{} = transport_binding} ->
          {:cont, {:ok, acc ++ [transport_binding]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp transport_binding(params) when is_map(params) do
    with {:ok, family_key} <- transport_family_key(params),
         {:ok, target_scope} <- transport_target_scope(params),
         {:ok, configuration} <- optional_map(params, "configuration", %{}) do
      {:ok,
       TransportBinding.new(%{
         transport_binding_id: string_value(params, "transport_binding_id"),
         family_key: family_key,
         target_scope: target_scope,
         configuration: configuration,
         metadata: map_value(params, "metadata")
       })}
    end
  end
end
