# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "logstash/json"
require "stud/buffer"

require "td-client"
require "msgpack"

require "securerandom"
require "stringio"
require "zlib"

# Logstash output plugin to send data to Treasure Data service.

class LogStash::Outputs::TreasureData < LogStash::Outputs::Base
  include Stud::Buffer

  concurrency :shared if self.respond_to?(:concurrency)

  config_name "treasure_data"

  IMPORT_SIZE_LIMIT = 32 * 1024 * 1024
  RECORD_KEYS_LIMIT = 512
  RECORD_SIZE_LIMIT = 32 * 1024 * 1024

  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  require 'rubygems'
  VERSION = Gem::Specification.load(File.expand_path('../../../../logstash-output-treasure_data.gemspec', __FILE__)).version

  config :apikey, validate: :password, required: true
  config :auto_create_table, validate: :boolean, default: true
  config :endpoint, validate: :string, default: TreasureData::API::NEW_DEFAULT_ENDPOINT
  config :use_ssl, validate: :boolean, default: true

  config :database, validate: :string, required: true
  config :table, validate: :string, required: true

  config :http_proxy, validate: :string, default: nil
  config :connect_timeout, validate: :number, default: nil
  config :read_timeout, validate: :number, default: nil
  config :send_timeout, validate: :number, default: nil

  config :flush_size, validate: :number, default: 10000      # 10,000 records for flush
  config :flush_interval, validate: :number, default: 60 * 5 # 5min for flush

  public
  def register
    @empty_gz_data = TreasureData::API.create_empty_gz_data
    @user_agent = "logstash-output-treasure_data: #{VERSION}".freeze

    TreasureData::API.validate_database_name(@database)
    TreasureData::API.validate_table_name(@table)

    @client_opts = {
      ssl: @use_ssl,
      http_proxy: @http_proxy,
      user_agent: @user_agent,
      endpoint: @endpoint,
      connect_timeout: @connect_timeout,
      read_timeout: @read_timeout,
      send_timeout: @send_timeout
    }

    buffer_initialize(
      max_items: @flush_size,
      max_interval: @flush_interval,
      logger: @logger
    )
  end # def register

  public
  def receive(event)
    # Logstash::Output::Base#multi_receive(events) calls this method by `events.each{|event| receive(event) }`
    record = event.clone
    @logger.debug "receive a event"

    record.set('time', record.timestamp.to_i || Time.now.to_i) unless record.get('time')
    if record.to_hash.size > RECORD_KEYS_LIMIT
      raise "Too many number of keys (#{record.keys.size} keys)"
    end

    row = convert_to_msgpack(record)
    if row.bytesize > RECORD_SIZE_LIMIT
      raise "Too large record (#{row.bytesize} bytes with keys:#{record.keys.join(',')})"
    end

    buffer_receive(row)
    @logger.debug "buffered a event"
  end

  def convert_to_msgpack(record)
    record.to_hash.to_msgpack
  rescue ArgumentError, NoMethodError
    LogStash::Json.load(LogStash::Json.dump(record.to_hash)).to_msgpack
  end

  public
  def flush(events, teardown = false)
    @logger.debug "flushing #{events} events (may include chunk uuid)"
    return if events.size < 1
    if UUID_FORMAT !~ events.first
      new_uuid = SecureRandom.uuid
      @logger.debug "adding chunk uuid #{new_uuid}"
      events.unshift new_uuid
    end

    uuid = events.first
    io = StringIO.new
    @logger.debug "gzipping chunk #{uuid}"
    Zlib::GzipWriter.wrap(io){|f|
      events.each do |row|
        unless row == uuid
          f.write row
        end
      end
      f.finish
    }
    data = io.string
    client = TreasureData::Client.new(@apikey.value, @client_opts)
    @logger.debug "sending gzipped chunk #{uuid}, #{data.bytesize} bytes"
    begin
      client.import(@database, @table, "msgpack.gz", data, data.bytesize, uuid)

    rescue TreasureData::NotFoundError => e
      raise unless @auto_create_table

      @logger.info "creating missing table #{@table} on database #{@database} for chunk #{uuid}"
      ensure_table_exists(client, @database, @table)
      @logger.info "retrying upload chunk #{uuid}"
      retry
    end

    @logger.debug "done #{uuid}"
  end # def flush

  public
  def ensure_table_exists(client, database, table)
    begin
      client.create_log_table(database, table)
    rescue TreasureData::NotFoundError => e
      client.create_database(database)
      client.create_log_table(database, table)
    rescue TreasureData::AlreadyExistsError => e
      # ignore
    end
  end

  public
  def on_flush_error(e)
    @logger.warn "flush error #{e.class}: #{e.message}"
  end

  public
  def on_full_buffer_error(opts={})
    @logger.warn "buffer exceeds limits: pending:#{opts[:pending_count]}, outgoing:#{opts[:outgoing_count]}"
  end

  public
  def close
    buffer_flush(final: true)
  end
end # class LogStash::Outputs::TreasureData
