require "test_helper"

class Account::ImportTest < ActiveSupport::TestCase
  setup do
    @identity = identities(:david)
    @source_account = accounts("37s")
  end

  test "perform_later enqueues ImportAccountDataJob" do
    import = create_import_with_file

    assert_enqueued_with(job: ImportAccountDataJob, args: [ import ]) do
      import.perform_later
    end
  end

  test "perform sets status to failed on error" do
    import = create_import_with_file
    import.stubs(:import_all).raises(StandardError.new("Test error"))

    assert_raises(StandardError) do
      import.perform
    end

    assert import.failed?
  end

  test "perform imports account name from export" do
    target_account = create_target_account
    import = create_import_for_account(target_account)

    import.perform

    assert_equal @source_account.name, target_account.reload.name
  end

  test "perform maps system user" do
    target_account = create_target_account
    import = create_import_for_account(target_account)

    import.perform

    # The target account should still have exactly one system user
    assert_equal 1, target_account.users.where(role: :system).count
  end

  test "perform imports users with identity matching" do
    target_account = create_target_account
    import = create_import_for_account(target_account)
    david_email = identities(:david).email_address

    import.perform

    # David's identity should be matched, not duplicated
    assert_equal 1, Identity.where(email_address: david_email).count

    # A user with david's email should exist in the new account
    new_david = target_account.users.joins(:identity).find_by(identities: { email_address: david_email })
    assert_not_nil new_david
  end

  test "perform preserves join code if unique" do
    target_account = create_target_account
    original_code = target_account.join_code.code
    import = create_import_for_account(target_account)

    # Set up a unique code in the export
    export_code = "UNIQ-CODE-1234"
    Account::JoinCode.where(code: export_code).delete_all

    # Modify the export zip to have this code
    import_with_custom_join_code = create_import_for_account(target_account, join_code: export_code)

    import_with_custom_join_code.perform

    assert_equal export_code, target_account.join_code.reload.code
  end

  test "perform keeps existing join code on collision" do
    target_account = create_target_account
    original_code = target_account.join_code.code

    # Create another account with a specific join code
    other_account = Account.create!(name: "Other")
    other_account.join_code.update!(code: "COLL-ISION-CODE")

    import = create_import_for_account(target_account, join_code: "COLL-ISION-CODE")

    import.perform

    # The target account should keep its original code since there's a collision
    assert_equal original_code, target_account.join_code.reload.code
  end

  test "perform validates export integrity - rejects foreign account references" do
    target_account = create_target_account
    import = create_import_with_foreign_account_reference(target_account)

    assert_raises(Account::Import::IntegrityError) do
      import.perform
    end
  end

  test "perform rolls back on ID collision" do
    target_account = create_target_account

    # Pre-create a card with a specific ID that will collide
    colliding_id = ActiveRecord::Type::Uuid.generate
    Card.create!(
      id: colliding_id,
      account: target_account,
      board: target_account.boards.first || Board.create!(account: target_account, name: "Test", creator: target_account.system_user),
      creator: target_account.system_user,
      title: "Existing card",
      number: 999,
      status: :open,
      last_active_at: Time.current
    )

    import = create_import_for_account(target_account, card_id: colliding_id)

    assert_raises(ActiveRecord::RecordNotUnique) do
      import.perform
    end

    # Import should be marked as failed
    assert import.reload.failed?
  end

  test "perform sends completion email and schedules cleanup on success" do
    target_account = create_target_account
    import = create_import_for_account(target_account)

    assert_enqueued_jobs 2 do # Email + cleanup job
      import.perform
    end

    assert import.completed?
  end

  test "perform sends failure email on error" do
    target_account = create_target_account
    import = create_import_for_account(target_account)
    import.stubs(:import_all).raises(StandardError.new("Test error"))

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      assert_raises(StandardError) do
        import.perform
      end
    end
  end

  private
    def create_target_account
      account = Account.create!(name: "Import Target")
      account.users.create!(role: :system, name: "System")
      account.users.create!(
        role: :owner,
        name: "Importer",
        identity: @identity,
        verified_at: Time.current
      )
      account
    end

    def create_import_with_file
      import = Account::Import.create!(identity: @identity)
      import.file.attach(io: generate_export_zip, filename: "export.zip", content_type: "application/zip")
      import
    end

    def create_import_for_account(target_account, **options)
      import = Account::Import.create!(identity: @identity, account: target_account)
      import.file.attach(io: generate_export_zip(**options), filename: "export.zip", content_type: "application/zip")
      import
    end

    def create_import_with_foreign_account_reference(target_account)
      import = Account::Import.create!(identity: @identity, account: target_account)
      import.file.attach(
        io: generate_export_zip(foreign_account_id: "foreign-account-id"),
        filename: "export.zip",
        content_type: "application/zip"
      )
      import
    end

    def generate_export_zip(join_code: nil, card_id: nil, foreign_account_id: nil)
      Tempfile.new([ "export", ".zip" ]).tap do |tempfile|
        Zip::File.open(tempfile.path, create: true) do |zip|
          account_data = @source_account.as_json.merge(
            "join_code" => {
              "code" => join_code || @source_account.join_code.code,
              "usage_count" => 0,
              "usage_limit" => 10
            }
          )
          zip.get_output_stream("data/account.json") { |f| f.write(JSON.generate(account_data)) }

          # Export users
          @source_account.users.each do |user|
            user_data = user.as_json.except("identity_id").merge(
              "email_address" => user.identity&.email_address,
              "account_id" => foreign_account_id || @source_account.id
            )
            zip.get_output_stream("data/users/#{user.id}.json") { |f| f.write(JSON.generate(user_data)) }
          end

          # Export boards
          @source_account.boards.each do |board|
            board_data = board.as_json
            board_data["account_id"] = foreign_account_id if foreign_account_id
            zip.get_output_stream("data/boards/#{board.id}.json") { |f| f.write(JSON.generate(board_data)) }
          end

          # Export columns
          @source_account.columns.each do |column|
            zip.get_output_stream("data/columns/#{column.id}.json") { |f| f.write(JSON.generate(column.as_json)) }
          end

          # Export cards
          @source_account.cards.each do |card|
            card_data = card.as_json
            card_data["id"] = card_id if card_id
            zip.get_output_stream("data/cards/#{card_data['id'] || card.id}.json") { |f| f.write(JSON.generate(card_data)) }
          end

          # Export tags
          @source_account.tags.each do |tag|
            zip.get_output_stream("data/tags/#{tag.id}.json") { |f| f.write(JSON.generate(tag.as_json)) }
          end

          # Export comments
          Comment.where(account: @source_account).each do |comment|
            zip.get_output_stream("data/comments/#{comment.id}.json") { |f| f.write(JSON.generate(comment.as_json)) }
          end

          # Export empty directories for other types
          %w[
            entropies board_publications webhooks webhook_delinquency_trackers
            accesses assignments taggings steps closures card_goldnesses
            card_not_nows card_activity_spikes watches pins reactions
            mentions filters events notifications notification_bundles
            webhook_deliveries active_storage_blobs active_storage_attachments
            action_text_rich_texts
          ].each do |dir|
            # Just create the directory structure
          end
        end

        tempfile.rewind
        StringIO.new(tempfile.read)
      end
    end
end
