defmodule Spotter.ProductSpec.Supervisor do
  @moduledoc """
  Supervisor for the Dolt-backed product spec subsystem.

  Starts the Dolt Ecto repo and ensures the schema exists.
  If Dolt is unreachable, logs a warning and returns `:ignore`
  so the rest of the application continues to boot.
  """

  use Supervisor

  alias Spotter.ProductSpec.Repo
  alias Spotter.ProductSpec.Schema

  require Logger

  def start_link(opts) do
    case Supervisor.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.warning(
          "ProductSpec.Supervisor failed to start (Dolt unavailable?): #{inspect(reason)}"
        )

        :ignore
    end
  end

  @impl true
  def init(_opts) do
    children = [
      Repo,
      {Task, &Schema.ensure_schema!/0}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
