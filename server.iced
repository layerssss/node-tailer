http = require 'http'
fs = require 'fs'
path = require 'path'
socket_io = require 'socket.io'
iced_coffee_script = require 'iced-coffee-script'
{
  spawn
} = require 'child_process'


await fs.readFile (path.join __dirname, 'index.html'), defer e, index_html
throw e if e
await fs.readFile (path.join __dirname, 'jquery.min.js'), defer e, jquery_min_js
throw e if e

server = http.createServer (rq, rs)->
  cb = (e)->
    rs.writeHead 500
    rs.end e.message
  if rq.url.match /^\/(\?.*)?$/
    if rq.headers.accept.match 'json'
      await fs.readdir (path.join process.env.HOME, '.node-tailer'), defer e, cmds
      cmds = [] if e
      rs.setHeader 'Content-Type', 'application/json'
      rs.writeHead 200
      return rs.end JSON.stringify cmds
    else
      rs.setHeader 'Content-Type', 'text/html'
      rs.writeHead 200
      return rs.end index_html
  if rq.url == '/jquery.min.js'
    rs.setHeader 'Content-Type', 'application/json'
    rs.writeHead 200
    return rs.end jquery_min_js
  if rq.url == '/tailer.js'
    rs.setHeader 'Content-Type', 'application/json'
    rs.writeHead 200
    return rs.end iced_coffee_script.compile """
      $ ->
        $.getJSON '.', (cmds)->
          $('.cmds').html ''
          for cmd in cmds
            $(document.createElement 'a')
              .text cmd
              .attr 'href', '?' + cmd
              .css 'display', 'block'
              .appendTo '.cmds'
        pend = (el)->
          bottom = $(document).height() - $(window).scrollTop() - $(window).height()
          $ el
            .insertBefore '.footer'
          setTimeout (->
            if bottom < $('.footer').height()
              $('html, body').scrollTop $(document).height() - $(window).height() - bottom
            ), 1
          $ el
        if cmd = location.search.substring 1
          $ pend document.createElement 'pre'
            .addClass 'msg'
            .text 'starting ' + cmd + ' ...'
          socket = io.connect()
          socket.on 'connect', ->
            socket.emit 'tail', cmd
          socket.on 'stdout', (data)->
            $ pend document.createElement 'pre'
              .addClass 'stdout'
              .text data
          socket.on 'stderr', (data)->
            $ pend document.createElement 'pre'
              .addClass 'stderr'
              .text data
          socket.on 'err', (message)->
            $ pend document.createElement 'pre'
              .addClass 'msg'
              .text 'error starting ' + cmd + ': ' + message

    """
  rs.writeHead 404
  rs.end "Not Found"

io = socket_io.listen server
io.sockets.on 'connection', (socket)->
  socket.on 'tail', (cmd)->
    await fs.readdir (path.join process.env.HOME, '.node-tailer'), defer e, cmds
    cmds = [] if e
    if -1 == cmds.indexOf cmd
      return socket.emit 'err', "~/.node-tailer/#{cmd} does not exists."
    child = spawn path.join(process.env.HOME, '.node-tailer', cmd), [], 
      cwd: process.env.HOME
      stdio: ['ignore', 'pipe', 'pipe']
    child.stdout.setEncoding 'utf8'
    child.stderr.setEncoding 'utf8'
    child.stdout.on 'data', (data)->
      socket.emit 'stdout', data
    child.stderr.on 'data', (data)->
      socket.emit 'stderr', data
    child.on 'error', (e)->
      socket.emit 'err', e.message
    child.on 'exit', (code)->
      socket.emit 'exited', code
    socket.on 'disconnect', ->
      killer = spawn 'pkill', ['-TERM', '-P', String child.pid]
      killer.on 'error', ->
        # fallback
        child.kill()



await server.listen Number(process.env.APP_PORT||process.env.PORT)||3000, process.env.APP_ADDR||'0.0.0.0', defer e
throw e if e
console.log "ready to tail on #{server.address().address}:#{server.address().port}"
