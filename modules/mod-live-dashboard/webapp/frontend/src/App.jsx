import { useState } from 'react'
import { usePolling } from './hooks/usePolling'
import { CONTINENTS } from './constants'
import StatsBar from './components/StatsBar'
import ContinentTabs from './components/ContinentTabs'
import WorldMap from './components/WorldMap'
import SidePanels from './components/SidePanels'
import Chronicle from './components/Chronicle'
import Admin from './components/Admin'
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
  return (
    <>
      <ContinentTabs active={activeTab} onChange={setActiveTab} />
      <main>
        <WorldMap positions={positions} activeTab={activeTab} />
        <SidePanels stats={stats} />
      </main>
    </>
  )
}
