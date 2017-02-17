# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"


class LogStash::Outputs::Stomp < LogStash::Outputs::Base
  config_name "stomp"

  # The address of the STOMP server.
  config :host, :validate => :string, :required => true

  # The port to connect to on your STOMP server.
  config :port, :validate => :number, :default => 61613

  # The username to authenticate with.
  config :user, :validate => :string, :default => ""

  # The password to authenticate with.
  config :password, :validate => :password, :default => ""

  # The destination to read events from. Supports string expansion, meaning
  # `%{foo}` values will expand to the field value.
  #
  # Example: "/topic/logstash"
  config :destination, :validate => :string, :required => true

  # The vhost to use
  config :vhost, :validate => :string, :default => nil

  # Custom headers to send with each message. Supports string expansion, meaning
  # %{foo} values will expand to the field value.
  #
  # Example: headers => ["amq-msg-type", "text", "host", "%{host}"]
  config :headers, :validate => :hash

  # Enable debugging output?
  config :debug, :validate => :boolean, :default => false

  private
  def connect
    begin
      @client.connect
      @logger.debug("Connected to stomp server") if @client.connected?
    rescue => e
      @logger.debug("Failed to connect to stomp server, will retry",
                    :exception => e, :backtrace => e.backtrace)
      sleep 2
      retry
    end
  end


  public
  def register
    require "onstomp"
    @client = OnStomp::Client.new("stomp://#{@host}:#{@port}", :login => @user, :passcode => @password.value)
    @client.host = @vhost if @vhost

    # Handle disconnects
    @client.on_connection_closed {
      connect
    }

    @done = false
    connect
  end # def register

  public
  def close
    @logger.warn("Disconnecting from stomp broker")
    Thread.pass until @done
    @client.disconnect :receipt => 'disconnect-receipt-id' if @client.connected?
  end # def close

  def done(inflight)
    @done = inflight == 0
    puts "#{inflight} => @done = #{@done}"
  end

  def multi_receive(events)
    @logger.debug("stomp sending events in batch", { :host => @host, :events => events.length })
    inflight = events.length
    done(inflight)

    @client.transaction do |t|
      events.each { |event|
        headers = Hash.new
        if @headers
          @headers.each do |k,v|
            headers[k] = event.sprintf(v)
          end
        end

        t.send(event.sprintf(@destination), event.to_json, headers) do |r|
          inflight -= 1
          done(inflight)
        end
      }
    end
  end # def multi_receive
end # class LogStash::Outputs::Stomp
