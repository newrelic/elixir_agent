defmodule NewRelic.Telemetry.Absinthe.MetadataTest do
  use ExUnit.Case, async: true
  alias NewRelic.Telemetry.Absinthe.Metadata

  describe "operation span name" do
    test "when query" do
      query_string = "{\n  hero {\n    name\n  }\n}"
      assert Metadata.operation_span_name(query_string) == "query:hero"
    end

    test "when custom a query name" do
      query_string = "query getHero {\n  hero {\n    name\n  }\n}"
      assert Metadata.operation_span_name(query_string) == "query:getHero"
    end

    test "when query contains a fragment" do
      query_string =
        "fragment NameParts on Person { \n  firstName \n  lastName \n}\nquery GetPerson {\n  people(id: 7) {\n    ...NameParts\n    avatar(size: LARGE)\n  }\n}"

      assert Metadata.operation_span_name(query_string) == "query:GetPerson"
    end

    test "when mutation" do
      query_string =
        "mutation ($ep: Episode!, $review: ReviewInput!) { \n  createReview(episode: $ep, review: $review) { \n    stars \n    commentary \n  } \n}"

      assert Metadata.operation_span_name(query_string) == "mutation:createReview"
    end

    test "when custom mutation" do
      query_string =
        "mutation CreateReviewForEpisode($ep: Episode!, $review: ReviewInput!) { \n  createReview(episode: $ep, review: $review) { \n    stars \n    commentary \n  } \n}"

      assert Metadata.operation_span_name(query_string) == "mutation:CreateReviewForEpisode"
    end
  end
end
