defmodule Cadence.RuntimeCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using opts do
    isolated? = Keyword.get(opts, :isolated, false)

    quote do
      @moduletag :runtime

      if unquote(isolated?) do
        @moduletag runtime_case: :isolated
      end

      alias Cadence.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Cadence.DataCase
    end
  end

  setup tags do
    setup_owned_runtime(tags)
  end

  def setup_owned_runtime(%{runtime_case: :isolated} = tags) do
    pid = Cadence.DataCase.start_sandbox_owner!(tags, shared?: false)

    on_exit(fn ->
      stop_isolated_sandbox_owner(pid)
    end)

    %{sandbox_owner_pid: pid}
  end

  def setup_owned_runtime(tags) do
    Cadence.RuntimeTestSupport.prepare_default_runtime()

    pid = Cadence.DataCase.start_sandbox_owner!(tags, shared?: true)

    on_exit(fn ->
      Cadence.RuntimeTestSupport.cleanup_default_runtime()
      Cadence.DataCase.stop_sandbox_owner(pid)
      Cadence.DataCase.ensure_cadence_started!()
    end)

    :ok
  end

  defp stop_isolated_sandbox_owner(pid) do
    if Process.alive?(pid) do
      Cadence.DataCase.stop_sandbox_owner(pid)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end
end
