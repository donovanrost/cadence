defmodule Cadence.Commanding.Groups.GroupSizeScaleTest do
  @moduledoc """
  How one command group behaves as it grows (#795): preflight, submit and the group read at
  N spacecraft x K stacked commands, with the size guard lifted out of the way. Excluded by default
  (`--include scale`). It prints the figures the PR states (they set the defaults of
  `Groups.Validation.bounds/0`) and asserts only a loose regression bound.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.{CommandGroups, CommandPreflight}

  @moduletag :scale
  @moduletag timeout: 1_800_000
  @moduletag sandbox_ownership_timeout: 1_800_000

  # {targets, stacked commands}: a wide group of a short stack, and a deep stack on fewer targets.
  @sizes (case System.get_env("GROUP_SCALE_SIZES") do
            nil ->
              [{500, 16}, {1_000, 16}, {5_000, 4}]

            list ->
              for pair <- String.split(list, ","),
                  [n, k] = String.split(pair, "x"),
                  do: {String.to_integer(n), String.to_integer(k)}
          end)

  setup do
    previous = Application.get_env(:cadence, :command_group_bounds)

    Application.put_env(:cadence, :command_group_bounds,
      max_targets: 1_000_000,
      max_commands: 1_000,
      max_members: 100_000_000
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence, :command_group_bounds, previous),
        else: Application.delete_env(:cadence, :command_group_bounds)
    end)
  end

  for {n, k} <- @sizes do
    test "#{n} targets x #{k} commands" do
      n = unquote(n)
      k = unquote(k)
      {setup_us, c} = :timer.tc(fn -> setup!(n) end)

      stack =
        for i <- 1..k, do: command(c, "SET_SIGNED", %{"counter" => i})

      draft = draft(c.spacecraft, stack, %{log_entry: "Scale run"})

      {preflight_us, {:ok, preflight}} =
        :timer.tc(fn -> CommandPreflight.run(c.org, c.mission, actor(c), draft) end)

      {submit_us, {:ok, group}} =
        :timer.tc(fn ->
          GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: preflight.digest)
        end)

      {get_us, {:ok, view}} =
        :timer.tc(fn ->
          CommandGroups.get(c.org, c.mission, group.command_group_id, c.scope.user.user_id)
        end)

      # The read's size in memory, a proxy for the JSON the console is sent.
      read_bytes = view |> :erlang.term_to_binary() |> byte_size()

      IO.puts(
        "GROUP_SCALE targets=#{n} commands=#{k} members=#{n * k} " <>
          "setup_ms=#{div(setup_us, 1000)} preflight_ms=#{div(preflight_us, 1000)} " <>
          "submit_ms=#{div(submit_us, 1000)} get_ms=#{div(get_us, 1000)} read_bytes=#{read_bytes}"
      )

      assert group.member_count == n * k
    end
  end
end
