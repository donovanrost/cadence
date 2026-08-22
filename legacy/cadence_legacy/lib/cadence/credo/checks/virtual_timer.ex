defmodule Cadence.Credo.Checks.VirtualTimer do
  @moduledoc false

  use Credo.Check,
    id: "CDV001",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Use Cadence.Time.Timer for scheduling and Cadence.Time for wall-clock reads
      so virtual time can drive deterministic tests and simulations.
      """
    ],
    param_defaults: [
      excluded_paths: [
        "lib/cadence/time/",
        "lib/cadence/time.ex",
        "lib/mix/"
      ],
      clock_excluded_paths: [
        "lib/cadence/time/",
        "lib/cadence/time.ex",
        "lib/cadence/harness/time/",
        "lib/cadence/harness/time.ex",
        "lib/mix/"
      ],
      clock_included_paths: [],
      test_excluded_paths: [
        "test/support/",
        "test/integration/"
      ],
      test_exit_status: 0,
      test_priority: :low,
      forbidden_calls: [
        {Process, :send_after, 3},
        {Process, :send_after, 4},
        {Process, :cancel_timer, 1},
        {:timer, :sleep, 1},
        {:timer, :send_after, 2},
        {:timer, :send_after, 3},
        {:timer, :send_after, 4},
        {:timer, :send_interval, 2},
        {:timer, :send_interval, 3},
        {:timer, :send_interval, 4},
        {:timer, :apply_after, 4},
        {:timer, :apply_interval, 4},
        {:erlang, :send_after, 3},
        {:erlang, :send_after, 4},
        {:erlang, :start_timer, 3},
        {:erlang, :start_timer, 4}
      ],
      clock_forbidden_calls: [
        {Date, :utc_today, 0},
        {DateTime, :utc_now, 0},
        {DateTime, :utc_now, 1},
        {DateTime, :now, 1},
        {DateTime, :now, 2},
        {NaiveDateTime, :utc_now, 0},
        {Time, :utc_now, 0},
        {System, :monotonic_time, 0},
        {System, :monotonic_time, 1},
        {System, :system_time, 0},
        {System, :system_time, 1},
        {System, :os_time, 0},
        {System, :os_time, 1},
        {System, :time_offset, 0},
        {System, :time_offset, 1},
        {:calendar, :local_time, 0},
        {:calendar, :universal_time, 0},
        {:erlang, :monotonic_time, 0},
        {:erlang, :monotonic_time, 1},
        {:erlang, :system_time, 0},
        {:erlang, :system_time, 1},
        {:erlang, :now, 0},
        {:os, :system_time, 0},
        {:os, :system_time, 1},
        {:os, :timestamp, 0}
      ]
    ]

  alias Credo.Check.Params

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    filename = filename || ""
    timer_enabled = not excluded_timer_file?(filename, params)
    clock_enabled = clock_enabled?(filename, params)

    if not timer_enabled and not clock_enabled do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      Credo.Code.prewalk(
        source_file,
        &traverse(&1, &2, issue_meta, params, filename, timer_enabled, clock_enabled)
      )
    end
  end

  defp traverse(
         {{:., meta, [module_ast, fun]}, _call_meta, args} = ast,
         issues,
         issue_meta,
         params,
         filename,
         timer_enabled,
         clock_enabled
       ) do
    module = module_atom(module_ast)
    arity = length(args)

    cond do
      timer_enabled && module && forbidden_call?(module, fun, arity, params) ->
        trigger = "#{inspect(module)}.#{fun}/#{arity}"

        {ast, [issue_for(issue_meta, meta, trigger, filename, params, timer_message()) | issues]}

      clock_enabled && module && clock_call?(module, fun, arity, params) ->
        trigger = "#{inspect(module)}.#{fun}/#{arity}"

        {ast, [issue_for(issue_meta, meta, trigger, filename, params, clock_message()) | issues]}

      true ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _params, _filename, _timer_enabled, _clock_enabled) do
    {ast, issues}
  end

  defp issue_for(issue_meta, meta, trigger, filename, params, message) do
    {priority, exit_status} = issue_severity(filename, params)

    format_issue(issue_meta,
      message: message,
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column],
      priority: priority,
      exit_status: exit_status
    )
  end

  defp issue_severity(filename, params) do
    if test_file?(filename) do
      {Params.get(params, :test_priority, __MODULE__),
       Params.get(params, :test_exit_status, __MODULE__)}
    else
      {nil, nil}
    end
  end

  defp forbidden_call?(module, fun, arity, params) do
    Params.get(params, :forbidden_calls, __MODULE__)
    |> Enum.any?(fn
      {^module, ^fun, :any} -> true
      {^module, ^fun, ^arity} -> true
      _ -> false
    end)
  end

  defp clock_call?(module, fun, arity, params) do
    Params.get(params, :clock_forbidden_calls, __MODULE__)
    |> Enum.any?(fn
      {^module, ^fun, :any} -> true
      {^module, ^fun, ^arity} -> true
      _ -> false
    end)
  end

  defp module_atom({:__aliases__, _, parts}), do: Module.concat(parts)
  defp module_atom(atom) when is_atom(atom), do: atom
  defp module_atom(_), do: nil

  defp excluded_timer_file?(filename, params) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)
    test_excluded_paths = Params.get(params, :test_excluded_paths, __MODULE__)

    excluded?(filename, excluded_paths) ||
      (test_file?(filename) && excluded?(filename, test_excluded_paths))
  end

  defp clock_enabled?(filename, params) do
    included_paths = Params.get(params, :clock_included_paths, __MODULE__) |> List.wrap()

    if included_paths == [] do
      false
    else
      not excluded_clock_file?(filename, params) &&
        Enum.any?(included_paths, &match_path?(filename, &1))
    end
  end

  defp excluded_clock_file?(filename, params) do
    excluded_paths = Params.get(params, :clock_excluded_paths, __MODULE__)
    test_excluded_paths = Params.get(params, :test_excluded_paths, __MODULE__)

    excluded?(filename, excluded_paths) ||
      (test_file?(filename) && excluded?(filename, test_excluded_paths))
  end

  defp excluded?(filename, paths) do
    paths
    |> List.wrap()
    |> Enum.any?(&match_path?(filename, &1))
  end

  defp match_path?(filename, %Regex{} = regex), do: Regex.match?(regex, filename)

  defp match_path?(filename, path) when is_binary(path) do
    if String.ends_with?(path, "/") do
      String.starts_with?(filename, path)
    else
      filename == path
    end
  end

  defp test_file?(filename), do: String.starts_with?(filename, "test/")

  defp timer_message, do: "Use Cadence.Time.Timer instead of real timer APIs."
  defp clock_message, do: "Use Cadence.Time instead of wall-clock APIs."
end
