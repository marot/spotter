defmodule Spotter.ProductSpec.Config do
  @moduledoc """
  Runtime configuration helpers for the product specification feature.
  """

  @doc """
  Returns `true` when the product spec feature is enabled via
  `SPOTTER_PRODUCT_SPEC_ENABLED=true`.
  """
  @spec enabled? :: boolean()
  def enabled? do
    Application.get_env(:spotter, :product_spec_enabled, false)
  end
end
