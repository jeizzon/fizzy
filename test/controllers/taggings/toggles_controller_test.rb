require "test_helper"

class Taggings::TogglesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "new" do
    get new_bucket_bubble_tagging_toggle_url(buckets(:writebook), bubbles(:logo))

    assert_response :success
  end

  test "create" do
    assert_changes "bubbles(:logo).tagged_with?(tags(:mobile))", from: false, to: true do
      post bucket_bubble_tagging_toggles_url(buckets(:writebook), bubbles(:logo)), params: { tag_id: tags(:mobile).id }, as: :turbo_stream
    end
    assert_response :success

    assert_changes "bubbles(:logo).tagged_with?(tags(:web))", from: false, to: true do
      assert_changes "bubbles(:logo).tagged_with?(tags(:mobile))", from: true, to: false do
        post bucket_bubble_tagging_toggles_url(buckets(:writebook), bubbles(:logo)), params: { tag_id: tags(:web).id }, as: :turbo_stream
      end
    end
    assert_response :success
  end
end
