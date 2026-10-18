defmodule Cadence.Applications.OpsConsole.Actions.ScheduleCancellations do
  @moduledoc "Compatibility adapter for reviewed contact cancellations."
  defdelegate execute(scope, mission, params), to: Cadence.Contacts.ScheduleCancellations
end
