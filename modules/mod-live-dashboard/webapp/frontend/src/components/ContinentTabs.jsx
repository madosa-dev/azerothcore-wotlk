import { CONTINENTS, OTHER_TAB_ID } from '../constants'

export default function ContinentTabs({ active, onChange }) {
  const tabs = [...CONTINENTS, [OTHER_TAB_ID, 'Other']]

  return (
    <nav>
      {tabs.map(([id, name]) => (
        <button
          key={id}
          type="button"
          className={id === active ? 'active' : ''}
          onClick={() => onChange(id)}
        >
          {name}
        </button>
      ))}
    </nav>
  )
}
