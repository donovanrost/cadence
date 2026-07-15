defmodule Cadence.Comms.TransportKind do
  @moduledoc """
  Allow-listed registry and behaviour for transport-kind specific configuration.

  Submitted form values are resolved through the explicit registry. They are
  never converted to atoms dynamically.
  """

  alias Cadence.Comms.Transport
  alias Cadence.Contacts.ProviderProfile

  @callback normalize_config(map()) :: {:ok, map()} | {:error, term()}
  @callback validate_config(map()) :: :ok | {:error, term()}
  @callback display_summary(map()) :: map()
  @callback form_metadata() :: map()
  @callback materialize_provider_profile(Transport.t()) ::
              {:ok, ProviderProfile.t()} | {:error, term()}

  @registry %{
    "tcp_socket" => %{
      kind: :tcp_socket,
      adapter_key: :tcp_socket,
      label: "TCP socket",
      module: Cadence.Comms.TransportKinds.TCPSocket
    }
  }

  @type entry :: %{
          kind: Transport.transport_kind(),
          adapter_key: Transport.adapter_key(),
          label: binary(),
          module: module(),
          form: map()
        }

  @spec form_options() :: [{binary(), binary()}]
  def form_options do
    @registry
    |> Enum.map(fn {form_value, entry} -> {entry.label, form_value} end)
    |> Enum.sort()
  end

  @spec resolve_form_value(binary()) :: {:ok, entry()} | {:error, :unsupported_transport_kind}
  def resolve_form_value(value) when is_binary(value) do
    case Map.fetch(@registry, value) do
      {:ok, entry} -> {:ok, Map.put(entry, :form, entry.module.form_metadata())}
      :error -> {:error, :unsupported_transport_kind}
    end
  end

  def resolve_form_value(_value), do: {:error, :unsupported_transport_kind}

  @spec fetch(Transport.transport_kind()) ::
          {:ok, entry()} | {:error, :unsupported_transport_kind}
  def fetch(kind) when is_atom(kind) do
    case Enum.find(@registry, fn {_form_value, entry} -> entry.kind == kind end) do
      {_form_value, entry} -> {:ok, Map.put(entry, :form, entry.module.form_metadata())}
      nil -> {:error, :unsupported_transport_kind}
    end
  end

  def fetch(_kind), do: {:error, :unsupported_transport_kind}
end
