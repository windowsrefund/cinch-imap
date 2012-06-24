require 'net/imap'
require 'yaml'
require 'tmpdir'

class Imap
  include Cinch::Plugin

  PLUGIN_VERSION='0.1.0'

  listen_to :join

  def create_poller(m, seconds)
    poller.stop if poller
    @poller_created = Time.now
    @poller_next = (Time.now + seconds).strftime('%T')
    @poller = Timer(seconds) do
      @poller_next = (Time.now + poller.interval).strftime('%T')
      imap = imap_connect(m)
      m.reply "DEBUG: connected to imap" if @monitor_debug
      m.reply "DEBUG: imap is nil? %s" % imap.nil? if @monitor_debug
      imap_poll(m, imap) unless imap.nil?
      if maintenance_hour == Time.now.hour
        imap_purge(m, imap, retain_days) if maintenance_needed
        @maintenance_needed = false
      else
        @maintenance_needed = true
      end
      write(m, 'count') if count_incremented
      imap.disconnect unless imap.nil?
    end
  end

  def listen(m)
    create_poller(m, interval) if autostart
  end

  match /monitor (start|stop|on|off)$/, method: :monitor
  match /monitor debug (on|off)$/, method: :monitor_debug
  match "monitor test", method: :imap_test
  match "monitor clean", method: :imap_purge
  match /monitor interval (\d+)/, method: :set_interval
  match "monitor version", method: :about
  match /monitor show (count|config|status)$/, method: :show
  match /monitor show (count) (.+)/, method: :show
  match /monitor write (count)/, method: :write
  match "monitor help", method: :usage
  match "monitor", method: :usage

  attr_reader :interval, :poller, :poller_created, :poller_next, :autostart,
    :maintenance_hour, :maintenance_needed, :retain_days, :mark_as_read,
    :mail_host, :mail_user, :mail_password, :mail_folder, :mail_port, :mail_ssl,
    :subject_matches, :from_rewrites, :count_incremented, :count_database, :count

  def initialize(*args)
    super
    @monitor_debug = false
    @mail_host = config[:host]
    @mail_user = config[:user]
    @mail_password = config[:password]
    @mail_folder = config[:folder] || 'INBOX'
    @mail_port = config[:port] || 143
    @mail_ssl = config[:ssl] || false
    @mark_as_read = config[:mark_as_read ] || true
    @interval = config[:interval] || 300
    @subject_matches = config[:subject_matches] || {}
    @from_rewrites = config[:from_rewrites] || {}
    @autostart = config[:autostart] || false
    @retain_days = config[:retain_days] || 0
    @maintenance_hour = config[:maintenance_hour] || 10

    if config.has_key?(:count_database)
      @count_database = config[:count_database]
    else
      @count_database = File.join(Dir.tmpdir, 'count.yml')
    end

    # Load or initialize a hash of counts
    @count = load_count
  end

  def load_count(timestamp = year_and_month)
    # load a hash where YYYY-MM is used for each key
    YAML.load_file(count_database).fetch(timestamp)
  rescue
    if count.is_a?(Hash)
      "No data found for #{timestamp}"
    else
      # initialize
      Hash[:problem, 0, :recovery, 0, :acknowledged, 0, :other, 0]
    end
  end
  def year_and_month
    "#{Time.now.year}-#{Time.now.strftime('%m')}"
  end

  # write to the file system
  def write(m, command)
    case command
    when /count/
      # read in existing data or create a new hash
      data = YAML.load_file(count_database) || Hash.new
      # add to it
      data[year_and_month] = count
      # write it out
      open(count_database, 'w') { |f| f.puts data.to_yaml }
    else
      usage(m)
    end
  rescue => e
    m.reply e
  end
  def about(m)
    m.reply "Looks like I'm on version %s" % PLUGIN_VERSION
  end
  def set_interval(m, sec)
    seconds = sec.to_i
    create_poller(m, seconds)
  end
  def monitor(m, option)
    action = case option
             when "on", "start"
               :start
             when "off", "stop"
               :stop
             end
    poller.send(action)
  end
  def monitor_debug(m, option)
    @monitor_debug = option == "on"
  end
  def show(m, command, timestamp = year_and_month)
    case command
    when /config/
      config.each do |k, v|
      m.reply "#{k}: #{config[k]}" unless k == :password
      end
    when /count/

      # Check formatting of argument
      case timestamp
      when /^\d{4}-\d{2}$/

        # A past month may have been requested
        data = timestamp == year_and_month ? count : load_count(timestamp)
        counts = []
        data.each do |k,v|
          counts << "#{k.capitalize}: #{v}"
        end if data.is_a?(Hash)

        response = data.is_a?(Hash) ? counts.join(', ') : data
      else
        response = "Optional timestamp must be in YYYY-MM format." 
      end

    m.reply response
    when /status/
      message = []
      message << "Enabled: %s" % poller.started?
      message << "Interval: %s" % poller.interval.to_i
      message << "Next: %s" % poller_next if poller.started?
      m.reply message.join(', ')
    else
      usage(m)
    end
  end
  def usage(m)
    m.reply "Usage: !monitor <command>"
    m.reply "Commands: start, stop, on, off, test, interval <seconds>, show <config|count [YYYY-MM]|status>"
  end
  def imap_test(m)
    begin
      imap = imap_connect(m)
      status = []
      status << "Retain Days: %s" % retain_days
      status << "Before: %s" % imap.search(["BEFORE", get_old_date]).length
      status << "Since: %s" % imap.search(["SINCE", get_old_date]).length
      status << "Unseen: %s" % imap.search(["UNSEEN"]).length
      status << "Seen: %s" % imap.search(["NOT", "NEW"]).length
      imap.disconnect
      m.reply status.join(', ')
    end
  end
  def get_old_date(days = retain_days)
    (Time.now - 60 * 60 * 24 * days).strftime("%d-%b-%Y")
  end
  
  def imap_purge(m, connection = imap_connect(m), retain = 0)
    m.reply "Time to make the donuts!"
    previous_date = get_old_date(retain)
    connection.search(["BEFORE", get_old_date]).each do |message_id|
      m.reply "Setting delete flag on #{message_id}"
      envelope = connection.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
      connection.store(message_id, "+FLAGS", [:Deleted])
    end
    m.reply "Running expunge"
    connection.expunge
    m.reply "Complete"
  end

  def get_messages(m, conn)
    m.reply "DEBUG: in get_messages with %s " % conn if @monitor_debug
    conn.search(["UNSEEN"]).each do |message_id|
      envelope = conn.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
      name = envelope.from[0].name
      mailbox = envelope.from[0].mailbox
      #reply_to = envelope.reply_to[0]
      host = envelope.from[0].host
      from = name.nil? ? host : name
      subj = envelope.subject
      conn.store(message_id, "+FLAGS", [:Seen]) if mark_as_read
      m.reply("DEBUG: Found message") if @monitor_debug
      yield from, host, subj
    end
  end

  def imap_connect(m)
    connection = Net::IMAP.new(mail_host, mail_port, mail_ssl)
    connection.login(mail_user, mail_password)
    connection.select(mail_folder)
    connection
  rescue Net::IMAP::NoResponseError
    m.reply "Mail server %s is offline" % mail_server
    nil
  end

  def imap_poll(m, connection)
    m.reply "DEBUG: in imap_poll with %s" % connection if @monitor_debug

    # This is used by the write method.
    # It will be set to true if anything is returned from the poll
    @count_incremented = false

    get_messages(m, connection) do |from, host, subj|
      m.reply "DEBUG: returned from get_messages" if @monitor_debug
      message_from, message_prefix = from, nil
      from_rewrites.each do |k, v|
        message_from = "#{v}" if from =~ /#{k}/ or host == k
      end
      subject_matches.each do |k, v|
        message_prefix = "#{v}" if subj =~ /#{k}/
      end

      # for reporting
      case subj
      when /PROBLEM/
        @count[:problem] += 1 if count.has_key?(:problem)
      when /RECOVERY/
        @count[:recovery] += 1 if count.has_key?(:recovery)
      when /ACKNOWLEDGED/
        @count[:acknowledged] += 1 if count.has_key?(:acknowledged)
      else 
        @count[:other] += 1 if count.has_key?(:other)
      end
      m.reply "%s %s: %s" % [message_prefix, message_from, subj]

      @count_incremented = true
    end
  end
end
