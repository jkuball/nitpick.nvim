import { expect, test } from 'claude-code/testing'

// What Claude Code passes to a ui.render hook for the mode labels.
const MODES = {
  plugin: 'nitpick',
  component: 'SessionMode',
  requestId: 'modes',
  surface: 'terminal',
  viewport: { columns: 100, rows: 30 },
  props: { modes: ['focus'] },
} as const

// The mod reads the bridge's output in a loop of its own, after the hook.
async function until(done: () => boolean) {
  for (let i = 0; i < 100000 && !done(); i++) await Promise.resolve()
}

test('reviews from the bridge become user prompts; state goes to its control socket', async ($, on) => {
  const prompts: unknown[] = []
  const posts: unknown[] = []
  let argv: readonly string[] = []

  on('session.start', () => ({ cwd: '/work' }))
  on('session.id', () => ({ value: '4c1d9e8f-0000-4000-8000-00a1b2c3d4e5' }))
  on('session.cwd', () => ({ value: '/work' }))
  // Claude Code's own drawing of the mode labels, joined as the footer shows them.
  on('ui.render', ($, e) => ({ type: 'Text', props: {}, children: [e.props.modes.join(' & ')] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.log', () => ({ value: undefined }))
  on('http.fetch', ($, e) => {
    posts.push({ url: e.url, socketPath: e.init.socketPath, body: JSON.parse(e.init.body) })
    return { value: { status: 204, ok: true, headers: {}, text: '' } }
  })
  on('prompt.submit', ($, e) => {
    prompts.push({ text: e.text, asUser: e.origin?.asUser })
    return { text: e.text }
  })
  // The bridge announces itself, then forwards one review, split mid-line.
  on('process.spawn', async function* ($, e) {
    argv = e.argv
    yield { stream: 'stdout', text: '{"type":"listening","socket":"/s/1.sock","control":"/s/1.ctl"}\n{"type":"sub' }
    yield { stream: 'stdout', text: 'mit","text":"Please fix","comments":1}\n' }
    return { value: { code: 0, signal: null } }
  })
  on('turn.start', ($, e) => ({ turnId: e.turnId }))

  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await until(() => prompts.length > 0)

  expect(argv[0].endsWith('/bin/nitpick-bridge')).toBe(true)
  expect(posts).toEqual([
    { url: 'http://nitpick/state', socketPath: '/s/1.ctl', body: { id: '4c1d9e8f-0000-4000-8000-00a1b2c3d4e5', cwd: '/work', idle: true } },
  ])
  expect(prompts).toEqual([{ text: 'Please fix', asUser: true }])
  // The bridge exited, so the tag is gone again.
  const ui = await $.ui.mount(MODES)
  expect(await ui.find({ type: 'Text', text: 'focus' })).toBeDefined()
})

test("the main conversation's turns mark the session busy, subagents do not", async ($, on) => {
  const idle: boolean[] = []
  let exit = () => {}
  const exited = new Promise<void>((resolve) => (exit = resolve))

  on('session.start', () => ({ cwd: '/work' }))
  on('session.id', () => ({ value: 'abc-000abc' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('ui.render', ($, e) => ({ type: 'Text', props: {}, children: [e.props.modes.join(' & ')] }))
  on('http.fetch', ($, e) => {
    idle.push(JSON.parse(e.init.body).idle)
    return { value: { status: 204, ok: true, headers: {}, text: '' } }
  })
  // A bridge that stays up until the test lets it go.
  on('process.spawn', async function* () {
    yield { stream: 'stdout', text: '{"type":"listening","socket":"/s/1.sock","control":"/s/1.ctl"}\n' }
    await exited
    return { value: { code: 0, signal: null } }
  })
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))

  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await until(() => idle.length === 1)
  const ui = await $.ui.mount(MODES)
  expect(await ui.find({ type: 'Text', text: 'focus & ŋ nvim 000abc' })).toBeDefined()
  await $.turn.start({ turnId: 't1' })
  await $.turn.start({ turnId: 't2', agentId: 'sub' })
  await $.turn.complete({ turnId: 't2', agentId: 'sub', answer: '', durationMs: 1, isAborted: false, usage: null })
  await $.turn.complete({ turnId: 't1', answer: '', durationMs: 1, isAborted: false, usage: null })
  exit()

  expect(idle).toEqual([true, false, true])
})
