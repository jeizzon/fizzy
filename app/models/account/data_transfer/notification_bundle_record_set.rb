class Account::DataTransfer::NotificationBundleRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    created_at
    ends_at
    id
    starts_at
    status
    updated_at
    user_id
  ].freeze

  private
    def records
      Notification::Bundle.where(account: account)
    end

    def export_record(bundle)
      zip.add_file "data/notification_bundles/#{bundle.id}.json", bundle.as_json.to_json
    end

    def files
      zip.glob("data/notification_bundles/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Notification::Bundle.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "NotificationBundle record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
