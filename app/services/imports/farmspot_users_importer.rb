module Imports
  class FarmspotUsersImporter
    Result = Struct.new(:imported, :updated, :skipped, keyword_init: true)

    def initialize(rows:)
      @rows = rows
    end

    def call
      imported = 0
      updated = 0
      skipped = 0

      rows.each do |row|
        email = row["email"].to_s.strip.downcase
        if email.blank?
          skipped += 1
          next
        end

        user = User.find_or_initialize_by(email:)
        new_record = user.new_record?

        assign_user_attributes(user, row)
        user.save!(validate: false)
        sync_balance!(user, row)
        sync_timestamps!(user, row)

        new_record ? imported += 1 : updated += 1
      end

      Result.new(imported:, updated:, skipped:)
    end

    private

    attr_reader :rows

    def assign_user_attributes(user, row)
      user.role = mapped_role(row)
      user.active = true
      user.external_id = "farmspot:#{row['id']}"
      user.hourly_rate_cents ||= 0
      user.import_metadata = user.import_metadata.merge(
        "source" => "farmspot",
        "source_user_id" => row["id"],
        "source_username" => row["username"],
        "source_roles" => old_roles(row),
        "source_client_balance" => row["client_balance"],
        "source_client_incoming" => row["client_incoming"],
        "source_client_spent" => row["client_spent"],
        "source_created_at" => row["created_at"],
        "source_updated_at" => row["updated_at"]
      )

      imported_password_digest = row["encrypted_password"].to_s
      if imported_password_digest.present?
        user.password_digest = imported_password_digest
      elsif user.new_record?
        generated_password = SecureRandom.base58(16)
        user.password = generated_password
        user.password_confirmation = generated_password
        user.import_metadata["generated_password"] = true
      end
    end

    def sync_balance!(user, row)
      source_balance_cents = ((row["client_balance"].presence || "0").to_d * 100).round.to_i
      delta = source_balance_cents - user.balance_cents
      return if delta.zero?

      user.update_columns(balance_cents: source_balance_cents)
      user.balance_ledger_entries.create!(
        kind: :import_adjustment,
        amount_cents: delta,
        balance_after_cents: source_balance_cents,
        metadata: {
          source: "farmspot",
          source_user_id: row["id"],
          imported_email: user.email
        }
      )
    end

    def sync_timestamps!(user, row)
      user.update_columns(
        created_at: parsed_time(row["created_at"]) || user.created_at,
        updated_at: parsed_time(row["updated_at"]) || user.updated_at
      )
    end

    def parsed_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    end

    def old_roles(row)
      row["role_names"].to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def mapped_role(row)
      roles = old_roles(row)
      if (roles & %w[superadmin admin]).any?
        :admin
      elsif roles.include?("client")
        :client
      else
        :user
      end
    end
  end
end
