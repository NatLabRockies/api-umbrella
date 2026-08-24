# vi: set ft=ruby :

require "erb"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "rainbow"
require "shellwords"
require "uri"

class Outdated < Thor
  REPOS = {
    "caddy" => {
      :git => "https://github.com/caddyserver/caddy.git",
      :github_release => "caddyserver/caddy",
    },
    "cue" => {
      :git => "https://github.com/cue-lang/cue.git",
      :github_release => "cue-lang/cue",
    },
    "envoy" => {
      :git => "https://github.com/envoyproxy/envoy.git",
      :github_release => "envoyproxy/envoy",
      :filename_matcher => /envoy-\d/,
    },
    "envoy_control_plane" => {
      :git => "https://github.com/GUI/envoy-control-plane.git",
      :github_release => "GUI/envoy-control-plane",
    },
    "fluent_bit" => {
      :git => "https://github.com/fluent/fluent-bit.git",
      :download => "https://github.com/fluent/fluent-bit/archive/refs/tags/v<%= version.fetch(:wanted_version) %>.tar.gz",
    },
    "glauth" => {
      :git => "https://github.com/glauth/glauth.git",
      :github_release => "glauth/glauth",
    },
    "hugo" => {
      :git => "https://github.com/gohugoio/hugo.git",
      :github_release => "gohugoio/hugo",
      :filename_matcher => /hugo_extended_\d.*\.tar\.gz/,
    },
    "lrexlib_pcre2" => {
      :luarock => "lrexlib-pcre2",
    },
    "lua_icu_date_ffi" => {
      :git => "https://github.com/GUI/lua-icu-date-ffi.git",
      :git_ref => "master",
    },
    "lua_resty_logger_socket" => {
      :git => "https://github.com/cloudflare/lua-resty-logger-socket.git",
      :git_ref => "master",
    },
    "lua_resty_openssl_aux_module" => {
      :git => "https://github.com/fffonion/lua-resty-openssl-aux-module.git",
    },
    "luarocks" => {
      :git => "https://github.com/keplerproject/luarocks.git",
      :download => "https://luarocks.github.io/luarocks/releases/luarocks-<%= version.fetch(:wanted_version) %>.tar.gz",
    },
    "mailpit" => {
      :git => "https://github.com/axllent/mailpit.git",
      :github_release => "axllent/mailpit",
    },
    "ngx_http_geoip2_module" => {
      :git => "https://github.com/leev/ngx_http_geoip2_module.git",
    },
    "nodejs" => {
      :git => "https://github.com/nodejs/node.git",
      :constraint => "~> 22.11",
      :checksums_download => "https://nodejs.org/download/release/v<%= version.fetch(:wanted_version) %>/SHASUMS256.txt",
      :filename_matcher => /node.*\.tar\.xz/,
    },
    "openresty" => {
      :git => "https://github.com/openresty/openresty.git",
      :download => "https://openresty.org/download/openresty-<%= version.fetch(:wanted_version) %>.tar.gz",
    },
    "perp" => {
      :http => "http://b0llix.net/perp/site.cgi?page=download",
    },
    "pnpm" => {
      :git => "https://github.com/pnpm/pnpm.git",
    },
    "shellcheck" => {
      :git => "https://github.com/koalaman/shellcheck.git",
      :github_release => "koalaman/shellcheck",
    },
    "task" => {
      :git => "https://github.com/go-task/task.git",
      :github_release => "go-task/task",
      :filename_matcher => /task.*\.tar\.gz/,
    },
    "trafficserver" => {
      :http => "https://archive.apache.org/dist/trafficserver/",
      :checksums_download => "https://archive.apache.org/dist/trafficserver/trafficserver-<%= version.fetch(:wanted_version) %>.tar.bz2.sha512",
      :filename_matcher => /trafficserver.*\.tar\.bz2/,
    },
  }.freeze

  class AdminUi < Thor
    namespace "outdated:admin-ui"

    desc "npm", "List outdated admin-ui NPM dependencies"
    def npm
      Dir.chdir(File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "src/api-umbrella/admin-ui")) do
        system("pnpm", "outdated", exception: false)
      end
    end
  end

  class Test < Thor
    desc "gems", "List outdated test gem dependencies"
    def gems
      env = {
        "BUNDLE_GEMFILE" => File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "Gemfile"),
        "BUNDLE_APP_CONFIG" => File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "tasks/app-deps/web-app/bundle/_persist/.bundle"),
      }

      system(env, "bundle", "outdated", exception: false)
    end

    desc "luarocks", "List outdated test LuaRocks dependencies"
    def luarocks
      Outdated.outdated_luarocks(
        rockspec_path: File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "test/api-umbrella-test-git-1.rockspec"),
        lock_path: File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "test/luarocks.lock"),
      )
    end
  end

  class WebApp < Thor
    namespace "outdated:web-app"

    desc "npm", "List outdated web-app NPM dependencies"
    def npm
      Dir.chdir(File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "src/api-umbrella/web-app")) do
        system("pnpm", "outdated", exception: false)
      end
    end
  end

  class ExampleWebsite < Thor
    namespace "outdated:example-website"

    desc "npm", "List outdated example-website NPM dependencies"
    def npm
      Dir.chdir(File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "src/api-umbrella/example-website")) do
        system("pnpm", "outdated", exception: false)
      end
    end
  end

  desc "luarocks", "List outdated LuaRocks dependencies"
  def luarocks
    Outdated.outdated_luarocks(
      rockspec_path: File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "src/api-umbrella-git-1.rockspec"),
      lock_path: File.join(ENV.fetch("API_UMBRELLA_SRC_ROOT"), "src/luarocks.lock"),
    )
  end

  desc "packages", "List outdated package dependencies"
  def packages
    versions = find_package_versions
    Outdated.print_versions(versions: versions)
  end

  desc "update-packages", "List outdated package dependencies"
  def update_packages
    versions = find_package_versions
    versions.each do |name, version|
      if version.fetch(:current_version) == version.fetch(:wanted_version)
        next
      end

      repo = REPOS.fetch(name)

      tmp_dir = Pathname.new("tmp/update-packages/#{name}/#{version.fetch(:wanted_version)}")
      FileUtils.mkdir_p(tmp_dir)

      amd64_hash = nil
      arm64_hash = nil
      source_hash = nil

      if repo[:github_release]
        release_json_path = tmp_dir.join("github_release.json")
        unless release_json_path.exist?
          system "curl", "-f", "-L", "-o", release_json_path.to_s, "https://api.github.com/repos/#{repo.fetch(:github_release)}/releases/tags/v#{version.fetch(:wanted_version)}", exception: true
        end
        github_release = JSON.parse(release_json_path.read(encoding: "utf-8"))

        checksums_release = github_release.fetch("assets").detect do |asset|
          asset.fetch("name").match?(/(checksums|shasums)\.txt/i)
        end&.fetch("browser_download_url")

        amd64_release = github_release.fetch("assets").detect do |asset|
          if !repo[:filename_matcher] || asset.fetch("name").match?(repo.fetch(:filename_matcher))
            asset.fetch("name").match?(/#{repo[:github_release_name]}.*linux.*(amd64|x86_64|x64)/i)
          else
            false
          end
        end&.fetch("browser_download_url")

        arm64_release = github_release.fetch("assets").detect do |asset|
          if !repo[:filename_matcher] || asset.fetch("name").match?(repo.fetch(:filename_matcher))
            asset.fetch("name").match?(/#{repo[:github_release_name]}.*linux.*(arm64|aarch_?64)/i)
          else
            false
          end
        end&.fetch("browser_download_url")
      elsif repo[:checksums_download]
        checksums_release = ERB.new(repo.fetch(:checksums_download)).result(binding)
      elsif repo[:download]
        source_release = ERB.new(repo.fetch(:download)).result(binding)
      end

      if checksums_release
        checksums_path = tmp_dir.join(File.basename(checksums_release))
        unless checksums_path.exist?
          system "curl", "-f", "-L", "-o", checksums_path.to_s, checksums_release, exception: true
        end

        checksums_path.read(encoding: "utf-8").split("\n").each do |line|
          if !repo[:filename_matcher] || line.match?(repo.fetch(:filename_matcher))
            parts = line.split(/\s+/)
            if line.match?(/linux.*(amd64|x86_64|x64)/i)
              amd64_hash = parts.first
            elsif line.match?(/linux.*(arm64|aarch_?64)/i)
              arm64_hash = parts.first
            else
              source_hash = parts.first
            end
          end
        end
      else
        if amd64_release
          amd64_path = tmp_dir.join(File.basename(amd64_release))
          unless amd64_path.exist?
            system "curl", "-f", "-L", "-o", amd64_path.to_s, amd64_release, exception: true
          end

          amd64_hash = `openssl dgst -sha256 #{Shellwords.escape(amd64_path)}`.split(/\s+/).last
        end

        if arm64_release
          arm64_path = tmp_dir.join(File.basename(arm64_release))
          unless arm64_path.exist?
            system "curl", "-f", "-L", "-o", arm64_path.to_s, arm64_release, exception: true
          end

          arm64_hash = `openssl dgst -sha256 #{Shellwords.escape(arm64_path)}`.split(/\s+/).last
        end

        if source_release
          source_path = tmp_dir.join(File.basename(source_release))
          unless source_path.exist?
            system "curl", "-f", "-L", "-o", source_path.to_s, source_release, exception: true
          end

          source_hash = `openssl dgst -sha256 #{Shellwords.escape(source_path)}`.split(/\s+/).last
        end
      end

      file_paths = `git grep -lP '^\\s*#{name}_version=' tasks`
      file_paths.split.each do |file_path|
        content = File.read(file_path)
        content.gsub!(/^(\s*#{name}_version=['"])([^'"]+)/) do |match|
          "#{Regexp.last_match(1)}#{version.fetch(:wanted_version)}"
        end

        match_index = 0
        content.gsub!(/^(\s*#{name}_hash=['"])([^'"]+)/) do |match|
          new_hash = Regexp.last_match(2)
          if match_index == 0
            new_hash = amd64_hash || source_hash
          elsif match_index == 1
            new_hash = arm64_hash
          end
          match_index += 1

          "#{Regexp.last_match(1)}#{new_hash}"
        end

        File.write(file_path, content)

        if name == "task" && file_path.start_with?("tasks/bootstrap-")
          new_path = "tasks/bootstrap-#{version.fetch(:wanted_version)}"
          system "git", "mv", file_path, new_path

          makefile_in = File.read("Makefile.in")
          makefile_in.gsub!(/^task_version:=.+/, "task_version:=#{version.fetch(:wanted_version)}")
          File.write("Makefile.in", makefile_in)
        end
      end
    end
  end

  desc "all", "List outdated dependencies"
  def all
    puts "\n\n"
    puts "==== LUAROCKS ===="
    luarocks
    puts "\n\n"

    puts "==== ADMIN-UI: NPM ===="
    AdminUi.new.npm
    puts "\n\n"

    puts "==== WEB-APP: NPM ===="
    WebApp.new.npm
    puts "\n\n"

    puts "==== EXAMPLE-WEBSITE: NPM ===="
    ExampleWebsite.new.npm
    puts "\n\n"

    puts "==== TEST: LUAROCKS ===="
    Test.new.luarocks
    puts "\n\n"

    puts "==== TEST: GEMS ===="
    Test.new.gems
    puts "\n\n"

    puts "==== PACKAGES ===="
    packages
  end

  private

  def find_package_versions
    seen_names = []
    versions = {}
    versions_content = `git grep -hP '^\\s*\\w+_version=' tasks`.strip
    versions_content.each_line do |line|
      current_version_matches = line.match(/^\s*(.+?)_version=['"]([^'"]+)/)
      if(!current_version_matches)
        next
      end

      name = current_version_matches[1].downcase
      seen_names.push(name)
      options = REPOS[name] || {}
      current_version_string = current_version_matches[2]

      Outdated.add_version(versions: versions, name: name, current_version_string: current_version_string, options: options)
    end

    unused_repos = REPOS.keys - seen_names
    if(unused_repos.any?)
      warn Rainbow("\nWARNING: Unused repos defined in #{__FILE__}: #{unused_repos.sort.join(", ")}\n").yellow
    end

    versions
  end

  class << self
    def luarocks_manifest
      @luarocks_manifest ||= JSON.parse(Net::HTTP.get_response(URI.parse("https://luarocks.org/manifest.json")).body)
    end

    def luarock_version_to_semver(version)
      version.gsub(/-(\d+)$/, '.0.0.\1')
    end

    def semver_to_luarock_version(version)
      version.gsub(/\.0\.0\.(\d+)$/, '-\1')
    end

    def tag_to_semver(name, tag)
      tag.downcase!

      case name
      when "fluent_bit"
        unless tag.start_with?("v")
          return nil
        end
      end

      # Remove prefixes containing the project name.
      tag.gsub!(/^#{name}[-_]/i, "")
      tag.gsub!(/^#{name.tr("_", "-")}[-_]/i, "")

      # Remove trailing "^{}" at end of git tags.
      tag.chomp!("^{}")

      # Remove "release-" prefixes.
      tag.gsub!(/^release-/, "")

      # Remove "v" or "r" prefixes before the version number.
      tag.gsub!(/^[vr](\d)/, '\1')

      # Project-specific normalizations.
      case name
      when "postgresql"
        tag.gsub!(/^rel_?/, "")
        tag.tr!("_", ".")
      end

      tag
    end

    def add_version(versions:, name:, current_version_string:, options:)
      begin
        if(options[:luarock])
          current_version = Gem::Version.new(luarock_version_to_semver(current_version_string))
        else
          current_version = Gem::Version.new(current_version_string)
        end
      rescue ArgumentError
        current_version = current_version_string.dup
      end
      versions[name] = {
        :current_version => current_version,
      }

      tags = []
      unparsable_tags = []

      if(options[:git] && options[:git_ref])
        current_commit = current_version_string
        if(current_commit !~ /^[0-9a-f]{5,40}$/)
          current_commit = `git ls-remote #{options[:git]} #{current_version_string}`.split(/\s/).first
          if(current_commit.to_s.empty?)
            puts "#{name}: Could not parse version #{current_version_string}"
          end
        end

        latest_commit = `git ls-remote #{options[:git]} #{options[:git_ref]}`.split(/\s/).first
        if(latest_commit.to_s.empty?)
          puts "#{name}: Could not parse latest commit: git ls-remote #{options[:git]} #{options[:git_ref]}"
        end

        versions[name][:current_version] = current_commit[0, 7]
        versions[name][:latest_version] = latest_commit[0, 7]
        versions[name][:wanted_version] = latest_commit[0, 7]
      elsif(options[:git])
        tags = `git ls-remote --tags #{options[:git]}`.lines
        tags.map! { |tag| tag_to_semver(name, tag.match(%r{refs/tags/(.+)$})[1]) }.compact
      elsif(options[:luarock])
        tags = luarocks_manifest.fetch("repository").fetch(options[:luarock]).keys
        tags.map! { |tag| luarock_version_to_semver(tag) }
      elsif(options[:http])
        content = Net::HTTP.get_response(URI.parse(options[:http])).body
        tags = content.scan(/#{name}-[\d.]+.tar/)
        tags.map! { |f| tag_to_semver(name, File.basename(f, ".tar")) }.compact
      end

      tags.compact!
      tags.uniq!
      tags.each do |tag|
        if(options[:string_version])
          available_version = tag
          if(!versions[name][:latest_version] || available_version > versions[name][:latest_version])
            versions[name][:latest_version] = available_version
            versions[name][:wanted_version] = available_version
          end
        else
          constraint = Gem::Dependency.new(name, options[:constraint])

          begin
            available_version = Gem::Version.new(tag)
            next if(available_version.prerelease?)

            if(!versions[name][:latest_version] || available_version > versions[name][:latest_version])
              versions[name][:latest_version] = available_version
            end

            if(constraint.match?(name, available_version))
              if(!versions[name][:wanted_version] || available_version > versions[name][:wanted_version])
                versions[name][:wanted_version] = available_version
              end
            end
          rescue ArgumentError
            unparsable_tags << tag
          end
        end
      end

      if(unparsable_tags.any?)
        warn "#{name}: Could not parse version tag #{unparsable_tags.join(", ")}"
      end
    end

    def print_versions(versions:, luarock: false)
      print Rainbow("Package".ljust(32)).underline
      print Rainbow("Current".rjust(16)).underline
      print Rainbow("Wanted".rjust(16)).underline
      print Rainbow("Latest".rjust(16)).underline
      puts ""

      versions.keys.sort.each do |name|
        info = versions[name]
        name_column = name.ljust(32)
        if(info[:wanted_version].to_s != info[:current_version].to_s)
          print Rainbow(name_column).red
        elsif(info[:current_version].to_s != info[:latest_version].to_s)
          print Rainbow(name_column).yellow
        else
          print name_column
        end

        if luarock
          info[:current_version] = semver_to_luarock_version(info[:current_version].to_s)
          info[:wanted_version] = semver_to_luarock_version(info[:wanted_version].to_s)
          info[:latest_version] = semver_to_luarock_version(info[:latest_version].to_s)
        end

        print info[:current_version].to_s.rjust(16)
        print Rainbow(info[:wanted_version].to_s.rjust(16)).green
        print Rainbow(info[:latest_version].to_s.rjust(16)).magenta
        puts ""
      end
    end

    def outdated_luarocks(rockspec_path:, lock_path:)
      rockspec_output, rockspec_status = Open3.capture2("api-umbrella-exec", "resty", "--errlog-level", "error", "-e", "local cjson = require 'cjson'; dofile('#{rockspec_path}'); print(cjson.encode(dependencies))")
      unless rockspec_status.success?
        exit 1
      end
      rockspec = JSON.parse(rockspec_output)
      rockspec_constraints = rockspec.to_h { |r| r.split(/\s+/, 2) }

      lock_output, lock_status = Open3.capture2("api-umbrella-exec", "resty", "-e", "local cjson = require 'cjson'; print(cjson.encode(dofile('#{lock_path}')))")
      unless lock_status.success?
        exit 1
      end
      lock = JSON.parse(lock_output)

      versions = {}
      lock.fetch("dependencies").each do |name, version|
        next if name == "lua"

        options = {
          :luarock => name,
        }

        if rockspec_constraints[name]
          options[:constraint] = rockspec_constraints.fetch(name)
        end

        add_version(versions: versions, name: name, current_version_string: version, options: options)
      end

      print_versions(versions: versions, luarock: true)
    end
  end
end

# Outdated.start(ARGV)
