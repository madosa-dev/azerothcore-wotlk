import { useState } from 'react'
import { usePolling } from './hooks/usePolling'
import { CONTINENTS } from './constants'
import StatsBar from './components/StatsBar'
import ContinentTabs from './components/ContinentTabs'
import AreaGrid from './components/AreaGrid'
import SidePanels from './components/SidePanels'
import './App.css'

export default function App() {
  const [activeTab, setActiveTab] = useState(CONTINENTS[0][0])
  const positions = usePolling('/api/positions') ?? []
  const stats = usePolling('/api/stats')

  return (
    <>
      <StatsBar stats={stats} />
      <ContinentTabs active={activeTab} onChange={setActiveTab} />
      <main>
        <AreaGrid positions={positions} activeTab={activeTab} />
        <SidePanels stats={stats} />
      </main>
    </>
  )
}
