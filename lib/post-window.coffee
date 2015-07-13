
##{$, ScrollView} = require 'atom'
{$, ScrollView} = require 'atom-space-pen-views'

Bacon = require('baconjs')

module.exports =
class PostWindow extends ScrollView

  constructor: (@uri, @bus, @onClose) ->
    super
    @handleEvents()

    @bus?.onValue (msg) =>
      if @destroyed
        Bacon.NoMore
      else
        @addMessage(msg)
        @scrollToBottom()

  serialize: ->

  destroy: ->
    @unsubscribe()
    @destroyed = true
    @onClose()

  getTitle: ->
    "#{@uri}"

  getModel: ->

  @content: ->
    @div class: 'native-key-bindings post-window', tabindex: -1, =>
      @div outlet:"scroller", class:"scroll-view post-window-editor editor-colors", =>
        @div outlet:"posts", class:"lines"

  addMessage: (text) ->
    @posts.append "<div>#{text}</div>"

  clearPostWindow: ->
    @posts.empty()

  handleEvents: ->
    @subscribe this, 'core:copy', =>
      return false if @copyToClipboard()

  copyToClipboard: ->
    selection = window.getSelection()
    selectedText = selection.toString()
    selectedNode = selection.baseNode

    # Use default copy event handler if there is selected text inside this view
    hasSelection = selectedText and
      selectedNode? and
      (@[0] is selectedNode or $.contains(@[0], selectedNode))

    return false if hasSelection

    atom.clipboard.write(@[0].innerText)
    true
