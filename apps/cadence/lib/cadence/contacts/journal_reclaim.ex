defmodule Cadence.Contacts.JournalReclaim do
  @moduledoc """
  Reclaims the ingress journal streams of settled contacts (#71 follow-up; lead and api-ops,
  11-14). A contact's stream directory otherwise stays on disk forever after its contact ends.

  A stream is removed only when ALL of these hold:

  - its contact is settled (`settlement.state == "settled"`), was inspected if it ended without a
    runtime to drain, and isn't already marked;
  - its contact settled more than the retention ago (config `:ingress_journal`
    `:completed_stream_retention_ms`, default 72 h for overnight forensics; a real deployment
    would tie it to its evidence-retention policy);
  - no journal of the contact is open (no runtime or replay writes into it);
  - it is drained ON DISK: processing AND archive cursors at the checkpoint's `next_offset`, and
    the segments end exactly there with no torn tail (the archive cursor means every byte is in
    the ingress archive, so nothing is lost);
  - its directory is a direct child of the journal's base path.

  One stream per mission per reconcile tick. A contact is marked `journal_disk: "reclaimed"` once
  all its streams are gone. A stream that isn't drained on disk is kept and its contact marked
  `journal_disk: "retained_undrained"` (logged once), for a manual decision; that keeps ALL of
  the contact's streams, its drained ones too (conservative).

  Retention counts from the settlement's `settled_at` (a replay that re-settles a contact restarts
  it), not from the stream files' times.
  """

  require Logger

  alias Cadence.Contacts.{ContactStore, RealizedContact}
  alias Cadence.Control.Contacts, as: Runtime
  alias Cadence.IngressJournal.Volume

  @default_retention_ms 72 * 60 * 60 * 1000
  @pressure_key {__MODULE__, :volume_pressure}

  @doc "How long a settled contact's journal stays on disk."
  @spec retention_ms() :: pos_integer()
  def retention_ms do
    :cadence
    |> Application.get_env(:ingress_journal, [])
    |> Enum.into(%{})
    |> Map.get(:completed_stream_retention_ms, @default_retention_ms)
  end

  @doc """
  Reclaims at most one stream of `mission_id`. Returns `{:reclaimed, contact_id}`,
  `{:retained, contact_id}` (marked undrained), or `:none`.

  Under disk pressure (the journal's disk at or above `:early_reclaim_at`, 80 %, until it's
  back below `:early_reclaim_to`, 70 %; director 11-15) the 72 h review window is skipped: the
  oldest-settled stream that passes every other check goes first (settled, inspected, not open,
  drained on disk, i.e. already all in the ingress archive), marked `reclaimed_early`. Never a
  stream still being stored or open. An unreadable disk means no early reclaim (fail-safe).
  """
  @spec run(binary(), DateTime.t(), keyword()) ::
          {:reclaimed, binary()} | {:retained, binary()} | :none
  def run(mission_id, %DateTime{} = now, opts \\ []) when is_binary(mission_id) do
    pressure = pressure(opts)
    retention = if pressure, do: 0, else: Keyword.get_lazy(opts, :retention_ms, &retention_ms/0)
    streams = Runtime.stored_ingress_journals(mission_id)
    streams_by_contact = Enum.group_by(streams, & &1.context.realized_contact_id)

    streams_by_contact
    |> Map.keys()
    |> Enum.flat_map(fn contact_id ->
      case ContactStore.fetch_realized(mission_id, contact_id) do
        {:ok, contact} -> [contact]
        _missing -> []
      end
    end)
    |> order(pressure)
    |> Enum.find_value(:none, fn contact ->
      contact_id = contact.realized_contact_id

      with true <- reclaimable?(contact, now, retention),
           false <- Runtime.ingress_journal_open?(mission_id, contact_id) do
        reclaim_one(contact, streams_by_contact[contact_id], now, pressure)
      else
        _not_this_contact -> nil
      end
    end)
  end

  @doc """
  Whether the journal's disk is under pressure: `nil`, or `%{percent}` while early reclaim runs
  (from at or above `:early_reclaim_at` until below `:early_reclaim_to`). `opts[:volume]` gives
  the reading (tests); otherwise the disk is read now. `:unknown` is never pressure.
  """
  @spec pressure(keyword()) :: nil | %{percent: float()}
  def pressure(opts \\ []) do
    t = Keyword.get_lazy(opts, :thresholds, &Volume.thresholds/0)
    volume = Keyword.get_lazy(opts, :volume, fn -> Runtime.ingress_journal_volume() end)
    active? = :persistent_term.get(@pressure_key, false)

    case volume do
      {:ok, %{percent: percent} = reading} ->
        under? = percent >= t.reclaim_at or (active? and percent >= t.reclaim_to)
        set_pressure(active?, under? and Volume.low_on_free?(reading, t), percent)

      _unknown ->
        set_pressure(active?, false, nil)
    end
  end

  defp set_pressure(active?, true, percent) do
    if not active?, do: :persistent_term.put(@pressure_key, true)
    %{percent: percent}
  end

  defp set_pressure(active?, false, _percent) do
    if active?, do: :persistent_term.put(@pressure_key, false)
    nil
  end

  @doc false
  def reset_pressure, do: :persistent_term.erase(@pressure_key)

  # Normal: any order (one per tick). Under pressure: the oldest settled first.
  defp order(contacts, nil), do: Enum.sort_by(contacts, & &1.realized_contact_id)
  defp order(contacts, _pressure), do: Enum.sort_by(contacts, &settled_at_key/1)

  defp settled_at_key(%RealizedContact{metadata: metadata}) do
    with %{"settled_at" => at} when is_binary(at) <- Map.get(metadata || %{}, "settlement"),
         {:ok, settled_at, _offset} <- DateTime.from_iso8601(at) do
      DateTime.to_unix(settled_at, :microsecond)
    else
      _unsettled -> :infinity
    end
  end

  @doc "Pure: whether a contact's journals may be reclaimed at `now` (all but the disk checks)."
  @spec reclaimable?(RealizedContact.t(), DateTime.t(), non_neg_integer()) :: boolean()
  def reclaimable?(%RealizedContact{lifecycle_state: state} = contact, now, retention_ms)
      when state in [:completed, :stopped] do
    settlement = Map.get(contact.metadata || %{}, "settlement", %{})

    settlement["state"] == "settled" and settlement["journal_disk"] == nil and
      (settlement["runtime"] != "absent" or is_binary(settlement["inspected_at"])) and
      settled_before?(settlement["settled_at"], DateTime.add(now, -retention_ms, :millisecond))
  end

  def reclaimable?(%RealizedContact{}, _now, _retention_ms), do: false

  defp settled_before?(at, cutoff) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, settled_at, _offset} -> DateTime.compare(settled_at, cutoff) != :gt
      _invalid -> false
    end
  end

  defp settled_before?(_at, _cutoff), do: false

  defp reclaim_one(contact, [stream | rest], now, pressure) do
    case Runtime.stored_ingress_journal_drain(stream) do
      {:drained, bytes} ->
        remove(contact, stream, bytes, rest == [], now, pressure)

      # Early, a stream still being stored is skipped, not marked: it may just be catching up.
      {:not_drained, _reason, _bytes} when not is_nil(pressure) ->
        nil

      {:not_drained, reason, bytes} ->
        Logger.warning(
          "kept ingress journal #{stream.stream_id} of #{contact.realized_contact_id}: " <>
            "not drained on disk (#{inspect(reason)}, #{bytes} bytes); needs a manual decision"
        )

        mark(
          contact,
          %{
            "journal_disk" => "retained_undrained",
            "journal_disk_bytes" => bytes,
            "journal_disk_reason" => inspect(reason)
          },
          now
        )

        {:retained, contact.realized_contact_id}
    end
  end

  defp remove(contact, stream, bytes, last?, now, nil) do
    case Runtime.reclaim_stored_ingress_journal(stream) do
      :ok ->
        Logger.info(
          "reclaimed ingress journal #{stream.stream_id} of #{contact.realized_contact_id} " <>
            "(#{bytes} bytes)"
        )

        if last?, do: mark(contact, %{"journal_disk" => "reclaimed"}, now)
        {:reclaimed, contact.realized_contact_id}

      {:error, reason} ->
        Logger.warning(
          "could not reclaim ingress journal #{stream.stream_id}: #{inspect(reason)}"
        )

        nil
    end
  end

  # Early, under disk pressure: the stream is already all in the ingress archive; only its
  # 72 h review copy goes. Logged as a warning and marked, so history says why it went early.
  defp remove(contact, stream, bytes, last?, now, %{percent: percent}) do
    case Runtime.reclaim_stored_ingress_journal(stream) do
      :ok ->
        Logger.warning(
          "reclaimed ingress journal #{stream.stream_id} of #{contact.realized_contact_id} " <>
            "EARLY (#{bytes} bytes; journal disk #{percent} % full)"
        )

        if last?,
          do:
            mark(
              contact,
              %{
                "journal_disk" => "reclaimed_early",
                "journal_disk_reason" => "volume_pressure",
                "journal_disk_volume_percent" => percent
              },
              now
            )

        {:reclaimed, contact.realized_contact_id}

      {:error, reason} ->
        Logger.warning(
          "could not reclaim ingress journal #{stream.stream_id}: #{inspect(reason)}"
        )

        nil
    end
  end

  defp mark(%RealizedContact{} = contact, fields, now) do
    settlement =
      contact.metadata
      |> Map.get("settlement", %{})
      |> Map.merge(fields)
      |> Map.put("journal_disk_at", DateTime.to_iso8601(now))

    {:ok, _updated} =
      ContactStore.update_realized_lifecycle(contact, contact.lifecycle_state, %{
        "settlement" => settlement
      })

    :ok
  end
end
