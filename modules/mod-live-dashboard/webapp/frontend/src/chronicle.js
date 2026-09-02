// How a chronicle row becomes a line someone wants to read.
//
// The server stores facts - kind, actor, target, value, detail - and nothing
// about presentation. All of the wording lives here, so a new event kind added
// on the server side still shows up (as its raw kind) and can be given a voice
// later without touching the server.

export const CLASS_NAMES = {
  1: 'Warrior', 2: 'Paladin', 3: 'Hunter', 4: 'Rogue', 5: 'Priest',
  6: 'Death Knight', 7: 'Shaman', 8: 'Mage', 9: 'Warlock', 11: 'Druid',
}

export const CLASS_COLORS = {
  1: '#c69b6d', 2: '#f48cba', 3: '#aad372', 4: '#fff468', 5: '#ffffff',
  6: '#c41e3a', 7: '#0070dd', 8: '#3fc7eb', 9: '#8788ee', 11: '#ff7c0a',
}

// icon, a colour for the row's accent, and a title for the filter chips.
export const KINDS = {
  pvp_kill:    { icon: '⚔', color: '#ff6b6b', label: 'Kills' },
  chest:       { icon: '📦', color: '#ffb454', label: 'Spoils' },
  insurance:   { icon: '🪙', color: '#ffd166', label: 'Insurance' },
  worldforged: { icon: '🔥', color: '#c77dff', label: 'Worldforged' },
  boss:        { icon: '💀', color: '#e0aaff', label: 'Bosses' },
  loot:        { icon: '✦', color: '#a78bfa', label: 'Epics' },
  max_level:   { icon: '★', color: '#ffd166', label: 'Level cap' },
  milestone:   { icon: '↑', color: '#6ea8fe', label: 'Milestones' },
  mode:        { icon: '🛡', color: '#4dd4ac', label: 'Risk mode' },
  treason:     { icon: '🏴', color: '#ff8fab', label: 'Treason' },
  loyalty:     { icon: '🕊', color: '#8b93ad', label: 'Loyalty' },
  login:       { icon: '→', color: '#6ea8fe', label: 'Arrivals' },
  death:       { icon: '✝', color: '#8b93ad', label: 'Deaths' },
}

export function kindMeta(kind) {
  return KINDS[kind] ?? { icon: '·', color: '#8b93ad', label: kind }
}

// The sentence. Returns an array of parts so names can be coloured by class
// without dangerously setting inner HTML.
export function describe(e) {
  const A = { name: e.actor, cls: e.actor_class, bot: e.actor_bot }
  const T = { name: e.target, cls: 0, bot: e.target_bot }

  switch (e.kind) {
    case 'pvp_kill':
      return [A, ' cut down ', T, '.']
    case 'chest':
      return [A, ' killed ', T, e.value
        ? ` and left ${e.value} of their belongings on the ground.`
        : ' and left a chest behind.']
    case 'insurance':
      return [A, ' killed ', T, `, whose insurance paid out ${e.value} gold instead of gear.`]
    case 'worldforged':
      return [A, ' claimed ', { text: e.detail || 'a Worldforged find', em: true }, '.']
    case 'boss':
      return [A, ' was there when ', { text: e.detail || 'a boss', em: true }, ' fell.']
    case 'loot':
      return [A, ' looted ', { text: e.detail || 'something rare', em: true },
        e.value > 1 ? ` ×${e.value}.` : '.']
    case 'max_level':
      return [A, ' reached the level cap.']
    case 'milestone':
      return [A, ` reached level ${e.value}.`]
    case 'mode':
      return [A, ' switched to ', { text: e.detail || 'another risk mode', em: true }, '.']
    case 'treason':
      return [A, ` turned traitor to the ${e.detail || 'realm'}.`]
    case 'loyalty':
      return [A, ` was forgiven their treason against the ${e.detail || 'realm'}.`]
    case 'login':
      return [A, ' arrived in the world.']
    case 'death':
      return [A, ' died.']
    default:
      return [A, ` — ${e.kind}${e.detail ? `: ${e.detail}` : ''}`]
  }
}

export function timeAgo(unix) {
  const s = Math.max(0, Math.floor(Date.now() / 1000) - unix)
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  return `${Math.floor(s / 86400)}d ago`
}
