defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelection.EvidencePanel do
  @moduledoc false

  def panel?({:evidence, inspector}) when is_map(inspector), do: true
  def panel?(_panel), do: false

  def status({:evidence, %{status: status}}), do: status
  def status({:evidence, %{"status" => status}}), do: status
  def status(_panel), do: nil

  def kind({:evidence, %{kind: kind}}), do: context_text(kind)
  def kind({:evidence, %{"kind" => kind}}), do: context_text(kind)
  def kind(_panel), do: nil

  def source_request(panel), do: row_value(panel, "Source request")
  def logical_source(panel), do: row_value(panel, "Logical source")
  def realm(panel), do: row_value(panel, "Realm")
  def data_source_id(panel), do: row_value(panel, "Data source")
  def source_binding_id(panel), do: row_value(panel, "Source binding")

  def row_value({:evidence, inspector}, label) do
    inspector
    |> evidence_rows()
    |> find_row_value(label)
  end

  def row_value(_panel, _label), do: nil

  defp evidence_rows(%{subject_rows: subject_rows, detail_rows: detail_rows}) do
    List.wrap(subject_rows) ++ List.wrap(detail_rows)
  end

  defp evidence_rows(%{subject_rows: subject_rows}), do: List.wrap(subject_rows)

  defp evidence_rows(%{"subject_rows" => subject_rows, "detail_rows" => detail_rows}) do
    List.wrap(subject_rows) ++ List.wrap(detail_rows)
  end

  defp evidence_rows(%{"subject_rows" => subject_rows}), do: List.wrap(subject_rows)
  defp evidence_rows(_inspector), do: []

  defp find_row_value(rows, label) do
    Enum.find_value(rows, fn
      %{label: ^label, value: value} -> context_text(value)
      %{"label" => ^label, "value" => value} -> context_text(value)
      _other -> nil
    end)
  end

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
  defp context_text(value) when is_integer(value), do: Integer.to_string(value)
  defp context_text(_value), do: nil
end
