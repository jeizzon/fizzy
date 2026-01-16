class Account::DataTransfer::CardActivitySpikeRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    card_id
    created_at
    id
    updated_at
  ].freeze

  private
    def records
      Card::ActivitySpike.where(account: account)
    end

    def export_record(activity_spike)
      zip.add_file "data/card_activity_spikes/#{activity_spike.id}.json", activity_spike.as_json.to_json
    end

    def files
      zip.glob("data/card_activity_spikes/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Card::ActivitySpike.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "CardActivitySpike record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
