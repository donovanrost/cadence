defmodule Cadence.GroundNetworks.ProviderEvent do
  @moduledoc "Validated advisory provider event at the adapter boundary."

  alias Cadence.GroundNetworks.Validation

  @data_byte_limit 65_536

  @type t :: %__MODULE__{
          id: binary(),
          schema_version: binary(),
          sequence: non_neg_integer() | nil,
          occurred_at: DateTime.t(),
          type: binary(),
          resource_type: binary(),
          resource_id: binary(),
          resource_revision: pos_integer() | nil,
          request_id: binary() | nil,
          correlation_id: binary() | nil,
          client_reference: binary() | nil,
          data: map(),
          evidence: map()
        }

  defstruct [
    :id,
    :schema_version,
    :sequence,
    :occurred_at,
    :type,
    :resource_type,
    :resource_id,
    :resource_revision,
    :request_id,
    :correlation_id,
    :client_reference,
    data: %{},
    evidence: %{}
  ]

  @spec from_external(map()) :: {:ok, t()} | {:error, term()}
  def from_external(event) when is_map(event) do
    event = Validation.sanitize(event)

    with {:ok, id} <- Validation.required_string(event, "id"),
         {:ok, schema_version} <- Validation.required_string(event, "schema_version"),
         {:ok, sequence} <- optional_non_negative_integer(event, "sequence"),
         {:ok, occurred_at} <- Validation.datetime(event, "occurred_at"),
         {:ok, type} <- Validation.required_string(event, "type"),
         {:ok, resource_type} <- Validation.required_string(event, "resource_type"),
         {:ok, resource_id} <- Validation.required_string(event, "resource_id"),
         {:ok, resource_revision} <- optional_positive_integer(event, "resource_revision"),
         {:ok, request_id} <- Validation.optional_string(event, "request_id"),
         {:ok, correlation_id} <- Validation.optional_string(event, "correlation_id"),
         {:ok, client_reference} <- Validation.optional_string(event, "client_reference"),
         {:ok, data} <- Validation.object(event, "data"),
         :ok <- validate_data_size(data) do
      {:ok,
       %__MODULE__{
         id: id,
         schema_version: schema_version,
         sequence: sequence,
         occurred_at: occurred_at,
         type: type,
         resource_type: resource_type,
         resource_id: resource_id,
         resource_revision: resource_revision,
         request_id: request_id,
         correlation_id: correlation_id,
         client_reference: client_reference,
         data: data,
         evidence: event
       }}
    end
  end

  def from_external(_event), do: Validation.malformed(:provider_event)

  defp optional_non_negative_integer(map, key) do
    case map[key] do
      nil -> {:ok, nil}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _other -> Validation.malformed(key)
    end
  end

  defp optional_positive_integer(map, key) do
    case map[key] do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> Validation.malformed(key)
    end
  end

  defp validate_data_size(data) do
    case Jason.encode(data) do
      {:ok, json} when byte_size(json) <= @data_byte_limit -> :ok
      {:ok, _json} -> Validation.malformed(:provider_event_data_too_large)
      {:error, _reason} -> Validation.malformed("data")
    end
  end
end
