defmodule Cadence.Reads.CommandGroups.VerifyTimes do
  @moduledoc """
  A group member's verification times (U1, fe-ops), from its verifier instances, so the request
  page words them without a series or history read:

    * `verify_by`: the latest verifier deadline (`timeout_at`);
    * `verified_at`: once every instance is satisfied, the latest `matched_at` (U69 A4a);
    * `timed_out_at`: the earliest deadline among instances that timed out;
    * `failed_at`: the earliest `matched_at` among instances whose failure criteria matched.

  Each is `nil` when it doesn't apply.
  """

  @spec fields(map() | nil) :: %{
          verify_by: DateTime.t() | nil,
          verified_at: DateTime.t() | nil,
          timed_out_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil
        }
  def fields(%{verifier_instances: [_ | _] = instances}) do
    %{
      verify_by: instances |> Enum.map(& &1.timeout_at) |> latest(),
      verified_at:
        if(Enum.all?(instances, &(state(&1) == "satisfied")),
          do: instances |> Enum.map(& &1.matched_at) |> latest()
        ),
      timed_out_at:
        instances
        |> Enum.filter(&(state(&1) == "timed_out"))
        |> Enum.map(& &1.timeout_at)
        |> earliest(),
      failed_at:
        instances
        |> Enum.filter(&(state(&1) == "failed"))
        |> Enum.map(& &1.matched_at)
        |> earliest()
    }
  end

  def fields(_row), do: %{verify_by: nil, verified_at: nil, timed_out_at: nil, failed_at: nil}

  defp state(instance), do: to_string(instance.lifecycle_state)

  defp latest(times), do: times |> Enum.reject(&is_nil/1) |> Enum.max(DateTime, fn -> nil end)
  defp earliest(times), do: times |> Enum.reject(&is_nil/1) |> Enum.min(DateTime, fn -> nil end)
end
