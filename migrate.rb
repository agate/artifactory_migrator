#!/usr/bin/env ruby

require 'etc'
require 'fileutils'
require 'tempfile'
require 'yaml'
require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

class Migrator
  BASE_DIR = __dir__

  DIST_DIR = "#{BASE_DIR}/dist"
  GEMS_DIR = "#{DIST_DIR}/gems"
  NPM_DIR = "#{DIST_DIR}/npm"

  POOL_SIZE = Etc.nprocessors

  def initialize
    @config = YAML.load_file("#{BASE_DIR}/config.yml")
    validate_config!
  end

  def migrate
    # migrate_ruby_gems
    migrate_npm_packages
  end

  def migrate_ruby_gems
    ruby_gems = prepare_ruby_gems
    dump_ruby_gems(ruby_gems)
    push_ruby_gems(ruby_gems)
  end

  def migrate_npm_packages
    npm_packages = prepare_npm_packages
    dump_npm_packages(npm_packages)
    push_npm_packages(npm_packages)
  end

  private

  def prepare_ruby_gems
    ruby_gems = {}
    xml = Faraday.get("#{@config['gems']['from']}/atom.xml").body
    entries = Nokogiri.XML(xml).css('feed entry')
    entries.each do |entry|
      name = entry.css('id').inner_text
      ruby_gems[name] = []
      entry.css('link').each do |link|
        source = link.attr('href')
        version = File.basename(source).sub(/^#{name}-/, '').sub(/.gem/, '')
        ruby_gems[name] << {
          'version' => version,
          'source' => source
        }
      end
    end
    return ruby_gems
  end

  def dump_ruby_gems(ruby_gems)
    with_worker do |worker|
      ruby_gems.each do |name, versions|
        versions.each do |version|
          source = version['source']
          filename = File.basename(source)
          target = "#{GEMS_DIR}/#{name}/#{filename}"
          worker.post { download(source, target) }
        end
      end
    end
  end

  def push_ruby_gems(ruby_gems)
    with_worker do |worker|
      ruby_gems.each do |name, versions|
        versions.each do |version|
          source = version['source']
          filename = File.basename(source)
          target = "#{GEMS_DIR}/#{name}/#{filename}"

          cmd = "gem push --host #{@config['gems']['to']} #{target}"
          puts cmd
          success = system(cmd)
          err("ERROR: #{cmd}") unless success
        end
      end
    end
  end

  def prepare_npm_packages
    npm_packages = {}
    with_worker do |worker|
      json = Faraday.get("#{@config['npm']['from']}/-/verdaccio/packages").body
      packages = JSON.parse(json)
      packages.each do |package|
        name = package['name']
        npm_packages[name] = []
        worker.post do
          json = Faraday.get("#{@config['npm']['from']}/#{name}").body
          package = JSON.parse(json)
          package['versions'].each do |version, meta|
            shasum = meta['dist']['shasum']
            source = meta['dist']['tarball']
            npm_packages[name] << {
              'version' => version,
              'shasum' => shasum,
              'source' => source
            }
          end
        end
      end
    end
    return npm_packages
  end

  def dump_npm_packages(npm_packages)
    npm_packages.each do |name, versions|
      with_worker do |worker|
        versions.each do |version|
          source = version['source']
          filename = File.basename(source)
          target = "#{NPM_DIR}/#{name}/#{filename}"
          worker.post { download(source, target) }
        end
      end
    end
  end

  def push_npm_packages(npm_packages)
    npm_packages.each do |name, versions|
      with_worker do |worker|
        versions.each do |version|
          source = version['source']
          filename = File.basename(source)
          target = "#{NPM_DIR}/#{name}/#{filename}"
          worker.post do
            cmd = "npm publish --silent --registry #{@config['npm']['to']} #{target}"
            puts cmd
            success = system(cmd)
            err("ERROR: #{cmd}") unless success
          end
        end
      end
    end
  end

  def download(source, target)
    if File.exist?(target)
      log("#{source} - SKIP")
    else
      begin
        FileUtils.mkdir_p(File.dirname(target))
        Tempfile.create(target) do |file|
          Faraday.new do |conn|
            conn.get(source) do |req|
              req.options.on_data = Proc.new do |chunk, _overall_received_bytes|
                file << chunk
              end
            end
          end
          FileUtils.mv(file.path, target)
        end
        log("#{source} - DOWNLOADED")
      rescue => e
        err("#{source} - ERR: #{e.message}")
      end
    end
  end

  def validate_config!
    valid = true

    if @config['gems']['registry'] != 'geminabox'
      err("We only support migrate ruby gems from geminabox registry.")
      valid = false
    end

    if @config['npm']['registry'] != 'verdaccio'
      err("We only support migrate npm packages from verdaccio registry.")
      valid = false
    end

    exit 1 unless valid
  end

  def with_worker(&block)
    worker = Concurrent::FixedThreadPool.new(POOL_SIZE)
    yield worker
    worker.shutdown
    worker.wait_for_termination
  end

  def log(message)
    message = color_text(message)
    puts(message)
  end

  def err(message)
    message = color_text(message, :red)
    warn(message)
  end

  def color_text(text, color = nil)
    code = case color
           when :red
             31
           when :green
             32
           when :yellow
             33
           when :blue
             34
           when :gray
             90
           else
             39
           end
    "\e[#{code}m#{text}\e[0m"
  end
end

Migrator.new.migrate
