require "digest"
require "fileutils"
require "json"
require "open3"
require "time"

# A dirty checkout is a valid candidate, but every production input is pinned.
# This receipt proves local verification/artifact identity, never device acceptance.
class KuroReleaseCandidate
  INPUT_ROOTS = %w[Kuro KuroTests KuroUITests Kuro.xcodeproj Packages Config fastlane scripts supabase/functions supabase/migrations supabase/prepared-migrations supabase/tests docs/plans docs/design docs/contracts tools/design-directions tests].freeze
  INPUT_FILES = %w[Info.plist package.json package-lock.json deno.json deno.jsonc deno.lock Gemfile Gemfile.lock AGENTS.md CLAUDE.md CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md supabase/config.toml archive/SQL_COMPATIBILITY_REPORT.md archive/README.md KNOWLEDGE/INDEX.md docs/documentation-surface-map.md docs/app-store-metadata.md docs/handoffs/2026-10-07-integrated-testflight-execution.md docs/handoffs/2026-10-07-integrated-release-checklist.csv docs/handoffs/2026-10-05-whole-codebase-modularity-contract.md].freeze
  SKIP_VARIABLES = %w[SKIP_IOS_BUILD SKIP_IOS_TEST SKIP_RAILS_AUDIT SKIP_LOCAL_DB KURO_ALLOW_PARTIAL_VERIFY].freeze
  CHECKS = {
    "secrets" => ["scripts/quality-gates/check_secrets.sh", %w[Kuro supabase/functions scripts], %w[bash rg grep]],
    "migrations" => ["scripts/quality-gates/check_migrations.sh", %w[supabase/migrations supabase/prepared-migrations], %w[bash git shasum]],
    "edge-functions" => ["scripts/quality-gates/test_edge_functions.sh", %w[supabase/functions tests/concierge-corpora scripts/quality-gates/router_test_cases.js deno.lock deno.json deno.jsonc], %w[bash deno]],
    "local-db" => ["scripts/db/run_local_db_tests.sh", %w[supabase/migrations supabase/prepared-migrations supabase/tests/lib supabase/tests/fixtures supabase/tests/pending_migrations.txt scripts/db supabase/functions/delete-account], %w[bash psql initdb pg_ctl postgres]],
    "swift-packages" => ["scripts/quality-gates/test_packages.sh", %w[Packages], %w[bash swift]],
    "ios-test" => ["scripts/quality-gates/test_ios_unit.sh", %w[Kuro KuroTests KuroUITests Kuro.xcodeproj Packages Config Info.plist scripts/quality-gates/ios_verify_helpers.sh], %w[bash xcodebuild xcrun python3]],
    "architecture" => ["scripts/quality-gates/check_architecture.sh", %w[Kuro KuroTests Packages], %w[bash rg]],
    "docs" => ["scripts/quality-gates/check_docs_current_state.sh", %w[CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md CLAUDE.md Kuro Packages supabase/migrations archive/SQL_COMPATIBILITY_REPORT.md archive/README.md KNOWLEDGE/INDEX.md docs/documentation-surface-map.md scripts/quality-gates/check_docs_current_state.py], %w[bash python3]],
    "rails" => ["scripts/quality-gates/audit_rails.sh", %w[scripts/audit_curated_rails_quality.js scripts/lib/project_config.js supabase/migrations supabase/prepared-migrations], %w[bash node]]
  }.freeze
  RELEASE_LOCAL_CHECKS = %w[secrets migrations edge-functions swift-packages ios-test local-db architecture docs].freeze
  RELEASE_SQL_SUITES = %w[
    70_import_apply_undo_transactions 80_series_home_foundation
    81_import_session_receipt 81_library_import_counts 92_series_progress_race
    93_series_fence_races 94_series_home_review_repairs 95_feature_flag_overrides
    95_series_producers_disclosure 96_series_account_lifecycle
    96_series_enrichment_backfill_races 51_account_deletion_barrier
    64_club_privacy_aggregates 65_club_membership_lifecycle
    90_deletion_write_barrier 91_club_lifecycle_join_race
  ].freeze
  CRITICAL_EDGE_DIRS = %w[_shared concierge-apply concierge-undo delete-account concierge-import-anilist].freeze
  GENERATED_COMPONENTS = %w[.build .swiftpm node_modules xcuserdata .temp __pycache__].freeze
  REQUIRED_FILES = %w[Kuro.xcodeproj/project.pbxproj Info.plist fastlane/Fastfile scripts/quality-gates/run_all.sh].freeze

  def initialize(root:, path:, git: ENV.fetch("KURO_GIT", "git"))
    @root = File.realpath(root)
    @path = File.expand_path(path)
    @git = git
  end

  def prepare!(build_number:)
    raise "Build number must be a positive integer" unless build_number.to_s.match?(/\A[1-9][0-9]*\z/)
    raise "A candidate receipt already exists; use a new path or resume it" if File.exist?(@path)
    versions = File.read(File.join(@root, "Kuro.xcodeproj/project.pbxproj")).scan(/CURRENT_PROJECT_VERSION = ([^;]+);/).flatten
    raise "Assign build #{build_number} in Xcode before freezing" if versions.empty? || versions.any? { |v| v != build_number.to_s }
    save({ "schema" => 1, "stage" => "prepared", "root" => @root,
           "build_number" => build_number.to_s, "snapshot" => snapshot,
           "prepared_at" => Time.now.utc.iso8601 })
  end

  def exists?
    File.exist?(@path)
  end

  def verify!
    receipt = read_stage!("prepared")
    forbidden = SKIP_VARIABLES.select { |name| ENV[name] && ENV[name] != "0" }
    raise "Release verification forbids partial/skip switches: #{forbidden.join(', ')}" unless forbidden.empty?
    evidence_file = ENV["KURO_LIVE_SERVICE_EVIDENCE"]
    raise "Collect pinned live evidence and set KURO_LIVE_SERVICE_EVIDENCE before verification" unless evidence_file && File.file?(evidence_file)
    pinned_evidence = evidence_snapshot(evidence_file)
    assert_current!(receipt)
    log = "#{@path}.gates.log"
    proofs = run_checks(release_checks, log: log, release: true)
    assert_current!(receipt)
    live_exit = run_command("scripts/quality-gates/check_live_services.sh", "#{log}.live", { "KURO_RELEASE_CANDIDATE_FILE" => @path })
    append_log(log, "live-services", "#{log}.live", live_exit.zero? ? "PASS" : "BLOCKED/FAIL")
    raise "Required live evidence failed or is unavailable (exit #{live_exit})" unless live_exit.zero?
    assert_current!(receipt)
    raise "Live evidence changed during verification; no receipt accepted" unless evidence_snapshot(evidence_file) == pinned_evidence
    File.open(log, "a") { |file| file.puts "Candidate local checks and live evidence PASSED; installed-native TestFlight qualification remains PENDING." }
    receipt.merge!("stage" => "verified", "verified_at" => Time.now.utc.iso8601,
                   "gate_log" => log, "gate_log_sha256" => Digest::SHA256.file(log).hexdigest,
                   "local_check_files" => proofs, "live_evidence_files" => pinned_evidence)
    save(receipt)
  end

  # Development checks never advance a release receipt or require live access.
  def check_development!(checks: %w[architecture])
    raise "Choose at least one development check" if checks.empty?
    raise "Development excludes hosted rails; run that explicitly at qualification" if checks.include?("rails")
    log = File.join(@root, ".codex-artifacts/verification/development-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{Process.pid}.log")
    run_checks(checks, log: log, release: false)
    puts "Development checks PASSED (source/local scope only; TestFlight acceptance is not implied)."
    log
  end

  def require_verified!
    receipt = read_stage!("verified", "archived", "processed")
    assert_current!(receipt)
    log = receipt.fetch("gate_log")
    raise "Verification log is missing or changed" unless File.file?(log) && Digest::SHA256.file(log).hexdigest == receipt.fetch("gate_log_sha256")
    (receipt.fetch("local_check_files") + receipt.fetch("live_evidence_files")).each do |path, digest|
      raise "Accepted live evidence or local proof is missing or changed" unless File.file?(path) && Digest::SHA256.file(path).hexdigest == digest
    end
    receipt
  end

  def record_archive!(ipa:, bundle_id:, build_number:, version:)
    receipt = read_stage!("verified")
    require_verified!
    raise "Wrong archived bundle" unless bundle_id == "com.Kuro.app"
    raise "Archive build differs from verified build" unless build_number.to_s == receipt.fetch("build_number")
    raise "Archive marketing version is missing" if version.to_s.empty?
    artifact = File.realpath(ipa)
    raise "Archive did not produce a nonempty IPA" unless File.file?(artifact) && File.size(artifact) > 0
    receipt.merge!("stage" => "archived", "ipa" => artifact,
                   "ipa_sha256" => Digest::SHA256.file(artifact).hexdigest,
                   "bundle_id" => bundle_id, "version" => version,
                   "archived_at" => Time.now.utc.iso8601)
    save(receipt)
  end

  def require_archive!
    receipt = read_stage!("archived", "processed")
    require_verified!
    ipa = receipt.fetch("ipa")
    raise "IPA is missing or changed; refuse upload" unless File.file?(ipa) && Digest::SHA256.file(ipa).hexdigest == receipt.fetch("ipa_sha256")
    receipt
  end

  def record_processed!
    receipt = require_archive!
    receipt.merge!("stage" => "processed", "processed_at" => Time.now.utc.iso8601,
                   "installed_native_qualification" => "PENDING")
    save(receipt)
  end

  def read
    raise "No frozen release candidate; development checks do not create one" unless File.file?(@path)
    receipt = JSON.parse(File.read(@path))
    raise "Unsupported or foreign candidate receipt" unless receipt["schema"] == 1 && receipt["root"] == @root
    receipt
  end

  def snapshot
    head = git_output("rev-parse", "HEAD").strip
    branch = git_output("rev-parse", "--abbrev-ref", "HEAD").strip
    paths = git_output("ls-files", "--cached", "--others", "--exclude-standard", "-z").split("\0").uniq.select { |p| input?(p) }.sort
    missing = REQUIRED_FILES.reject { |p| paths.include?(p) && File.file?(File.join(@root, p)) }
    raise "Missing candidate inputs: #{missing.join(', ')}" unless missing.empty?
    files = paths.map do |relative|
      path = File.join(@root, relative)
      if File.symlink?(path)
        raise "Candidate input symlinks are unsupported: #{relative}"
      elsif File.file?(path)
        [relative, File.stat(path).mode & 0777, Digest::SHA256.file(path).hexdigest]
      elsif File.exist?(path)
        raise "Unsupported input (including unpinned submodule): #{relative}"
      else
        [relative, "deleted"]
      end
    end
    { "head" => head, "branch" => branch, "files" => files,
      "sha256" => Digest::SHA256.hexdigest(JSON.generate([head, branch, files])) }
  end

  private

  def evidence_snapshot(path)
    evidence_path = File.realpath(path)
    evidence = JSON.parse(File.read(evidence_path))
    references = [evidence.fetch("deployment"), *evidence.fetch("reports").values]
    files = [evidence_path, *references.map { |ref| File.expand_path(ref.fetch("path"), File.dirname(evidence_path)) }].uniq
    files.map { |file| [file, Digest::SHA256.file(file).hexdigest] }
  end

  def input?(relative)
    return false if relative.split("/").any? { |part| GENERATED_COMPONENTS.include?(part) }
    return false if relative.match?(/(?:\.log|\.xcresult|\.xcuserstate|\.pyc)\z/)
    return false if relative.start_with?("fastlane/screenshots/", "fastlane/test_output/")
    return false if %w[fastlane/report.xml fastlane/Preview.html fastlane/README.md].include?(relative)
    INPUT_FILES.include?(relative) || INPUT_ROOTS.any? { |prefix| relative.start_with?("#{prefix}/") }
  end

  def git_output(*args)
    output, error, status = Open3.capture3(@git, "-C", @root, *args)
    raise "Git inspection failed: #{error.strip}" unless status.success?
    output
  end

  def assert_current!(receipt)
    raise "Candidate inputs changed; prepare and verify a new candidate" unless snapshot == receipt.fetch("snapshot")
  end

  def read_stage!(*stages)
    receipt = read
    raise "Expected #{stages.join('/')} candidate; got #{receipt['stage']}" unless stages.include?(receipt["stage"])
    receipt
  end

  def release_checks
    checks = RELEASE_LOCAL_CHECKS.dup
    # The dedicated corpus/router wrappers duplicate tests already selected by
    # the affected production edge directories. Rails require an actual input delta.
    changed = changed_paths
    rails_changed = changed.any? { |path| path == "scripts/audit_curated_rails_quality.js" || path == "scripts/quality-gates/audit_rails.sh" ||
      (path.end_with?(".sql") && File.file?(File.join(@root, path)) && File.read(File.join(@root, path)).match?(/curated_rails|curated_rail_items|curated_rail_cards/)) }
    checks << "rails" if rails_changed
    checks
  end

  def changed_paths
    (git_output("diff", "--name-only", "HEAD", "-z").split("\0") +
     git_output("ls-files", "--others", "--exclude-standard", "-z").split("\0")).uniq
  end

  def edge_selection
    root = File.join(@root, "supabase/functions")
    directories = Dir.children(root).select { |name| File.directory?(File.join(root, name)) }
    changed = changed_paths
    missing = CRITICAL_EDGE_DIRS - directories
    raise "Missing critical backend directories: #{missing.join(', ')}" unless missing.empty?
    selected = CRITICAL_EDGE_DIRS.dup
    selected += %w[concierge-parse concierge-recommend] if changed.any? { |path| path.start_with?("tests/concierge-corpora/") || path == "scripts/quality-gates/router_test_cases.js" }
    directories.each do |name|
      dependencies = backend_dependencies(name)
      selected << name if changed.any? { |path| path.start_with?("supabase/functions/#{name}/") || dependencies.include?(path) }
    end
    selected.sort.uniq
  end

  def backend_dependencies(name)
    pending = Dir.glob(File.join(@root, "supabase/functions", name, "**/*.{ts,json}"))
    found = []
    until pending.empty?
      file = pending.pop
      next if found.include?(file)
      found << file
      next unless File.file?(file)
      File.read(file).scan(/(?:from\s*|import\s*\(\s*|import\s*)["'](\.[^"']+)["']/).flatten.each do |specifier|
        pending << File.expand_path(specifier, File.dirname(file))
      end
    end
    found.map { |path| path.delete_prefix(@root + "/") }
  end

  def required_sql_files
    files = Dir.glob(File.join(@root, "supabase/tests/{rls,concurrency}/*.sql"))
    RELEASE_SQL_SUITES.map do |suite|
      matching = files.select { |path| File.basename(path).include?(suite + ".sql") }
      raise "Required SQL suite missing or ambiguous: #{suite}" unless matching.size == 1 && File.basename(matching.first) == suite + ".sql"
      matching.first.delete_prefix(@root + "/")
    end
  end

  def validate_sql_output(output)
    rows = output.scan(/^PASS\s+(\S+\.sql)\s+(\d+) assertions, (\d+) blocked markers, (\d+) findings(.*)$/)
    RELEASE_SQL_SUITES.each do |suite|
      matching = rows.select { |row| row[0] == suite + ".sql" }
      raise "Required SQL suite did not execute cleanly: #{suite}" unless matching.size == 1 && matching[0][1].to_i > 0 &&
        matching[0][2].to_i.zero? && matching[0][3].to_i.zero? && !matching[0][4].include?("BLOCKED")
    end
  end

  def check_identity(name, env)
    script, scopes, tools = CHECKS.fetch(name)
    scopes = edge_selection.flat_map { |directory| backend_dependencies(directory) } + %w[tests/concierge-corpora scripts/quality-gates/router_test_cases.js deno.json deno.jsonc] if name == "edge-functions"
    scopes = scopes + required_sql_files if name == "local-db"
    scopes = scopes + [script, "fastlane/release_candidate.rb", "Gemfile.lock", "package-lock.json", "deno.lock"]
    files = snapshot.fetch("files").select { |row| scopes.any? { |scope| row[0] == scope || row[0].start_with?(scope + "/") } }
    pg_bin = nil
    if name == "local-db"
      pg_bin = [ENV["KURO_PG_BIN"], "/opt/homebrew/opt/postgresql@17/bin", "/usr/local/opt/postgresql@17/bin", "/usr/lib/postgresql/17/bin"].compact.find do |directory|
        %w[initdb pg_ctl psql].all? { |tool| File.executable?(File.join(directory, tool)) }
      end
    end
    tool_ids = tools.map do |tool|
      path = if name == "local-db" && %w[psql initdb pg_ctl postgres].include?(tool)
        pg_bin && File.join(pg_bin, tool)
      else
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }.find { |file| File.executable?(file) && File.file?(file) }
      end
      next [tool, "unavailable"] unless path && File.file?(path)
      real = File.realpath(path); stat = File.stat(real)
      [tool, real, tool_digest(real, stat)]
    end
    if tools.any? { |tool| %w[swift xcodebuild xcrun].include?(tool) }
      directory = ENV["DEVELOPER_DIR"]
      unless directory
        output, _, status = Open3.capture3("xcode-select", "-p")
        directory = output.strip if status.success?
      end
      if directory
        %w[../version.plist Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc].each do |relative|
          file = File.expand_path(relative, directory)
          tool_ids << [file, tool_digest(file, File.stat(file))] if File.file?(file)
        end
      end
    end
    configuration = %w[DEVELOPER_DIR SDKROOT TOOLCHAINS MIGRATIONS_ALLOW_UNTRACKED KURO_PG_BIN KURO_ALLOW_PG_MAJOR KURO_DB_PORT].to_h { |key| [key, ENV[key]] }
    configuration["sql_selection"] = RELEASE_SQL_SUITES.map { |suite| suite + ".sql" } if name == "local-db"
    configuration["migration_git_status"] = git_output("status", "--porcelain", "--", "supabase/migrations") if name == "migrations"
    Digest::SHA256.hexdigest(JSON.generate([name, files, tool_ids, configuration, env]))
  end

  def tool_digest(path, stat)
    @tool_digests ||= {}
    key = [path, stat.size, stat.mtime.to_f, stat.ctime.to_f]
    @tool_digests[key] ||= Digest::SHA256.file(path).hexdigest
  end

  def run_checks(checks, log:, release:)
    unknown = checks - CHECKS.keys
    raise "Unknown checks: #{unknown.join(', ')}" unless unknown.empty?
    FileUtils.mkdir_p(File.dirname(log)); File.write(log, "#{release ? 'Candidate' : 'Development'} checks; local/source proof only.\n")
    proofs = []
    checks.uniq.each do |name|
      script = CHECKS.fetch(name)[0]
      env = name == "edge-functions" ? { "KURO_EDGE_TEST_DIRS" => edge_selection.join(",") } : {}
      arguments = []
      if name == "local-db"
        required_sql_files # Missing/ambiguous required cases never become partial acceptance.
        env["KURO_RELEASE_SQL_SELECTION"] = RELEASE_SQL_SUITES.map { |suite| suite + ".sql" }.join(",")
        arguments = ["--only", env.fetch("KURO_RELEASE_SQL_SELECTION")]
      end
      identity = check_identity(name, env)
      # Unlocked mutable remote Deno imports are not reusable dependency proof.
      # A live rails dataset is also nonpinnable. Keep each execution immutable.
      reusable = !%w[rails edge-functions].include?(name)
      suffix = reusable ? "" : "-#{Time.now.utc.strftime('%Y%m%dT%H%M%S%N')}-#{Process.pid}"
      cache_path = File.join(@root, ".codex-artifacts/verification", "#{name}-#{identity}#{suffix}.json")
      cached = File.file?(cache_path) ? JSON.parse(File.read(cache_path)) : nil
      if reusable && cached && cached["identity"] == identity && cached["status"] == "PASS" &&
          File.file?(cached["log"]) && Digest::SHA256.file(cached["log"]).hexdigest == cached["log_sha256"]
        check_log = cached["log"]
        append_log(log, name, check_log, "REUSED unchanged source/test/tool dependencies")
      else
        check_log = "#{cache_path}.log"
        code = run_command(script, check_log, env, arguments)
        append_log(log, name, check_log, code.zero? ? "PASS" : "BLOCKED/FAIL")
        raise "#{name} check failed or is unavailable (exit #{code}); inspect #{check_log}" unless code.zero?
        output = File.read(check_log)
        validate_sql_output(output) if name == "local-db"
        raise "Partial verification cannot qualify #{name}" if output.match?(/Not a complete verification|Developer partial mode:|QUALITY GATES FAILED|^--- \[.*\] (SKIPPED|BLOCKED)/)
        raise "Check inputs changed during #{name}" unless identity == check_identity(name, env)
        File.write(cache_path, JSON.pretty_generate({ "identity" => identity, "status" => "PASS", "log" => check_log,
          "log_sha256" => Digest::SHA256.file(check_log).hexdigest, "checked_at" => Time.now.utc.iso8601 }) + "\n")
      end
      proofs << [check_log, Digest::SHA256.file(check_log).hexdigest]
      proofs << [cache_path, Digest::SHA256.file(cache_path).hexdigest]
    end
    proofs
  end

  def append_log(log, name, check_log, status)
    File.open(log, "a") { |file| file.puts "--- #{name}: #{status}"; file.write(File.read(check_log)) }
  end

  def run_command(script, log, extra_env = {}, arguments = [])
    env = SKIP_VARIABLES.to_h { |name| [name, "0"] }.merge(extra_env)
    FileUtils.mkdir_p(File.dirname(log))
    File.open(log, "w") do |file|
      file.puts "Command: bash #{script} #{arguments.join(' ')}"
      Open3.popen2e(env, "bash", File.join(@root, script), *arguments, chdir: @root) do |stdin, stream, wait|
        stdin.close
        stream.each_line { |line| file.write(line); $stdout.write(line) }
        wait.value.exitstatus
      end
    end
  end

  def save(receipt)
    FileUtils.mkdir_p(File.dirname(@path))
    temporary = "#{@path}.tmp-#{Process.pid}"
    File.write(temporary, JSON.pretty_generate(receipt) + "\n")
    File.rename(temporary, @path)
    receipt
  end
end
