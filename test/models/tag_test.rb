require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "creating or deleting a tag touches the account, so tags dialog fragment cache is invalidated" do
    account = accounts("37s")

    assert_changes -> { account.reload.updated_at } do
      account.tags.create!(title: "ReleaseBlocker")
    end

    assert_changes -> { account.reload.updated_at } do
      account.tags.find_by(title: "ReleaseBlocker").destroy
    end
  end
end
