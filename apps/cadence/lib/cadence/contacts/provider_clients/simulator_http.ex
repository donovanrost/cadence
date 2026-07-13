defmodule Cadence.Contacts.ProviderClients.SimulatorHTTP do
  @moduledoc "Req-backed client for the canonical Cadence ground-network simulator API."

  @behaviour Cadence.Contacts.ProviderClient

  alias Cadence.Contacts.ProviderProfile

  @default_receive_timeout 5_000

  @impl true
  def search_opportunities(%ProviderProfile{} = profile, params, opts \\ []) do
    config = scheduling_config(profile)
    body = Map.put_new(params, "run_id", config["run_id"])
    request(profile, :post, "/v1/contact-opportunities/search", Keyword.put(opts, :json, body))
  end

  @impl true
  def reserve_contact(%ProviderProfile{} = profile, attrs, opts \\ []) do
    config = scheduling_config(profile)

    body =
      attrs
      |> Map.put_new("run_id", config["run_id"])
      |> Map.put_new("data_plane", data_plane_config(profile, config))

    opts =
      case Keyword.get(opts, :idempotency_key) do
        key when is_binary(key) and key != "" ->
          Keyword.update(opts, :headers, [{"idempotency-key", key}], fn headers ->
            [{"idempotency-key", key} | headers]
          end)

        _other ->
          opts
      end

    request(profile, :post, "/v1/contact-reservations", Keyword.put(opts, :json, body))
  end

  @impl true
  def describe_contact(%ProviderProfile{} = profile, provider_contact_id, opts \\ []) do
    request(profile, :get, "/v1/contact-reservations/#{provider_contact_id}", opts)
  end

  @impl true
  def cancel_contact(%ProviderProfile{} = profile, provider_contact_id, opts \\ []) do
    request(profile, :post, "/v1/contact-reservations/#{provider_contact_id}/cancel", opts)
  end

  @impl true
  def events(%ProviderProfile{} = profile, cursor, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:params, %{cursor: cursor})
      |> Keyword.put(:preserve_envelope, true)

    request(profile, :get, "/v1/events", opts)
  end

  defp request(profile, method, path, opts) do
    config = scheduling_config(profile)
    req_request = Keyword.get(opts, :req_request, &Req.request/1)

    case config["base_url"] do
      base_url when is_binary(base_url) and base_url != "" ->
        request_opts = [
          method: method,
          url: String.trim_trailing(base_url, "/") <> path,
          headers: request_headers(config, Keyword.get(opts, :headers, [])),
          receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
          retry: :safe_transient
        ]

        request_opts =
          request_opts
          |> maybe_put(:json, Keyword.get(opts, :json))
          |> maybe_put(:params, Keyword.get(opts, :params))

        normalize_response(
          req_request.(request_opts),
          Keyword.get(opts, :preserve_envelope, false)
        )

      _other ->
        {:error, {:invalid_provider_configuration, :base_url}}
    end
  end

  defp normalize_response(
         {:ok, %Req.Response{status: status, body: %{"data" => _data} = body}},
         true
       )
       when status >= 200 and status < 300,
       do: {:ok, body}

  defp normalize_response({:ok, %Req.Response{status: status, body: %{"data" => data}}}, false)
       when status >= 200 and status < 300,
       do: {:ok, data}

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}, _preserve_envelope),
    do: {:error, {:provider_http_error, status, body}}

  defp normalize_response({:error, reason}, _preserve_envelope),
    do: {:error, {:provider_request_failed, reason}}

  defp scheduling_config(%ProviderProfile{configuration: configuration}) do
    Map.get(configuration, "scheduling", Map.get(configuration, :scheduling, %{}))
  end

  defp request_headers(config, headers) do
    case config["api_token"] do
      token when is_binary(token) and token != "" ->
        [{"authorization", "Bearer #{token}"} | headers]

      _other ->
        headers
    end
  end

  defp data_plane_config(%ProviderProfile{configuration: configuration}, scheduling) do
    compact(%{
      "host" => scheduling["delivery_host"],
      "port" => configuration["port"],
      "tm_frame_size" =>
        configuration["fixed_message_bytes"] ||
          get_in(configuration, ["framing", "fixed_message_bytes"])
    })
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
