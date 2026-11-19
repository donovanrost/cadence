defmodule Cadence.DevSeedGuardTest do
  @moduledoc """
  #250: no dev seed writes a decision, an approval-setting change or active state.

  Every `dev/**/*.exs` is parsed (never run). A remote call to a decision verb (approve,
  approve_and_execute, execute, reject, decide), an approval-setting save, or a reference to
  the lab-only activation code fails the test. Approvals, settings changes and the first
  activation are made in the console by people, with a decision record.

  Limits (reviewed 11-19; a follow-up may close them): the scanner sees REMOTE calls by name
  (`Module.fun(...)`). It doesn't see `apply/3`, a function imported and then called bare, or a
  direct `Repo` write of an approval or settings row. A seed doing any of those slips past this
  test, so reviewers check new seeds for them.
  """
  use ExUnit.Case, async: true

  @dev Path.expand("../../../../dev", __DIR__)

  # dev/chaos is the user's lab; not edited by the team (director 11-18). It is not scanned.
  @excluded_dirs ["chaos"]

  # Loaded by the user's chaos lab (LAB_ACTION=activate) and kept unchanged for it. No other
  # dev file may reference it (see "the lab-only activation code").
  @lab_only ["reflect_orbital/activation.exs"]

  # OPEN (#250): the user's own opt-in demo script (301ad377b). It stays unscanned until the
  # user decides whether it goes or stays as a named opt-in.
  @pending_user_decision ["reflect_orbital_activate.exs"]

  # The one guarded call: the chaos lab still approves its fleet planning policy, only under
  # Fixture.chaos_lab?() (CADENCE_CHAOS_LAB=true and POD_NAMESPACE=cadence-chaos), never on
  # a dev stack (lead's ruling 11-18).
  @allowed_lab_calls [{"reflect_orbital/planning.exs", "FleetPlanningPolicies", :approve}]

  @decision_verbs [:approve, :approve_and_execute, :execute, :reject, :decide]
  @collection_modules ~w(Enum Stream Map MapSet Keyword List)
  @settings_modules ~w(ActivationPolicy ConsoleSettings ScopedSettings)

  describe "dev seeds" do
    test "make no decision, approval-setting save or activation outside the chaos lab" do
      {guarded, unguarded} = seed_files() |> Enum.flat_map(&denied_calls/1) |> split_guarded()

      assert unguarded == [],
             "dev seeds must not decide, save an approval setting or activate (#250): " <>
               inspect(unguarded)

      assert Enum.map(guarded, &Map.take(&1, [:file, :module, :fun])) ==
               Enum.map(@allowed_lab_calls, fn {f, m, fun} -> %{file: f, module: m, fun: fun} end)
    end

    test "never reach the lab-only activation code" do
      references =
        for file <- seed_files(),
            source = File.read!(Path.join(@dev, file)),
            source =~ ~r/ReflectOrbital\.Activation\b|activation\.exs/,
            do: file

      assert references == []
    end

    test "the scan sees the seed tree" do
      files = seed_files()
      assert "reflect_orbital/seed.exs" in files
      assert "reflect_orbital/planning.exs" in files
      refute Enum.any?(files, &String.starts_with?(&1, "chaos/"))
    end
  end

  describe "the scanner" do
    test "flags a decision verb and a settings save" do
      calls =
        scan("""
        Activations.execute(approved)
        FleetPlanningPolicies.approve(scope, m, id, 1, hash, "why")
        Cadence.Governance.ActivationPolicy.save(scope, m, token, %{})
        """)

      assert Enum.map(calls, &{&1.module, &1.fun, &1.guarded?}) == [
               {"Activations", :execute, false},
               {"FleetPlanningPolicies", :approve, false},
               {"ActivationPolicy", :save, false}
             ]
    end

    test "ignores collection functions and other saves" do
      assert scan("Enum.reject(list, & &1)\nDrafts.save(scope, m, id, token, doc)") == []
    end

    test "marks only calls under Fixture.chaos_lab?() as guarded" do
      calls =
        scan("""
        if F.chaos_lab?() do
          FleetPlanningPolicies.approve(scope, m, id, 1, hash, "why")
        end

        if other?() do
          FleetPlanningPolicies.approve(scope, m, id, 1, hash, "why")
        end
        """)

      assert Enum.map(calls, & &1.guarded?) == [true, false]
    end

    test "an approve in the else branch of a lab check is NOT guarded" do
      calls =
        scan("""
        if F.chaos_lab?() do
          :ok
        else
          FleetPlanningPolicies.approve(scope, m, id, 1, hash, "why")
        end
        """)

      assert Enum.map(calls, & &1.guarded?) == [false]
    end
  end

  defp seed_files do
    excluded = @lab_only ++ @pending_user_decision

    @dev
    |> Path.join("**/*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, @dev))
    |> Enum.reject(fn file ->
      file in excluded or Enum.any?(@excluded_dirs, &String.starts_with?(file, &1 <> "/"))
    end)
    |> Enum.sort()
  end

  defp denied_calls(file) do
    @dev |> Path.join(file) |> File.read!() |> scan() |> Enum.map(&Map.put(&1, :file, file))
  end

  defp split_guarded(calls), do: Enum.split_with(calls, & &1.guarded?)

  defp scan(source) do
    source
    |> Code.string_to_quoted!(columns: false)
    |> collect(false)
    |> Enum.sort_by(& &1.line)
  end

  # Only the `do:` branch of `if Fixture.chaos_lab?()` is lab-only; its `else:` runs on a dev
  # stack, so it isn't guarded (api-ops' and fe-setup's review).
  defp collect({:if, _meta, [condition, branches]}, guarded?) when is_list(branches) do
    lab? = lab_check?(condition)

    collect(condition, guarded?) ++
      Enum.flat_map(branches, fn
        {:do, body} -> collect(body, guarded? or lab?)
        {_else, body} -> collect(body, guarded?)
      end)
  end

  defp collect({{:., meta, [module, fun]}, _call_meta, args} = _call, guarded?)
       when is_atom(fun) and is_list(args) do
    name = module_name(module)

    here =
      if denied?(name, fun),
        do: [%{module: name, fun: fun, line: meta[:line], guarded?: guarded?}],
        else: []

    here ++ collect(module, guarded?) ++ collect(args, guarded?)
  end

  defp collect({left, _meta, right}, guarded?),
    do: collect(left, guarded?) ++ collect(right, guarded?)

  defp collect({left, right}, guarded?), do: collect(left, guarded?) ++ collect(right, guarded?)
  defp collect(list, guarded?) when is_list(list), do: Enum.flat_map(list, &collect(&1, guarded?))
  defp collect(_leaf, _guarded?), do: []

  defp lab_check?({{:., _, [{:__aliases__, _, parts}, :chaos_lab?]}, _, []}),
    do: List.last(parts) in [:F, :Fixture]

  defp lab_check?(_condition), do: false

  defp module_name({:__aliases__, _, parts}), do: parts |> List.last() |> Atom.to_string()
  defp module_name(other), do: inspect(other)

  defp denied?(module, fun) when fun in @decision_verbs, do: module not in @collection_modules
  defp denied?(module, :save), do: module in @settings_modules
  defp denied?(_module, _fun), do: false
end
