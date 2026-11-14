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
  `journal_disk: "retained_undrained"` (logged once), for a manual decision.
  """

  require Logger

  alias Cadence.Contacts.{ContactStore, RealizedContact}
  alias Cadence.Control.Contacts, as: Runtime

  @default_retention_ms 72 * 60 * 60 * 1000

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
  """
  @spec run(binary(), DateTime.t(), keyword()) ::
          {:reclaimed, binary()} | {:retained, binary()} | :none
  def run(mission_id, %DateTime{} = now, opts \\ []) when is_binary(mission_id) do
    retention = Keyword.get_lazy(opts, :retention_ms, &retention_ms/0)
    streams = Runtime.stored_ingress_journals(mission_id)
    streams_by_contact = Enum.group_by(streams, & &1.context.realized_contact_id)

    streams_by_contact
    |> Map.keys()
    |> Enum.sort()
    |> Enum.find_value(:none, fn contact_id ->
      with {:ok, contact} <- ContactStore.fetch_realized(mission_id, contact_id),
           true <- reclaimable?(contact, now, retention),
           false <- Runtime.ingress_journal_open?(mission_id, contact_id) do
        reclaim_one(contact, streams_by_contact[contact_id], now)
      else
        _not_this_contact -> nil
      end
    end)
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

  defp reclaim_one(contact, [stream | rest], now) do
    case Runtime.stored_ingress_journal_drain(stream) do
      {:drained, bytes} ->
        case Runtime.reclaim_stored_ingress_journal(stream) do
          :ok ->
            Logger.info(
              "reclaimed ingress journal #{stream.stream_id} of #{contact.realized_contact_id} " <>
                "(#{bytes} bytes)"
            )

            if rest == [], do: mark(contact, %{"journal_disk" => "reclaimed"}, now)
            {:reclaimed, contact.realized_contact_id}

          {:error, reason} ->
            Logger.warning(
              "could not reclaim ingress journal #{stream.stream_id}: #{inspect(reason)}"
            )

            nil
        end

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
