defmodule Cadence.Reads.ApplicationSurfaces.Planning.Form do
  @moduledoc """
  Plain initial-form presentation data shared by planning surfaces.
  These reads do not carry validation results; action validation remains server-owned.
  No Phoenix form or socket crosses the domain read boundary.
  """

  def new(name, params), do: %{name: name, params: params}

  def value(form, field) do
    case Map.get(form.params, Atom.to_string(field)) do
      nil -> ""
      value -> to_string(value)
    end
  end

  def field(form, field, id, label, type, opts \\ []) do
    %{
      id: id,
      name: "#{form.name}[#{field}]",
      type: type,
      label: label,
      required: Keyword.get(opts, :required, false),
      min: Keyword.get(opts, :min),
      step: Keyword.get(opts, :step),
      options: Keyword.get(opts, :options, []),
      value: value(form, field),
      errors: []
    }
  end

  def checkbox(form, field, id, label) do
    %{
      id: id,
      name: "#{form.name}[#{field}]",
      type: "checkbox",
      label: label,
      value: Map.get(form.params, Atom.to_string(field)) in [true, "true", "on", "1", 1],
      errors: []
    }
  end

  def options(options),
    do: Enum.map(options, fn {label, value} -> %{label: label, value: value} end)
end
