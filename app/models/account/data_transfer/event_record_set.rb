class Account::DataTransfer::EventRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    action
    board_id
    created_at
    creator_id
    eventable_id
    eventable_type
    id
    particulars
    updated_at
  ].freeze

  private
    def records
      Event.where(account: account)
    end

    def export_record(event)
      zip.add_file "data/events/#{event.id}.json", event.as_json.to_json
    end

    def files
      zip.glob("data/events/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Event.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Event record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
