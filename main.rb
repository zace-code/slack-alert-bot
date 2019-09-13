# if we're building with Ocra we have to package our own
#  SSL cert pems
unless defined?(Ocra)
  ENV['SSL_CERT_DIR'] = './dist'
  ENV['SSL_CERT_FILE'] = './dist/cert.pem'
end

require 'slack-ruby-client'
require 'rufus-scheduler'
require_relative 'file_handler'

# load our bot config and init our wait list
config = load_config
wait_list = []
raise "Config file either doesn't exist or is empty" if config.nil?

# set our constants
WaitTime = "#{config[:timeout] || 45}m"
Scheduler = Rufus::Scheduler.new
PopupMessage = config[:popup_message] % "\"#{config[:keywords].join('" ,"')}\""
MsgRegex = /^\s*(?<keyword>#{config[:keywords].join('|')})/i

# just a wrapper for evaluating a block after a certain time
def after_timeout
  Scheduler.in WaitTime do
    yield
  end
end

# we need a user token AND a bot token because slack :shrug:
wclient  = Slack::Web::Client.new(token: config[:user_token])
rtclient = Slack::RealTime::Client.new(token: config[:bot_token])

# transform our channel names into channel IDs
config[:watch_channels] = wclient.conversations_list(types: 'public_channel,private_channel')['channels']
                      .select {|c| config[:watch_channels].include? c.name}
                      .collect {|c| c['id']}
config[:alert_channels] = wclient.conversations_list(types: 'public_channel,private_channel')['channels']
                      .select {|c| config[:alert_channels].include? c.name}
                      .collect {|c| c['id']}

# print a message saying that we've been connected
rtclient.on :hello do
  puts 'Successfully Connected!'
end

# listen for typing events
rtclient.on :user_typing do |event|
  
  # if the event happened in a channel we're supposed to watch
  #  and the user hasn't been flagged to ignore
  if config[:watch_channels].include?(event['channel']) and
     not wait_list.include?(event['user'])

    # show our popup to the user
    wclient.chat_postEphemeral(channel: event['channel'],
                               user: event['user'],
                               text: PopupMessage)

    # then we add that user to the wait list so we don't annoy
    #  them with popups....for a bit ;p
    wait_list << event['user']
    after_timeout do
      wait_list.delete event['user']
    end
    
  end
end

# listen for messages
rtclient.on :message do |event|
  # check if the message matches our regex
  match = MsgRegex.match(event['text'])

  # if the channel is one we should be watching, it IS a message
  #  AND it matches what we're looking for
  if config[:watch_channels].include?(event['channel']) and
     event['type'] == 'message' and match
    
    # we get the info for that user
    user_info = wclient.users_info(user: event['user'])['user']
    
    # create a hash with info about the user who had the idea
    idea = { user: user_info[:name] }

    # save the status (making sure we strip out the keywords)
    idea[:message] = Slack::Messages::Formatting.unescape(
      wclient.channels_history(channel: event['channel'],
                               latest: event['ts'],
                               inclusive: true,
                               count: 1)['messages'].first['text'])
                       .gsub(match[:keyword], '').strip

    # fetch a permalink while we're at it
    idea[:link] = wclient.chat_getPermalink(channel: event['channel'],
                                            message_ts: event['ts'])['permalink']

    # add it to the google doc
    add_to_doc idea

    # and finally message the correct channels
    config[:alert_channels].each do |channel|
      wclient.chat_postMessage(channel: channel,
                               text: "<@here> There was a new idea: #{idea[:link]}")
    end
  end
end

# start the realtime client if not compiling using Ocra
unless defined?(Ocra)
  rtclient.start!
end
