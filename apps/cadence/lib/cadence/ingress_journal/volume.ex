defmodule Cadence.IngressJournal.Volume do
  @moduledoc """
  The disk the ingress journal lives on, and what's on it (ux U66, DECISIONS #95 follow-up).

  Each stream has its own cap (`max_bytes`), but nothing caps their sum: when this disk fills,
  every stream's appends fail and telemetry from every pass stops at once. `usage/2` reads the
  disk holding `base_path` on demand from OTP's disksup (`:disksup.get_disk_info/1`, OTP 26+;
  only disksup runs, see config.exs); `:unknown` when it can't be read, which callers treat as
  "don't act" (no early reclaim). `streams/1` lists the streams on it with their bytes.
  """

  alias Cadence.IngressJournal.FileSystem, as: JournalFileSystem

  @type usage :: %{size_bytes: non_neg_integer(), used_bytes: non_neg_integer(), percent: float()}

  # Deployment config under :cadence, :ingress_journal (ratios of the disk; bytes for the floor).
  # Defaults are for a disk of its own (ux U66, director 11-15). On a shared disk (dev: the
  # host's) the floor keeps a big disk with plenty free from counting as an emergency (lead).
  @defaults %{
    disk_caution: 0.70,
    disk_critical: 0.90,
    disk_clear: 0.60,
    early_reclaim_at: 0.80,
    early_reclaim_to: 0.70,
    disk_emergency_free_bytes: nil
  }

  @doc """
  The disk thresholds in percent (`caution`, `critical`, `clear`, `reclaim_at`, `reclaim_to`) and
  `emergency_free_bytes` (nil: no floor): critical and early reclaim need the free space below it.
  """
  @spec thresholds() :: map()
  def thresholds do
    config =
      Map.merge(
        @defaults,
        :cadence
        |> Application.get_env(:ingress_journal, [])
        |> Map.new()
        |> Map.take(Map.keys(@defaults))
      )

    %{
      caution: config.disk_caution * 100,
      critical: config.disk_critical * 100,
      clear: config.disk_clear * 100,
      reclaim_at: config.early_reclaim_at * 100,
      reclaim_to: config.early_reclaim_to * 100,
      emergency_free_bytes: config.disk_emergency_free_bytes
    }
  end

  @doc "Whether a reading is short enough of free space to count as an emergency (the floor)."
  @spec low_on_free?(map(), map()) :: boolean()
  def low_on_free?(_reading, %{emergency_free_bytes: nil}), do: true

  def low_on_free?(%{size_bytes: size, used_bytes: used}, %{emergency_free_bytes: floor}),
    do: size - used < floor

  @doc """
  The disk holding `base_path`: `{:ok, %{size_bytes, used_bytes, percent}}` or `:unknown`.
  `opts[:reader]` replaces disksup (tests): `path -> [{id, total_kib, available_kib, capacity}]`.
  """
  @spec usage(binary(), keyword()) :: {:ok, usage()} | :unknown
  def usage(base_path, opts \\ []) when is_binary(base_path) do
    reader = Keyword.get(opts, :reader, &disk_info/1)

    case reader.(base_path) do
      [{_id, total_kib, available_kib, _capacity} | _rest]
      when is_integer(total_kib) and total_kib > 0 and is_integer(available_kib) ->
        size = total_kib * 1024
        used = max(size - available_kib * 1024, 0)
        {:ok, %{size_bytes: size, used_bytes: used, percent: Float.round(used * 100 / size, 2)}}

      _unreadable ->
        :unknown
    end
  rescue
    _error -> :unknown
  catch
    :exit, _reason -> :unknown
  end

  @doc """
  The journal streams stored under `base_path`, largest first:
  `[%{mission_id, realized_contact_id, stream_id, bytes}]` (the bytes of its files on disk).
  """
  @spec streams(binary()) :: [map()]
  def streams(base_path) when is_binary(base_path) do
    base_path
    |> JournalFileSystem.stored_stream_directories()
    |> Enum.map(fn %{directory: directory, stream_id: stream_id, context: context} ->
      %{
        mission_id: context[:mission_id],
        realized_contact_id: context[:realized_contact_id],
        stream_id: stream_id,
        bytes: directory_bytes(directory)
      }
    end)
    |> Enum.sort_by(& &1.bytes, :desc)
  end

  defp directory_bytes(directory) do
    case File.ls(directory) do
      {:ok, names} ->
        names |> Enum.map(&file_bytes(Path.join(directory, &1))) |> Enum.sum()

      {:error, _reason} ->
        0
    end
  end

  defp file_bytes(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} -> size
      _other -> 0
    end
  end

  # disksup only answers when os_mon runs with it started; anything else is :unknown upstream.
  defp disk_info(base_path) do
    if Process.whereis(:disksup),
      do: :disksup.get_disk_info(String.to_charlist(base_path)),
      else: []
  end
end
