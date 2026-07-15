defmodule Cadence.Contacts.ProviderClients.SimulatorHTTP do
  @moduledoc "Req-backed client for Simulator Provider Contract v1."

  @behaviour Cadence.Contacts.ProviderClient

  alias Cadence.GroundNetworks.{
    DeliveryProfile,
    Opportunity,
    ProviderCapabilities,
    ProviderContact,
    ProviderContext,
    ProviderError,
    ServiceProfile,
    Validation
  }

  @default_receive_timeout 5_000

  @impl true
  def validate_connection(%ProviderContext{} = context, opts \\ []) do
    request_data(context, :get, "/provider/v1/account", opts)
  end

  @impl true
  def capabilities(%ProviderContext{} = context, opts \\ []) do
    with {:ok, data} <- request_data(context, :get, "/provider/v1/capabilities", opts) do
      normalize(ProviderCapabilities.from_external(data))
    end
  end

  @impl true
  def list_spacecraft(%ProviderContext{} = context, params \\ %{}, opts \\ []) do
    list_inventory(context, "/provider/v1/spacecraft", params, opts)
  end

  @impl true
  def list_ground_stations(%ProviderContext{} = context, params \\ %{}, opts \\ []) do
    list_inventory(context, "/provider/v1/ground-stations", params, opts)
  end

  @impl true
  def list_service_profiles(%ProviderContext{} = context, params \\ %{}, opts \\ []) do
    with {:ok, data} <-
           request_data(context, :get, "/provider/v1/service-profiles", put_params(opts, params)) do
      normalize_list(data, ServiceProfile)
    end
  end

  @impl true
  def list_delivery_profiles(%ProviderContext{} = context, params \\ %{}, opts \\ []) do
    with {:ok, data} <-
           request_data(context, :get, "/provider/v1/delivery-profiles", put_params(opts, params)) do
      normalize_list(data, DeliveryProfile)
    end
  end

  @impl true
  def provision_delivery_profile(%ProviderContext{} = context, attrs, opts \\ []) do
    with {:ok, capabilities} <- effective_capabilities(context, opts),
         :ok <- require_operation(capabilities, :delivery_profile_provisioning),
         {:ok, data} <-
           request_data(
             context,
             :post,
             "/provider/v1/delivery-profiles",
             Keyword.put(opts, :json, attrs)
           ) do
      normalize(DeliveryProfile.from_external(data))
    end
  end

  @impl true
  def search_opportunities(%ProviderContext{} = context, params, opts \\ []) do
    with {:ok, body} <-
           request_envelope(
             context,
             :post,
             "/provider/v1/opportunities/search",
             Keyword.put(opts, :json, params)
           ),
         {:ok, opportunities} <- normalize_list(body["data"], Opportunity) do
      meta = Map.get(body, "meta", %{})

      {:ok,
       %{
         data: opportunities,
         next_cursor: meta["next_cursor"],
         truncated: Map.get(meta, "truncated", false)
       }}
    end
  end

  @impl true
  def reserve_contact(%ProviderContext{} = context, attrs, opts \\ []) do
    with {:ok, capabilities} <- effective_capabilities(context, opts),
         {:ok, request_opts} <- reservation_opts(capabilities, attrs, opts),
         {:ok, data} <-
           request_data(
             context,
             :post,
             "/provider/v1/contacts",
             Keyword.put(request_opts, :json, attrs)
           ) do
      normalize(ProviderContact.from_external(data))
    end
  end

  @impl true
  def describe_contact(%ProviderContext{} = context, provider_contact_ref, opts \\ []) do
    with {:ok, data} <-
           request_data(context, :get, "/provider/v1/contacts/#{provider_contact_ref}", opts) do
      normalize(ProviderContact.from_external(data))
    end
  end

  @impl true
  def cancel_contact(%ProviderContext{} = context, provider_contact_ref, opts \\ []) do
    with {:ok, data} <-
           request_data(
             context,
             :post,
             "/provider/v1/contacts/#{provider_contact_ref}/cancel",
             opts
           ) do
      normalize(ProviderContact.from_external(data))
    end
  end

  @impl true
  def find_contact_by_client_reference(%ProviderContext{} = context, client_reference, opts \\ []) do
    opts = put_params(opts, %{"client_reference" => client_reference})

    with {:ok, capabilities} <- effective_capabilities(context, opts),
         :ok <- require_recovery(capabilities),
         {:ok, contacts} <- request_data(context, :get, "/provider/v1/contacts", opts),
         {:ok, contact} <- exactly_one_contact(contacts) do
      normalize(ProviderContact.from_external(contact))
    end
  end

  @impl true
  def events(%ProviderContext{} = context, cursor, opts \\ []) do
    params = if is_nil(cursor), do: %{}, else: %{"cursor" => cursor}

    with {:ok, capabilities} <- effective_capabilities(context, opts),
         :ok <- require_polling(capabilities),
         {:ok, body} <-
           request_envelope(context, :get, "/provider/v1/events", put_params(opts, params)),
         events when is_list(events) <- body["data"],
         true <- Enum.all?(events, &valid_event?/1) do
      meta = Map.get(body, "meta", %{})

      {:ok,
       %{
         data: events,
         next_cursor: meta["next_cursor"],
         truncated: Map.get(meta, "truncated", false)
       }}
    else
      {:error, %ProviderError{} = error} -> {:error, error}
      _other -> {:error, ProviderError.malformed(:event_page)}
    end
  end

  defp list_inventory(context, path, params, opts) do
    with {:ok, resources} <- request_data(context, :get, path, put_params(opts, params)),
         true <- is_list(resources) and Enum.all?(resources, &is_map/1) do
      {:ok, Enum.map(resources, &sanitize_evidence/1)}
    else
      {:error, %ProviderError{} = error} -> {:error, error}
      _other -> {:error, ProviderError.malformed(:inventory)}
    end
  end

  defp effective_capabilities(
         %ProviderContext{capabilities: %ProviderCapabilities{} = caps},
         _opts
       ),
       do: {:ok, caps}

  defp effective_capabilities(context, opts), do: capabilities(context, opts)

  defp require_operation(%ProviderCapabilities{} = capabilities, operation) do
    if ProviderCapabilities.supports?(capabilities, operation) do
      :ok
    else
      {:error, unsupported(operation)}
    end
  end

  defp require_recovery(%ProviderCapabilities{reservation: %{recovery: :client_reference}}),
    do: :ok

  defp require_recovery(_capabilities), do: {:error, unsupported(:client_reference_recovery)}

  defp require_polling(%ProviderCapabilities{events: %{polling: true}}), do: :ok
  defp require_polling(_capabilities), do: {:error, unsupported(:event_polling)}

  defp unsupported(operation) do
    ProviderError.from_response(422, %{
      "error" => %{
        "code" => "unsupported_capability",
        "detail" => "provider does not support #{operation}"
      }
    })
  end

  defp reservation_opts(%ProviderCapabilities{} = capabilities, attrs, opts) do
    case capabilities.reservation.idempotency do
      :native -> native_idempotency_opts(opts)
      :client_reference -> require_client_reference(attrs, opts)
      :none -> {:ok, Keyword.delete(opts, :idempotency_key)}
    end
  end

  defp native_idempotency_opts(opts) do
    case Keyword.get(opts, :idempotency_key) do
      key when is_binary(key) and key != "" ->
        {:ok, add_header(opts, "idempotency-key", key)}

      _other ->
        {:error, ProviderError.invalid("native idempotency requires an idempotency key")}
    end
  end

  defp require_client_reference(attrs, opts) do
    if is_binary(attrs["client_reference"]) and attrs["client_reference"] != "",
      do: {:ok, Keyword.delete(opts, :idempotency_key)},
      else: {:error, ProviderError.invalid("client_reference is required")}
  end

  defp request_data(context, method, path, opts) do
    with {:ok, body} <- request_envelope(context, method, path, opts) do
      {:ok, body["data"]}
    end
  end

  defp request_envelope(context, method, path, opts) do
    with {:ok, base_url} <- require_context(context.base_url, :base_url),
         {:ok, environment_ref} <- require_context(context.environment_ref, :environment_ref),
         {:ok, credential} <- resolve_credential(context, opts) do
      req_request = Keyword.get(opts, :req_request, &Req.request/1)

      request_opts = [
        method: method,
        url: String.trim_trailing(base_url, "/") <> path,
        headers: request_headers(environment_ref, credential, opts),
        receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
        retry: :safe_transient
      ]

      request_opts =
        request_opts
        |> maybe_put(:json, Keyword.get(opts, :json))
        |> maybe_put(:params, Keyword.get(opts, :params))

      normalize_response(req_request.(request_opts))
    end
  end

  defp normalize_response({:ok, %Req.Response{status: status, body: %{"data" => _data} = body}})
       when status >= 200 and status < 300,
       do: {:ok, sanitize_evidence(body)}

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, ProviderError.from_response(status, body)}

  defp normalize_response({:error, reason}) do
    if request_not_sent?(reason),
      do: {:error, ProviderError.unavailable(reason)},
      else: {:error, ProviderError.ambiguous(reason)}
  end

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

  defp normalize({:ok, value}), do: {:ok, value}
  defp normalize({:error, reason}), do: {:error, ProviderError.malformed(reason)}

  defp normalize_list(data, module) when is_list(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, acc} ->
      case module.from_external(item) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, ProviderError.malformed(reason)}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp normalize_list(_data, _module), do: {:error, ProviderError.malformed(:list)}

  defp exactly_one_contact([contact]) when is_map(contact), do: {:ok, contact}

  defp exactly_one_contact([]),
    do:
      {:error,
       ProviderError.from_response(404, %{
         "error" => %{"code" => "not_found", "detail" => "Contact not found"}
       })}

  defp exactly_one_contact(_contacts), do: {:error, ProviderError.malformed(:contact_list)}

  defp valid_event?(event) when is_map(event) do
    is_binary(event["id"]) and is_binary(event["schema_version"]) and
      is_integer(event["sequence"]) and is_binary(event["type"]) and
      is_binary(event["resource_type"]) and is_binary(event["resource_id"]) and
      is_map(event["data"])
  end

  defp valid_event?(_event), do: false

  defp put_params(opts, params) when params == %{}, do: opts
  defp put_params(opts, params), do: Keyword.put(opts, :params, params)

  defp add_header(opts, name, value) do
    Keyword.update(opts, :headers, [{name, value}], &[{name, value} | &1])
  end

  defp prepend_header(headers, _name, nil), do: headers
  defp prepend_header(headers, name, value), do: [{name, value} | headers]

  defp request_not_sent?(%Req.TransportError{reason: reason}),
    do: reason in [:econnrefused, :nxdomain, :enetunreach, :ehostunreach]

  defp request_not_sent?({:failed_connect, _details}), do: true
  defp request_not_sent?(_reason), do: false

  defp sanitize_evidence(value), do: Validation.sanitize(value)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
