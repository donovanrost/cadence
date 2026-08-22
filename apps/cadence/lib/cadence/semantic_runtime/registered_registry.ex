defmodule Cadence.SemanticRuntime.RegisteredRegistry do
  @moduledoc "Runtime-only allowlist for registered semantic algorithms."

  alias Cadence.SemanticRuntime.RegisteredImplementation

  @spec bind(map(), map()) :: map()
  def bind(implementation, registry \\ configured()) when is_map(implementation) do
    case kind(implementation) do
      :expression ->
        %{kind: :expression}

      :registered ->
        key = value(implementation, :key)
        version = value(implementation, :version)

        case fetch(registry, key, version) do
          {:ok, module, artifact_sha256} ->
            %{
              kind: :registered,
              key: key,
              version: version,
              module: module,
              artifact_sha256: artifact_sha256,
              authorized?: true
            }

          {:error, reason} ->
            %{kind: :registered, key: key, version: version, authorization_error: reason}
        end

      other ->
        %{kind: other, authorization_error: :unsupported_implementation_kind}
    end
  end

  @spec configured() :: map()
  def configured do
    Application.get_env(:cadence, :semantic_algorithm_implementations, %{})
  end

  defp fetch(_registry, key, version)
       when not is_binary(key) or key == "" or not is_binary(version) or version == "",
       do: {:error, :registered_implementation_identity_required}

  defp fetch(registry, key, version) when is_map(registry) do
    entry =
      Map.get(
        registry,
        {key, version},
        get_in(registry, [key, version]) || Map.get(registry, key)
      )

    {module, configured_artifact_sha256} =
      case entry do
        %{module: configured_module, version: ^version} = configured ->
          {configured_module, Map.get(configured, :artifact_sha256)}

        %{"module" => configured_module, "version" => ^version} = configured ->
          {configured_module, Map.get(configured, "artifact_sha256")}

        configured_module when is_atom(configured_module) ->
          {configured_module, nil}

        _other ->
          {nil, nil}
      end

    with true <- implementation?(module),
         {:ok, artifact_sha256} <- artifact_sha256(module),
         true <- configured_artifact_sha256 in [nil, artifact_sha256] do
      {:ok, module, artifact_sha256}
    else
      _other -> {:error, :registered_implementation_not_allowed}
    end
  end

  defp artifact_sha256(module) do
    case :code.get_object_code(module) do
      {^module, beam, _filename} when is_binary(beam) ->
        {:ok, :crypto.hash(:sha256, beam) |> Base.encode16(case: :lower)}

      _other ->
        {:error, :registered_implementation_artifact_unavailable}
    end
  end

  defp implementation?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :evaluate, 3) and
      RegisteredImplementation in behaviours(module)
  end

  defp implementation?(_module), do: false

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp kind(implementation) do
    case value(implementation, :kind, :expression) do
      value when value in [:expression, "expression"] -> :expression
      value when value in [:registered, "registered"] -> :registered
      value -> value
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
