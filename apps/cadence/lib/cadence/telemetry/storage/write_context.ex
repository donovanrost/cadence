defmodule Cadence.Telemetry.Storage.WriteContext do
  @moduledoc """
  Tenant and source context for telemetry observation writes.

  The context is supplied by Cadence's ingest/source-binding layer. It is not
  derived from sample payloads, which lets storage adapters enforce tenancy and
  realm separation consistently.
  """

  @type realm :: :flight | :rehearsal | :ai_t | :simulation | :replay | :lab | :backfill

  @type t :: %__MODULE__{
          organization_id: binary(),
          mission_id: binary(),
          realm: realm(),
          data_source_id: binary(),
          binding_id: binary(),
          source_endpoint_id: binary() | nil,
          replay_run_id: binary() | nil,
          recorded_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :organization_id,
    :mission_id,
    :realm,
    :data_source_id,
    :binding_id,
    :source_endpoint_id,
    :replay_run_id,
    :recorded_at,
    metadata: %{}
  ]

  @realms [:flight, :rehearsal, :ai_t, :simulation, :replay, :lab, :backfill]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    context =
      struct!(
        __MODULE__,
        attrs
        |> Enum.into(%{})
        |> Map.update(:realm, nil, &normalize_realm/1)
      )

    with :ok <- validate(context) do
      {:ok, context}
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = context) do
    with :ok <- require_binary(context, :organization_id),
         :ok <- require_binary(context, :mission_id),
         :ok <- require_binary(context, :data_source_id),
         :ok <- require_binary(context, :binding_id),
         :ok <- require_realm(context.realm),
         :ok <- require_replay_run(context) do
      require_metadata_map(context.metadata)
    end
  end

  @spec realms() :: [realm()]
  def realms, do: @realms

  defp require_binary(context, field) do
    case Map.fetch!(context, field) do
      value when is_binary(value) and value != "" -> :ok
      _other -> {:error, {:missing_field, field}}
    end
  end

  defp require_realm(realm) when realm in @realms, do: :ok
  defp require_realm(realm), do: {:error, {:unsupported_realm, realm}}

  defp require_replay_run(%__MODULE__{realm: :replay, replay_run_id: replay_run_id})
       when is_binary(replay_run_id) and replay_run_id != "" do
    :ok
  end

  defp require_replay_run(%__MODULE__{realm: :replay}),
    do: {:error, {:missing_field, :replay_run_id}}

  defp require_replay_run(%__MODULE__{}), do: :ok

  defp require_metadata_map(metadata) when is_map(metadata), do: :ok
  defp require_metadata_map(_metadata), do: {:error, {:invalid_field, :metadata}}

  defp normalize_realm(realm) when realm in @realms, do: realm
  defp normalize_realm("flight"), do: :flight
  defp normalize_realm("rehearsal"), do: :rehearsal
  defp normalize_realm("AI&T"), do: :ai_t
  defp normalize_realm("ai_t"), do: :ai_t
  defp normalize_realm("simulation"), do: :simulation
  defp normalize_realm("replay"), do: :replay
  defp normalize_realm("lab"), do: :lab
  defp normalize_realm("backfill"), do: :backfill
  defp normalize_realm(other), do: other
end
