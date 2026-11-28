defmodule Cadence.Runtime.ProfileAcceptor.Routing do
  @moduledoc false

  import Bitwise

  alias Cadence.Comms.{ListenEndpoint, PeerAddresses}
  alias Cadence.ProviderAdapters.InboundSocket
  alias Cadence.ProviderAdapters.InboundSocket.Authorization

  @identify_timeout_ms 10_000

  def route(socket, acceptor) do
    peer = peer_address(socket)

    case routing(acceptor) do
      {:ok, %{registrations: []}} ->
        refuse(socket, peer, :no_registered_contact, [], acceptor)

      {:ok, state} ->
        authenticate(socket, peer, state, acceptor)

      {:error, :listener_unavailable} ->
        InboundSocket.close(socket)
    end
  end

  defp authenticate(socket, peer, state, acceptor) do
    case InboundSocket.authenticate(socket, &authorize(state.registrations, &1)) do
      {:ok, socket} ->
        identify(socket, peer, acceptor)

      {:error, reason} ->
        refuse(socket, peer, reason, state.registrations, acceptor, :tls_handshake_failed)
    end
  end

  defp authorize(registrations, fingerprint) do
    Enum.reduce_while(registrations, {:error, :unknown_leaf}, fn registration, previous ->
      case Authorization.authorize(registration[:delivery_authorization], fingerprint) do
        {:ok, %{"provider_binding_id" => id}} = authorized
        when id == registration.delivery_binding_id ->
          {:halt, authorized}

        {:error, :unknown_leaf} ->
          {:cont, previous}

        {:error, _reason} = refusal ->
          {:cont, refusal}

        {:ok, _other_binding} ->
          {:halt, {:error, :wrong_binding}}
      end
    end)
  end

  defp identify(socket, {ip, _address} = peer, acceptor) do
    identity = InboundSocket.identity(socket)

    result =
      with {:ok, before} <- routing(acceptor),
           {:ok, candidates} <- candidates(before, identity, ip),
           {:ok, {frame, read_at}} <- read_frame(socket, candidates.bytes),
           {:ok, scid} <- scid(frame),
           {:ok, selected} <- match_scid(candidates, scid),
           :ok <- recheck(acceptor, identity, ip, scid, candidates.bytes, selected) do
        {:ok, selected, frame, read_at}
      end

    case result do
      {:ok, selected, frame, read_at} ->
        hand_over(socket, selected.adapter, frame, read_at, peer, acceptor)

      {:error, reason} ->
        refuse(socket, peer, reason, registrations(acceptor), acceptor)
    end
  end

  defp candidates(%{registrations: []}, _identity, _ip), do: {:error, :no_registered_contact}

  defp candidates(state, identity, ip) do
    with {:ok, binding} <- binding(state, identity),
         {:ok, bound} <- within_binding(state.registrations, binding),
         {:ok, allowed} <- admitted(bound, identity, ip, state.mode),
         {:ok, bytes} <- frame_size(bound) do
      {:ok, %{bound: bound, allowed: allowed, bytes: bytes}}
    end
  end

  defp binding(%{mode: :mtls}, %{"provider_binding_id" => binding}), do: {:ok, binding}

  defp binding(%{mode: :plaintext, plaintext_binding: binding}, nil) when is_binary(binding),
    do: {:ok, binding}

  defp binding(_state, _identity), do: {:error, :wrong_binding}

  defp within_binding(registrations, binding) do
    case Enum.filter(registrations, &(&1.delivery_binding_id == binding)) do
      [] -> {:error, :wrong_binding}
      bound -> {:ok, bound}
    end
  end

  defp admitted(registrations, identity, ip, mode) do
    case Enum.filter(
           registrations,
           &(Authorization.stream_allowed?(&1[:delivery_authorization], identity) == :ok)
         ) do
      [] -> {:error, :wrong_binding}
      authorized -> allowlisted(authorized, ip, mode)
    end
  end

  defp allowlisted(registrations, ip, mode) do
    case Enum.filter(registrations, &peer_allowed?(&1, ip, mode)) do
      [] -> {:error, :peer_not_allowed}
      allowed -> {:ok, allowed}
    end
  end

  defp peer_allowed?(registration, ip, mode) do
    ranges = Map.get(registration, :allowed_peers, [])
    (mode == :mtls and ranges == []) or PeerAddresses.allowed?(ranges, ip)
  end

  defp frame_size(registrations) do
    case Enum.uniq_by(registrations, & &1[:frame_size]) do
      [%{frame_size: bytes}] ->
        if ListenEndpoint.shared_frame_size?(bytes),
          do: {:ok, bytes},
          else: {:error, :unidentified}

      _different ->
        {:error, :unidentified}
    end
  end

  defp read_frame(socket, bytes) do
    case InboundSocket.recv(socket, bytes, @identify_timeout_ms) do
      {:ok, frame} when byte_size(frame) == bytes -> {:ok, {frame, DateTime.utc_now()}}
      {:ok, _partial} -> {:error, :unidentified}
      {:error, reason} -> {:error, {:read_failed, reason}}
    end
  end

  # TM transfer frame primary header: version (2 bits), spacecraft id (10 bits).
  defp scid(<<0::2, id::10, _rest::bitstring>>), do: {:ok, id}
  defp scid(_frame), do: {:error, :unidentified}

  defp match_scid(candidates, scid) do
    case Enum.filter(candidates.bound, &(&1.scid == scid)) do
      [registration] ->
        if registration in candidates.allowed,
          do: {:ok, registration},
          else: {:error, :peer_not_allowed}

      [] ->
        {:error, {:unregistered_scid, scid}}

      _several ->
        {:error, {:ambiguous_scid, scid}}
    end
  end

  defp recheck(acceptor, identity, ip, scid, bytes, selected) do
    with {:ok, current} <- routing(acceptor),
         {:ok, %{bytes: ^bytes} = candidates} <- candidates(current, identity, ip),
         {:ok, ^selected} <- match_scid(candidates, scid) do
      :ok
    else
      {:error, _reason} = error -> error
      {:ok, _changed} -> {:error, :stale_registration}
    end
  end

  defp hand_over(socket, adapter, frame, read_at, {_ip, address} = peer, acceptor) do
    case InboundSocket.transfer(socket, adapter) do
      :ok ->
        send(adapter, {:peer_accepted, socket, frame, address, read_at})

      {:error, _reason} ->
        refuse(socket, peer, :stale_registration, registrations(acceptor), acceptor)
    end
  end

  defp refuse(socket, {_ip, address}, reason, registrations, acceptor, kind \\ nil) do
    InboundSocket.close(socket)
    Enum.each(registrations, &send(&1.adapter, {:peer_refused, address, reason}))
    send(acceptor, {:refused, address, reason, kind || reason})
  end

  defp registrations(acceptor) do
    case routing(acceptor) do
      {:ok, state} -> state.registrations
      {:error, _reason} -> []
    end
  end

  defp routing(acceptor) do
    {:ok, GenServer.call(acceptor, :routing)}
  catch
    :exit, _reason -> {:error, :listener_unavailable}
  end

  defp peer_address(socket) do
    case InboundSocket.peername(socket) do
      {:ok, {address, _port}} -> {address, format_address(address)}
      _unknown -> {nil, "unknown"}
    end
  end

  defp format_address({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: format_address({high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF})

  defp format_address(address), do: address |> :inet.ntoa() |> to_string()
end
