defmodule Cadence.Catalog.MissionModel.Inheritance do
  @moduledoc "Validates and materializes explicit container and command inheritance."

  alias Cadence.Catalog.MissionModel.{Declaration, Diagnostic}

  @inheritable_kinds [:container, :command]

  @spec apply(%{binary() => Declaration.t()}, [map()]) ::
          {%{binary() => Declaration.t()}, [Diagnostic.t()]}
  def apply(declarations, edges) when is_map(declarations) and is_list(edges) do
    base_by_child =
      edges
      |> Enum.filter(&(&1.role == :base))
      |> Enum.group_by(& &1.from, & &1.to)

    diagnostics =
      multiple_base_diagnostics(base_by_child, declarations) ++
        invalid_kind_diagnostics(base_by_child, declarations) ++
        cycle_diagnostics(base_by_child, declarations)

    if diagnostics == [] do
      materialized =
        Map.new(declarations, fn {id, _declaration} ->
          {id, materialize(id, declarations, base_by_child, %{}) |> elem(0)}
        end)

      {materialized, []}
    else
      {declarations, diagnostics}
    end
  end

  defp materialize(id, declarations, base_by_child, memo) do
    case Map.fetch(memo, id) do
      {:ok, declaration} ->
        {declaration, memo}

      :error ->
        declaration = Map.fetch!(declarations, id)

        case Map.get(base_by_child, id, []) do
          [base_id] ->
            {base, memo} = materialize(base_id, declarations, base_by_child, memo)
            inherited = inherit(declaration, base)
            {inherited, Map.put(memo, id, inherited)}

          _other ->
            {declaration, Map.put(memo, id, declaration)}
        end
    end
  end

  defp inherit(%Declaration{} = declaration, %Declaration{} = base) do
    references =
      (base.references ++ declaration.references)
      |> Enum.reject(&(&1.role == :base))
      |> Enum.uniq_by(&{&1.expected_kind, &1.source_ref, &1.role, &1.resolved_id})

    compiler =
      declaration.extensions
      |> Map.get("cadence_compiler", %{})
      |> Map.put("inherited_from", base.semantic_id)

    %Declaration{
      declaration
      | definition: deep_merge(base.definition, declaration.definition),
        references: references,
        extensions: Map.put(declaration.extensions, "cadence_compiler", compiler)
    }
  end

  defp multiple_base_diagnostics(base_by_child, declarations) do
    base_by_child
    |> Enum.filter(fn {_child, bases} -> length(Enum.uniq(bases)) > 1 end)
    |> Enum.map(fn {child, bases} ->
      declaration = Map.get(declarations, child)

      diagnostic(
        declaration,
        "MM_INHERITANCE_BASE_AMBIGUOUS",
        "A declaration may inherit from only one base",
        %{base_ids: Enum.uniq(bases) |> Enum.sort()}
      )
    end)
  end

  defp invalid_kind_diagnostics(base_by_child, declarations) do
    Enum.flat_map(base_by_child, fn {child, bases} ->
      child_declaration = Map.get(declarations, child)

      bases
      |> Enum.uniq()
      |> Enum.flat_map(&invalid_base_diagnostic(child_declaration, &1, declarations))
    end)
  end

  defp invalid_base_diagnostic(child, base_id, declarations) do
    base = Map.get(declarations, base_id)

    if valid_inheritance?(child, base) do
      []
    else
      [
        diagnostic(
          child,
          "MM_INHERITANCE_KIND_INVALID",
          "Inheritance is supported only between declarations of the same container or command kind",
          %{base_id: base_id}
        )
      ]
    end
  end

  defp valid_inheritance?(%Declaration{kind: kind}, %Declaration{kind: kind}),
    do: kind in @inheritable_kinds

  defp valid_inheritance?(_child, _base), do: false

  defp cycle_diagnostics(base_by_child, declarations) do
    declarations
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce({MapSet.new(), []}, fn id, {visited, diagnostics} ->
      case walk(id, base_by_child, visited, []) do
        {:ok, next_visited} ->
          {next_visited, diagnostics}

        {:cycle, cycle, next_visited} ->
          declaration = Map.get(declarations, id)

          {next_visited,
           [
             diagnostic(
               declaration,
               "MM_INHERITANCE_CYCLE",
               "Declaration inheritance cycle detected",
               %{cycle: cycle}
             )
             | diagnostics
           ]}
      end
    end)
    |> elem(1)
  end

  defp walk(id, base_by_child, visited, stack) do
    cond do
      id in stack ->
        {:cycle, Enum.reverse([id | stack]), MapSet.put(visited, id)}

      MapSet.member?(visited, id) ->
        {:ok, visited}

      true ->
        walk_bases(
          Map.get(base_by_child, id, []),
          base_by_child,
          MapSet.put(visited, id),
          [id | stack]
        )
    end
  end

  defp walk_bases(bases, base_by_child, visited, stack) do
    Enum.reduce_while(bases, {:ok, visited}, fn base, {:ok, acc} ->
      case walk(base, base_by_child, acc, stack) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:cycle, cycle, next} -> {:halt, {:cycle, cycle, next}}
      end
    end)
  end

  defp diagnostic(declaration, code, message, metadata) do
    Diagnostic.new(%{
      code: code,
      severity: :error,
      stage: :inheritance,
      semantic_id: declaration && declaration.semantic_id,
      message: message,
      provenance: declaration && declaration.provenance,
      metadata: metadata
    })
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right),
    do: Map.merge(left, right, fn _key, l, r -> deep_merge(l, r) end)

  defp deep_merge(_left, right), do: right
end
