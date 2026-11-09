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

  @doc "Cadence-received volume for one realized contact from the archives."
  @spec received(binary(), binary()) :: %{bytes: non_neg_integer(), frames: non_neg_integer()}
  def received(mission_id, realized_contact_id) do
    bytes = IngressArchive.received_bytes(mission_id, [realized_contact_id])
    frames = RecordArchive.received_frames(mission_id, [realized_contact_id])

    %{
      bytes: Map.get(bytes, realized_contact_id, 0),
      frames: Map.get(frames, realized_contact_id, 0)
    }
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
