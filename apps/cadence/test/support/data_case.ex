defmodule Cadence.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.CurrentValueStore.ETS

  @repo_ready_attempts 200
  @repo_ready_sleep_ms 50
  @repo_operation_attempts 5

  using do
    quote do
      alias Cadence.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Cadence.DataCase
    end
  end

  setup tags do
    ensure_cadence_started!()

    unless tags[:async] do
      Cadence.Runtime.stop_all_missions()
    end

    pid = start_owner_with_retry!(sandbox_owner_options(tags))

    on_exit(fn ->
      unless tags[:async] do
        Cadence.Runtime.stop_all_missions()
      end

      if telemetry_current_value_store_module() == ETS do
        CurrentValueStore.reset()
      end

      Sandbox.stop_owner(pid)
      Process.sleep(25)
      ensure_cadence_started!()
    end)

    :ok
  end

  defp start_owner_with_retry!(opts, attempts \\ 20)

  defp start_owner_with_retry!(_opts, 0) do
    raise "Cadence.Repo sandbox owner did not start in time"
  end

  defp start_owner_with_retry!(opts, attempts) do
    ensure_cadence_started!()
    Sandbox.start_owner!(Cadence.Repo, opts)
  rescue
    MatchError ->
      retry_start_owner(opts, attempts)
  catch
    :exit, _reason ->
      retry_start_owner(opts, attempts)
  end

  def persist_mission_scope(organization_id, mission_id, opts \\ []) do
    with_repo_operation_retry(fn ->
      do_persist_mission_scope(organization_id, mission_id, opts)
    end)
  end

  defp do_persist_mission_scope(organization_id, mission_id, opts) do
    ensure_cadence_started!()

    organization =
      Organization.new(%{
        organization_id: organization_id,
        slug: Keyword.get(opts, :organization_slug, organization_id),
        display_name: Keyword.get(opts, :organization_name, organization_id)
      })

    mission =
      Mission.new(%{
        mission_id: mission_id,
        organization_id: organization_id,
        slug: Keyword.get(opts, :mission_slug, mission_id),
        display_name: Keyword.get(opts, :mission_name, mission_id)
      })

    {:ok, persisted_organization} = Cadence.persist_organization(organization)

    wait_for_repo_ready!()

    {:ok, persisted_mission} = Cadence.persist_mission(mission)

    %{organization: persisted_organization, mission: persisted_mission}
  end

  defp with_repo_operation_retry(fun, attempts \\ @repo_operation_attempts)

  defp with_repo_operation_retry(fun, attempts) when attempts > 1 do
    fun.()
  rescue
    DBConnection.ConnectionError ->
      retry_repo_operation(fun, attempts)

    error in RuntimeError ->
      if retryable_repo_runtime_error?(error) do
        retry_repo_operation(fun, attempts)
      else
        reraise error, __STACKTRACE__
      end
  catch
    :exit, reason ->
      if retryable_repo_exit?(reason) do
        retry_repo_operation(fun, attempts)
      else
        exit(reason)
      end
  end

  defp with_repo_operation_retry(fun, _attempts), do: fun.()

  defp retry_repo_operation(fun, attempts) do
    Process.sleep(@repo_ready_sleep_ms)
    ensure_cadence_started!()
    with_repo_operation_retry(fun, attempts - 1)
  end

  defp retryable_repo_runtime_error?(%RuntimeError{message: message}) do
    String.contains?(message, "could not lookup Ecto repo Cadence.Repo") or
      String.contains?(message, "Cadence.Repo did not become ready in time")
  end

  defp retryable_repo_exit?(:shutdown), do: true

  defp retryable_repo_exit?({:noproc, _call}), do: true

  defp retryable_repo_exit?(reason) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.any?(&retryable_repo_exit?/1)
  end

  defp retryable_repo_exit?(_reason), do: false

  defp telemetry_current_value_store_module do
    Application.get_env(:cadence, :telemetry_current_value_store, [])
    |> Keyword.get(:module)
  end

  defp retry_start_owner(opts, attempts) do
    Process.sleep(50)
    ensure_cadence_started!()
    start_owner_with_retry!(opts, attempts - 1)
  end

  defp ensure_cadence_started! do
    case Application.ensure_all_started(:cadence) do
      {:ok, _started_apps} ->
        wait_for_repo_ready!()

      {:error, reason} ->
        raise "Cadence application did not start: #{inspect(reason)}"
    end
  end

  defp wait_for_repo_ready!(attempts \\ @repo_ready_attempts)

  defp wait_for_repo_ready!(0) do
    raise "Cadence.Repo did not become ready in time"
  end

  defp wait_for_repo_ready!(attempts) do
    case Process.whereis(Cadence.Repo) do
      nil ->
        Process.sleep(@repo_ready_sleep_ms)
        wait_for_repo_ready!(attempts - 1)

      _pid ->
        :ok
    end
  end

  defp sandbox_owner_options(tags) do
    shared? = not tags[:async]

    [shared: shared?]
    |> maybe_put_ownership_timeout(
      tags[:sandbox_ownership_timeout] || default_ownership_timeout(shared?)
    )
  end

  defp default_ownership_timeout(true), do: 600_000
  defp default_ownership_timeout(false), do: nil

  defp maybe_put_ownership_timeout(options, timeout) when is_integer(timeout) and timeout > 0 do
    Keyword.put(options, :ownership_timeout, timeout)
  end

  defp maybe_put_ownership_timeout(options, _timeout), do: options
end
