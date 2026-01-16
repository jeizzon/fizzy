class Account::DataTransfer::NotificationRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    created_at
    creator_id
    id
    read_at
    source_id
    source_type
    updated_at
    user_id
  ].freeze

  private
    def records
      Notification.where(account: account)
    end

    def export_record(notification)
      zip.add_file "data/notifications/#{notification.id}.json", notification.as_json.to_json
    end

    def files
      zip.glob("data/notifications/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Notification.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Notification record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
