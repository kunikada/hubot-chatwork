HTTPS          = require 'https'
{EventEmitter} = require 'events'

Robot         = (require 'hubot').Robot
Adapter       = (require 'hubot').Adapter
TextMessage   = (require 'hubot').TextMessage

class Chatwork extends Adapter
  # override
  send: (envelope, strings...) ->
    for string in strings
      @bot.Room(envelope.room).Messages().create string, (err, data) =>
        @robot.logger.error "Chatwork send error: #{err}" if err?

  # override
  reply: (envelope, strings...) ->
    @send envelope, strings.map((str) ->
      "[To:#{envelope.user.id}] #{envelope.user.name}さん\n#{str}")...

  # override
  run: ->
    options =
      token: process.env.HUBOT_CHATWORK_TOKEN
      interval: process.env.HUBOT_CHATWORK_INTERVAL_SEC or 5

    bot = new ChatworkStreaming(options, @robot)

    bot.listen()

    bot.on 'message', (roomId, id, account, body, sendAt, updatedAt) =>
      user = @robot.brain.userForId account.account_id,
        name: account.name
        avatarImageUrl: account.avatar_image_url
        room: roomId
      @receive new TextMessage user, body, id

    @bot = bot

    @emit 'connected'

exports.use = (robot) ->
  new Chatwork robot

class ChatworkStreaming extends EventEmitter
  constructor: (options, @robot) ->
    unless options.token?
      @robot.logger.error \
        'Not enough parameters provided. I need a token'
      process.exit 1

    @token = options.token
    @interval = options.interval
    @host = 'api.chatwork.com'
    @waitTime = 0

  Me: (callback) =>
    @get "/me", "", callback

  My: =>
    status: (callback) =>
      @get "/my/status", "", callback

    tasks: (opts, callback) =>
      params = []
      params.push "assigned_by_account_id=#{opts.assignedBy}" if opts.assignedBy?
      params.push "status=#{opts.status}" if opts.status?
      body = params.join '&'
      @get "/my/tasks", body, callback

  Contacts: (callback) =>
    @get "/contacts", "", callback

  Rooms: =>
    show: (callback) =>
      @get "/rooms", "", callback

    create: (name, adminIds, opts, callback) =>
      params = []
      params.push "name=#{name}"
      params.push "members_admin_ids=#{adminIds.join ','}"
      params.push "description=#{opts.desc}" if opts.desc?
      params.push "icon_preset=#{opts.icon}" if opts.icon?
      params.push "members_member_ids=#{opts.memberIds.join ','}" if opts.memberIds?
      params.push "members_readonly_ids=#{opts.roIds.join ','}" if opts.roIds?
      body = params.join '&'
      @post "/rooms", body, callback

  Room: (id) =>
    baseUrl = "/rooms/#{id}"

    show: (callback) =>
      @get "#{baseUrl}", "", callback

    update: (opts, callback) =>
      params = []
      params.push "description=#{opts.desc}" if opts.desc?
      params.push "icon_preset=#{opts.icon}" if opts.icon?
      params.push "name=#{opts.name}" if opts.name?
      body = params.join '&'
      @put "#{baseUrl}", body, callback

    leave: (callback) =>
      body = "action_type=leave"
      @delete "#{baseUrl}", body, callback

    delete: (callback) =>
      body = "action_type=delete"
      @delete "#{baseUrl}", body, callback

    Members: =>
      show: (callback) =>
        @get "#{baseUrl}/members", "", callback

      update: (adminIds, opts, callback) =>
        params = []
        params.push "members_admin_ids=#{adminIds.join ','}"
        params.push "members_member_ids=#{opts.memberIds.join ','}" if opts.memberIds?
        params.push "members_readonly_ids=#{opts.roIds.join ','}" if opts.roIds?
        body = params.join '&'
        @put "#{baseUrl}/members", body, callback

    Messages: =>
      show: (callback) =>
        @get "#{baseUrl}/messages", "", callback

      create: (text, callback) =>
        body = "body=#{text}"
        @post "#{baseUrl}/messages", body, callback

      open: =>
        @Room(id).Messages().show (err, messages) =>
          for message in messages
            @emit 'message',
              id,
              message.message_id,
              message.account,
              message.body,
              message.send_time,
              message.update_time

    Message: (mid) =>
      show: (callback) =>
        @get "#{baseUrl}/messages/#{mid}", "", callback

    Tasks: =>
      show: (opts, callback) =>
        params = []
        params.push "account_id=#{opts.account}" if opts.account?
        params.push "assigned_by_account_id=#{opts.assignedBy}" if opts.assignedBy?
        params.push "status=#{opts.status}" if opts.status?
        body = params.join '&'
        @get "#{baseUrl}/tasks", body, callback

      create: (text, toIds, opts, callback) =>
        params = []
        params.push "body=#{text}"
        params.push "to_ids=#{toIds.join ','}"
        params.push "limit=#{opts.limit}" if opts.limit?
        body = params.join '&'
        @post "#{baseUrl}/tasks", body, callback

    Task: (tid) =>
      show: (callback) =>
        @get "#{baseUrl}/tasks/#{tid}", "", callback

    Files: =>
      show: (opts, callback) =>
        body = ""
        body += "account_id=#{opts.account}" if opts.account?
        @get "#{baseUrl}/files", body, callback

    File: (fid) =>
      show: (opts, callback) =>
        body = ""
        body += "create_download_url=#{opts.createUrl}" if opts.createUrl?
        @get "#{baseUrl}/files/#{fid}", body, callback

  get: (path, body, callback) ->
    @request "GET", path, body, callback

  post: (path, body, callback) ->
    @request "POST", path, body, callback

  put: (path, body, callback) ->
    @request "PUT", path, body, callback

  delete: (path, body, callback) ->
    @request "DELETE", path, body, callback

  request: (method, path, body, callback) ->
    if @waitTime > 0
      delay = @waitTime * 1000
      @waitTime = 0
      setTimeout @request, delay, method, path, body, callback

    logger = @robot.logger

    headers =
      "Host"           : @host
      "X-ChatWorkToken": @token
      "Content-Type"   : 'application/x-www-form-urlencoded'

    options =
      "agent"  : false
      "host"   : @host
      "port"   : 443
      "path"   : "/v1#{path}"
      "method" : method
      "headers": headers

    body = new Buffer body
    options.headers["Content-Length"] = body.length

    request = HTTPS.request options, (response) =>
      data = ""

      response.on "data", (chunk) ->
        data += chunk

      response.on "end", =>
        if response.statusCode >= 400
          switch response.statusCode
            when 401
              throw new Error "Invalid access token provided"
            else
              logger.error "Chatwork HTTPS status code: #{response.statusCode}"
              logger.error "Chatwork HTTPS response data: #{data}"

        if response.headers['x-ratelimit-remaining'] is '0'
          @waitTime = response.headers['x-ratelimit-reset'] - (Date.now() / 1000 | 0)

        if callback
          json = try JSON.parse data catch e then data or {}
          callback null, json

      response.on "error", (err) ->
        logger.error "Chatwork HTTPS response error: #{err}"
        callback err, {}

    request.end body, 'binary'

    request.on "error", (err) ->
      logger.error "Chatwork request error: #{err}"

  listen: ->
    timeout = =>
      @Rooms().show (err, rooms) =>
        now = Date.now() / 1000 | 0
        for room in rooms
          continue if room.last_update_time < now - @interval
          @Room(room.room_id).Messages().open()
      setTimeout timeout, @interval * 1000
    timeout()
