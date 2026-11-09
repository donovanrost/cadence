defmodule Cadence.Control.PassResultsCloseOut do
  @moduledoc """
  Closes out pass results every minute (S9): passes past LOS or canceled get their provider
  result recorded with Cadence's received volume from the ingress and protocol archives. The
  composition layer joins the two, so contacts never depends on the telemetry archives.
  """

  use GenServer

  require Logger

  alias Cadence.Contacts.PassResults
  alias Cadence.IngressArchive
  alias Cadence.Organizations
  alias Cadence.Protocol.RecordArchive

  @tick_ms 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  @doc "Runs one close-out now (tests, operators)."
  @spec close_out_now(GenServer.server()) :: :ok
  def close_out_now(server \\ __MODULE__), do: GenServer.call(server, :close_out, 120_000)

  @doc "One close-out pass over every organization."
  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    Enum.each(Organizations.list_organizations(), fn organization ->
      PassResults.close_out(
        organization.organization_id,
        Keyword.put_new(opts, :received, &received/2)
      )
    end)
  end

  @doc """
  Cadence-received volume for one realized contact. Frames come from the protocol archive (0 when
  it recorded none); bytes from the ingress index, nil when it has no entry for the contact
  (unknown, not zero). Either is nil when its archive backend can't say.
  """
  @spec received(binary(), binary()) :: %{
          bytes: non_neg_integer() | nil,
          frames: non_neg_integer() | nil
        }
  def received(mission_id, realized_contact_id) do
    frames =
      case RecordArchive.received_frames(mission_id, [realized_contact_id]) do
        {:ok, counts} -> Map.get(counts, realized_contact_id, 0)
        :unknown -> nil
      end

    bytes =
      case IngressArchive.received_bytes(mission_id, [realized_contact_id]) do
        {:ok, sizes} -> Map.get(sizes, realized_contact_id)
        :unknown -> nil
      end

    %{bytes: bytes, frames: frames}
  end

  @impl true
  def init(opts) do
    state = %{tick_ms: Keyword.get(opts, :tick_ms, @tick_ms)}
    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:close_out, _from, state), do: {:reply, run(), state}

  @impl true
  def handle_info(:tick, state) do
    safely_run()
    schedule(state)
    {:noreply, state}
  end

  # A failing sweep (database unavailable, table not migrated yet) must not crash-loop the
  # control supervisor; the next tick tries again.
  defp safely_run do
    run()
  rescue
    error -> Logger.warning("pass results close-out failed: #{Exception.message(error)}")
  end

  defp schedule(%{tick_ms: ms}) when is_integer(ms) and ms > 0,
    do: Process.send_after(self(), :tick, ms)

  defp schedule(_state), do: :ok
end
