class Account::Import < ApplicationRecord
  class IntegrityError < StandardError; end

  belongs_to :account
  belongs_to :identity

  has_one_attached :file

  enum :status, %w[ pending processing completed failed ].index_by(&:itself), default: :pending

  def perform_later
    ImportAccountDataJob.perform_later(self)
  end

  def perform
    processing!

    Current.set(account: account, user: owner_user) do
      file.open do |tempfile|
        Zip::File.open(tempfile.path) do |zip|
          ApplicationRecord.transaction do
            @old_account_data = load_account_data(zip)
            @id_mapper = IdMapper.new(account, @old_account_data)

            validate_export_integrity!(zip)
            import_all(zip)
          end
        end
      end
    end

    mark_completed
  rescue => e
    mark_failed
    raise
  end

  def owner_user
    account.users.find_by(identity: identity)
  end

  private
    def mark_completed
      update!(status: :completed, completed_at: Time.current)
      ImportMailer.completed(identity).deliver_later
    end

    def mark_failed
      update!(status: :failed)
      ImportMailer.failed(identity).deliver_later
    end

    def load_account_data(zip)
      entry = zip.find_entry("data/account.json")
      raise IntegrityError, "Missing account.json in export" unless entry

      JSON.parse(entry.get_input_stream.read)
    end

    def import_all(zip)
      # Phase 1: Foundation
      import_account_data
      import_join_code

      # Phase 2: Users (create identities, map system user)
      import_users(zip)

      # Phase 3: Basic entities
      import_tags(zip)
      import_boards(zip)
      import_columns(zip)
      import_entropies(zip)
      import_board_publications(zip)

      # Phase 4: Cards & content
      import_cards(zip)
      import_comments(zip)
      import_steps(zip)

      # Phase 5: Relationships
      import_accesses(zip)
      import_assignments(zip)
      import_taggings(zip)
      import_closures(zip)
      import_card_goldnesses(zip)
      import_card_not_nows(zip)
      import_card_activity_spikes(zip)
      import_watches(zip)
      import_pins(zip)
      import_reactions(zip)
      import_mentions(zip)
      import_filters(zip)

      # Phase 6: Webhooks
      import_webhooks(zip)
      import_webhook_delinquency_trackers(zip)
      import_webhook_deliveries(zip)

      # Phase 7: Activity & notifications
      import_events(zip)
      import_notifications(zip)
      import_notification_bundles(zip)

      # Phase 8: Storage & rich text
      import_active_storage_blobs(zip)
      import_active_storage_attachments(zip)
      import_action_text_rich_texts(zip)
      import_blob_files(zip)
    end

    # Phase 1: Foundation

    def import_account_data
      account.update!(name: @old_account_data["name"])
    end

    def import_join_code
      join_code_data = @old_account_data["join_code"]
      return unless join_code_data

      # Preserve the code if it's unique, otherwise keep the auto-generated one
      unless Account::JoinCode.exists?(code: join_code_data["code"])
        account.join_code.update!(
          code: join_code_data["code"],
          usage_count: join_code_data["usage_count"],
          usage_limit: join_code_data["usage_limit"]
        )
      end
    end

    # Phase 2: Users

    def import_users(zip)
      users_data = read_json_files(zip, "data/users")

      # Map system user first
      old_system = users_data.find { |u| u["role"] == "system" }
      if old_system
        @id_mapper.map(:users, old_system["id"], account.system_user.id)
      end

      # Import non-system users
      users_data.reject { |u| u["role"] == "system" }.each do |data|
        import_user(data)
      end
    end

    def import_user(data)
      email = data.delete("email_address")
      old_id = data.delete("id")

      user_identity = if email.present?
        Identity.find_or_create_by!(email_address: email)
      end

      # Check if user already exists for this identity in this account (e.g., the owner)
      existing_user = account.users.find_by(identity: user_identity) if user_identity
      if existing_user
        existing_user.update!(data.slice("name", "role", "active", "verified_at"))
        @id_mapper.map(:users, old_id, existing_user.id)
      else
        new_user = User.create!(
          data.slice(*User.column_names).merge(
            "account_id" => account.id,
            "identity_id" => user_identity&.id
          )
        )
        @id_mapper.map(:users, old_id, new_user.id)
      end
    end

    # Phase 3: Basic entities

    def import_tags(zip)
      records = read_json_files(zip, "data/tags").map do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data)
        new_record = Tag.create!(data)
        @id_mapper.map(:tags, old_id, new_record.id)
      end
    end

    def import_boards(zip)
      read_json_files(zip, "data/boards").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data)
        new_record = Board.create!(data)
        @id_mapper.map(:boards, old_id, new_record.id)
      end
    end

    def import_columns(zip)
      read_json_files(zip, "data/columns").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: { "board_id" => :boards })
        new_record = Column.create!(data)
        @id_mapper.map(:columns, old_id, new_record.id)
      end
    end

    def import_entropies(zip)
      read_json_files(zip, "data/entropies").each do |data|
        old_id = data.delete("id")

        # Remap polymorphic container_id based on container_type
        container_type = data["container_type"]
        if container_type == "Account"
          data["container_id"] = account.id
        elsif container_type == "Board"
          data["container_id"] = @id_mapper.lookup(:boards, data["container_id"])
        end

        data = @id_mapper.remap(data)

        # Find existing or create new
        existing = Entropy.find_by(container_type: data["container_type"], container_id: data["container_id"])
        if existing
          existing.update!(data.slice("auto_postpone_period"))
          @id_mapper.map(:entropies, old_id, existing.id)
        else
          new_record = Entropy.create!(data)
          @id_mapper.map(:entropies, old_id, new_record.id)
        end
      end
    end

    def import_board_publications(zip)
      read_json_files(zip, "data/board_publications").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: { "board_id" => :boards })
        new_record = Board::Publication.create!(data)
        @id_mapper.map(:board_publications, old_id, new_record.id)
      end
    end

    # Phase 4: Cards & content

    def import_cards(zip)
      read_json_files(zip, "data/cards").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "board_id" => :boards,
          "column_id" => :columns
        })
        new_record = Card.create!(data)
        @id_mapper.map(:cards, old_id, new_record.id)
      end
    end

    def import_comments(zip)
      read_json_files(zip, "data/comments").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "card_id" => :cards
        })
        new_record = Comment.create!(data)
        @id_mapper.map(:comments, old_id, new_record.id)
      end
    end

    def import_steps(zip)
      read_json_files(zip, "data/steps").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: { "card_id" => :cards })
        new_record = Step.create!(data)
        @id_mapper.map(:steps, old_id, new_record.id)
      end
    end

    # Phase 5: Relationships

    def import_accesses(zip)
      read_json_files(zip, "data/accesses").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "board_id" => :boards
        })

        # Board creation auto-creates access for creator, check if it exists
        existing = Access.find_by(board_id: data["board_id"], user_id: data["user_id"])
        if existing
          @id_mapper.map(:accesses, old_id, existing.id)
        else
          new_record = Access.create!(data)
          @id_mapper.map(:accesses, old_id, new_record.id)
        end
      end
    end

    def import_assignments(zip)
      read_json_files(zip, "data/assignments").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "card_id" => :cards
        })
        new_record = Assignment.create!(data)
        @id_mapper.map(:assignments, old_id, new_record.id)
      end
    end

    def import_taggings(zip)
      read_json_files(zip, "data/taggings").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: {
          "card_id" => :cards,
          "tag_id" => :tags
        })
        new_record = Tagging.create!(data)
        @id_mapper.map(:taggings, old_id, new_record.id)
      end
    end

    def import_closures(zip)
      read_json_files(zip, "data/closures").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "card_id" => :cards
        })
        new_record = Closure.create!(data)
        @id_mapper.map(:closures, old_id, new_record.id)
      end
    end

    def import_card_goldnesses(zip)
      read_json_files(zip, "data/card_goldnesses").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: { "card_id" => :cards })
        new_record = Card::Goldness.create!(data)
        @id_mapper.map(:card_goldnesses, old_id, new_record.id)
      end
    end

    def import_card_not_nows(zip)
      read_json_files(zip, "data/card_not_nows").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "card_id" => :cards
        })
        new_record = Card::NotNow.create!(data)
        @id_mapper.map(:card_not_nows, old_id, new_record.id)
      end
    end

    def import_card_activity_spikes(zip)
      read_json_files(zip, "data/card_activity_spikes").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: { "card_id" => :cards })
        new_record = Card::ActivitySpike.create!(data)
        @id_mapper.map(:card_activity_spikes, old_id, new_record.id)
      end
    end

    def import_watches(zip)
      read_json_files(zip, "data/watches").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "card_id" => :cards
        })

        # Card creation auto-creates watch for creator, check if it exists
        existing = Watch.find_by(card_id: data["card_id"], user_id: data["user_id"])
        if existing
          @id_mapper.map(:watches, old_id, existing.id)
        else
          new_record = Watch.create!(data)
          @id_mapper.map(:watches, old_id, new_record.id)
        end
      end
    end

    def import_pins(zip)
      read_json_files(zip, "data/pins").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "card_id" => :cards
        })
        new_record = Pin.create!(data)
        @id_mapper.map(:pins, old_id, new_record.id)
      end
    end

    def import_reactions(zip)
      read_json_files(zip, "data/reactions").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "comment_id" => :comments
        })
        new_record = Reaction.create!(data)
        @id_mapper.map(:reactions, old_id, new_record.id)
      end
    end

    def import_mentions(zip)
      read_json_files(zip, "data/mentions").each do |data|
        old_id = data.delete("id")

        # Remap polymorphic source_id based on source_type
        source_type = data["source_type"]
        source_mapping = case source_type
        when "Card" then :cards
        when "Comment" then :comments
        end
        data["source_id"] = @id_mapper.lookup(source_mapping, data["source_id"]) if source_mapping

        data = @id_mapper.remap_with_users(data)
        new_record = Mention.create!(data)
        @id_mapper.map(:mentions, old_id, new_record.id)
      end
    end

    def import_filters(zip)
      read_json_files(zip, "data/filters").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data)
        new_record = Filter.create!(data)
        @id_mapper.map(:filters, old_id, new_record.id)
      end
    end

    # Phase 6: Webhooks

    def import_webhooks(zip)
      read_json_files(zip, "data/webhooks").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: { "board_id" => :boards })
        new_record = Webhook.create!(data)
        @id_mapper.map(:webhooks, old_id, new_record.id)
      end
    end

    def import_webhook_delinquency_trackers(zip)
      read_json_files(zip, "data/webhook_delinquency_trackers").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: { "webhook_id" => :webhooks })
        new_record = Webhook::DelinquencyTracker.create!(data)
        @id_mapper.map(:webhook_delinquency_trackers, old_id, new_record.id)
      end
    end

    def import_webhook_deliveries(zip)
      read_json_files(zip, "data/webhook_deliveries").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data, foreign_keys: {
          "webhook_id" => :webhooks,
          "event_id" => :events
        })
        new_record = Webhook::Delivery.create!(data)
        @id_mapper.map(:webhook_deliveries, old_id, new_record.id)
      end
    end

    # Phase 7: Activity & notifications

    def import_events(zip)
      read_json_files(zip, "data/events").each do |data|
        old_id = data.delete("id")

        # Remap polymorphic eventable_id
        eventable_type = data["eventable_type"]
        eventable_mapping = polymorphic_type_to_mapping(eventable_type)
        data["eventable_id"] = @id_mapper.lookup(eventable_mapping, data["eventable_id"]) if eventable_mapping

        data = @id_mapper.remap_with_users(data, additional_foreign_keys: {
          "board_id" => :boards
        })
        new_record = Event.create!(data)
        @id_mapper.map(:events, old_id, new_record.id)
      end
    end

    def import_notifications(zip)
      read_json_files(zip, "data/notifications").each do |data|
        old_id = data.delete("id")

        # Remap polymorphic source_id
        source_type = data["source_type"]
        source_mapping = polymorphic_type_to_mapping(source_type)
        data["source_id"] = @id_mapper.lookup(source_mapping, data["source_id"]) if source_mapping

        data = @id_mapper.remap_with_users(data)
        new_record = Notification.create!(data)
        @id_mapper.map(:notifications, old_id, new_record.id)
      end
    end

    def import_notification_bundles(zip)
      read_json_files(zip, "data/notification_bundles").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap_with_users(data)
        new_record = Notification::Bundle.create!(data)
        @id_mapper.map(:notification_bundles, old_id, new_record.id)
      end
    end

    # Phase 8: Storage & rich text

    def import_active_storage_blobs(zip)
      read_json_files(zip, "data/active_storage_blobs").each do |data|
        old_id = data.delete("id")
        data = @id_mapper.remap(data)
        new_record = ActiveStorage::Blob.create!(data)
        @id_mapper.map(:active_storage_blobs, old_id, new_record.id)
      end
    end

    def import_active_storage_attachments(zip)
      read_json_files(zip, "data/active_storage_attachments").each do |data|
        old_id = data.delete("id")

        # Remap polymorphic record_id
        record_type = data["record_type"]
        record_mapping = polymorphic_type_to_mapping(record_type)
        data["record_id"] = @id_mapper.lookup(record_mapping, data["record_id"]) if record_mapping

        data = @id_mapper.remap(data, foreign_keys: { "blob_id" => :active_storage_blobs })
        new_record = ActiveStorage::Attachment.create!(data)
        @id_mapper.map(:active_storage_attachments, old_id, new_record.id)
      end
    end

    def import_action_text_rich_texts(zip)
      read_json_files(zip, "data/action_text_rich_texts").each do |data|
        old_id = data.delete("id")

        # Remap polymorphic record_id
        record_type = data["record_type"]
        record_mapping = polymorphic_type_to_mapping(record_type)
        data["record_id"] = @id_mapper.lookup(record_mapping, data["record_id"]) if record_mapping

        data["body"] = convert_gids_and_fix_links(data["body"])
        data = @id_mapper.remap(data)
        new_record = ActionText::RichText.create!(data)
        @id_mapper.map(:action_text_rich_texts, old_id, new_record.id)
      end
    end

    def import_blob_files(zip)
      zip.glob("storage/*").each do |entry|
        key = File.basename(entry.name)
        blob = ActiveStorage::Blob.find_by(key: key, account: account)
        next unless blob

        blob.upload(entry.get_input_stream)
      end
    end

    # Helper methods

    def read_json_files(zip, directory)
      zip.glob("#{directory}/*.json").map do |entry|
        JSON.parse(entry.get_input_stream.read)
      end
    end

    def convert_gids_and_fix_links(html)
      return html if html.blank?

      fragment = Nokogiri::HTML.fragment(html)

      # Convert GIDs to SGIDs
      fragment.css("action-text-attachment[gid]").each do |node|
        gid = GlobalID.parse(node["gid"])
        next unless gid

        type = gid.model_name.plural.underscore.to_sym
        new_id = @id_mapper.lookup(type, gid.model_id)
        record = gid.model_class.find(new_id)

        node["sgid"] = record.attachable_sgid
        node.remove_attribute("gid")
      end

      # Fix links
      fragment.css("a[href]").each do |link|
        link["href"] = rewrite_link(link["href"])
      end

      fragment.to_html
    end

    def rewrite_link(url)
      uri = URI.parse(url) rescue nil
      return url unless uri&.path

      path = uri.path
      old_slug_pattern = %r{^/#{Regexp.escape(@id_mapper.old_account_slug)}/}

      return url unless path.match?(old_slug_pattern)

      # Replace account slug
      path = path.sub(old_slug_pattern, "#{account.slug}/")

      # Try to recognize and remap IDs in the path
      begin
        params = Rails.application.routes.recognize_path(path)

        case params[:controller]
        when "cards"
          if params[:id] && @id_mapper[:cards].key?(params[:id])
            new_id = @id_mapper[:cards][params[:id]]
            path = Rails.application.routes.url_helpers.card_path(new_id)
          end
        when "boards"
          if params[:id] && @id_mapper[:boards].key?(params[:id])
            new_id = @id_mapper[:boards][params[:id]]
            path = Rails.application.routes.url_helpers.board_path(new_id)
          end
        end
      rescue ActionController::RoutingError
        # Unknown route, just update the slug
      end

      uri.path = path
      uri.to_s
    end

    def polymorphic_type_to_mapping(type)
      case type
      when "Card" then :cards
      when "Comment" then :comments
      when "Board" then :boards
      when "User" then :users
      when "Tag" then :tags
      when "Assignment" then :assignments
      when "Tagging" then :taggings
      when "Closure" then :closures
      when "Step" then :steps
      when "Watch" then :watches
      when "Pin" then :pins
      when "Reaction" then :reactions
      when "Mention" then :mentions
      when "Event" then :events
      when "Access" then :accesses
      when "Webhook" then :webhooks
      when "Webhook::Delivery" then :webhook_deliveries
      when "Card::Goldness" then :card_goldnesses
      when "Card::NotNow" then :card_not_nows
      when "Card::ActivitySpike" then :card_activity_spikes
      when "ActiveStorage::Blob" then :active_storage_blobs
      when "ActiveStorage::Attachment" then :active_storage_attachments
      when "ActionText::RichText" then :action_text_rich_texts
      end
    end

    # Data integrity validation

    def validate_export_integrity!(zip)
      exported_ids = collect_exported_ids(zip)

      zip.glob("data/**/*.json").each do |entry|
        next if entry.name == "data/account.json"

        data = JSON.parse(entry.get_input_stream.read)
        validate_account_id(data, entry.name, exported_ids[:account])
        validate_foreign_keys(data, exported_ids, entry.name)
      end
    end

    def collect_exported_ids(zip)
      ids = Hash.new { |h, k| h[k] = Set.new }

      # Account ID
      ids[:account] = @old_account_data["id"]

      # Collect IDs from each entity type
      entity_directories = {
        "data/users" => :users,
        "data/tags" => :tags,
        "data/boards" => :boards,
        "data/columns" => :columns,
        "data/cards" => :cards,
        "data/comments" => :comments,
        "data/steps" => :steps,
        "data/accesses" => :accesses,
        "data/assignments" => :assignments,
        "data/taggings" => :taggings,
        "data/closures" => :closures,
        "data/card_goldnesses" => :card_goldnesses,
        "data/card_not_nows" => :card_not_nows,
        "data/card_activity_spikes" => :card_activity_spikes,
        "data/watches" => :watches,
        "data/pins" => :pins,
        "data/reactions" => :reactions,
        "data/mentions" => :mentions,
        "data/filters" => :filters,
        "data/events" => :events,
        "data/notifications" => :notifications,
        "data/notification_bundles" => :notification_bundles,
        "data/webhooks" => :webhooks,
        "data/webhook_delinquency_trackers" => :webhook_delinquency_trackers,
        "data/webhook_deliveries" => :webhook_deliveries,
        "data/entropies" => :entropies,
        "data/board_publications" => :board_publications,
        "data/active_storage_blobs" => :active_storage_blobs,
        "data/active_storage_attachments" => :active_storage_attachments,
        "data/action_text_rich_texts" => :action_text_rich_texts
      }

      entity_directories.each do |directory, type|
        zip.glob("#{directory}/*.json").each do |entry|
          data = JSON.parse(entry.get_input_stream.read)
          ids[type].add(data["id"])
        end
      end

      ids
    end

    def validate_account_id(data, filename, expected_account_id)
      if data["account_id"] && data["account_id"] != expected_account_id
        raise IntegrityError, "#{filename} references foreign account: #{data["account_id"]}"
      end
    end

    FOREIGN_KEY_VALIDATIONS = {
      "board_id" => :boards,
      "card_id" => :cards,
      "column_id" => :columns,
      "user_id" => :users,
      "creator_id" => :users,
      "assignee_id" => :users,
      "assigner_id" => :users,
      "closer_id" => :users,
      "mentioner_id" => :users,
      "mentionee_id" => :users,
      "reacter_id" => :users,
      "tag_id" => :tags,
      "comment_id" => :comments,
      "webhook_id" => :webhooks,
      "event_id" => :events,
      "blob_id" => :active_storage_blobs,
      "filter_id" => :filters
    }.freeze

    def validate_foreign_keys(data, exported_ids, filename)
      FOREIGN_KEY_VALIDATIONS.each do |field, type|
        ref_id = data[field]
        next unless ref_id

        unless exported_ids[type]&.include?(ref_id)
          raise IntegrityError, "#{filename} references unknown #{type}: #{ref_id}"
        end
      end
    end
end
