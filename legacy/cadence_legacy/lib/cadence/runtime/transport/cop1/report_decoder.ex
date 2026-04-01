defmodule Cadence.Runtime.Transport.COP1.ReportDecoder do
  @moduledoc """
  Behavior for decoding COP-1 reports into normalized structs.
  """

  alias Cadence.Runtime.Transport.COP1.Report

  @callback decode(term(), map()) :: {:ok, Report.t()} | :not_a_report | {:error, term()}
end
