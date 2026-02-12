defmodule SpotterWeb.HeatmapLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{FileHeatmap, Project}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_heatmap(project, path, opts \\ []) do
    Ash.create!(FileHeatmap, %{
      project_id: project.id,
      relative_path: path,
      change_count_30d: opts[:count] || 1,
      heat_score: opts[:score] || 50.0,
      last_changed_at: opts[:last_changed_at] || ~U[2026-02-01 12:00:00Z]
    })
  end

  describe "populated heatmap" do
    test "renders file rows ranked by heat score" do
      project = create_project("heatmap-pop")
      create_heatmap(project, "lib/hot.ex", score: 85.0, count: 15)
      create_heatmap(project, "lib/cold.ex", score: 10.0, count: 1)

      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/heatmap")

      assert html =~ "lib/hot.ex"
      assert html =~ "lib/cold.ex"
      assert html =~ "85.0"
      assert html =~ "15 changes"
    end

    test "heat badges have correct classes" do
      project = create_project("heatmap-badges")
      create_heatmap(project, "hot.ex", score: 75.0)
      create_heatmap(project, "warm.ex", score: 45.0)
      create_heatmap(project, "mild.ex", score: 20.0)
      create_heatmap(project, "cold.ex", score: 5.0)

      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/heatmap")

      assert html =~ "badge-hot"
      assert html =~ "badge-warm"
      assert html =~ "badge-mild"
      assert html =~ "badge-cold"
    end
  end

  describe "filtering" do
    test "filter_min_score filters out low-score files" do
      project = create_project("heatmap-filter")
      create_heatmap(project, "lib/high.ex", score: 80.0)
      create_heatmap(project, "lib/low.ex", score: 10.0)

      {:ok, view, _html} = live(build_conn(), "/projects/#{project.id}/heatmap")

      html = render_click(view, "filter_min_score", %{"min_score" => "40"})

      assert html =~ "lib/high.ex"
      refute html =~ "lib/low.ex"
    end
  end

  describe "sorting" do
    test "sort_by change_count_30d reorders files" do
      project = create_project("heatmap-sort")
      create_heatmap(project, "lib/many.ex", score: 30.0, count: 20)
      create_heatmap(project, "lib/few.ex", score: 80.0, count: 2)

      {:ok, view, _html} = live(build_conn(), "/projects/#{project.id}/heatmap")

      html = render_click(view, "sort_by", %{"field" => "change_count_30d"})

      # many.ex should come first when sorted by change count
      many_pos = :binary.match(html, "lib/many.ex") |> elem(0)
      few_pos = :binary.match(html, "lib/few.ex") |> elem(0)
      assert many_pos < few_pos
    end
  end

  describe "empty states" do
    test "renders empty message for project with no data" do
      project = create_project("heatmap-empty")

      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/heatmap")

      assert html =~ "No file activity data for this project yet"
    end

    test "renders not found for invalid project id" do
      {:ok, _view, html} =
        live(build_conn(), "/projects/019c0000-0000-7000-8000-000000000000/heatmap")

      assert html =~ "Project not found"
    end
  end
end
