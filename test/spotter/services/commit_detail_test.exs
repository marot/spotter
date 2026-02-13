defmodule Spotter.Services.CommitDetailTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.CommitDetail

  alias Spotter.Transcripts.{
    CoChangeGroup,
    Commit,
    Message,
    Project,
    Session,
    SessionCommitLink
  }

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project_session_commit do
    project =
      Ash.create!(Project, %{
        name: "detail-test-#{System.unique_integer([:positive])}",
        pattern: "^test"
      })

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        cwd: "/tmp/test-project",
        project_id: project.id
      })

    commit =
      Ash.create!(Commit, %{
        commit_hash: String.duplicate("a", 40),
        subject: "feat: add feature",
        changed_files: ["lib/foo.ex", "lib/bar.ex"]
      })

    Ash.create!(SessionCommitLink, %{
      session_id: session.id,
      commit_id: commit.id,
      link_type: :observed_in_session,
      confidence: 1.0
    })

    {project, session, commit}
  end

  test "load_commit returns commit by id" do
    {_project, _session, commit} = create_project_session_commit()

    assert {:ok, loaded} = CommitDetail.load_commit(commit.id)
    assert loaded.commit_hash == commit.commit_hash
  end

  test "load_commit returns error for unknown id" do
    assert {:error, :not_found} = CommitDetail.load_commit(Ash.UUID.generate())
  end

  test "load_linked_sessions returns sessions sorted by confidence" do
    {_project, session, commit} = create_project_session_commit()

    sessions = CommitDetail.load_linked_sessions(commit.id)

    assert length(sessions) == 1
    assert hd(sessions).session.id == session.id
    assert hd(sessions).max_confidence == 1.0
    assert :observed_in_session in hd(sessions).link_types
  end

  test "load_linked_sessions returns empty for no links" do
    commit = Ash.create!(Commit, %{commit_hash: String.duplicate("z", 40)})

    assert CommitDetail.load_linked_sessions(commit.id) == []
  end

  test "load_co_change_overlaps finds matching groups" do
    {project, _session, commit} = create_project_session_commit()

    Ash.create!(CoChangeGroup, %{
      project_id: project.id,
      scope: :file,
      group_key: "lib/foo.ex|lib/baz.ex",
      members: ["lib/foo.ex", "lib/baz.ex"],
      frequency_30d: 3
    })

    groups = CommitDetail.load_co_change_overlaps(commit)

    assert length(groups) == 1
    assert hd(groups).group_key == "lib/foo.ex|lib/baz.ex"
  end

  test "load_co_change_overlaps returns empty when no overlap" do
    commit =
      Ash.create!(Commit, %{
        commit_hash: String.duplicate("y", 40),
        changed_files: ["lib/unique.ex"]
      })

    assert CommitDetail.load_co_change_overlaps(commit) == []
  end

  test "load_session_messages returns messages for session" do
    {_project, session, _commit} = create_project_session_commit()

    Ash.create!(Message, %{
      uuid: "msg-detail-1",
      type: :assistant,
      role: :assistant,
      timestamp: DateTime.utc_now(),
      session_id: session.id,
      content: %{"blocks" => [%{"type" => "text", "text" => "hello"}]}
    })

    messages = CommitDetail.load_session_messages(session.id)

    assert length(messages) == 1
    assert hd(messages).uuid == "msg-detail-1"
  end
end
