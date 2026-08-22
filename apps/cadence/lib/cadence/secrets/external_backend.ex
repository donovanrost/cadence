defmodule Cadence.Secrets.ExternalBackend do
  @moduledoc "Req-backed integration with an external secret-management service."

  @behaviour Cadence.Secrets.Backend

  alias Cadence.Persistence.JsonDocument

  @default_timeout_ms 5_000
  @max_timeout_ms 30_000

  @default_paths %{
    resolve: "/v1/secrets/resolve",
    create: "/v1/secrets",
    rotate: "/v1/secrets/rotate",
    revoke: "/v1/secrets/revoke"
  }

  @impl true
  def capabilities(_opts), do: [:resolve, :create, :rotate, :revoke]

  @impl true
  def resolve(descriptor, opts \\ []), do: request(:resolve, descriptor, opts)

  @impl true
  def create(descriptor, opts \\ []), do: request(:create, descriptor, opts)

  @impl true
  def rotate(descriptor, opts \\ []), do: request(:rotate, descriptor, opts)

  @impl true
  def revoke(descriptor, opts \\ []), do: request(:revoke, descriptor, opts)

  defp request(operation, descriptor, opts) do
    with {:ok, url} <- secret_manager_url(operation, opts),
         {:ok, response} <- request_backend(url, operation, descriptor, opts) do
      response_payload(operation, response)
    end
  end

  defp secret_manager_url(operation, opts) do
    configured =
      Keyword.get(opts, :secret_manager_url) ||
        Keyword.get(opts, :external_secret_manager_url) ||
        secret_config_value(:secret_manager_url) ||
        secret_config_value(:external_secret_manager_url)

    case configured do
      url when is_binary(url) and url != "" ->
        url
        |> compose_url(operation, opts)
        |> validate_url(opts)

      _missing ->
        {:error, :external_secret_manager_not_configured}
    end
  end

  defp validate_url(url, opts) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) ->
        {:ok, url}

      %URI{scheme: "http", host: host, userinfo: nil} when is_binary(host) ->
        if allow_insecure_http?(opts),
          do: {:ok, url},
          else: {:error, {:invalid_external_secret_manager_url, :https_required}}

      _other ->
        {:error, {:invalid_external_secret_manager_url, :invalid_url}}
    end
  end

  defp allow_insecure_http?(opts) do
    Keyword.get(opts, :allow_insecure_secret_manager_http?, false) ||
      secret_config_value(:allow_insecure_secret_manager_http?) == true
  end

  defp request_backend(url, operation, descriptor, opts) do
    req_request = Keyword.get(opts, :req_request, &Req.request/1)

    request = [
      method: method(operation),
      url: url,
      json: request_payload(operation, descriptor),
      headers: request_headers(opts),
      receive_timeout: request_timeout_ms(opts),
      retry: false,
      retry_log_level: false,
      redirect_log_level: false
    ]

    case req_request.(request) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, {:external_secret_manager_request_failed, reason_token(reason)}}
    end
  end

  defp response_payload(operation, %Req.Response{status: status, body: body})
       when status in 200..299,
       do: success_payload(operation, body)

  defp response_payload(_operation, %Req.Response{status: status}),
    do: {:error, {:external_secret_manager_http_error, status}}

  defp response_payload(operation, %{status: status, body: body}) when status in 200..299,
    do: success_payload(operation, body)

  defp response_payload(_operation, %{status: status}) when is_integer(status),
    do: {:error, {:external_secret_manager_http_error, status}}

  defp response_payload(_operation, _response),
    do: {:error, :invalid_external_secret_manager_response}

  defp success_payload(:resolve, body) when is_map(body) do
    case map_value(body, :material) do
      material when is_map(material) or is_binary(material) ->
        {:ok, response_metadata(body) |> Map.put(:material, material)}

      nil ->
        {:ok, %{material: body}}

      _other ->
        {:error, :invalid_external_secret_manager_response}
    end
  end

  defp success_payload(:resolve, _body),
    do: {:error, :invalid_external_secret_manager_response}

  defp success_payload(_operation, body) when is_map(body), do: {:ok, response_metadata(body)}
  defp success_payload(_operation, _body), do: {:ok, %{}}

  defp response_metadata(body) do
    %{
      backend_version: map_value(body, :backend_version) || map_value(body, :version),
      fingerprint: map_value(body, :fingerprint),
      expires_at: map_value(body, :expires_at),
      backend_reference: map_value(body, :backend_reference)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp compose_url(url, operation, opts) do
    path = Keyword.get(opts, :secret_manager_path, Map.fetch!(@default_paths, operation))
    parsed = URI.parse(url)

    if parsed.path in [nil, "", "/"] and is_binary(path) do
      parsed
      |> Map.put(:path, path)
      |> URI.to_string()
    else
      url
    end
  end

  defp request_headers(opts) do
    opts
    |> Keyword.get(:secret_manager_headers, [])
    |> normalize_headers()
    |> maybe_put_bearer_token(opts)
  end

  defp normalize_headers(headers) when is_map(headers),
    do: Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)

  defp normalize_headers(headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      {key, value} -> [{to_string(key), to_string(value)}]
      _other -> []
    end)
  end

  defp normalize_headers(_headers), do: []

  defp maybe_put_bearer_token(headers, opts) do
    case secret_manager_token(opts) do
      token when is_binary(token) and token != "" ->
        [{"authorization", "Bearer #{token}"} | headers]

      _missing ->
        headers
    end
  end

  defp secret_manager_token(opts) do
    non_empty_string(Keyword.get(opts, :secret_manager_token)) ||
      non_empty_string(token_from_env(opts)) ||
      non_empty_string(secret_config_value(:secret_manager_token))
  end

  defp token_from_env(opts) do
    env_var =
      Keyword.get(opts, :secret_manager_token_env) ||
        secret_config_value(:secret_manager_token_env)

    env_reader = Keyword.get(opts, :env_reader, &System.get_env/1)

    if is_binary(env_var) and env_var != "" and is_function(env_reader, 1),
      do: env_reader.(env_var)
  end

  defp request_timeout_ms(opts) do
    case Keyword.get(opts, :secret_manager_timeout_ms, @default_timeout_ms) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 ->
        min(timeout_ms, @max_timeout_ms)

      _invalid ->
        @default_timeout_ms
    end
  end

  defp request_payload(operation, descriptor) do
    descriptor
    |> descriptor_map()
    |> Map.drop([:secret_material?, :references])
    |> JsonDocument.encode()
    |> atomize_known_payload_keys(descriptor)
    |> Map.put(:operation, operation)
  end

  defp atomize_known_payload_keys(encoded, descriptor) do
    descriptor
    |> descriptor_map()
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, payload ->
      if key in [:secret_material?, :references] do
        payload
      else
        Map.put(payload, key, Map.get(encoded, Atom.to_string(key)))
      end
    end)
  end

  defp method(:create), do: :post
  defp method(:resolve), do: :post
  defp method(:rotate), do: :post
  defp method(:revoke), do: :post

  defp secret_config_value(key) do
    shared = Application.get_env(:cadence, :secrets, [])
    dashboard = Application.get_env(:cadence, :data_source_credentials, [])
    Keyword.get(shared, key) || Keyword.get(dashboard, key)
  end

  defp non_empty_string(value) when is_binary(value) and value != "", do: value
  defp non_empty_string(_value), do: nil

  defp reason_token(reason) when is_atom(reason), do: reason
  defp reason_token(%{reason: reason}) when is_atom(reason), do: reason
  defp reason_token(_reason), do: :request_failed

  defp map_value(map, key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp descriptor_map(%_{} = descriptor), do: Map.from_struct(descriptor)
  defp descriptor_map(descriptor) when is_map(descriptor), do: descriptor
end
