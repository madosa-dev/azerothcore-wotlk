export const CONTINENTS = [
  [0, 'Eastern Kingdoms'],
  [1, 'Kalimdor'],
  [530, 'Outland'],
  [571, 'Northrend'],
]

export const OTHER_TAB_ID = -1

export const KNOWN_MAP_IDS = new Set(CONTINENTS.map(([id]) => id))

// Stitched from the client's own terrain minimap tiles (textures/minimap),
// one image per continent. Natural pixel size is needed up front so the map
// container can reserve the right aspect ratio before the image loads.
export const MAP_IMAGES = {
  0: { src: '/maps/azeroth.webp', width: 672, height: 1344 },
  1: { src: '/maps/kalimdor.webp', width: 1632, height: 1792 },
  530: { src: '/maps/outland.webp', width: 1568, height: 1248 },
  571: { src: '/maps/northrend.webp', width: 1248, height: 928 },
}

// Continent-wide world-coordinate bounding box per map, straight from
// WorldMapArea.dbc's area_id=0 ("whole continent") rows - the same data the
// client itself uses to place the world map at the top zoom level. Matches
// the core's Map2ZoneCoordinates() convention: x is north/south, y is
// west/east, and the client map swaps them (x -> vertical, y -> horizontal).
export const MAP_BOUNDS = {
  0: { x1: 11176.34375, x2: -15973.34375, y1: 18171.970703125, y2: -22569.2109375 },
  1: { x1: 12799.900390625, x2: -11733.2998046875, y1: 17066.599609375, y2: -19733.2109375 },
  530: { x1: 5821.359375, x2: -5821.359375, y1: 12996.0390625, y2: -4468.0390625 },
  571: { x1: 10593.375, x2: -1240.8900146484375, y1: 9217.15234375, y2: -8534.24609375 },
}

// Same transform as the core's Map2ZoneCoordinates(), just parameterised on
// a continent's bounding box instead of a single zone's. Returns 0-100
// percentages ready to use as CSS left/top on the continent map image.
export function worldToContinentPct(mapId, posX, posY) {
  const b = MAP_BOUNDS[mapId]
  if (!b) return null

  const rawX = (posX - b.x1) / ((b.x2 - b.x1) / 100)
  const rawY = (posY - b.y1) / ((b.y2 - b.y1) / 100)
  return { pctX: rawY, pctY: rawX }
}
