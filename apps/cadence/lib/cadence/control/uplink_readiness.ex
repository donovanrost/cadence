defmodule Cadence.Control.UplinkReadiness do
  @moduledoc """
  Whether each live provider-booked pass can command (DECISIONS #58/#59), as the qualification
  driver last saw it, for the console: `state` (`:ready | :qualifying | :blocked`), a plain
  `reason` key and `since`. Kept in an ETS table the driver writes, so reads are cheap. Passes
  without a live uplink session aren't listed (not active).

  Reason keys:
  - `cop1_awaiting_clcw` (qualifying): the uplink waits for the spacecraft's first link report.
  - `uplink_state_unavailable` (qualifying): the uplink runtime didn't report its protocol state
    (busy or unresponsive), so the pass isn't shown ready until it does (#38).
  - `session_not_attached` and other session review failures (qualifying): the provider
    connection isn't attached yet.
  - `cop1_awaiting_clcw` (qualifying): the FOP is waiting for the spacecraft's first CLCW (#59).
  - `cop1_no_clcw_report` (blocked): no first CLCW within 15 s of the uplink connecting; no
    Recover (re-qualifying doesn't help, only the spacecraft's report does).
  - `cop1_clcw_stale` (qualifying): the spacecraft's CLCW reports stopped for more than 15 s.
  - `protocol_state_restore_required` (blocked): the pass's uplink restarted after it had sent
    commands; this pass can't command again (no Recover).
  - `provider_cannot_attest_uplink_sessions` (blocked): the provider can't vouch for uplink
    sessions at all; no Recover.
  - attestation and provider failures (blocked), e.g. `attestation_signature_invalid`,
    `uplink_farm_locked_out`; Recover retries.

  `recover/3` re-runs qualification for one pass (operate_mission, audited).
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Control.UplinkQualification
  alias Cadence.GroundNetworks.{ProviderAudit, ProviderAuditEntry}
  alias Cadence.Platform.ScopedReadUpdates

  @table __MODULE__
  @resolved_keep_s 300
  # Re-qualifying can't help: protocol state is gone, or the provider can't vouch at all.
  @unrecoverable [
    :protocol_state_restore_required,
    :provider_cannot_attest_uplink_sessions,
    # #59 follow-up: re-qualifying neither reconnects nor resets the FOP's wait; only the
    # spacecraft's report (or a new connection) clears it.
    :cop1_no_clcw_report
  ]

  @doc false
  def table, do: @table

  @doc false
  def create_table(name \\ @table) do
    if :ets.whereis(name) == :undefined,
      do: :ets.new(name, [:named_table, :public, :set, read_concurrency: true]),
      else: name
  end

  ## Writes (the qualification driver)

  @doc false
  def record(table, key, pass, state, reason, now) do
    previous = lookup(table, key)

    unchanged? = same?(previous, state, reason)
    since = if unchanged?, do: previous.since, else: now

    entry = Map.merge(pass, %{key: key, state: state, reason: reason, since: since})
    :ets.insert(table, {{:session, key}, entry})

    if recovered?(previous, state), do: resolve(table, previous, "uplink recovered", now)
    unless unchanged?, do: changed(entry)
    entry
  end

  defp same?(%{state: state, reason: reason}, state, reason), do: true
  defp same?(_previous, _state, _reason), do: false

  defp recovered?(%{state: :blocked}, :ready), do: true
  defp recovered?(_previous, _state), do: false

  @doc false
  def forget(table, key, now) do
    case lookup(table, key) do
      nil ->
        :ok

      entry ->
        :ets.delete(table, {:session, key})
        if entry.state == :blocked, do: resolve(table, entry, "pass ended", now)
        changed(entry)
    end
  end

  @doc false
  def keys(table) do
    table |> safe_select([{{{:session, :"$1"}, :_}, [], [:"$1"]}]) |> MapSet.new()
  end

  defp resolve(table, entry, action, now) do
    :ets.insert(table, {{:resolved, entry.key, now}, Map.put(entry, :action, action)})
    expired = DateTime.add(now, -@resolved_keep_s, :second)

    table
    |> safe_select([{{{:resolved, :_, :"$1"}, :_}, [], [:"$_"]}])
    |> Enum.each(fn {{:resolved, _key, at} = id, _entry} ->
      if DateTime.compare(at, expired) == :lt, do: :ets.delete(table, id)
    end)
  end

  defp lookup(table, key) do
    case :ets.lookup(table, {:session, key}) do
      [{_id, entry}] -> entry
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp changed(entry) do
    ScopedReadUpdates.publish(:contacts_changed, entry.organization_id, entry.mission_id)
    ScopedReadUpdates.publish(:attention_changed, entry.organization_id, entry.mission_id)
  end

  ## Reads

  @doc "Live passes of a mission, as recorded entries."
  @spec live(binary(), binary(), atom()) :: [map()]
  def live(org, mission, table \\ @table) do
    table
    |> safe_select([{{{:session, :_}, :"$1"}, [], [:"$1"]}])
    |> Enum.filter(&(&1.organization_id == org and &1.mission_id == mission))
  end

  @doc "`%{scheduled_contact_id => %{state, reason, since, ends_at}}` for the live ones asked for."
  @spec for_contacts(binary(), binary(), [binary()], atom()) :: map()
  def for_contacts(org, mission, scheduled_contact_ids, table \\ @table) do
    wanted = MapSet.new(scheduled_contact_ids)

    for entry <- live(org, mission, table),
        MapSet.member?(wanted, entry.scheduled_contact_id),
        into: %{},
        do: {entry.scheduled_contact_id, view(entry)}
  end

  @doc "Blocked passes resolved since `since`: `[%{entry..., action, resolved_at}]`."
  @spec resolved_since(binary(), binary(), DateTime.t(), atom()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since, table \\ @table) do
    table
    |> safe_select([{{{:resolved, :_, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.filter(fn {at, entry} ->
      entry.organization_id == org and entry.mission_id == mission and
        DateTime.compare(at, since) != :lt
    end)
    |> Enum.map(fn {at, entry} -> Map.put(entry, :resolved_at, at) end)
  end

  @doc false
  def view(entry), do: Map.take(entry, [:state, :reason, :since, :starts_at, :ends_at])

  defp safe_select(table, spec) do
    :ets.select(table, spec)
  rescue
    ArgumentError -> []
  end

  ## Recover

  @doc """
  Re-runs qualification for one pass now (operate_mission; audited). `{:ok, %{state: :ready,
  ready_at}}`, or `{:error, :forbidden | :not_found | :not_blocked | {:refused, reason}}`. A pass
  blocked on `protocol_state_restore_required` is refused without trying: re-qualification
  can't restore protocol state.
  """
  @spec recover(Scope.t(), binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def recover(%Scope{} = scope, mission, scheduled_contact_id, opts \\ []) do
    table = Keyword.get(opts, :table, @table)
    driver = Keyword.get(opts, :driver, UplinkQualification)

    with {:ok, actor} <- authorize(scope, mission),
         {:ok, entry} <- find(scope.organization_id, mission, scheduled_contact_id, table),
         :ok <- recoverable(entry) do
      result =
        case UplinkQualification.requalify(driver, entry.key) do
          :ready -> {:ok, %{state: :ready, ready_at: DateTime.utc_now()}}
          {:error, reason} -> {:error, {:refused, reason}}
        end

      audit(entry, actor, result)
      result
    else
      {:error, {:refused, _reason}} = refused -> refused
      error -> error
    end
  end

  defp authorize(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp authorize(_scope, _mission), do: {:error, :forbidden}

  defp find(org, mission, scheduled_contact_id, table) do
    case Enum.find(live(org, mission, table), &(&1.scheduled_contact_id == scheduled_contact_id)) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp recoverable(%{state: :ready}), do: {:error, :not_blocked}

  defp recoverable(%{reason: reason}) when reason in @unrecoverable,
    do: {:error, {:refused, reason}}

  defp recoverable(_entry), do: :ok

  defp audit(entry, actor, result) do
    {outcome, reason} =
      case result do
        {:ok, _} -> {"recovered", nil}
        {:error, {:refused, reason}} -> {"refused", inspect(reason)}
      end

    entry_attrs = %{
      organization_id: entry.organization_id,
      mission_id: entry.mission_id,
      action: "uplink_session.recover",
      outcome: outcome,
      provider_id: entry.provider_id,
      provider_reservation_id: entry.provider_reservation_id,
      scheduled_contact_id: entry.scheduled_contact_id,
      actor_document: actor,
      previous_document: %{
        "state" => Atom.to_string(entry.state),
        "reason" => inspect(entry.reason)
      },
      current_document: %{"reason" => reason}
    }

    {:ok, _entry} = entry_attrs |> ProviderAuditEntry.new() |> ProviderAudit.append()
    :ok
  end
end
