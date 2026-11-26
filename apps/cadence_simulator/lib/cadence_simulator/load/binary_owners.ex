defmodule CadenceSimulator.Load.BinaryOwners do
  @moduledoc false

  @top_count 10

  def snapshot do
    owners = Enum.flat_map(Process.list(), &sample_owner/1)

    %{
      top_processes:
        owners
        |> Enum.sort_by(& &1.referenced_bytes, :desc)
        |> Enum.take(@top_count),
      by_role: summarize_roles(owners)
    }
  end

  defp sample_owner(pid) do
    case Process.info(pid, :binary) do
      {:binary, [_ | _] = binaries} ->
        referenced_bytes = Enum.sum_by(binaries, fn {_id, bytes, _ref_count} -> bytes end)

        [
          %{
            pid: inspect(pid),
            role: role(pid),
            referenced_bytes: referenced_bytes,
            references: length(binaries)
          }
        ]

      _other ->
        []
    end
  end

  defp role(pid) do
    case :proc_lib.get_label(pid) do
      {:simulator_load_receiver, _scid} ->
        "TCP sink receiver"

      _other ->
        {module, _function, _arity} = :proc_lib.translate_initial_call(pid)
        inspect(module)
    end
  end

  defp summarize_roles(owners) do
    owners
    |> Enum.group_by(& &1.role)
    |> Enum.map(fn {role, processes} ->
      %{
        role: role,
        processes: length(processes),
        referenced_bytes: Enum.sum_by(processes, & &1.referenced_bytes)
      }
    end)
    |> Enum.sort_by(& &1.referenced_bytes, :desc)
  end
end
