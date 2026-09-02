import { useEffect, useMemo, useState } from 'react'
import { usePolling } from './hooks/usePolling'
import { CONTINENTS, MAP_IMAGES } from './constants'
import StatsBar from './components/StatsBar'
import ContinentTabs from './components/ContinentTabs'
import WorldMap from './components/WorldMap'
import SidePanels from './components/SidePanels'
import Chronicle from './components/Chronicle'
import Admin from './components/Admin'
import CharacterCard from './components/CharacterCard'
import './App.css'

const VIEWS = [
  ['map', 'Live map'],
  ['chronicle', 'Chronicle'],
  ['admin', 'Admin'],
]

export default function App() {
  const [view, setView] = useState('map')
  const [activeTab, setActiveTab] = useState(CONTINENTS[0][0])

  // The map is the only view that needs a two-second heartbeat. Polling it from
  // here would keep that traffic going while the chronicle is on screen, so the
  // positions request lives inside the map branch.
  const stats = usePolling('/api/stats')

  return (
    <>
      <StatsBar stats={stats} />
      <div className="views">
        {VIEWS.map(([id, label]) => (
          <button key={id} className={view === id ? 'on' : ''} onClick={() => setView(id)}>
            {label}
          </button>
        ))}
      </div>
      {view === 'map' && <MapView activeTab={activeTab} setActiveTab={setActiveTab} stats={stats} />}
      {view === 'chronicle' && <main className="wide"><Chronicle /></main>}
      {view === 'admin' && <main className="wide"><Admin /></main>}
    </>
  )
}

function MapView({ activeTab, setActiveTab, stats }) {
  const positions = usePolling('/api/positions') ?? []

  // ?guid=N opens a character straight away, so a card can be linked to.
  const [selected, setSelected] = useState(() => {
    const guid = Number(new URLSearchParams(window.location.search).get('guid'))
    return guid > 0 ? guid : null
  })

  // The card follows the live row, so HP and area keep moving while it is
  // open; when the character logs off the card stays until it is closed.
  const live = useMemo(() => positions.find((p) => p.guid === selected) ?? null, [positions, selected])

  // A linked character's continent comes up with them - once, when the live
  // row first arrives; after that the tabs are the user's to change.
  const [followed, setFollowed] = useState(false)
  useEffect(() => {
    if (followed || !live) return
    setFollowed(true)
    if (MAP_IMAGES[live.mapId]) setActiveTab(live.mapId)
  }, [live, followed, setActiveTab])

  return (
    <>
      <ContinentTabs active={activeTab} onChange={setActiveTab} />
      <main>
        <div className="map-row">
          <WorldMap positions={positions} activeTab={activeTab} selected={selected} onSelect={setSelected} />
          {selected != null && (
            <CharacterCard guid={selected} live={live} onClose={() => setSelected(null)} />
          )}
        </div>
        <SidePanels stats={stats} />
      </main>
    </>
  )
}
