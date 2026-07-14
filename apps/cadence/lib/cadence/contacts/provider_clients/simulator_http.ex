defmodule Cadence.Contacts.ProviderClients.SimulatorHTTP do
  @moduledoc "Req-backed client for the canonical Cadence ground-network simulator API."

  @behaviour Cadence.Contacts.ProviderClient

  alias Cadence.Contacts.ProviderProfile
  alias Cadence.Persistence.JsonDocument

  @default_receive_timeout 5_000

  @normalized_statuses %{
    "pending" => "pending",
    "scheduled" => "confirmed",
    "acquiring" => "confirmed",
    "active" => "active",
    "completed" => "completed",
    "rejected" => "rejected",
    "canceled" => "canceled",
    "failed" => "failed",
    "terminated_early" => "failed"
  }

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

    with {:ok, response} <-
           request(profile, :post, "/v1/contact-reservations", Keyword.put(opts, :json, body)) do
      normalize_reservation(response)
    end
  end

  @impl true
  def describe_contact(%ProviderProfile{} = profile, provider_contact_id, opts \\ []) do
    with {:ok, response} <-
           request(profile, :get, "/v1/contact-reservations/#{provider_contact_id}", opts) do
      normalize_reservation(response)
    end
  end

  @impl true
  def cancel_contact(%ProviderProfile{} = profile, provider_contact_id, opts \\ []) do
    with {:ok, response} <-
           request(profile, :post, "/v1/contact-reservations/#{provider_contact_id}/cancel", opts) do
      normalize_reservation(response)
    end
  end

  @impl true
  def find_contact_by_idempotency_key(%ProviderProfile{} = profile, idempotency_key, opts \\ []) do
    opts = Keyword.put(opts, :params, %{"idempotency_key" => idempotency_key})

    with {:ok, reservations} when is_list(reservations) <-
           request(profile, :get, "/v1/contact-reservations", opts),
         [reservation] <- reservations do
      normalize_reservation(reservation)
    else
      [] -> {:error, :provider_contact_not_found}
      {:ok, _other} -> {:error, {:malformed_provider_response, :reservation_list}}
      {:error, reason} -> {:error, reason}
    end
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

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}, _preserve_envelope)
       when status in [400, 401, 403, 404, 409, 422, 429],
       do: {:error, {:provider_rejected, status, sanitize_evidence(body)}}

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}, _preserve_envelope),
    do: {:error, {:provider_http_failure, status, sanitize_evidence(body)}}

  defp normalize_response({:error, reason}, _preserve_envelope) do
    if request_not_sent?(reason) do
      {:error, {:provider_unavailable, sanitize_evidence(reason)}}
    else
      {:error, {:provider_request_uncertain, sanitize_evidence(reason)}}
    end
  end

  @doc false
  @spec normalize_reservation(map()) :: {:ok, map()} | {:error, term()}
  def normalize_reservation(response) when is_map(response) do
    with id when is_binary(id) and id != "" <- response["id"],
         provider_status when is_binary(provider_status) <- response["status"],
         {:ok, status} <- normalize_status(provider_status),
         {:ok, starts_at} <- normalize_time(response["starts_at"], :starts_at),
         {:ok, ends_at} <- normalize_time(response["ends_at"], :ends_at) do
      {:ok,
       %{
         "id" => id,
         "provider_contact_ref" => response["provider_contact_ref"] || id,
         "status" => status,
         "provider_status" => provider_status,
         "starts_at" => starts_at,
         "ends_at" => ends_at,
         "provider_evidence" => sanitize_evidence(response)
       }}
    else
      nil -> {:error, {:malformed_provider_response, :required_field}}
      "" -> {:error, {:malformed_provider_response, :required_field}}
      {:error, reason} -> {:error, reason}
      _other -> {:error, {:malformed_provider_response, :required_field}}
    end
  end

  def normalize_reservation(_response),
    do: {:error, {:malformed_provider_response, :reservation}}

  defp normalize_status(status) do
    case Map.fetch(@normalized_statuses, status) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, {:unsupported_provider_status, status}}
    end
  end

  defp normalize_time(value, field) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.to_iso8601(datetime)}
      _error -> {:error, {:malformed_provider_response, field}}
    end
  end

  defp normalize_time(_value, field), do: {:error, {:malformed_provider_response, field}}

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

  defp request_not_sent?(%Req.TransportError{reason: reason}),
    do: reason in [:econnrefused, :nxdomain, :enetunreach, :ehostunreach]

  defp request_not_sent?({:failed_connect, _details}), do: true
  defp request_not_sent?(_reason), do: false

  defp sanitize_evidence(value) do
    value
    |> JsonDocument.encode()
    |> case do
      encoded when is_map(encoded) -> encoded
      encoded -> %{"value" => encoded}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
