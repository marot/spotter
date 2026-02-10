defmodule SpotterTest do
  use ExUnit.Case
  doctest Spotter

  test "greets the world" do
    assert Spotter.hello() == :world
  end
end
