// Builds the map style the same way the NOMAD server does (admin/app/services/map_service.ts generateStylesFile):
// the base style's source-bound layers are repeated once per .pmtiles file, and sprites and glyphs point at bundled assets.
(async () => {
  // nomad://app inside the app; the same paths work from any local HTTP server for testing.
  const origin = `${location.protocol}//${location.host}`;
  const files = new URLSearchParams(location.search).getAll('file');

  const showMessage = (text) => {
    const box = document.getElementById('message');
    box.textContent = text;
    box.style.display = 'flex';
  };

  if (files.length === 0) {
    showMessage('No map files selected.');
    return;
  }

  try {
    const protocol = new pmtiles.Protocol();
    maplibregl.addProtocol('pmtiles', protocol.tile);

    const style = await (await fetch(`${origin}/mapassets/nomad-base-styles.json`)).json();
    const attribution = Object.values(style.sources)[0]?.attribution;
    const sourceLayers = style.layers.filter((layer) => layer.source);
    style.layers = style.layers.filter((layer) => !layer.source);
    style.sources = {};

    const archives = files.map((file, i) => {
      const url = `${origin}/maps/${encodeURIComponent(file)}`;
      const archive = new pmtiles.PMTiles(url);
      protocol.add(archive);
      const id = `region-${i}`;
      style.sources[id] = { type: 'vector', url: `pmtiles://${url}`, attribution };
      for (const layer of sourceLayers) {
        style.layers.push({ ...layer, id: `${layer.id}-${id}`, source: id });
      }
      return archive;
    });

    style.sprite = `${origin}/mapassets/basemaps-assets/sprites/v4/light`;
    style.glyphs = `${origin}/mapassets/basemaps-assets/fonts/{fontstack}/{range}.pbf`;

    const header = await archives[0].getHeader();
    const map = new maplibregl.Map({
      container: 'map',
      style,
      center: [header.centerLon, header.centerLat],
      zoom: header.centerZoom,
      maxZoom: 18,
    });
    map.addControl(new maplibregl.NavigationControl(), 'top-right');
    map.addControl(new maplibregl.ScaleControl({ unit: 'metric' }), 'bottom-left');
    map.on('error', (event) => console.error(event.error));
  } catch (error) {
    showMessage(`Could not open the map: ${error.message}`);
  }
})();
