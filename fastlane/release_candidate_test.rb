require "minitest/autorun"
require "tmpdir"
require_relative "release_candidate"

class KuroReleaseCandidateTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("kuro-release-")
    @git = ENV.fetch("KURO_GIT", "git")
    write("Kuro.xcodeproj/project.pbxproj", "CURRENT_PROJECT_VERSION = 18;\n")
    write("Info.plist", "source")
    write("fastlane/Fastfile", "source")
    write("Kuro/App.swift", "source")
    KuroReleaseCandidate::CRITICAL_EDGE_DIRS.each { |name| write("supabase/functions/#{name}/run_test.ts", "export const fixture = true;") }
    KuroReleaseCandidate::RELEASE_SQL_SUITES.each { |suite| write("supabase/tests/rls/#{suite}.sql", "select 1;") }
    write_gate("echo 'Local check PASSED.'")
    git("init", "-q")
    git("add", ".")
    git("-c", "user.name=Pipeline Test", "-c", "user.email=pipeline@example.invalid", "commit", "-qm", "fixture")
    @receipt = File.join(@root, "reports/candidate.json")
    @candidate = KuroReleaseCandidate.new(root: @root, path: @receipt, git: @git)
    @saved_env = (KuroReleaseCandidate::SKIP_VARIABLES + ["KURO_LIVE_SERVICE_EVIDENCE"]).to_h { |key| [key, ENV[key]] }
    KuroReleaseCandidate::SKIP_VARIABLES.each { |key| ENV.delete(key) }
    write("reports/live-deployment.json", "{}")
    ENV["KURO_LIVE_SERVICE_EVIDENCE"] = write("reports/live.json", JSON.generate({ deployment: { path: "live-deployment.json" }, reports: {} }))
  end

  def teardown
    @saved_env.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    FileUtils.remove_entry(@root)
  end

  def test_untracked_required_dependency_changes_identity_but_reports_do_not
    before = @candidate.snapshot
    write("reports/worker.log", "moving operations")
    assert_equal before, @candidate.snapshot
    write("Packages/KuroModules/Sources/New.swift", "required untracked code")
    refute_equal before, @candidate.snapshot
  end

  def test_partial_switch_and_partial_output_fail_even_with_zero_exit
    prepare
    ENV["KURO_ALLOW_PARTIAL_VERIFY"] = "1"
    assert_match(/partial\/skip/, assert_raises(RuntimeError) { @candidate.verify! }.message)
    ENV.delete("KURO_ALLOW_PARTIAL_VERIFY")
    write_gate("echo 'Developer partial mode: PARTIAL result, not release qualification.'\necho 'All quality gates PASSED.'")
    # The changed gate needs its own fresh receipt, then still cannot qualify.
    File.delete(@receipt)
    prepare
    assert_match(/Partial verification/, assert_raises(RuntimeError) { @candidate.verify! }.message)
  end

  def test_blocked_gate_cannot_advance_stage
    write_gate("echo BLOCKED\nexit 4")
    prepare
    assert_match(/exit 4/, assert_raises(RuntimeError) { @candidate.verify! }.message)
    assert_equal "prepared", @candidate.read.fetch("stage")
    assert_raises(RuntimeError) { @candidate.require_verified! }
  end

  def test_mutation_during_verification_invalidates_candidate
    write_gate("echo changed >> Kuro/App.swift\necho 'All quality gates PASSED.'")
    prepare
    assert_match(/inputs changed/, assert_raises(RuntimeError) { @candidate.verify! }.message)
    assert_equal "prepared", @candidate.read.fetch("stage")
  end

  def test_replacing_evidence_during_gates_cannot_advance_receipt
    write_gate("echo replaced > reports/live-deployment.json\necho 'All quality gates PASSED.'")
    prepare
    assert_match(/evidence changed during verification/, assert_raises(RuntimeError) { @candidate.verify! }.message)
    assert_equal "prepared", @candidate.read.fetch("stage")
  end

  def test_exact_artifact_flow_does_not_rerun_gates_and_keeps_installation_pending
    write_gate("echo ran >> reports/counter\necho 'All quality gates PASSED.'")
    prepare
    @candidate.verify!
    @candidate.require_verified!
    ipa = write("reports/Kuro.ipa", "verified artifact")
    @candidate.record_archive!(ipa: ipa, bundle_id: "com.Kuro.app", build_number: "18", version: "1.0")
    @candidate.require_archive!
    @candidate.record_processed!
    assert_equal @candidate.send(:release_checks).size + 1, File.readlines(File.join(@root, "reports/counter")).size
    assert_equal "PENDING", @candidate.read.fetch("installed_native_qualification")
    File.write(ipa, "replaced artifact")
    assert_match(/IPA is missing or changed/, assert_raises(RuntimeError) { @candidate.require_archive! }.message)
  end

  def test_modified_source_and_modified_verification_log_reject_archive
    prepare
    @candidate.verify!
    original = File.read(File.join(@root, "Kuro/App.swift"))
    write("Kuro/App.swift", "changed")
    assert_match(/inputs changed/, assert_raises(RuntimeError) { @candidate.require_verified! }.message)
    write("Kuro/App.swift", original)
    File.write("#{@receipt}.gates.log", "forged success")
    assert_match(/log is missing or changed/, assert_raises(RuntimeError) { @candidate.require_verified! }.message)
  end

  def test_wrong_build_and_bundle_are_rejected
    assert_raises(RuntimeError) { @candidate.prepare!(build_number: 19) }
    prepare
    @candidate.verify!
    ipa = write("reports/Kuro.ipa", "artifact")
    assert_raises(RuntimeError) { @candidate.record_archive!(ipa: ipa, bundle_id: "com.Kuro.other", build_number: 18, version: "1.0") }
    assert_raises(RuntimeError) { @candidate.record_archive!(ipa: ipa, bundle_id: "com.Kuro.app", build_number: 19, version: "1.0") }
  end

  def test_changed_real_evidence_cannot_be_reused_for_archive
    prepare
    @candidate.verify!
    write("reports/live-deployment.json", "changed evidence")
    assert_match(/live evidence or local proof is missing or changed/, assert_raises(RuntimeError) { @candidate.require_verified! }.message)
  end

  def test_development_has_no_release_access_requirement_and_reuses_unchanged_proof
    ENV.delete("KURO_LIVE_SERVICE_EVIDENCE")
    write_gate("echo ran >> reports/counter\necho 'Local check PASSED.'")
    @candidate.check_development!(checks: ["architecture"])
    write("docs/unrelated.md", "A documentation edit cannot invalidate architecture execution.")
    @candidate.check_development!(checks: ["architecture"])
    assert_equal 1, File.readlines(File.join(@root, "reports/counter")).size
    refute File.exist?(@receipt)
    assert_raises(RuntimeError) { @candidate.require_verified! }
    write("Kuro/App.swift", "changed authority")
    @candidate.check_development!(checks: ["architecture"])
    assert_equal 2, File.readlines(File.join(@root, "reports/counter")).size
  end

  def test_edge_selection_has_critical_checks_and_actual_shared_dependency_fanout
    write("supabase/functions/concierge-recommend/index.ts", "import '../_shared/policy.ts';")
    write("supabase/functions/_shared/policy.ts", "export const value = 1;")
    git("add", ".")
    git("-c", "user.name=Pipeline Test", "-c", "user.email=pipeline@example.invalid", "commit", "-qm", "dependency baseline")
    refute_includes @candidate.send(:edge_selection), "concierge-recommend"
    write("supabase/functions/_shared/policy.ts", "export const value = 2;")
    assert_includes @candidate.send(:edge_selection), "concierge-recommend"
    assert_empty KuroReleaseCandidate::CRITICAL_EDGE_DIRS - @candidate.send(:edge_selection)
    refute_includes @candidate.send(:release_checks), "rails"
  end

  def test_actual_edge_selector_refuses_empty_invalid_and_zero_test_success
    actual = File.read(File.join(__dir__, "../scripts/quality-gates/test_edge_functions.sh"))
    script = write("scripts/quality-gates/test_edge_functions.sh", actual)
    deno = write("tools/deno", "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> deno-commands\necho \"ok | ${FAKE_PASSED:-2} passed | 0 failed\"\n")
    File.chmod(0755, deno)
    environment = { "PATH" => File.dirname(deno) + File::PATH_SEPARATOR + ENV.fetch("PATH"), "KURO_EDGE_TEST_DIRS" => "concierge-apply" }
    _, error, status = Open3.capture3(environment, "bash", script, chdir: @root)
    assert status.success?, error
    commands = File.read(File.join(@root, "supabase/functions/deno-commands"))
    assert_equal "test --no-prompt concierge-apply", commands.strip
    ["", "../concierge-apply", "unknown", "concierge-apply,,delete-account"].each do |selection|
      _, _, status = Open3.capture3(environment.merge("KURO_EDGE_TEST_DIRS" => selection), "bash", script, chdir: @root)
      refute status.success?
    end
    _, _, status = Open3.capture3(environment.merge("FAKE_PASSED" => "0"), "bash", script, chdir: @root)
    refute status.success?
  end

  def test_actual_pg_resolver_and_semantic_configuration_change_scope_identity
    saved = %w[KURO_PG_BIN KURO_ALLOW_PG_MAJOR].to_h { |key| [key, ENV[key]] }
    begin
      %w[first second].each do |directory|
        %w[initdb pg_ctl psql postgres].each do |tool|
          file = write("tools/#{directory}/#{tool}", "#!/bin/sh\nexit 0\n")
          File.chmod(0755, file)
        end
      end
      ENV["KURO_PG_BIN"] = File.join(@root, "tools/first")
      first = @candidate.send(:check_identity, "local-db", {})
      ENV["KURO_PG_BIN"] = File.join(@root, "tools/second")
      refute_equal first, @candidate.send(:check_identity, "local-db", {})
      second = @candidate.send(:check_identity, "local-db", {})
      write("tools/second/pg_ctl", "#!/bin/sh\nexit 3\n")
      refute_equal second, @candidate.send(:check_identity, "local-db", {})
      changed = @candidate.send(:check_identity, "local-db", {})
      ENV["KURO_ALLOW_PG_MAJOR"] = "1"
      refute_equal changed, @candidate.send(:check_identity, "local-db", {})
    ensure
      saved.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    end
  end

  def test_unlocked_edge_checks_run_again_without_overwriting_previous_proof
    script = KuroReleaseCandidate::CHECKS.fetch("edge-functions")[0]
    write(script, "#!/bin/bash\necho ran >> reports/edge-counter\necho 'Local check PASSED.'\n")
    prepare
    @candidate.verify!
    second = KuroReleaseCandidate.new(root: @root, path: File.join(@root, "reports/second.json"), git: @git)
    second.prepare!(build_number: 18)
    second.verify!
    @candidate.require_verified!
    assert_equal 2, File.readlines(File.join(@root, "reports/edge-counter")).size
  end

  def test_final_sql_selector_is_explicit_pinned_and_follows_native_verification
    script = KuroReleaseCandidate::CHECKS.fetch("local-db")[0]
    write(script, "#!/bin/bash\nprintf '%s\\n' \"$*\" > reports/sql-arguments\nprintf '%s\\n' \"$KURO_RELEASE_SQL_SELECTION\" > reports/sql-environment\necho 'Local check PASSED.'\n" + sql_pass_output)
    prepare
    @candidate.verify!
    selector = KuroReleaseCandidate::RELEASE_SQL_SUITES.map { |suite| suite + ".sql" }.join(",")
    assert_equal "--only " + selector, File.read(File.join(@root, "reports/sql-arguments")).strip
    assert_equal selector, File.read(File.join(@root, "reports/sql-environment")).strip
    checks = @candidate.send(:release_checks)
    assert_operator checks.index("ios-test"), :<, checks.index("local-db")
    output = KuroReleaseCandidate::RELEASE_SQL_SUITES.map { |suite| "PASS  #{suite}.sql 1 assertions, 0 blocked markers, 0 findings\n" }.join
    @candidate.send(:validate_sql_output, output)
    assert_raises(RuntimeError) { @candidate.send(:validate_sql_output, output.lines.drop(1).join) }
    assert_raises(RuntimeError) { @candidate.send(:validate_sql_output, output.sub("1 assertions", "0 assertions")) }
    before = @candidate.send(:check_identity, "local-db", {})
    write("supabase/tests/rls/unrelated_historical.sql", "select 'diagnostic';")
    assert_equal before, @candidate.send(:check_identity, "local-db", {})
    File.delete(File.join(@root, "supabase/tests/rls/51_account_deletion_barrier.sql"))
    assert_match(/Required SQL suite missing/, assert_raises(RuntimeError) { @candidate.send(:check_identity, "local-db", {}) }.message)
  end

  def test_symlink_input_cannot_hide_unpinned_source
    File.symlink(File.join(@root, "Info.plist"), File.join(@root, "Kuro/Hidden.swift"))
    assert_match(/symlinks are unsupported/, assert_raises(RuntimeError) { @candidate.snapshot }.message)
  end

  private

  def prepare
    @candidate.prepare!(build_number: 18)
  end

  def write_gate(body)
    write("scripts/quality-gates/run_all.sh", "#!/usr/bin/env bash\n#{body}\n")
    (KuroReleaseCandidate::CHECKS.values.map(&:first) + ["scripts/quality-gates/check_live_services.sh"]).each do |script|
      extra = script == KuroReleaseCandidate::CHECKS.fetch("local-db")[0] ? sql_pass_output : ""
      write(script, "#!/usr/bin/env bash\n#{body}\n#{extra}")
    end
  end

  def sql_pass_output
    KuroReleaseCandidate::RELEASE_SQL_SUITES.map { |suite| "echo 'PASS  #{suite}.sql 1 assertions, 0 blocked markers, 0 findings'\n" }.join
  end

  def write(relative, content)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def git(*args)
    _, error, status = Open3.capture3(@git, "-C", @root, *args)
    raise error unless status.success?
  end
end
