defmodule Spotter.ProductSpec.Repo do
  @moduledoc """
  Ecto repo for the Dolt SQL-server backing the product specification store.
  """

  use Ecto.Repo, otp_app: :spotter, adapter: Ecto.Adapters.MyXQL
end
