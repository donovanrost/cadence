defmodule Cadence.Dashboards.SourceCredentials.ExternalSecretBackend do
  @moduledoc """
  HTTP-backed secret-manager integration for dashboard source credentials.

  The backend sends the non-secret credential descriptor to a configured secret
  manager endpoint and expects ephemeral adapter material in response. It does
  not persist or log returned material; `SecretMaterialResolver` validates the
  returned map before it reaches source adapters.
  """

  @behaviour Cadence.Dashboards.SourceCredentials.SecretBackend

  alias Cadence.Dashboards.ResolvedSourceCredential

  @default_path "/v1/dashboard-source-credentials/material"
  @default_timeout_ms 5_000

  @impl true
  @spec fetch_material(ResolvedSourceCredential.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_material(%ResolvedSourceCredential{} = credential, opts \\ [])
      when is_list(opts) do
    with {:ok, url} <- secret_manager_url(opts),
         {:ok, response} <- request_material(url, credential, opts) do
      material_from_response(response)
    end
  end

  defp secret_manager_url(opts) do
    configured =
      Keyword.get(opts, :secret_manager_url) ||
        Keyword.get(opts, :external_secret_manager_url) ||
        credential_config_value(:secret_manager_url) ||
        credential_config_value(:external_secret_manager_url)

    case configured do
      url when is_binary(url) and url != "" -> {:ok, compose_url(url, opts)}
      _missing -> {:error, :external_secret_manager_not_configured}
    end
  end

  defp request_material(url, %ResolvedSourceCredential{} = credential, opts) do
    req_request = Keyword.get(opts, :req_request, &Req.request/1)

    request = [
      method: :post,
      url: url,
      json: request_payload(credential),
      headers: request_headers(opts),
      receive_timeout: request_timeout_ms(opts)
    ]

    case req_request.(request) do
      {:ok, %Req.Response{} = response} ->
        {:ok, response}

      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, {:external_secret_manager_request_failed, reason_token(reason)}}
    end
  end

  defp material_from_response(%Req.Response{status: status, body: body})
       when status in 200..299 do
    material_from_body(body)
  end

  defp material_from_response(%Req.Response{status: status}) do
    {:error, {:external_secret_manager_http_error, status}}
  end

  defp material_from_response(%{status: status, body: body}) when status in 200..299 do
    material_from_body(body)
  end

  defp material_from_response(%{status: status}) when is_integer(status) do
    {:error, {:external_secret_manager_http_error, status}}
  end

  defp material_from_response(_response), do: {:error, :invalid_external_secret_manager_response}

  defp material_from_body(%{"material" => material}) when is_map(material), do: {:ok, material}
  defp material_from_body(%{material: material}) when is_map(material), do: {:ok, material}
  defp material_from_body(material) when is_map(material), do: {:ok, material}
  defp material_from_body(_body), do: {:error, :invalid_external_secret_manager_response}

  defp compose_url(url, opts) do
    path = Keyword.get(opts, :secret_manager_path, @default_path)
    parsed = URI.parse(url)

    if parsed.path in [nil, "", "/"] and is_binary(path) do
      url
      |> URI.parse()
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

  defp normalize_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

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
      non_empty_string(credential_config_value(:secret_manager_token))
  end

  defp token_from_env(opts) do
    env_var =
      Keyword.get(opts, :secret_manager_token_env) ||
        credential_config_value(:secret_manager_token_env)

    env_reader = Keyword.get(opts, :env_reader, &System.get_env/1)

    if is_binary(env_var) and env_var != "" and is_function(env_reader, 1) do
      env_reader.(env_var)
    end
  end

  defp request_timeout_ms(opts) do
    case Keyword.get(opts, :secret_manager_timeout_ms, @default_timeout_ms) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 -> timeout_ms
      _invalid -> @default_timeout_ms
    end
  end

  defp request_payload(%ResolvedSourceCredential{} = credential) do
    %{
      credentials_ref: credential.credentials_ref,
      organization_id: credential.organization_id,
      mission_id: credential.mission_id,
      data_source_id: credential.data_source_id,
      owner: credential.owner,
      kind: credential.kind,
      provider: credential.provider,
      status: credential.status,
      credential_version: credential.credential_version,
      current_event_id: credential.current_event_id,
      metadata: credential.metadata
    }
  end

  defp credential_config_value(key) do
    :cadence
    |> Application.get_env(:dashboard_source_credentials, [])
    |> Keyword.get(key)
  end

  defp non_empty_string(value) when is_binary(value) and value != "", do: value
  defp non_empty_string(_value), do: nil

  defp reason_token(reason) when is_atom(reason), do: reason

  defp reason_token(%{reason: reason}) when is_atom(reason), do: reason

  defp reason_token(reason) when is_exception(reason) do
    reason.__struct__
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp reason_token(_reason), do: :request_failed
end
