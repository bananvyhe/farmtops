namespace :users do
  desc "Import users from CSV. Usage: rake users:import CSV=path/to/file.csv"
  task import: :environment do
    require "csv"

    csv_path = ENV["CSV"]
    raise "Specify CSV=path/to/file.csv" if csv_path.blank?

    CSV.foreach(csv_path, headers: true) do |row|
      email = row.fetch("email").to_s.strip.downcase
      raise "email is required" if email.blank?

      user = User.find_or_initialize_by(email:)
      was_new = user.new_record?
      user.password = row["password"].presence || SecureRandom.base58(16) if was_new || row["password"].present?
      user.role = row["role"].presence || user.role || :client
      user.hourly_rate_cents = row["hourly_rate_cents"].presence&.to_i || user.hourly_rate_cents || 0
      user.active = row["active"].blank? ? true : ActiveModel::Type::Boolean.new.cast(row["active"])
      user.external_id = row["external_id"].presence || user.external_id
      user.import_metadata = user.import_metadata.merge("source" => row["source"].presence || "csv")
      user.save!

      next if row["balance_cents"].blank?

      delta = row["balance_cents"].to_i - user.balance_cents
      next if delta.zero?

      Users::BalanceManager.apply_delta!(
        user:,
        amount_cents: delta,
        kind: :import_adjustment,
        metadata: { source: "csv", imported_email: email }
      )
    end

    puts "Import completed"
  end

  desc "Import users from old Farmspot PostgreSQL. Usage: rake users:import_farmspot OLD_DATABASE_URL=postgres://..."
  task import_farmspot: :environment do
    require "pg"

    old_database_url = ENV["OLD_DATABASE_URL"]
    raise "Specify OLD_DATABASE_URL=postgres://user:pass@host:5432/dbname" if old_database_url.blank?

    sql = <<~SQL
      SELECT
        users.id,
        users.email,
        users.encrypted_password,
        users.username,
        users.created_at,
        users.updated_at,
        clients.ballance AS client_balance,
        clients.incoming AS client_incoming,
        clients.spent AS client_spent,
        STRING_AGG(DISTINCT roles.name, ',') AS role_names
      FROM users
      LEFT JOIN clients ON clients.user_id = users.id
      LEFT JOIN users_roles ON users_roles.user_id = users.id
      LEFT JOIN roles ON roles.id = users_roles.role_id
      GROUP BY
        users.id,
        users.email,
        users.encrypted_password,
        users.username,
        users.created_at,
        users.updated_at,
        clients.ballance,
        clients.incoming,
        clients.spent
      ORDER BY users.id ASC
    SQL

    conn = PG.connect(old_database_url)
    result = Imports::FarmspotUsersImporter.new(rows: conn.exec(sql)).call
    puts "Farmspot import completed: imported=#{result.imported}, updated=#{result.updated}, skipped=#{result.skipped}"
  ensure
    conn&.close
  end
end
