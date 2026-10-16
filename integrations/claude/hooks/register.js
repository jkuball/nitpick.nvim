// nitpick for Claude Code: receive code reviews written in Neovim.
//
// A mod cannot open sockets, so it spawns bin/nitpick-bridge for the
// session's life: reviews arrive as JSON lines on its stdout and become
// prompts; the session's state (id, cwd, busy) goes to its control socket.

// Drawn among the mode labels right of the prompt, as Pi draws it in its footer.
const ICON = 'ŋ'

let control
let pending = ''
let tag = ''

async function report($, idle) {
  const id = await $.session.id()
  if (!control) return
  const short = id.replace(/-/g, '').slice(-6)
  if (short !== tag) {
    tag = short
    $.ui.invalidate('ui.render')
  }
  try {
    const cwd = await $.session.cwd()
    await $.http.fetch('http://nitpick/state', {
      method: 'POST',
      socketPath: control,
      body: JSON.stringify({ id, cwd, idle }),
    })
  } catch (error) {
    $.ui.log('nitpick: could not reach the bridge: ' + String(error), { to: 'debug' })
  }
}

async function receive($, line) {
  let message
  try {
    message = JSON.parse(line)
  } catch {
    return
  }
  if (message.type === 'listening') {
    control = message.control
    await report($, true)
  } else if (message.type === 'submit') {
    const what = typeof message.comments === 'number' ? 'Review with ' + message.comments + ' comment(s)' : 'Review'
    $.ui.toast(what + ' received from Neovim')
    // Resolves only when the turn starts, so it must not hold anything up.
    void $.prompt.submit({ text: message.text, asUser: true })
  }
}

async function run($) {
  const bridge = $.process.spawn({ argv: [$.plugin.root + '/bin/nitpick-bridge'] })
  for await (const { stream, text } of bridge) {
    if (stream === 'stderr') {
      $.ui.log(text, { to: 'debug' })
      continue
    }
    pending += text
    let newline = pending.indexOf('\n')
    while (newline !== -1) {
      const line = pending.slice(0, newline)
      pending = pending.slice(newline + 1)
      await receive($, line)
      newline = pending.indexOf('\n')
    }
  }
  control = undefined
  tag = ''
  $.ui.invalidate('ui.render')
}

export function register(on) {
  // "ŋ nvim a3f9c1" beside Claude Code's own mode labels, while the bridge runs.
  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    if (!tag) return next(e)
    return next({ ...e, props: { ...e.props, modes: [...e.props.modes, ICON + ' nvim ' + tag] } })
  })

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    // The bridge lives as long as this loop, which outlives the hook.
    void run($)
    return started
  })

  // Only the main conversation's turns make the session busy.
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) await report($, false)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined) await report($, true)
    return result
  })
}
