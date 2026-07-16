defmodule Cadence.Secrets.Resolver do
  @moduledoc "Capability-gated dispatcher for configured secret backends."

  alias Cadence.Secrets.{MaterialPolicy, ResolvedSecret}

  @operations [:resolve, :create, :rotate, :revoke]

  @spec resolve(struct() | map(), keyword()) :: {:ok, ResolvedSecret.t()} | {:error, term()}
  def resolve(descriptor, opts \\ []) when is_map(descriptor) and is_list(opts) do
    with {:ok, response} <- perform(:resolve, descriptor, opts),
         {:ok, material, metadata} <- normalize_resolution_response(response),
         {:ok, material} <- MaterialPolicy.normalize_and_validate(material, material_policy(opts)) do
      {:ok, ResolvedSecret.new(descriptor, material, metadata)}
    end
  end

  @spec mutate(:create | :rotate | :revoke, struct() | map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def mutate(operation, descriptor, opts)
      when operation in [:create, :rotate, :revoke] and is_map(descriptor) and is_list(opts) do
    with {:ok, response} <- perform(operation, descriptor, opts) do
      {:ok, public_metadata(response)}
    end
  end

  @spec configured?(keyword()) :: boolean()
  def configured?(opts \\ []) when is_list(opts), do: not is_nil(backend(opts))

  @spec backend(keyword()) :: term()
  def backend(opts) when is_list(opts) do
    Keyword.get(opts, :secret_backend) ||
      Keyword.get(opts, :credential_secret_backend) ||
      Keyword.get(opts, :provider_secret_backend) ||
      :cadence
      |> Application.get_env(:secrets, [])
      |> Keyword.get(:backend)
  end

  defp perform(operation, descriptor, opts) when operation in @operations do
    case backend(opts) do
      nil ->
        {:error, :secret_backend_not_configured}

      backend ->
        with :ok <- ensure_capability(backend, operation, opts),
             result <- call_backend(backend, operation, descriptor, opts) do
          normalize_backend_result(result, opts)
        end
    end
  end

  defp ensure_capability(backend, operation, opts) do
    if operation in backend_capabilities(backend, opts),
      do: :ok,
      else: {:error, {:secret_backend_capability_not_supported, operation}}
  end

  defp backend_capabilities(backend, opts) when is_atom(backend) do
    if Code.ensure_loaded?(backend) and function_exported?(backend, :capabilities, 1),
      do: backend.capabilities(opts),
      else: [:resolve]
  end

  defp backend_capabilities({module, _function}, opts) when is_atom(module) do
    if function_exported?(module, :capabilities, 1),
      do: module.capabilities(opts),
      else: [:resolve]
  end

  defp backend_capabilities({module, _function, _extra_args}, opts) when is_atom(module) do
    if function_exported?(module, :capabilities, 1),
      do: module.capabilities(opts),
      else: [:resolve]
  end

  defp backend_capabilities(backend, _opts) when is_function(backend), do: [:resolve]
  defp backend_capabilities(_backend, _opts), do: []

  defp call_backend(backend, operation, descriptor, opts) when is_atom(backend) do
    if Code.ensure_loaded?(backend) and function_exported?(backend, operation, 2) do
      apply(backend, operation, [descriptor, opts])
    else
      {:error, {:unsupported_secret_backend, backend}}
    end
  end

  defp call_backend(backend, :resolve, descriptor, opts) when is_function(backend, 2),
    do: backend.(descriptor, opts)

  defp call_backend(backend, :resolve, descriptor, _opts) when is_function(backend, 1),
    do: backend.(descriptor)

  defp call_backend({module, function}, :resolve, descriptor, opts)
       when is_atom(module) and is_atom(function),
       do: apply(module, function, [descriptor, opts])

  defp call_backend({module, function, extra_args}, :resolve, descriptor, opts)
       when is_atom(module) and is_atom(function) and is_list(extra_args),
       do: apply(module, function, [descriptor, opts | extra_args])

  defp call_backend(_backend, operation, _descriptor, _opts),
    do: {:error, {:unsupported_secret_backend_operation, operation}}

  defp normalize_backend_result({:ok, response}, _opts)
       when is_map(response) or is_binary(response),
       do: {:ok, response}

  defp normalize_backend_result(response, _opts) when is_map(response) or is_binary(response),
    do: {:ok, response}

  defp normalize_backend_result({:error, reason}, opts) do
    if Keyword.get(opts, :sanitize_secret_errors?, true),
      do: {:error, sanitize_reason(reason)},
      else: {:error, reason}
  end

  defp normalize_backend_result(_other, _opts), do: {:error, :invalid_secret_backend_response}

  defp normalize_resolution_response(response) when is_binary(response),
    do: {:ok, %{value: response}, %{}}

  defp normalize_resolution_response(response) when is_map(response) do
    case response_value(response, :material) do
      material when is_map(material) or is_binary(material) ->
        {:ok, material, response}

      nil ->
        {:ok, response, %{}}

      _other ->
        {:error, :invalid_secret_backend_material}
    end
  end

  defp material_policy(opts) do
    [
      allowed_material_keys:
        Keyword.get(opts, :allowed_material_keys, MaterialPolicy.provider_keys()),
      validate_auth_shape?: Keyword.get(opts, :validate_auth_shape?, true),
      allow_empty?: false
    ]
  end

  defp public_metadata(response) when is_binary(response), do: %{}

  defp public_metadata(response) when is_map(response) do
    %{
      backend_version: response_value(response, :backend_version),
      fingerprint: response_value(response, :fingerprint),
      expires_at: response_value(response, :expires_at),
      backend_reference: response_value(response, :backend_reference)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp response_value(response, key),
    do: Map.get(response, key, Map.get(response, Atom.to_string(key)))

  defp sanitize_reason(reason) when is_atom(reason), do: reason
  defp sanitize_reason({kind, value}) when is_atom(kind) and is_integer(value), do: {kind, value}
  defp sanitize_reason({kind, value}) when is_atom(kind) and is_atom(value), do: {kind, value}

  defp sanitize_reason({kind, value}) when is_atom(kind) and is_binary(value),
    do: {kind, :redacted}

  defp sanitize_reason(reason) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.map(&sanitize_reason/1)
    |> List.to_tuple()
  end

  defp sanitize_reason(_reason), do: :secret_backend_failed
end
