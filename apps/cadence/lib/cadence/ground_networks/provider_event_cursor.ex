defmodule Cadence.GroundNetworks.ProviderEventCursor do
  @moduledoc "Durable polling position and lease for one exact provider event stream."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @health_states [:healthy, :degraded, :disabled, :unknown]

  @type t :: %__MODULE__{
          provider_event_cursor_id: binary(),
          organization_id: binary(),
          provider_account_id: binary(),
          provider_account_version: pos_integer(),
          environment_ref: binary(),
          channel_ref: binary(),
          stream_ref: binary(),
          cursor: term(),
          health: atom(),
          last_fetched_at: DateTime.t() | nil,
          last_advanced_at: DateTime.t() | nil,
          last_event_at: DateTime.t() | nil,
          lease_owner: binary() | nil,
          lease_expires_at: DateTime.t() | nil,
          consecutive_failures: non_neg_integer(),
          error_document: map()
        }

  defstruct [
    :provider_event_cursor_id,
    :organization_id,
    :provider_account_id,
    :provider_account_version,
    :environment_ref,
    :channel_ref,
    :stream_ref,
    :cursor,
    :health,
    :last_fetched_at,
    :last_advanced_at,
    :last_event_at,
    :lease_owner,
    :lease_expires_at,
    consecutive_failures: 0,
    error_document: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_event_cursor_id:
        value(attrs, :provider_event_cursor_id, Ids.new("provider_event_cursor")),
      organization_id: required(attrs, :organization_id),
      provider_account_id: required(attrs, :provider_account_id),
      provider_account_version: positive(attrs, :provider_account_version),
      environment_ref: required(attrs, :environment_ref),
      channel_ref: required(attrs, :channel_ref),
      stream_ref: required(attrs, :stream_ref),
      cursor: value(attrs, :cursor),
      health: enum(attrs, :health, @health_states, :unknown),
      last_fetched_at: optional_datetime(attrs, :last_fetched_at),
      last_advanced_at: optional_datetime(attrs, :last_advanced_at),
      last_event_at: optional_datetime(attrs, :last_event_at),
      lease_owner: optional_text(attrs, :lease_owner),
      lease_expires_at: optional_datetime(attrs, :lease_expires_at),
      consecutive_failures: non_negative(attrs, :consecutive_failures, 0),
      error_document: attrs |> value(:error_document, %{}) |> JsonDocument.encode()
    }
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      text when is_binary(text) and text != "" -> text
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_text(attrs, key) do
    case value(attrs, key) do
      nil -> nil
      text when is_binary(text) and text != "" -> text
      _other -> raise ArgumentError, "#{key} must be non-empty text"
    end
  end

  defp positive(attrs, key) do
    case value(attrs, key) do
      number when is_integer(number) and number > 0 -> number
      _other -> raise ArgumentError, "#{key} must be positive"
    end
  end

  defp non_negative(attrs, key, default) do
    case value(attrs, key, default) do
      number when is_integer(number) and number >= 0 -> number
      _other -> raise ArgumentError, "#{key} must be non-negative"
    end
  end

  defp optional_datetime(attrs, key) do
    case value(attrs, key) do
      nil -> nil
      %DateTime{} = datetime -> DateTime.truncate(datetime, :microsecond)
      _other -> raise ArgumentError, "#{key} must be a DateTime"
    end
  end

  defp enum(attrs, key, allowed, default) do
    current = value(attrs, key, default)

    Enum.find(allowed, fn item -> item == current or Atom.to_string(item) == current end) ||
      raise ArgumentError, "unsupported #{key}"
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
