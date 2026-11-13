defmodule Cadence.Accounts.AttemptLimit do
  @moduledoc """
  Slows password guessing on every password check: sign-in, the console Account password
  change and admin mode. Failures count in three buckets, and a bucket past its free failures
  holds further checks back for a delay that doubles per failure, capped at #{300} s:

  - the account from one address (`{email, ip}`): 5 free failures. This is what a person
    mistyping hits, and what one attacker guessing one account hits;
  - the account from anywhere (`email`): 20 free, for guessing spread over many addresses;
  - the address (`ip`): 50 free, for one address trying many accounts.

  There is no lockout: a delay never exceeds the cap, a held-back check doesn't count as a
  failure (so waiting always works), and a bucket forgets its failures #{15} min after the last
  one. A success clears the account's buckets. Buckets are keyed by the normalized email
  whether or not an account has it, so the answer never says whether the account exists.

  State is in memory on this node (a restart forgets it). To let someone in early, an operator
  runs `Cadence.Accounts.AttemptLimit.clear("person@example.com")` on the node's remote console;
  that works for the environment admin too.
  """

  use GenServer

  require Logger

  alias Cadence.Accounts.User

  @table :cadence_password_attempts
  @free %{pair: 5, account: 20, ip: 50}
  @cap_ms 300_000
  @window_ms 15 * 60_000
  @sweep_ms 60_000

  @type ip :: :inet.ip_address() | binary() | nil

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "`:ok`, or how many seconds until a check for this email from this address may run."
  @spec check(binary(), ip()) :: :ok | {:error, {:too_many_attempts, pos_integer()}}
  def check(email, ip) do
    now = now_ms()

    case email |> keys(ip) |> Enum.map(&wait_ms(&1, now)) |> Enum.max() do
      0 -> :ok
      ms -> {:error, {:too_many_attempts, div(ms + 999, 1000)}}
    end
  rescue
    # The table belongs to the platform supervisor; without it, checks run unthrottled
    # rather than refusing every sign-in.
    ArgumentError -> :ok
  end

  @doc "Records a failed password check."
  @spec failed(binary(), ip()) :: :ok
  def failed(email, ip) do
    now = now_ms()

    for {kind, _id} = key <- keys(email, ip) do
      count = :ets.update_counter(@table, key, {2, 1}, {key, 0, now})
      :ets.update_element(@table, key, {3, now})

      if count == Map.fetch!(@free, kind) + 1,
        do:
          Logger.warning(
            "password checks slowed down: the #{kind} bucket passed its free failures"
          )
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Records a successful password check: the account's buckets start over."
  @spec succeeded(binary(), ip()) :: :ok
  def succeeded(email, ip) do
    email |> keys(ip) |> Enum.reject(&match?({:ip, _}, &1)) |> Enum.each(&:ets.delete(@table, &1))
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Forgets every failure for this email (operator unlock, any address)."
  @spec clear(binary()) :: :ok
  def clear(email) do
    email = normalize(email)
    :ets.match_delete(@table, {{:pair, {email, :_}}, :_, :_})
    :ets.delete(@table, {:account, email})
    :ok
  end

  @doc false
  def reset, do: :ets.delete_all_objects(@table)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = now_ms() - @window_ms
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end

  defp keys(email, ip) do
    email = normalize(email)
    ip = address(ip)
    [{:pair, {email, ip}}, {:account, email}, {:ip, ip}]
  end

  defp wait_ms({kind, _id} = key, now) do
    case :ets.lookup(@table, key) do
      [{^key, failures, last}] when now - last < @window_ms ->
        over = failures - Map.fetch!(@free, kind)
        if over > 0, do: max(last + delay_ms(over) - now, 0), else: 0

      _none ->
        0
    end
  end

  defp delay_ms(over), do: min(1000 * Integer.pow(2, min(over - 1, 20)), @cap_ms)

  defp normalize(email), do: User.normalize_email(email) || ""

  defp address(nil), do: "unknown"
  defp address(ip) when is_binary(ip), do: ip
  defp address(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()

  defp now_ms, do: System.monotonic_time(:millisecond)
end
