defmodule SpotterWeb.ProductLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  test "/product mounts and renders page header" do
    conn = build_conn()
    {:ok, view, html} = live(conn, "/product")
    assert html =~ "Product"
    assert html =~ "Rolling spec derived from commits"
    assert has_element?(view, "h1", "Product")
  end

  test "/product shows Dolt unavailable callout when repo is down" do
    # In test env, Dolt is typically not running, so the supervisor returns :ignore
    # and ProductSpec.Repo process won't exist
    if Process.whereis(Spotter.ProductSpec.Repo) == nil do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/product")
      assert html =~ "Dolt is unavailable"
      assert html =~ "docker compose"
    end
  end

  test "sidebar contains link to /product" do
    conn = build_conn()
    {:ok, _view, html} = live(conn, "/product")
    assert html =~ ~s|href="/product"|
    assert html =~ "Product"
  end
end
