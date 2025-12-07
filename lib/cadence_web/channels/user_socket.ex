defmodule CadenceWeb.UserSocket do
  @moduledoc """
  Socket for real-time telemetry streaming to browser clients.

  This socket handles authentication and provides access to the
  TelemetryChannel for receiving live spacecraft telemetry updates.
  """

  use Phoenix.Socket

  # Channels
  channel "telemetry:*", CadenceWeb.TelemetryChannel
  channel "execution:*", CadenceWeb.ExecutionChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(CadenceWeb.Endpoint, "user socket", token, max_age: 86_400) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user_id, user_id)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
