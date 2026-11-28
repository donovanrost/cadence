defmodule CadenceSimulator.Provider.DeliveryTLS do
  @moduledoc "Run-scoped client authentication for provider-managed realtime downlinks."

  @type identity :: {binary(), binary()}
  @identifier ~r/\A[A-Za-z0-9_-]{1,128}\z/
  @credential_prefix "delivery_credential_"

  def enabled?, do: not is_nil(backend())

  @doc "The provider's identity travels with the delivery profile, independent of its destination."
  def identity(_run_id, %{"delivery_auth" => mode}) when mode in [nil, "plaintext"],
    do: {:ok, nil}

  def identity(run_id, %{
        "delivery_auth" => "mtls",
        "egress" => %{"delivery_credential_ref" => ref}
      }) do
    if valid_identifier?(run_id) and valid_reference?(ref),
      do: {:ok, {run_id, ref}},
      else: {:error, :delivery_tls_credential_unavailable}
  end

  def identity(_run_id, %{"delivery_auth" => _mode}),
    do: {:error, :delivery_tls_credential_unavailable}

  def identity(_run_id, _profile), do: {:ok, nil}

  def valid_reference?(@credential_prefix <> suffix = ref) when byte_size(suffix) > 0,
    do: valid_identifier?(ref)

  def valid_reference?(_ref), do: false

  def valid_identifier?(id), do: is_binary(id) and Regex.match?(@identifier, id)

  @doc "Validates a registered binding before provisioning its public delivery profile."
  def available?({run_id, ref}) do
    match?({:ok, _material}, load(run_id, ref))
  end

  def connect({run_id, ref}, host, port, socket_opts, timeout) do
    with {:ok, options} <- load(run_id, ref) do
      host
      |> ssl_host()
      |> :ssl.connect(port, socket_opts ++ options, timeout)
      |> socket_result()
    end
  rescue
    _error -> {:error, :delivery_tls_handshake_failed}
  catch
    :exit, _reason -> {:error, :delivery_tls_handshake_failed}
  end

  def socket_result({:error, {:tls_alert, _detail}}), do: {:error, :delivery_tls_handshake_failed}

  def socket_result({:error, reason}) when not is_atom(reason),
    do: {:error, :delivery_tls_socket_failed}

  def socket_result(result), do: result

  defp ssl_host(host) do
    name = String.to_charlist(host)

    case :inet.parse_address(name) do
      {:ok, address} -> address
      {:error, _invalid} -> name
    end
  end

  defp load(run_id, ref) do
    with true <- valid_identifier?(run_id) and valid_reference?(ref),
         {:ok, material} <- resolve(backend(), run_id, ref),
         %{certificate_pem: leaf, private_key_pem: key, server_ca_pem: ca} <- material,
         [{:Certificate, certificate, :not_encrypted}] <- :public_key.pem_decode(leaf),
         [{type, private_key, :not_encrypted}] <- :public_key.pem_decode(key),
         true <- type in [:ECPrivateKey, :RSAPrivateKey, :PrivateKeyInfo],
         [{:Certificate, server_ca, :not_encrypted}] <- :public_key.pem_decode(ca) do
      {:ok,
       [
         cert: certificate,
         key: {type, private_key},
         cacerts: [server_ca],
         verify: :verify_peer,
         versions: [:"tlsv1.3", :"tlsv1.2"],
         session_tickets: :disabled,
         reuse_sessions: false,
         log_level: :none
       ]}
    else
      _unavailable -> {:error, :delivery_tls_credential_unavailable}
    end
  rescue
    _error -> {:error, :delivery_tls_credential_unavailable}
  catch
    :exit, _reason -> {:error, :delivery_tls_credential_unavailable}
  end

  defp backend, do: Application.get_env(:cadence_simulator, :delivery_tls_backend)

  defp resolve({module, function, args}, run_id, ref),
    do: apply(module, function, [run_id, ref | args])

  defp resolve(resolver, run_id, ref) when is_function(resolver, 2), do: resolver.(run_id, ref)
  defp resolve(_backend, _run_id, _ref), do: {:error, :delivery_tls_credential_unavailable}
end
