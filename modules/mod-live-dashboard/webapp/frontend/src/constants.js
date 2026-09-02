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

// The continent images are stitched from the client's minimap tiles
// (textures/minimap/md5translate.trs), one 32 px square per 533.33-yard ADT
// tile, cropped to the tiles that actually exist - so an image's edges are
// tile boundaries, not the WorldMapArea.dbc continent rectangle. These are the
// tile ranges each image covers: which column/row the top-left pixel is, and
// how many of each fit in the picture.
//
// Plotting against the DBC rectangle instead was the bug that put dots in the
// sea: for the Eastern Kingdoms that rectangle spans tile columns -2 to 74
// while the picture holds columns 24 to 44, so everything was squeezed into
// the middle third and drifted with distance from the centre.
export const MAP_TILES = {
  0: { colMin: 24, cols: 21, rowMin: 20, rows: 42 },
  1: { colMin: 0, cols: 51, rowMin: 0, rows: 56 },
  530: { colMin: 12, cols: 49, rowMin: 6, rows: 39 },
  571: { colMin: 11, cols: 39, rowMin: 9, rows: 29 },
}

// One ADT tile is 533.33 yards, and the grid is 64x64 with its origin at the
// centre of the map: tile column = 32 - y / 533.33 (world y runs east to
// west), tile row = 32 - x / 533.33 (world x runs south to north). The same
// arithmetic the core's GridDefines use, in the other direction.
const ADT_YARDS = 533.33333

// One web tile (and one stitched minimap tile) is 256 px square.
export const TILE_SIZE = 256

export function tileColRow(posX, posY) {
  return { col: 32 - posY / ADT_YARDS, row: 32 - posX / ADT_YARDS }
}

// Returns 0-100 percentages ready to use as CSS left/top on the continent
// image, or null for a map without a picture.
export function worldToContinentPct(mapId, posX, posY) {
  const t = MAP_TILES[mapId]
  if (!t) return null

  const { col, row } = tileColRow(posX, posY)
  return {
    pctX: ((col - t.colMin) / t.cols) * 100,
    pctY: ((row - t.rowMin) / t.rows) * 100,
  }
}
