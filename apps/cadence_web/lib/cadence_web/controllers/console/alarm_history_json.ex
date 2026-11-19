defmodule CadenceWeb.Console.AlarmHistoryJSON do
  @moduledoc """
  Wire shape of Investigate's History reads. Occurrence items are a subset of the episode shape
  (`CadenceWeb.Console.AlarmEpisodeJSON`) plus `condition`, `direction`, `duration_s` and
  `ended`. `next_before` is an opaque cursor for `?before=`.
  """

  alias CadenceWeb.Console.{AlarmEpisodeJSON, WireValue}

  @spec spacecraft(map()) :: map()
  def spacecraft(history), do: page(history)

  @spec episode(map()) :: map()
  def episode(history) do
    history
    |> page()
    |> Map.merge(%{
      episode: AlarmEpisodeJSON.episode(history.episode),
      first_opened_at: history.first_opened_at,
      median_duration_s: history.median_duration_s
    })
  end

  defp page(history) do
    %{
      counts: history.counts,
      retention_days: history.retention_days,
      items: Enum.map(history.items, &occurrence/1),
      next_before: encode_cursor(history.next_before)
    }
  end

  defp occurrence(item) do
    %{
      id: item.id,
      source: to_string(item.source),
      status: to_string(item.status),
      severity: to_string(item.severity),
      peak_severity: to_string(item.peak_severity),
      condition: item.condition,
      direction: item.direction && to_string(item.direction),
      point: item.point,
      opened_at: item.opened_at,
      cleared_at: item.cleared_at,
      duration_s: item.duration_s,
      ended: item.ended && to_string(item.ended),
      cleared_unacknowledged: item.cleared_unacknowledged,
      acknowledged_by: item.acknowledged_by,
      first_value: WireValue.encode(item.first_value),
      last_value: WireValue.encode(item.last_value)
    }
  end

  @doc "Encodes a `{opened_at, episode_id}` page cursor (nil passes through)."
  @spec encode_cursor({DateTime.t(), String.t()} | nil) :: String.t() | nil
  def encode_cursor(nil), do: nil

  def encode_cursor({%DateTime{} = at, id}),
    do: Base.url_encode64(DateTime.to_iso8601(at) <> "|" <> id, padding: false)

  @doc "Decodes `?before=`: `{:ok, nil}` when absent, `:error` when malformed."
  @spec decode_cursor(term()) :: {:ok, {DateTime.t(), String.t()} | nil} | :error
  def decode_cursor(nil), do: {:ok, nil}

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [at, id] when id != "" <- String.split(raw, "|", parts: 2),
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      {:ok, {at, id}}
    else
      _malformed -> :error
    end
  end

  def decode_cursor(_cursor), do: :error
end
