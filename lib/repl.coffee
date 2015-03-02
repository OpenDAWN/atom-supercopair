PostWindow = require('./post-window')
Bacon = require('baconjs')
url = require('url')
os = require('os')
Q = require('q')
supercolliderjs = require('supercolliderjs')
escape = require('escape-html')
rendering = require './rendering'
growl = require 'growl'


module.exports =
class Repl

  constructor: (@uri="sclang://localhost:57120", projectRoot, @onClose) ->
    @projectRoot = projectRoot
    @ready = Q.defer()
    @makeBus()

  stop: ->
    @sclang?.quit()
    @postWindow.destroy()

  createPostWindow: ->

    onClose = () =>
      @sclang?.quit()
      @onClose()

    @postWindow = new PostWindow(@uri, @bus, onClose)

  makeBus: ->
    @bus = new Bacon.Bus()
    @emit = new Bacon.Bus()

  startSCLang: () ->
    @recompiling = false

    opts =
      stdin: false
      echo: false

    dir = process.cwd()
    if @projectRoot
      process.chdir(@projectRoot)

    supercolliderjs.resolveOptions(null, opts)
      .then (options) =>
        @bus.push rendering.displayOptions(options)
        options.errorsAsJSON =
          !(atom.config.get 'supercopair.classicRepl')
        @bootProcess(dir, options)

  bootProcess: (dir, options) ->

    pass = () =>
      @ready.resolve()

    fail = (error) =>
      @ready.reject()

      state = @sclang.state
      switch state
        when 'compileError'
          # stdout
          # dirs
          i = 0
          for error in error.errors
            @bus.push rendering.renderParseError(error)
            error.index = i
            @emit.push(error)
            i += 1
        else
          # initFailure
          # descrepency
          # systemError
          @bus.push("<div class='error'>STATE: #{state}</div>")
          # @bus.push("<div class='pre error'>#{error}</div>")

    lastErrorTime = null

    process.chdir(dir)
    @sclang = new supercolliderjs.sclang(options)

    unlisten = (sclang) ->
      for event in ['exit', 'stdout', 'stderr', 'error', 'state']
        sclang.removeAllListeners(event)

    @sclang.on 'state', (state) =>
      if state
        @bus.push("<div class='state #{state}'>#{state}</div>")

    @sclang.on 'exit', () =>
      @bus.push("<div class='state dead'>sclang exited</div>")
      unless @recompiling
        if atom.config.get 'supercopair.growlOnError'
          growl("sclang exited", {title: "SuperCollider"})
      unlisten(@sclang)
      @sclang = null

    @sclang.on 'stdout', (d) =>
      d = rendering.cleanStdout(d)
      d = rendering.stylizeErrors(d)
      @bus.push("<div class='pre stdout'>#{d}</div>")

    @sclang.on 'stderr', (d) =>
      d = rendering.cleanStdout(d)
      d = rendering.stylizeErrors(d)
      @bus.push("<div class='pre stderr'>#{d}</div>")

    @sclang.on 'error', (err) =>
      errorTime = new Date()
      err.errorTime = errorTime
      @bus.push rendering.renderError(err, null)
      if atom.config.get 'supercopair.growlOnError'
        show = true
        if lastErrorTime?
          show = (errorTime - lastErrorTime) > 1000
        if show
          growl(err.error.errorString, {title: 'SuperCollider'})
        lastErrorTime = errorTime

    onBoot = () =>
      @sclang.initInterpreter()
                  .then(pass, fail)

    @sclang.boot().then(onBoot, fail)

  eval: (expression, noecho=false, nowExecutingPath=null) ->

    deferred = Q.defer()

    classic = atom.config.get 'supercopair.classicRepl'

    ok = (result) =>
      @bus.push "<div class='pre out'>#{result}</div>"
      deferred.resolve(result)

    err = (error) =>
      deferred.reject(error)
      if classic
        stdout = error.error.stdout
        if stdout
          stdout = escape(stdout.trim())
        else
          stdout = "ERROR"
        @bus.push "<div class='error pre'>#{stdout}</div>"
      else
        error.errorTime = new Date()
        @bus.push rendering.renderError(error, expression)
        # dbug = JSON.stringify(error, undefined, 2)
        # @bus.push "<div class='pre debug'>#{dbug}</div>"

    @ready.promise.then =>
      noecho = true
      unless noecho
        if expression.length > 80
          echo = expression.substr(0, 80) + '...'
        else
          echo = expression
        @bus.push "<div class='pre in'>#{echo}</div>"

      # expression path asString postErrors getBacktrace
      @sclang.interpret(expression, nowExecutingPath, true, classic, !classic)
        .then(ok, err)

    deferred.promise

  recompile: ->
    @recompiling = true
    if @sclang?
      @sclang.quit()
        .then () =>
          @startSCLang()
    else
      @startSCLang()

  isCompiled: ->
    @sclang?.state is 'ready'

  warnIsNotCompiled: ->
    @bus.push "<div class='error stderr'>Library is not compiled</div>"

  cmdPeriod: ->
    @eval("CmdPeriod.run;", true)

  clearPostWindow: ->
    @postWindow.clearPostWindow()
