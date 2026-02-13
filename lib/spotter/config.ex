defmodule Spotter.Config do
  @moduledoc "Domain for app configuration overrides."
  use Ash.Domain

  resources do
    resource Spotter.Config.Setting
  end
end
