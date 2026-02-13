defmodule SpotterWeb.FileDetailLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox

  alias Spotter.Transcripts.{
    Commit,
    CommitFile,
    Project,
    Session,
    SessionCommitLink
  }

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-file-detail", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    commit =
      Ash.create!(Commit, %{
        commit_hash: String.duplicate("c", 40),
        subject: "feat: add file detail page",
        git_branch: "main",
        author_name: "Test Author",
        changed_files: ["lib/foo.ex", "lib/bar.ex"]
      })

    Ash.create!(CommitFile, %{
      commit_id: commit.id,
      relative_path: "lib/foo.ex",
      change_type: :modified
    })

    Ash.create!(SessionCommitLink, %{
      session_id: session.id,
      commit_id: commit.id,
      link_type: :observed_in_session,
      confidence: 1.0
    })

    %{project: project, session: session, commit: commit}
  end

  describe "file detail page" do
    test "renders file detail root", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      assert html =~ ~s(data-testid="file-detail-root")
      assert html =~ "lib/foo.ex"
    end

    test "renders commits for file", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      assert html =~ String.duplicate("c", 8)
      assert html =~ "modified"
    end

    test "renders linked sessions", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      assert html =~ "Linked Sessions"
      assert html =~ "Verified"
    end

    test "renders not found for unknown project" do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{Ash.UUID.generate()}/files/lib/foo.ex")

      assert html =~ "File not found"
    end

    test "renders language class", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/files/lib/foo.ex")

      assert html =~ "elixir"
    end
  end
end
