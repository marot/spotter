defmodule Spotter.Transcripts.ResourcesTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, Message, Project, Session, SessionCommitLink, Subagent}

  setup do
    Sandbox.checkout(Repo)
  end

  describe "Project" do
    test "creates and reads a project" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      assert project.name == "test"
      assert project.pattern == "^test"
      assert project.id != nil

      projects = Ash.read!(Project)
      assert length(projects) == 1
    end

    test "enforces unique name" do
      Ash.create!(Project, %{name: "test", pattern: "^test"})

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Project, %{name: "test", pattern: "^test2"})
      end
    end
  end

  describe "Session" do
    test "creates session with project" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      assert session.schema_version == 1
      assert session.transcript_dir == "test-dir"
    end
  end

  describe "Message" do
    test "creates message with session" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      message =
        Ash.create!(Message, %{
          uuid: "msg-1",
          type: :user,
          role: :user,
          timestamp: DateTime.utc_now(),
          session_id: session.id,
          content: %{"text" => "hello"}
        })

      assert message.type == :user
      assert message.content == %{"text" => "hello"}
    end
  end

  describe "Subagent" do
    test "creates subagent with session" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      subagent =
        Ash.create!(Subagent, %{
          agent_id: "abc123",
          session_id: session.id
        })

      assert subagent.agent_id == "abc123"
    end
  end

  describe "Commit" do
    test "creates and reads a commit" do
      commit = Ash.create!(Commit, %{commit_hash: "a" |> String.duplicate(40)})

      assert commit.commit_hash == String.duplicate("a", 40)
      assert commit.parent_hashes == []
      assert commit.changed_files == []
    end

    test "enforces unique commit_hash" do
      hash = String.duplicate("b", 40)
      Ash.create!(Commit, %{commit_hash: hash})

      # upsert returns existing record
      commit2 = Ash.create!(Commit, %{commit_hash: hash})
      assert commit2.commit_hash == hash
    end
  end

  describe "SessionCommitLink" do
    setup do
      project = Ash.create!(Project, %{name: "test-link", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      commit = Ash.create!(Commit, %{commit_hash: String.duplicate("c", 40)})

      %{session: session, commit: commit}
    end

    test "creates link with confidence", %{session: session, commit: commit} do
      link =
        Ash.create!(SessionCommitLink, %{
          session_id: session.id,
          commit_id: commit.id,
          link_type: :observed_in_session,
          confidence: 1.0,
          evidence: %{"source" => "hook-minimal"}
        })

      assert link.link_type == :observed_in_session
      assert link.confidence == 1.0
    end

    test "enforces unique session+commit+link_type", %{session: session, commit: commit} do
      attrs = %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      }

      Ash.create!(SessionCommitLink, attrs)

      # upsert updates confidence/evidence
      link2 = Ash.create!(SessionCommitLink, Map.put(attrs, :confidence, 0.8))
      assert link2.confidence == 0.8
    end

    test "allows different link_types for same session+commit", %{
      session: session,
      commit: commit
    } do
      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      link2 =
        Ash.create!(SessionCommitLink, %{
          session_id: session.id,
          commit_id: commit.id,
          link_type: :patch_match,
          confidence: 0.7
        })

      assert link2.link_type == :patch_match
    end
  end
end
