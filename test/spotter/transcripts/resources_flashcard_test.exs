defmodule Spotter.Transcripts.ResourcesFlashcardTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    Annotation,
    Flashcard,
    Project,
    Session
  }

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-flashcard", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    annotation =
      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "some code",
        comment: "explain this",
        purpose: :explain
      })

    %{project: project, annotation: annotation}
  end

  test "creates flashcard with required fields", %{project: project, annotation: annotation} do
    flashcard =
      Ash.create!(Flashcard, %{
        project_id: project.id,
        annotation_id: annotation.id,
        front_snippet: "What does this code do?",
        answer: "It processes data.",
        references: %{"urls" => ["https://example.com"]}
      })

    assert flashcard.front_snippet == "What does this code do?"
    assert flashcard.answer == "It processes data."
    assert flashcard.references == %{"urls" => ["https://example.com"]}
    assert flashcard.question == nil
  end

  test "creates flashcard with optional question", %{project: project, annotation: annotation} do
    flashcard =
      Ash.create!(Flashcard, %{
        project_id: project.id,
        annotation_id: annotation.id,
        question: "How does pattern matching work?",
        front_snippet: "case x do ...",
        answer: "Pattern matching dispatches on structure."
      })

    assert flashcard.question == "How does pattern matching work?"
  end

  test "rejects flashcard without front_snippet", %{project: project, annotation: annotation} do
    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(Flashcard, %{
        project_id: project.id,
        annotation_id: annotation.id,
        answer: "some answer"
      })
    end
  end

  test "rejects flashcard without answer", %{project: project, annotation: annotation} do
    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(Flashcard, %{
        project_id: project.id,
        annotation_id: annotation.id,
        front_snippet: "some snippet"
      })
    end
  end
end
