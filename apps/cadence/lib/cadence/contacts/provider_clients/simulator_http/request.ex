defmodule Cadence.Contacts.ProviderClients.SimulatorHTTP.Request do
  @moduledoc """
  How `Cadence.Contacts.ProviderClients.SimulatorHTTP` talks HTTP to a Provider Contract v1
  provider: the context's base URL and environment, the resolved credential, every request
  through the outbound guard, and the response normalized to data or a `ProviderError`.
  """

  alias Cadence.Contacts.ProviderClients.OutboundGuard
  alias Cadence.GroundNetworks.{ProviderContext, ProviderError, Validation}

  @default_receive_timeout 5_000

  @doc "The response's `data`, or a `ProviderError`."
  @spec data(ProviderContext.t(), atom(), binary(), keyword()) :: {:ok, term()} | {:error, term()}
  def data(context, method, path, opts) do
    with {:ok, body} <- envelope(context, method, path, opts) do
      {:ok, body["data"]}
    end
  end

  @doc "The whole response envelope (`data` and `meta`), or a `ProviderError`."
  @spec envelope(ProviderContext.t(), atom(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def envelope(context, method, path, opts) do
    with {:ok, base_url} <- require_context(context.base_url, :base_url),
         {:ok, environment_ref} <- require_context(context.environment_ref, :environment_ref),
         {:ok, credential} <- resolve_credential(context, opts) do
      # Every request goes through the outbound guard (private and reserved networks refused,
      # resolved before connecting, no redirects). An injected :req_request only replaces how a
      # CHECKED request is sent (api's review): it can never skip the check.
      guard_opts = [
        send: Keyword.get(opts, :req_request),
        resolver: Keyword.get(opts, :outbound_resolver)
      ]

      req_request = &OutboundGuard.request(&1, guard_opts)

      request_opts = [
        method: method,
        url: String.trim_trailing(base_url, "/") <> path,
        headers: request_headers(environment_ref, credential, opts),
        receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
        retry: retry_policy(method)
      ]

      request_opts =
        request_opts
        |> maybe_put(:json, Keyword.get(opts, :json))
        |> maybe_put(:params, Keyword.get(opts, :params))

      normalize_response(req_request.(request_opts), path)
    end
  end

  # The typed opportunity decoder and the evidence projection each sanitize their own input.
  defp normalize_response(
         {:ok, %Req.Response{status: status, body: %{"data" => _data} = body}},
         "/provider/v1/opportunities/search"
       )
       when status >= 200 and status < 300,
       do: {:ok, body}

  defp normalize_response(result, _path), do: normalize_response(result)

  defp normalize_response({:ok, %Req.Response{status: status, body: %{"data" => _data} = body}})
       when status >= 200 and status < 300,
       do: {:ok, Validation.sanitize(body)}

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, ProviderError.from_response(status, body)}

  # Refused before sending: the account's address isn't one Cadence may call. The detail stays
  # generic (no resolved address in errors, metadata or audit).
  defp normalize_response({:error, {code, _host}})
       when code in [:outbound_address_denied, :outbound_address_unresolved],
       do: {:error, ProviderError.invalid(outbound_detail(code))}

  defp normalize_response({:error, reason}) do
    if request_not_sent?(reason),
      do: {:error, ProviderError.unavailable(reason)},
      else: {:error, ProviderError.ambiguous(reason)}
  end

  defp outbound_detail(:outbound_address_denied),
    do: "the provider address is on a network Cadence doesn't call"

  defp outbound_detail(:outbound_address_unresolved),
    do: "the provider address could not be resolved"

  defp resolve_credential(%ProviderContext{credential_ref: nil}, _opts), do: {:ok, nil}

  defp resolve_credential(%ProviderContext{credential_ref: reference}, opts) do
    case Keyword.get(opts, :credential_resolver) do
      resolver when is_function(resolver, 1) ->
        case resolver.(reference) do
          {:ok, credential} when is_binary(credential) and credential != "" ->
            {:ok, credential}

          {:error, reason} ->
            {:error, ProviderError.invalid("credential could not be resolved", reason)}

          _other ->
            {:error, ProviderError.invalid("credential resolver returned an invalid value")}
        end

      _other ->
        {:error, ProviderError.invalid("credential resolver is required")}
    end
  end

  defp request_headers(environment_ref, credential, opts) do
    []
    |> prepend_header("x-simulator-environment-ref", environment_ref)
    |> prepend_header("authorization", if(credential, do: "Bearer #{credential}"))
    |> prepend_header("x-request-id", Keyword.get(opts, :request_id))
    |> Kernel.++(Keyword.get(opts, :headers, []))
  end

  defp require_context(value, _field) when is_binary(value) and value != "", do: {:ok, value}

  defp require_context(_value, field),
    do: {:error, ProviderError.invalid("provider context is missing #{field}")}

  defp retry_policy(:get), do: :safe_transient
  defp retry_policy(_write), do: false

  defp prepend_header(headers, _name, nil), do: headers
  defp prepend_header(headers, name, value), do: [{name, value} | headers]

  defp request_not_sent?(%Req.TransportError{reason: reason}),
    do: reason in [:econnrefused, :nxdomain, :enetunreach, :ehostunreach]

  defp request_not_sent?({:failed_connect, _details}), do: true
  defp request_not_sent?(_reason), do: false

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
