defmodule CadenceWeb.API.CatalogParams do
  @moduledoc "Catalog and governed activation request parsing boundary."

  import CadenceWeb.API.ParamParser

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance,
    Selector,
    SelectorMatch,
    SelectorScope
  }

  alias Cadence.Catalog.Artifact
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @spec packet_definition(binary(), binary(), map()) ::
          {:ok, PacketDefinition.t()} | {:error, term()}
  def packet_definition(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, packet_name} <- required_string(params, "packet_name"),
         {:ok, apid} <- required_integer(params, "apid"),
         {:ok, version} <- positive_integer(params, "version", 1),
         {:ok, fields} <- field_definitions(params) do
      {:ok,
       PacketDefinition.new(%{
         packet_definition_id: string_value(params, "packet_definition_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         packet_name: packet_name,
         apid: apid,
         version: version,
         fields: fields
       })}
    end
  end

  @spec catalog_importer_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def catalog_importer_filters(params) when is_map(params) do
    with {:ok, catalog_family} <- optional_catalog_family(params, "catalog_family") do
      {:ok, [] |> maybe_put_opt(:catalog_family, catalog_family)}
    end
  end

  @spec catalog_artifact(binary(), binary(), map(), keyword()) ::
          {:ok, Artifact.t()} | {:error, term()}
  def catalog_artifact(organization_id, mission_id, params, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) and
             is_list(opts) do
    with {:ok, artifact_name} <- required_string(params, "artifact_name"),
         {:ok, catalog_family} <- required_catalog_family(params, "catalog_family"),
         {:ok, format_key} <- required_string(params, "format_key"),
         {:ok, source_artifact} <- required_json_term(params, "source_artifact") do
      {:ok,
       Artifact.new(%{
         artifact_id: string_value(params, "artifact_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         catalog_database_id: string_value(params, "catalog_database_id"),
         catalog_family: catalog_family,
         artifact_name: artifact_name,
         format_key: format_key,
         format_version: string_value(params, "format_version"),
         media_type: string_value(params, "media_type"),
         source_artifact: source_artifact,
         uploaded_by: Keyword.get(opts, :uploaded_by, %{}),
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec catalog_artifact_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def catalog_artifact_filters(params) when is_map(params) do
    with {:ok, catalog_family} <- optional_catalog_family(params, "catalog_family") do
      {:ok, [] |> maybe_put_opt(:catalog_family, catalog_family)}
    end
  end

  @spec catalog_import_run_request(map(), keyword()) ::
          {:ok, {binary(), binary(), keyword()}} | {:error, term()}
  def catalog_import_run_request(params, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, artifact_id} <- required_string(params, "artifact_id"),
         {:ok, importer_key} <- required_string(params, "importer_key"),
         {:ok, importer_version} <- optional_positive_integer(params, "importer_version") do
      {:ok,
       {artifact_id, importer_key,
        []
        |> Keyword.put(:requested_by, Keyword.get(opts, :requested_by, %{}))
        |> maybe_put_opt(:importer_version, importer_version)
        |> maybe_put_opt(:catalog_database_id, string_value(params, "catalog_database_id"))
        |> Keyword.put(:metadata, map_value(params, "metadata"))}}
    end
  end

  @spec catalog_import_run_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def catalog_import_run_filters(params) when is_map(params) do
    with {:ok, status} <- optional_import_run_status(params, "status") do
      {:ok,
       []
       |> maybe_put_opt(:artifact_id, string_value(params, "artifact_id"))
       |> maybe_put_opt(:status, status)}
    end
  end

  @spec binding_set(binary(), binary(), map()) :: {:ok, BindingSet.t()} | {:error, term()}
  def binding_set(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, version} <- positive_integer(params, "version", 1),
         {:ok, capability_instances} <- capability_instances(params),
         {:ok, rules} <- binding_rules(params) do
      {:ok,
       BindingSet.new(%{
         binding_set_id: string_value(params, "binding_set_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         version: version,
         capability_instances: capability_instances,
         rules: rules
       })}
    end
  end

  defp field_definitions(params) do
    params
    |> list_value("fields")
    |> Enum.reduce_while({:ok, []}, fn field_params, {:ok, acc} ->
      case field_definition(field_params) do
        {:ok, %FieldDefinition{} = field_definition} -> {:cont, {:ok, acc ++ [field_definition]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp field_definition(params) when is_map(params) do
    with {:ok, name} <- required_string(params, "name"),
         {:ok, size_bits} <- positive_integer(params, "size_bits", nil),
         {:ok, offset_bits} <- non_neg_integer(params, "offset_bits", 0),
         {:ok, data_type} <- existing_atom(params, "data_type", :uint) do
      {:ok,
       FieldDefinition.new(%{
         field_id: string_value(params, "field_id"),
         name: name,
         offset_bits: offset_bits,
         size_bits: size_bits,
         data_type: data_type,
         engineering_unit: string_value(params, "engineering_unit")
       })}
    end
  end

  defp capability_instances(params) do
    params
    |> list_value("capability_instances")
    |> Enum.reduce_while({:ok, []}, fn capability_instance_params, {:ok, acc} ->
      case capability_instance(capability_instance_params) do
        {:ok, %CapabilityInstance{} = capability_instance} ->
          {:cont, {:ok, acc ++ [capability_instance]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp capability_instance(params) when is_map(params) do
    with {:ok, family_key} <- existing_atom(params, "family_key", nil),
         {:ok, target_scope} <- existing_atom(params, "target_scope", :mission),
         {:ok, lifecycle_state} <- existing_atom(params, "lifecycle_state", :active),
         {:ok, capability_config} <- capability_config(params),
         {:ok, runtime_configuration} <- optional_map(params, "runtime_configuration") do
      {:ok,
       CapabilityInstance.new(%{
         capability_instance_id: string_value(params, "capability_instance_id"),
         family_key: family_key,
         target_scope: target_scope,
         source_endpoint_ref: string_value(params, "source_endpoint_ref"),
         lifecycle_state: lifecycle_state,
         capability_config: capability_config,
         runtime_configuration: runtime_configuration
       })}
    end
  end

  defp binding_rules(params) do
    params
    |> list_value("rules")
    |> Enum.reduce_while({:ok, []}, fn binding_rule_params, {:ok, acc} ->
      case binding_rule(binding_rule_params) do
        {:ok, %BindingRule{} = binding_rule} -> {:cont, {:ok, acc ++ [binding_rule]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp binding_rule(params) when is_map(params) do
    with {:ok, handler_key} <- existing_atom(params, "handler_key", nil),
         {:ok, priority} <- non_neg_integer(params, "priority", 100),
         {:ok, fanout_mode} <- existing_atom(params, "fanout_mode", :exclusive),
         {:ok, selector} <- selector(params),
         {:ok, capability_config} <- capability_config(params),
         {:ok, handler_configuration} <- optional_map(params, "handler_configuration") do
      {:ok,
       BindingRule.new(%{
         binding_rule_id: string_value(params, "binding_rule_id"),
         capability_instance_id: string_value(params, "capability_instance_id"),
         handler_key: handler_key,
         selector: selector,
         capability_config: capability_config,
         priority: priority,
         fanout_mode: fanout_mode,
         handler_configuration: handler_configuration
       })}
    end
  end

  defp selector(params) do
    with {:ok, scope} <- selector_scope(map_value(params, "selector") |> Map.get("scope", %{})),
         {:ok, match} <- selector_match(map_value(params, "selector") |> Map.get("match", %{})) do
      {:ok, %Selector{scope: scope, match: match}}
    end
  end

  defp selector_scope(params) when is_map(params) do
    with {:ok, target_scope} <- existing_atom(params, "target_scope", nil) do
      {:ok,
       SelectorScope.new(%{
         target_scope: target_scope,
         source_endpoint_ref: string_value(params, "source_endpoint_ref")
       })}
    end
  end

  defp selector_match(params) when is_map(params) do
    with {:ok, packet_kind} <- existing_atom(params, "packet_kind", nil),
         {:ok, apid} <- optional_integer(params, "apid") do
      {:ok, %SelectorMatch{packet_kind: packet_kind, apid: apid}}
    end
  end

  defp capability_config(params) do
    config_params = map_value(params, "capability_config")

    with {:ok, config_type} <- capability_config_type(config_params),
         {:ok, document} <- optional_map(config_params, "document", %{}) do
      {:ok,
       CapabilityConfig.new(%{
         config_type: config_type,
         document: document
       })}
    end
  end

  defp capability_config_type(params) when map_size(params) == 0, do: {:ok, :none}
  defp capability_config_type(params), do: existing_atom(params, "config_type", :none)
end
