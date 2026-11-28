defmodule Cadence.ProviderAdapters.InboundSocket do
  @moduledoc """
  Passive inbound TCP and TLS sockets. TLS validates the chain and authorizes the exact peer
  certificate against server-supplied bindings before returning a socket to the frame reader.
  """

  alias Cadence.Secrets.ProviderDeliveryListenerIdentity, as: ServerIdentity

  @handshake_timeout 2_000
  @options [:binary, packet: 0, active: false, reuseaddr: true, nodelay: true]

  @derive {Inspect, except: [:socket]}
  defstruct [:socket, :peer_identity]

  def listen(host, port, mode, options \\ [])

  def listen(host, port, :plaintext, options),
    do: :gen_tcp.listen(port, ip_option(host) ++ @options ++ options)

  def listen(host, port, :mtls, options) do
    with {:ok, identity} <- ServerIdentity.socket_options() do
      tls_listen(ip_option(host) ++ @options ++ options ++ identity, port)
    end
  end

  def listen(_host, _port, _mode, _options), do: {:error, :mode_mismatch}

  defp tls_listen(options, port) do
    case :ssl.listen(port, options) do
      {:ok, socket} -> {:ok, %__MODULE__{socket: socket}}
      {:error, :eaddrinuse} = error -> error
      {:error, _reason} -> {:error, :delivery_tls_listen_failed}
    end
  end

  def transport_accept(%__MODULE__{socket: listener}) do
    case :ssl.transport_accept(listener) do
      {:ok, socket} -> {:ok, %__MODULE__{socket: socket}}
      {:error, :closed} = error -> error
      {:error, _reason} -> {:error, :delivery_tls_accept_failed}
    end
  end

  def transport_accept(listener) when is_port(listener), do: :gen_tcp.accept(listener)

  @doc "Completes TLS and repeats the fingerprint check before handing off the socket."
  def authenticate(%__MODULE__{socket: socket}, authorize) when is_function(authorize, 1) do
    task = self()
    ref = make_ref()
    state = %{authorize: authorize, task: task, ref: ref}

    with {:ok, connected} <-
           :ssl.handshake(socket, [verify_fun: {&verify/4, state}], @handshake_timeout),
         {:ok, der} <- :ssl.peercert(connected),
         {:ok, identity} <- authorize.(fingerprint(der)) do
      {:ok, %__MODULE__{socket: connected, peer_identity: identity}}
    else
      {:error, {:tls_alert, {code, _detail}}} -> {:error, verification_failure(ref, code)}
      {:error, :no_peercert} -> {:error, :certificate_required}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _detail} -> {:error, :tls_handshake_failed}
    end
  rescue
    _error -> {:error, :tls_handshake_failed}
  catch
    :exit, _reason -> {:error, :tls_handshake_failed}
  end

  def authenticate(socket, _authorize) when is_port(socket), do: {:ok, socket}

  defp verify(_certificate, _der, {:bad_cert, :cert_expired}, state),
    do: verification_refused(state, :expired)

  defp verify(_certificate, _der, {:bad_cert, _reason}, state),
    do: verification_refused(state, :invalid_certificate)

  defp verify(_certificate, _der, {:extension, _extension}, state), do: {:unknown, state}
  defp verify(_certificate, _der, :valid, state), do: {:valid, state}

  defp verify(_certificate, der, :valid_peer, state) do
    case state.authorize.(fingerprint(der)) do
      {:ok, _identity} -> {:valid, state}
      {:error, reason} -> verification_refused(state, reason)
    end
  end

  defp verification_refused(state, reason) do
    send(state.task, {state.ref, reason})
    {:fail, reason}
  end

  defp verification_failure(ref, alert) do
    receive do
      {^ref, reason} -> reason
    after
      0 ->
        if(alert == :certificate_required, do: :certificate_required, else: :tls_handshake_failed)
    end
  end

  defp fingerprint(der), do: Base.encode16(:crypto.hash(:sha256, der), case: :lower)

  def identity(%__MODULE__{peer_identity: identity}), do: identity
  def identity(_socket), do: nil

  def connected?(%__MODULE__{peer_identity: identity}), do: is_map(identity)
  def connected?(socket), do: is_port(socket)

  def recv(socket, size, timeout \\ :infinity)

  def recv(%__MODULE__{socket: socket}, size, timeout),
    do: sanitize(:ssl.recv(socket, size, timeout))

  def recv(socket, size, timeout) when is_port(socket), do: :gen_tcp.recv(socket, size, timeout)

  def send_data(%__MODULE__{socket: socket}, data), do: sanitize(:ssl.send(socket, data))
  def send_data(socket, data) when is_port(socket), do: :gen_tcp.send(socket, data)

  def transfer(%__MODULE__{socket: socket}, pid),
    do: sanitize(:ssl.controlling_process(socket, pid))

  def transfer(socket, pid) when is_port(socket), do: :gen_tcp.controlling_process(socket, pid)

  def peername(%__MODULE__{socket: socket}), do: sanitize(:ssl.peername(socket))
  def peername(socket) when is_port(socket), do: :inet.peername(socket)
  def peername(nil), do: {:error, :closed}

  def port(%__MODULE__{socket: socket}) do
    with {:ok, {_address, port}} <- sanitize(:ssl.sockname(socket)), do: {:ok, port}
  end

  def port(socket) when is_port(socket), do: :inet.port(socket)

  def close(%__MODULE__{socket: socket}), do: sanitize(:ssl.close(socket))
  def close(socket) when is_port(socket), do: :gen_tcp.close(socket)
  def close(nil), do: :ok

  defp sanitize({:error, reason}) when not is_atom(reason),
    do: {:error, :delivery_tls_socket_error}

  defp sanitize(result), do: result

  defp ip_option(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> [ip: ip]
      {:error, _reason} -> []
    end
  end

  defp ip_option(nil), do: []
end
