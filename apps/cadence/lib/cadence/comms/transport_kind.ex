defmodule Cadence.Comms.TransportKind do
  @moduledoc """
  Allow-listed registry and behaviour for transport-kind specific configuration.

  Submitted form values are resolved through the explicit registry. They are
  never converted to atoms dynamically.
  """

  alias Cadence.Comms.Transport
  alias Cadence.Comms.TransportKind.Definition
  alias Cadence.Comms.TransportKinds.TCPSocket
  alias Cadence.Contacts.ProviderProfile

  @callback normalize_config(map()) :: {:ok, map()} | {:error, term()}
  @callback validate_config(map()) :: :ok | {:error, term()}
  @callback display_summary(map()) :: map()
  @callback definition() :: Definition.t()
  @callback from_delivery_profile(map()) :: {:ok, map()} | {:error, binary()}
  @callback materialize_provider_profile(Transport.t()) ::
              {:ok, ProviderProfile.t()} | {:error, term()}

  @type entry :: Definition.t()
  @type fetch_error ::
          :unsupported_transport_kind
          | :unsupported_transport_kind_version
          | :invalid_transport_kind_definition

  @spec all() :: [Definition.t()]
  def all, do: [TCPSocket.definition()]

  @spec available() :: [Definition.t()]
  def available, do: Enum.filter(all(), &(Definition.validate(&1) == :ok))

  @spec form_options() :: [{binary(), binary()}]
  def form_options do
    available()
    |> Enum.map(&{&1.label, &1.form_value})
    |> Enum.sort()
  end

  @spec resolve_form_value(binary(), pos_integer() | :latest | nil) ::
          {:ok, entry()} | {:error, fetch_error()}
  def resolve_form_value(value, version \\ :latest)

  def resolve_form_value(value, version) when is_binary(value) do
    case Enum.find(all(), &(&1.form_value == value)) do
      %Definition{} = definition when version in [:latest, nil, definition.version] ->
        validate_definition(definition)

      %Definition{} ->
        {:error, :unsupported_transport_kind_version}

      nil ->
        {:error, :unsupported_transport_kind}
    end
  end

  def resolve_form_value(_value, _version), do: {:error, :unsupported_transport_kind}

  @spec fetch(Transport.transport_kind(), pos_integer() | :latest | nil) ::
          {:ok, entry()} | {:error, fetch_error()}
  def fetch(kind, version \\ :latest)

  def fetch(kind, version) when is_atom(kind) do
    case Enum.find(all(), &(&1.kind == kind)) do
      %Definition{} = definition when version in [:latest, nil, definition.version] ->
        validate_definition(definition)

      %Definition{} ->
        {:error, :unsupported_transport_kind_version}

      nil ->
        {:error, :unsupported_transport_kind}
    end
  end

  def fetch(_kind, _version), do: {:error, :unsupported_transport_kind}

  defp validate_definition(definition) do
    case Definition.validate(definition) do
      :ok ->
        {:ok, definition}

      {:error, :invalid_transport_kind_definition} ->
        {:error, :invalid_transport_kind_definition}
    end
  end
end
